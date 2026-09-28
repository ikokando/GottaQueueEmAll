-------------------------------------------------------------------------------
--  GottaQueueEmAll_Create.lua  --  "Start a Group" and your own listing
--
--  Three places, one set of controls (the "draft" of your listing):
--   - center: Start a Group (dungeons). Our form replaces Blizzard's in the
--     panel: dungeon tiles with your season best, "My key", difficulty,
--     playstyle (required), requirements with "mine" values, options, listing
--     presets on the left; Blizzard's title / details / voice chat boxes on
--     the right. Blizzard's List Group / Back buttons stay at the bottom.
--   - side: while your dungeon group is listed (applicant view), the same
--     controls sit in a sidebar. Edit / Delist click Blizzard's own buttons;
--     "Relist with these settings" delists and then offers a new listing.
--   - after a relist Blizzard shows its category page (no sidebar there): its
--     Start a Group button is highlighted, and the form opens pre-filled with
--     the draft. Opening it ourselves would run Blizzard's panel switch from
--     addon code and taint the applicant viewer (secret values), so one extra
--     click stays.
--
--  Blizzard's rules, read before editing:
--   - Title, details and voice chat are secure edit boxes
--     (securityDisableSetText): never SetText / SetScript on them. They are
--     only re-anchored, resized and raised; the player types in them and the
--     client reads them itself when listing.
--   - Blizzard's other form widgets are never hidden (Hide() would change what
--     List Group reads: ItemLevel:IsShown / CrossFactionGroup:IsShown). They
--     get alpha 0 under a mouse-blocking cover, and our controls write into
--     them: requirement edit boxes, option check buttons, the activity via
--     LFGListEntryCreation_Select and the playstyle via
--     LFGListEntryCreation_OnPlayStyleSelectedInternal - the same calls
--     Blizzard's dropdowns make. Those two fields are then set by addon code;
--     if List Group ever reports a blocked action, this is the place to look.
--   - List Group, Edit, Delist and Start Group are Blizzard's buttons, or
--     secure clicks on them. Nothing here creates or removes a listing itself.
-------------------------------------------------------------------------------
local _, ns = ...
local CR = {}
ns.Create = CR

local L = ns.L
local PAD, BTN_H, HEADER_H, SECTION_GAP = L.PAD, L.BTN_H, L.HEADER_H, L.SECTION_GAP
local COL_W, COL_GAP, CHECK_H = L.COL_W, L.COL_GAP, L.CHECK_H
local SIDEBAR_W, GAP = L.SIDEBAR_W, L.GAP
local DUNGEON = L.DUNGEON_CATEGORY
local INNER_W = SIDEBAR_W - PAD * 2
local TILE_H = 36
local STATUS_H = 28
local COVER_TOP, COVER_BOTTOM = 56, 30   -- center: below Blizzard's heading, above its buttons
local COL2_X = 8 + SIDEBAR_W + 14         -- center: title / details column
local DETAILS_H = 120                      -- center: details box (Blizzard's allows 255 letters)
local PREVIEW_H = 84
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local issecretvalue = issecretvalue or function() return false end

local EC, AV, CS   -- LFGListFrame.EntryCreation / .ApplicationViewer / .CategorySelection
local P            -- our controls panel
local cover        -- center mode: covers Blizzard's form, holds the column labels
local applyLayout
local mode         -- "center" | "side" | nil
local pushing, pendingRelist = false, false

-- What the next listing should be. Requirements can be relative ("mine" minus
-- an offset), so presets and relists stay right as you gear up.
local draft = {
    activity = nil, playstyle = nil,
    rating = { mode = "off", off = 0, value = 0 },
    ilvl   = { mode = "off", off = 0, value = 0 },
    private = false, ownFaction = false,
    lust = false, brez = false,   -- "Looking for": marks applicants who bring it (not part of the listing)
}

local function Presets()
    local d = ns.DB()
    if type(d.createPresets) ~= "table" then d.createPresets = {} end
    return d.createPresets
end

-------------------------------------------------------------------------------
--  Values
-------------------------------------------------------------------------------
local function Num(v) return type(v) == "number" and not issecretvalue(v) and v or nil end
local function Bool(v) return type(v) == "boolean" and not issecretvalue(v) and v or false end

local function MyRating()
    local s = C_ChallengeMode.GetOverallDungeonScore and Num(C_ChallengeMode.GetOverallDungeonScore())
    return s and floor(s) or 0
end

local function MyItemLevel()
    local _, equipped = GetAverageItemLevel()
    equipped = Num(equipped)
    return equipped and floor(equipped) or 0
end

-- The keystone in your bags: activityID, level, dungeon name, texture.
local function MyKey()
    if not C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel then return end
    local act, _, lvl = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
    if not Num(act) then act, _, lvl = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel(true) end
    act, lvl = Num(act), Num(lvl)
    if not act then return end
    local name, tex
    local map = C_MythicPlus.GetOwnedKeystoneChallengeMapID and Num(C_MythicPlus.GetOwnedKeystoneChallengeMapID())
    if map then name, _, _, tex = C_ChallengeMode.GetMapUIInfo(map) end
    if not name then
        local ai = C_LFGList.GetActivityInfoTable(act)
        name = ai and ai.shortName
    end
    return act, lvl, name, tex
end

local function Info(act) return Num(act) and C_LFGList.GetActivityInfoTable(act) or nil end

local function GroupOf(act)
    local ai = Info(act)
    return ai and Num(ai.groupFinderActivityGroupID)
end

-- Activities of a dungeon (Normal, Heroic, Mythic, Mythic Keystone ...).
local function ActivitiesOf(gid)
    local out = {}
    if not gid then return out end
    for _, act in ipairs(C_LFGList.GetAvailableActivities(DUNGEON, gid) or {}) do
        local ai = C_LFGList.GetActivityInfoTable(act)
        if ai then
            out[#out + 1] = { id = act, name = ai.shortName or ai.fullName or "?",
                              mplus = ai.isMythicPlusActivity, order = ai.orderIndex or 0 }
        end
    end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return out
end

-- Resolved value of a requirement ("mine" = own value minus offset).
local function Resolve(r, mine)
    if r.mode == "mine" then return max(0, mine - (r.off or 0)) end
    if r.mode == "off" then return 0 end
    return r.value or 0
end

-- Take over a value from Blizzard unless the current mode already yields it.
local function Adopt(r, v, mine)
    v = v or 0
    if Resolve(r, mine) == v then return end
    r.mode, r.off, r.value = (v > 0) and "fixed" or "off", 0, v
end

-------------------------------------------------------------------------------
--  Blizzard's form
-------------------------------------------------------------------------------
local REQ = { rating = "MythicPlusRating", ilvl = "ItemLevel" }

local function Req(which) return EC and EC[REQ[which]] end

local function ReadReq(which)
    local r = Req(which)
    return r and tonumber(r.EditBox:GetText()) or 0
end

local function WriteReq(which, v)
    local r = Req(which)
    if not r then return end
    v = (v and v > 0) and floor(v) or 0
    if v == ReadReq(which) then return end
    pcall(function()
        if v > 0 then
            r.EditBox:SetText(tostring(v))       -- Blizzard ticks + validates on text change
        else
            r.EditBox:SetText("")
            r.CheckButton:SetChecked(false)      -- what Blizzard's own unticking does
        end
    end)
end

local function Option(key) return EC and EC[key] and EC[key].CheckButton end

local function SetOption(key, on)
    local cb = Option(key)
    if cb and cb:IsEnabled() and EC[key]:IsShown() then pcall(cb.SetChecked, cb, on and true or false) end
end

local function GetOption(key)
    local cb = Option(key)
    return cb and EC[key]:IsShown() and cb:GetChecked() and true or false
end

local function CurrentPlaystyle()
    local v = EC and Num(EC.generalPlaystyle)
    return (v and v > 0) and v or nil
end

local PLAYSTYLES = {}
if Enum and Enum.LFGEntryGeneralPlaystyle then
    local E = Enum.LFGEntryGeneralPlaystyle
    PLAYSTYLES = {
        { value = E.Learning,   label = GROUP_FINDER_GENERAL_PLAYSTYLE1 or "Learning" },
        { value = E.FunRelaxed, label = GROUP_FINDER_GENERAL_PLAYSTYLE2 or "Relaxed" },
        { value = E.FunSerious, label = GROUP_FINDER_GENERAL_PLAYSTYLE3 or "Competitive" },
        { value = E.Expert,     label = GROUP_FINDER_GENERAL_PLAYSTYLE4 or "Carry offered" },
    }
end

local function PlaystyleLabel(v)
    for _, s in ipairs(PLAYSTYLES) do if s.value == v then return s.label end end
end

local function EditMode() return EC and EC.editMode and true or false end

-- Draft -> Blizzard's form (only while it is on screen).
local pushWarned = false
local function Push()
    if not (EC and EC:IsVisible()) then return end
    pushing = true
    local ok, err = pcall(function()
        if not EditMode() and draft.activity and draft.activity ~= Num(EC.selectedActivity)
           and LFGListEntryCreation_Select then
            LFGListEntryCreation_Select(EC, nil, nil, nil, draft.activity)
        end
        if draft.playstyle and draft.playstyle ~= CurrentPlaystyle()
           and LFGListEntryCreation_OnPlayStyleSelectedInternal then
            LFGListEntryCreation_OnPlayStyleSelectedInternal(EC, draft.playstyle)
        end
        if Req("rating") and Req("rating"):IsShown() then WriteReq("rating", Resolve(draft.rating, MyRating())) end
        WriteReq("ilvl", Resolve(draft.ilvl, MyItemLevel()))
        SetOption("PrivateGroup", draft.private)
        SetOption("CrossFactionGroup", draft.ownFaction)
    end)
    pushing = false
    if not ok and not pushWarned then
        pushWarned = true
        ns.Print("could not fill in Blizzard's form (" .. tostring(err) .. ").")
    end
end

-- Blizzard's form -> draft (it opened, or Blizzard changed it itself).
local function PullForm()
    if pushing or not EC then return end
    draft.activity = Num(EC.selectedActivity) or draft.activity
    draft.playstyle = CurrentPlaystyle()
    if Req("rating") and Req("rating"):IsShown() then Adopt(draft.rating, ReadReq("rating"), MyRating()) end
    Adopt(draft.ilvl, ReadReq("ilvl"), MyItemLevel())
    draft.private = GetOption("PrivateGroup")
    if EC.CrossFactionGroup:IsShown() then draft.ownFaction = GetOption("CrossFactionGroup") end
end

-- The active listing -> draft (entering the listed view).
local function PullListing()
    local e = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
    if type(e) ~= "table" or issecretvalue(e) then return end
    local ids = e.activityIDs
    local act = type(ids) == "table" and not issecretvalue(ids) and Num(ids[1]) or Num(e.activityID)
    if act then draft.activity = act end
    local ps = Num(e.generalPlaystyle)
    if ps and ps > 0 then draft.playstyle = ps end
    Adopt(draft.rating, Num(e.requiredDungeonScore) or 0, MyRating())
    Adopt(draft.ilvl, Num(e.requiredItemLevel) or 0, MyItemLevel())
    draft.private = Bool(e.privateGroup)
    if type(e.isCrossFactionListing) == "boolean" and not issecretvalue(e.isCrossFactionListing) then
        draft.ownFaction = not e.isCrossFactionListing
    end
end

-- Changes made in the listed view wait for Edit listing (or a relist).
local staged = false

-- Every control goes through here.
local function Changed()
    if mode == "center" then Push() end
    if mode == "side" then staged = true end
    CR.Refresh()
end

local function ListedActivity()
    local e = C_LFGList.HasActiveEntryInfo() and C_LFGList.GetActiveEntryInfo()
    if type(e) ~= "table" or issecretvalue(e) then return nil end
    local ids = e.activityIDs
    return type(ids) == "table" and not issecretvalue(ids) and Num(ids[1]) or Num(e.activityID)
end

-------------------------------------------------------------------------------
--  Presets (requirements, options, playstyle; not the dungeon)
-------------------------------------------------------------------------------
local function CopyReq(r) return { mode = r.mode, off = r.off, value = r.value } end

local function CurrentPresetData(name)
    return {
        name = name, rating = CopyReq(draft.rating), ilvl = CopyReq(draft.ilvl),
        private = draft.private, ownFaction = draft.ownFaction, playstyle = draft.playstyle,
        lust = draft.lust, brez = draft.brez,
    }
end

local function PresetMatches(p)
    if Resolve(p.rating, MyRating()) ~= Resolve(draft.rating, MyRating()) then return false end
    if Resolve(p.ilvl, MyItemLevel()) ~= Resolve(draft.ilvl, MyItemLevel()) then return false end
    if (p.private or false) ~= draft.private then return false end
    if (p.ownFaction or false) ~= draft.ownFaction then return false end
    if p.playstyle and p.playstyle ~= draft.playstyle then return false end
    if (p.lust or false) ~= draft.lust or (p.brez or false) ~= draft.brez then return false end
    return true
end

local function CurrentPreset()
    for _, p in ipairs(Presets()) do
        if PresetMatches(p) then return p end
    end
end

local function FindPreset(name)
    for i, p in ipairs(Presets()) do
        if p.name == name then return p, i end
    end
end

local function PinnedPresets()
    local out = {}
    for _, p in ipairs(Presets()) do
        if p.pinned then out[#out + 1] = p end
        if #out == L.QUICK_SLOTS then break end
    end
    return out
end

local function ApplyPreset(p)
    draft.rating, draft.ilvl = CopyReq(p.rating), CopyReq(p.ilvl)
    draft.private, draft.ownFaction = p.private or false, p.ownFaction or false
    if p.playstyle then draft.playstyle = p.playstyle end
    CR.SetLookingFor(p.lust or false, p.brez or false)
    Changed()
end

-------------------------------------------------------------------------------
--  Building
-------------------------------------------------------------------------------
local function Header(text, parent)
    local fs = ns.MakeText(parent or P, "GameFontNormal")
    fs:SetText(text)
    return fs
end

local function Relaid()
    if mode and not InCombatLockdown() then applyLayout() end
    CR.Refresh()
end

local function StartNameEdit(editMode, target)
    if InCombatLockdown() then ns.Print("presets can't be edited in combat."); return end
    P.editMode, P.editTarget = editMode, target
    Relaid()
    P.nameBox:SetText(editMode == "rename" and target.name or "")
    P.nameBox:SetFocus()
    P.nameBox:HighlightText()
end

local function CommitNameEdit()
    local name = strtrim(P.nameBox:GetText() or "")
    local editMode, target = P.editMode, P.editTarget
    P.editMode, P.editTarget = nil, nil
    P.nameBox:ClearFocus()
    local list = Presets()
    if name ~= "" then
        local existing, idx = FindPreset(name)
        if editMode == "rename" and target then
            if existing and existing ~= target then
                ns.Print("a listing preset named \"" .. name .. "\" already exists.")
            else
                target.name = name
            end
        elseif existing then
            local p = CurrentPresetData(name)
            p.pinned = existing.pinned
            list[idx] = p
            ns.Print("updated \"" .. name .. "\".")
        elseif #list >= L.MAX_PRESETS then
            ns.Print("maximum of " .. L.MAX_PRESETS .. " listing presets reached.")
        else
            list[#list + 1] = CurrentPresetData(name)
        end
    end
    Relaid()
end

local function SetupPresetMenu(dd)
    dd:SetupMenu(function(_, root)
        local list = Presets()
        if #list == 0 then root:CreateTitle("No listing presets yet") end
        for _, p in ipairs(list) do
            local label = p.pinned and ("|A:auctionhouse-icon-favorite:12:12|a " .. p.name) or p.name
            root:CreateRadio(label, function() return PresetMatches(p) end, function() ApplyPreset(p) end)
        end
        root:CreateDivider()
        root:CreateButton("Save current settings as new preset...", function() StartNameEdit("new") end)
        local cur = CurrentPreset()
        if cur then
            local sub = root:CreateButton("Manage \"" .. cur.name .. "\"")
            sub:CreateCheckbox("Pin to quick bar", function() return cur.pinned end, function()
                if not cur.pinned and #PinnedPresets() >= L.QUICK_SLOTS then
                    ns.Print("the quick bar holds " .. L.QUICK_SLOTS .. " presets; unpin one first.")
                    return
                end
                cur.pinned = not cur.pinned
                Relaid()
            end)
            sub:CreateButton("Rename...", function() StartNameEdit("rename", cur) end)
            local del = sub:CreateButton("Delete")
            del:CreateButton("|cffff5555Delete \"" .. cur.name .. "\"|r", function()
                local _, idx = FindPreset(cur.name)
                if idx then table.remove(list, idx) end
                Relaid()
            end)
        end
    end)
end

local function BuildPresets()
    P.hPresets = Header("Listing presets")
    P.presetDD = ns.MakeDropdown(P, INNER_W)
    SetupPresetMenu(P.presetDD)

    P.quick = {}
    for i = 1, L.QUICK_SLOTS do
        local b = ns.MakeButton(P, "")
        b:SetScript("OnClick", function(self) if self.preset then ApplyPreset(self.preset) end end)
        ns.AddTip(b, function(tt)
            tt:SetText(b.preset and b.preset.name or "", 1, 1, 1)
            tt:AddLine("Click: requirements, options and playstyle of this preset", 0.8, 0.8, 0.8, true)
        end)
        b:Hide()
        P.quick[i] = b
    end

    local box = CreateFrame("EditBox", nil, P, "InputBoxTemplate")
    box:SetHeight(BTN_H)
    box:SetAutoFocus(false)
    box:SetMaxLetters(32)
    box:SetScript("OnEnterPressed", CommitNameEdit)
    box:SetScript("OnEscapePressed", function()
        P.editMode, P.editTarget = nil, nil
        box:ClearFocus()
        Relaid()
    end)
    box:Hide()
    ns.W.edits[#ns.W.edits + 1] = box
    local skin = ns.Skin()
    if skin then skin.EditBox(box) end
    P.nameBox = box
    P.nameOK = ns.MakeButton(P, "Save")
    P.nameOK:SetScript("OnClick", CommitNameEdit)
    P.nameOK:Hide()
end

-- Dungeon tile: icon with your season best on it, name next to it, a key
-- marker on the dungeon of the keystone in your bags.
local function PaintTile(t)
    local ar, ag, ab = ns.Accent()
    if t.selected then
        t.bg:SetColorTexture(ar, ag, ab, t.hover and 0.28 or 0.18)
        ns.SetBorderColor(t, ar, ag, ab, 0.95)
    elseif ns.Skin() then
        t.bg:SetColorTexture(0.061, 0.095, 0.120, t.hover and 0.85 or 0.6)
        ns.SetBorderColor(t, 1, 1, 1, t.hover and 0.35 or 0.1)
    else
        t.bg:SetColorTexture(0, 0, 0, t.hover and 0.55 or 0.4)
        ns.SetBorderColor(t, 0.5, 0.5, 0.5, t.hover and 0.9 or 0.45)
    end
    t:SetAlpha(t.locked and not t.selected and 0.45 or 1)
end

local function PickGroup(gid)
    local cur = Info(draft.activity)
    local list = ActivitiesOf(gid)
    local pick
    if cur then
        for _, a in ipairs(list) do if a.name == cur.shortName then pick = a.id; break end end
    end
    if not pick then
        for _, a in ipairs(list) do if a.mplus then pick = a.id; break end end
    end
    pick = pick or (list[1] and list[1].id)
    if pick then draft.activity = pick; Changed() end
end

local function CreateTile()
    local t = CreateFrame("Button", nil, P)
    t:SetSize(COL_W, TILE_H)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    ns.CreateBorder(t)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(TILE_H - 6, TILE_H - 6)
    t.icon:SetPoint("LEFT", 3, 0)
    t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    t.key = t:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    t.key:SetPoint("BOTTOM", t.icon, "BOTTOM", 0, 1)
    t.mine = t:CreateTexture(nil, "OVERLAY")
    t.mine:SetSize(14, 14)
    t.mine:SetPoint("TOPRIGHT", -2, -2)
    t.mine:SetTexture("Interface\\Icons\\INV_Relics_Hourglass")
    t.mine:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    t.name = ns.MakeText(t, "GameFontHighlightSmall")
    t.name:SetPoint("LEFT", t.icon, "RIGHT", 5, 0)
    t.name:SetPoint("RIGHT", t, "RIGHT", -14, 0)
    t.name:SetJustifyH("LEFT")
    t.name:SetWordWrap(true)
    t.name:SetMaxLines(2)
    t:SetScript("OnEnter", function(self) self.hover = true; PaintTile(self); ns.ShowTip(self) end)
    t:SetScript("OnLeave", function(self) self.hover = false; PaintTile(self); ns.HideTip(self) end)
    t:SetScript("OnClick", function(self)
        if self.locked then return end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        PickGroup(self.groupID)
    end)
    t.tip = function(tt)
        tt:SetText(t.dungeonName or "", 1, 1, 1)
        if t.bestLevel then
            tt:AddLine(("Season best: +%d (%s)"):format(t.bestLevel,
                t.bestTimed and "|cff40ff40in time|r" or "|cffff8040over time|r"), 1, 0.82, 0)
        else
            tt:AddLine("No run this season", 0.6, 0.6, 0.6)
        end
        if t.mine:IsShown() then tt:AddLine("Your keystone is for this dungeon.", 0.85, 0.85, 0.85) end
        if t.locked then
            tt:AddLine(" ")
            tt:AddLine("A listed group keeps its dungeon. To list another one: Relist with these settings.", 1, 0.6, 0.2, true)
        end
    end
    return t
end

local function UpdateTiles()
    P.groups = ns.SeasonGroups()
    for i, g in ipairs(P.groups) do
        local t = P.tiles[i] or CreateTile()
        P.tiles[i] = t
        t.groupID, t.dungeonName = g.id, g.name
        t.name:SetText(g.name)
        local tex = g.cid and select(4, C_ChallengeMode.GetMapUIInfo(g.cid))
        t.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        local level, timed = ns.BestKey(g.cid)
        t.bestLevel, t.bestTimed = level, timed
        if level then
            t.key:SetText("+" .. level)
            ns.ColorKeyText(t.key, level, timed)
            t.key:Show()
        else
            t.key:Hide()
        end
    end
    for i = #P.groups + 1, #P.tiles do P.tiles[i]:Hide() end
end

local function BuildDungeons()
    P.hDungeon = Header("Dungeon")
    P.myKey = ns.MakeButton(P, "My key")
    P.myKey:SetSize(70, 18)
    P.myKey:SetScript("OnClick", function()
        local act = MyKey()
        if act then draft.activity = act; Changed() end
    end)
    ns.AddTip(P.myKey, function(tt)
        local act, lvl, name = MyKey()
        tt:SetText("My key", 1, 1, 1)
        if act then
            tt:AddLine(("Selects %s (Mythic Keystone), your +%d."):format(name or "?", lvl or 0), 0.85, 0.85, 0.85, true)
        else
            tt:AddLine("No keystone in your bags.", 0.6, 0.6, 0.6)
        end
    end)
    local holder = CreateFrame("Frame", nil, P)   -- own frame: the EUI panel skin covers textures on P
    holder:SetSize(16, 16)
    P.keyIcon = holder:CreateTexture(nil, "ARTWORK")
    P.keyIcon:SetAllPoints()
    P.keyIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    P.keyHolder = holder
    P.keyText = ns.MakeText(P, "GameFontHighlightSmall")
    P.keyText:SetJustifyH("LEFT")
    P.keyText:SetWidth(INNER_W - 22)
    P.keyText:SetWordWrap(false)
    P.tiles = {}

    -- Difficulty: the activities of the selected dungeon (Normal ... Mythic Keystone).
    P.hDiff = Header("Difficulty")
    P.diffDD = ns.MakeDropdown(P, COL_W)
    P.diffDD:SetupMenu(function(_, root)
        local acts = ActivitiesOf(GroupOf(draft.activity))
        if #acts == 0 then root:CreateTitle("Pick a dungeon first") end
        for _, a in ipairs(acts) do
            root:CreateRadio(a.name, function() return draft.activity == a.id end, function()
                draft.activity = a.id; Changed()
            end)
        end
    end)
end

-- One requirement: label + box, then "mine minus" and "mine" quick buttons.
local function BuildRequirement(which, label, minusLabel, minusOff, myValue, tip)
    local r = {}
    r.label = ns.MakeText(P)
    r.label:SetText(label)
    r.box = ns.MakeNumberBox(P, 64, 4,
        function() return Resolve(draft[which], myValue()) end,
        function(v)
            v = (v and v > 0) and floor(v) or 0
            draft[which] = { mode = v > 0 and "fixed" or "off", off = 0, value = v }
            Changed()
        end, tip)
    local function Mine(off)
        return function()
            draft[which] = { mode = "mine", off = off, value = 0 }
            Changed()
        end
    end
    r.minus = ns.MakeButton(P, minusLabel)
    r.minus:SetScript("OnClick", Mine(minusOff))
    r.mine = ns.MakeButton(P, "Mine")
    r.mine:SetScript("OnClick", Mine(0))
    local function MineTip(off)
        return function(tt)
            tt:SetText(label, 1, 1, 1)
            tt:AddLine(("Your %s: %d. Sets %d."):format(label:lower(), myValue(), max(0, myValue() - off)), 0.85, 0.85, 0.85, true)
            tt:AddLine("Presets and relists keep this relative to your own value.", 0.6, 0.6, 0.6, true)
        end
    end
    ns.AddTip(r.minus, MineTip(minusOff))
    ns.AddTip(r.mine, MineTip(0))
    return r
end

local function BuildStyleAndRequirements()
    P.hStyle = Header("Playstyle")
    P.styleDD = ns.MakeDropdown(P, COL_W)
    P.styleDD:SetupMenu(function(_, root)
        for _, s in ipairs(PLAYSTYLES) do
            root:CreateRadio(s.label, function() return draft.playstyle == s.value end, function()
                draft.playstyle = s.value; Changed()
            end)
        end
    end)

    -- Looking for: nobody sees this but you. Applicants who bring it are
    -- marked in the applicant list (Blizzard has no field for it, and the
    -- title / details can't be written by addons).
    P.hLook = Header("Looking for")
    local function Look(key)
        return function(cb)
            local on = cb:GetChecked() and true or false
            if key == "lust" then CR.SetLookingFor(on, draft.brez) else CR.SetLookingFor(draft.lust, on) end
            CR.Refresh()   -- not part of the listing: no Edit / relist needed
        end
    end
    local function LookTip(what)
        return function(tt)
            tt:SetText("Looking for " .. what, 1, 1, 1)
            tt:AddLine("Applicants who bring it get a green mark in the applicant list.", 0.85, 0.85, 0.85, true)
            tt:AddLine("Only you see this: Blizzard's listing has no field for it, and addons can't write the title or details. Type it into the title yourself if applicants should know.", 0.6, 0.6, 0.6, true)
        end
    end
    P.lookLust = ns.MakeCheck(P, ns.LUST_ICON .. " Lust", Look("lust"), LookTip("Bloodlust / Heroism"))
    P.lookBrez = ns.MakeCheck(P, ns.BREZ_ICON .. " Brez", Look("brez"), LookTip("a battle res"))

    P.hReq = Header("Requirements")
    P.reqRating = BuildRequirement("rating", "Min. rating", "Mine -200", 200, MyRating,
        "Minimum Mythic+ rating to apply. Empty = none. Mythic+ only.")
    P.reqIlvl = BuildRequirement("ilvl", "Item level", "Mine -10", 10, MyItemLevel,
        "Minimum item level to apply. Empty = none.")
    P.optPrivate = ns.MakeCheck(P, LFG_LIST_PRIVATE or "Private", function(cb)
        draft.private = cb:GetChecked() and true or false; Changed()
    end, LFG_LIST_PRIVATE_TOOLTIP or "Only friends and guild members can see the group.")
    P.optFaction = ns.MakeCheck(P, "Own faction only", function(cb)
        draft.ownFaction = cb:GetChecked() and true or false; Changed()
    end, function(tt)
        tt:SetText(EC and EC.CrossFactionGroup.Label:GetText() or "Own faction only", 1, 1, 1)
        tt:AddLine(EC and EC.CrossFactionGroup.tooltip or "Only players of your faction can join.", 0.85, 0.85, 0.85, true)
    end)
end

-- Secure buttons that click Blizzard's own buttons (attributes set once, out of combat).
local function SecureClicker(text, target, tip)
    local b = ns.MakeButton(P, text, nil, true)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type1", "click")
    b:SetAttribute("clickbutton", target)
    if tip then ns.AddTip(b, tip) end
    b:Hide()
    return b
end

local function BuildBottom()
    P.status = ns.MakeText(P, "GameFontHighlightSmall")
    P.status:SetJustifyH("CENTER")
    P.status:SetWordWrap(true)
    P.status:SetMaxLines(2)

    -- Edit / Delist / Browse Groups stay Blizzard's own buttons under the
    -- applicant list (no duplicates here). Blizzard's Edit picks up what you
    -- changed in this sidebar (see the EntryCreation OnShow hook).
    -- One click relist: a secure macro /clicks two named helper buttons of
    -- ours; each one secure-clicks one of Blizzard's (nameless) buttons:
    -- Delist, then Start a Group. No addon code runs in between, so
    -- Blizzard's panel switch stays untainted. /click sends an "up" click,
    -- so the helpers act on up (useOnKeyDown false) whatever the cvar says.
    -- They stay shown (1px, invisible) so Click() reaches them.
    local function Helper(name, target)
        local h = CreateFrame("Button", name, P, "SecureActionButtonTemplate")
        h:SetSize(1, 1)
        h:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", 0, 0)
        h:SetAlpha(0)
        h:EnableMouse(false)
        h:SetAttribute("type", "click")
        h:SetAttribute("clickbutton", target)
        h:SetAttribute("useOnKeyDown", false)
        return h
    end
    local hDelist = Helper("GottaQueueEmAllRelistDelist", AV.RemoveEntryButton)
    local hStart = Helper("GottaQueueEmAllRelistStart", CS.StartGroupButton)
    local ok, a, b = pcall(function()
        return GetClickFrame("GottaQueueEmAllRelistDelist"), GetClickFrame("GottaQueueEmAllRelistStart")
    end)
    CR.oneClickRelist = ok and a == hDelist and b == hStart
    P.btnRelist = SecureClicker("Relist with these settings", AV.RemoveEntryButton,
        CR.oneClickRelist
        and "Delists the group and opens Start a Group right away, filled in with the dungeon, playstyle, requirements and options set here. Title and details carry over. Check them, then List Group."
        or "Delists the group. Then click Start a Group (highlighted): the new form opens with the dungeon, playstyle, requirements and options set here. Title and details carry over.")
    if CR.oneClickRelist then
        P.btnRelist:SetAttribute("type1", "macro")
        P.btnRelist:SetAttribute("macrotext1", "/click GottaQueueEmAllRelistDelist\n/click GottaQueueEmAllRelistStart")
    end
    P.btnRelist:SetScript("PreClick", function(_, button)
        if button == "LeftButton" then pendingRelist = true end
    end)
end

-- Right column of the center form: labels, and a preview of the listing
-- under Blizzard's boxes. The cover spans only this column: Blizzard's faded
-- widgets are parked under it, our controls on the left stay clickable.
local function BuildCover()
    cover = CreateFrame("Frame", nil, EC)
    cover:SetPoint("TOPLEFT", EC, "TOPLEFT", COL2_X - 8, -COVER_TOP)
    cover:SetPoint("BOTTOMRIGHT", EC, "BOTTOMRIGHT", 0, COVER_BOTTOM)
    cover:EnableMouse(true)   -- Blizzard's own widgets stay underneath (alpha 0) and must not take clicks
    cover.title = Header("Title", cover)
    cover.title:SetPoint("TOPLEFT", cover, "TOPLEFT", 8, -4)
    cover.titleWarn = ns.MakeText(cover, "GameFontNormalSmall")
    cover.titleWarn:SetPoint("LEFT", cover.title, "RIGHT", 10, 0)
    cover.titleWarn:SetPoint("RIGHT", cover, "RIGHT", -18, 0)
    cover.titleWarn:SetJustifyH("LEFT")
    cover.titleWarn:SetWordWrap(false)
    cover.details = Header("Details", cover)
    cover.details:SetPoint("TOPLEFT", cover, "TOPLEFT", 8, -58)

    local card = CreateFrame("Frame", nil, cover)
    card:SetHeight(PREVIEW_H)
    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetAllPoints()
    card.bg:SetColorTexture(0, 0, 0, 0.35)
    ns.CreateBorder(card)
    ns.SetBorderColor(card, 0.5, 0.5, 0.5, 0.45)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(PREVIEW_H - 16, PREVIEW_H - 16)
    card.icon:SetPoint("LEFT", 8, 0)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.key = card:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    card.key:SetPoint("BOTTOM", card.icon, "BOTTOM", 0, 3)
    card.lines = {}
    for i = 1, 4 do
        local fs = ns.MakeText(card, i == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        if i == 1 then
            fs:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
        else
            fs:SetPoint("TOPLEFT", card.lines[i - 1], "BOTTOMLEFT", 0, -5)
        end
        card.lines[i] = fs
    end
    cover.preview = Header("Preview", cover)
    cover.card = card
    cover:Hide()
end

-- What the listing will show, from the draft.
local function RefreshPreview()
    local card = cover and cover.card
    if not (card and cover:IsShown()) then return end
    local ai = Info(draft.activity)
    local gid = GroupOf(draft.activity)
    local cid
    for _, g in ipairs(P.groups or {}) do if g.id == gid then cid = g.cid end end
    card.icon:SetTexture(cid and select(4, C_ChallengeMode.GetMapUIInfo(cid)) or "Interface\\Icons\\INV_Misc_QuestionMark")
    local level, timed = ns.BestKey(cid)
    if level then
        card.key:SetText("+" .. level); ns.ColorKeyText(card.key, level, timed); card.key:Show()
    else
        card.key:Hide()
    end
    card.lines[1]:SetText(ai and (ai.fullName or ai.shortName) or "|cff999999No dungeon selected|r")
    card.lines[2]:SetText(draft.playstyle and ("Playstyle: |cffffffff" .. (PlaystyleLabel(draft.playstyle) or "?") .. "|r")
        or "|cffff5555Playstyle missing|r")
    local req = {}
    local r = (ai and ai.isMythicPlusActivity) and Resolve(draft.rating, MyRating()) or 0
    local il = Resolve(draft.ilvl, MyItemLevel())
    if r > 0 then req[#req + 1] = "rating " .. r end
    if il > 0 then req[#req + 1] = "item level " .. il end
    card.lines[3]:SetText(#req > 0 and ("Requires: |cffffffff" .. table.concat(req, ", ") .. "|r") or "|cff999999No requirements|r")
    local opts = {}
    opts[#opts + 1] = draft.private and "Private" or "Public"
    opts[#opts + 1] = draft.ownFaction and "own faction only" or "cross-faction"
    local look = {}
    if draft.lust then look[#look + 1] = ns.LUST_ICON .. " Lust" end
    if draft.brez then look[#look + 1] = ns.BREZ_ICON .. " Brez" end
    card.lines[4]:SetText("|cff999999" .. table.concat(opts, ", ") .. "|r"
        .. (#look > 0 and ("   |cffffffffLooking for:|r " .. table.concat(look, "  ")) or ""))
end

local function Build()
    P = CreateFrame("Frame", "GottaQueueEmAllCreatePanel", LFGListFrame, "InsetFrameTemplate")
    P:SetWidth(SIDEBAR_W)
    P:EnableMouse(true)
    -- Before any child exists: children take their level from it only once.
    -- Above Blizzard's form (same level as LFGListFrame) and its faded widgets.
    P:SetFrameLevel(LFGListFrame:GetFrameLevel() + 10)
    BuildPresets()
    BuildDungeons()
    BuildStyleAndRequirements()
    BuildBottom()
    BuildCover()
    P:SetScript("OnShow", function() CR.Refresh() end)
    CR.ApplySkin()
    P:Hide()
end

-------------------------------------------------------------------------------
--  Blizzard's form in the larger window
-------------------------------------------------------------------------------
-- Outside the center form (other categories) the fields keep their XML sizes,
-- made for a 338x428 form: they are widened with the window. At stock size
-- every value equals Blizzard's own.
local FORM_W, FORM_H = 338, 428
local DESC_W, DESC_H, DESC_MAX_H = 283, 46, 130
local NAME_W, GROUP_W, ACT_W = 288, 141, 138
local ROW_W, VOICE_W = 296, 125
local ROWS = { "MythicPlusRating", "PVPRating", "ItemLevel", "PvpItemLevel", "VoiceChat", "CrossFactionGroup" }
-- Blizzard widgets our center form replaces: faded out, never hidden.
local FADED = { "NameLabel", "DescriptionLabel", "GroupDropdown", "ActivityDropdown", "PlayStyleDropdown",
                "MythicPlusRating", "PVPRating", "ItemLevel", "PvpItemLevel", "CrossFactionGroup", "PrivateGroup" }
local RAISED = { "Name", "Description", "VoiceChat" }
local formW, formH
local centered, levels = false, {}

-- Frame levels are raised child by child: a parent's new level does not carry
-- over to children that already exist. Originals are kept for LeaveCenter.
local function Raise(f, lvl)
    if levels[f] == nil then levels[f] = f:GetFrameLevel() end
    f:SetFrameLevel(lvl)
    for _, c in ipairs({ f:GetChildren() }) do Raise(c, lvl + 1) end
end

local function StretchForm()
    if not EC or centered or InCombatLockdown() then return end
    local w, h = EC:GetWidth(), EC:GetHeight()
    if not (w and h and w > 0 and h > 0) then return end
    local ew = floor(max(0, w - FORM_W))
    local eh = floor(max(0, h - FORM_H))
    if ew == formW and eh == formH then return end
    formW, formH = ew, eh
    pcall(function()
        EC.Description:SetSize(DESC_W + ew, min(DESC_MAX_H, DESC_H + eh))
        EC.Name:SetWidth(NAME_W + ew)
        EC.GroupDropdown:SetWidth(GROUP_W + floor(ew / 2))
        EC.ActivityDropdown:SetWidth(ACT_W + ew - floor(ew / 2))
        for _, key in ipairs(ROWS) do
            if EC[key] then EC[key]:SetWidth(ROW_W + ew) end
        end
        if EC.VoiceChat and EC.VoiceChat.EditBox then EC.VoiceChat.EditBox:SetWidth(VOICE_W + ew) end
    end)
end

-- Voice chat box width follows the column.
local function SizeColumn2()
    local colW = EC:GetWidth() - COL2_X - 14
    if colW > 0 and EC.VoiceChat.EditBox then EC.VoiceChat.EditBox:SetWidth(max(VOICE_W, colW - 130)) end
end

local function RestoreLevels()
    for f, lvl in pairs(levels) do f:SetFrameLevel(lvl) end
    wipe(levels)
end

-- Blizzard's title / details / voice chat into the right column; everything
-- Blizzard's that we replace fades out under the cover. Anchors only.
local function EnterCenter()
    if centered then return end
    local ok, err = pcall(function()
        Raise(cover, EC:GetFrameLevel() + 6)
        cover:Show()
        for _, key in ipairs(FADED) do EC[key]:SetAlpha(0) end

        -- Title, details (fixed height), voice chat, preview.
        EC.Name:ClearAllPoints()
        EC.Name:SetPoint("TOPLEFT", cover, "TOPLEFT", 14, -22)
        EC.Name:SetPoint("TOPRIGHT", cover, "TOPRIGHT", -18, -22)
        EC.Description:ClearAllPoints()
        EC.Description:SetPoint("TOPLEFT", cover, "TOPLEFT", 13, -81)
        EC.Description:SetPoint("TOPRIGHT", cover, "TOPRIGHT", -18, -81)
        EC.Description:SetHeight(DETAILS_H)
        EC.VoiceChat:ClearAllPoints()
        EC.VoiceChat:SetPoint("TOPLEFT", EC.Description, "BOTTOMLEFT", -5, -12)
        EC.VoiceChat:SetPoint("TOPRIGHT", EC.Description, "BOTTOMRIGHT", 6, -12)
        for _, key in ipairs(RAISED) do Raise(EC[key], cover:GetFrameLevel() + 2) end
        cover.preview:ClearAllPoints()
        cover.preview:SetPoint("TOPLEFT", EC.VoiceChat, "BOTTOMLEFT", 0, -16)
        cover.card:ClearAllPoints()
        cover.card:SetPoint("TOPLEFT", cover.preview, "BOTTOMLEFT", 0, -6)
        cover.card:SetPoint("RIGHT", cover, "RIGHT", -12, 0)

        -- Faded widgets: parked under the cover (behind title and details), so
        -- none sits under our controls or over Blizzard's buttons.
        EC.GroupDropdown:ClearAllPoints()
        EC.GroupDropdown:SetPoint("TOPLEFT", cover, "TOPLEFT", 20, -30)
        EC.PlayStyleDropdown:ClearAllPoints()
        EC.PlayStyleDropdown:SetPoint("TOPLEFT", cover, "TOPLEFT", 20, -60)
        EC.PlayStyleDropdown:SetPoint("TOPRIGHT", cover, "TOPLEFT", 300, -60)
        EC.CrossFactionGroup:ClearAllPoints()
        EC.CrossFactionGroup:SetPoint("TOPLEFT", cover, "TOPLEFT", 20, -170)
        EC.PrivateGroup:ClearAllPoints()
        EC.PrivateGroup:SetPoint("TOPLEFT", cover, "TOPLEFT", 200, -170)
        SizeColumn2()
    end)
    centered = true
    if not ok then ns.Print("could not arrange Blizzard's form (" .. tostring(err) .. ").") end
end

-- Back to Blizzard's XML anchors (LFGList.xml) and sizes.
local function LeaveCenter()
    if not centered then return end
    centered = false
    formW, formH = nil, nil
    pcall(function()
        cover:Hide()
        for _, key in ipairs(FADED) do EC[key]:SetAlpha(1) end
        RestoreLevels()
        EC.GroupDropdown:ClearAllPoints()
        EC.GroupDropdown:SetPoint("TOPLEFT", EC, "TOPLEFT", 19, -76)
        EC.Name:ClearAllPoints()
        EC.Name:SetPoint("TOPLEFT", EC.NameLabel, "BOTTOMLEFT", 5, -5)
        EC.Description:ClearAllPoints()
        EC.Description:SetPoint("TOPLEFT", EC.DescriptionLabel, "BOTTOMLEFT", 5, -10)
        EC.PlayStyleDropdown:ClearAllPoints()
        EC.PlayStyleDropdown:SetPoint("TOPLEFT", EC.Description, "BOTTOMLEFT", -5, -20)
        EC.PlayStyleDropdown:SetPoint("TOPRIGHT", EC.Description, "BOTTOMRIGHT", 5, -20)
        EC.VoiceChat:ClearAllPoints()
        EC.VoiceChat:SetPoint("TOPLEFT", EC.ItemLevel, "BOTTOMLEFT", 0, -3)
        EC.CrossFactionGroup:ClearAllPoints()
        EC.CrossFactionGroup:SetPoint("TOPLEFT", EC.VoiceChat, "BOTTOMLEFT", 0, -3)
        EC.PrivateGroup:ClearAllPoints()
        EC.PrivateGroup:SetPoint("TOPLEFT", EC.VoiceChat, "BOTTOMLEFT", 220, -3)
    end)
    StretchForm()
end

-------------------------------------------------------------------------------
--  Layout
-------------------------------------------------------------------------------
local function Place(f, x, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", P, "TOPLEFT", x, y)
    f:Show()
end

local function PlaceHeader(fs, y)
    Place(fs, PAD, y)
    return y - HEADER_H - 4
end

local function PlaceRequirement(r, y)
    Place(r.label, PAD + 2, y - 5)
    r.box:ClearAllPoints(); r.box:SetPoint("TOPRIGHT", P, "TOPRIGHT", -PAD, y); r.box:Show()
    y = y - BTN_H - 4
    r.minus:SetWidth(COL_W); Place(r.minus, PAD, y)
    r.mine:SetWidth(COL_W);  Place(r.mine, PAD + COL_W + COL_GAP, y)
    return y - BTN_H - 6
end

local function PlaceRow(b1, b2, y)
    local half = floor((INNER_W - 6) / 2)
    b1:ClearAllPoints(); b1:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", PAD, y); b1:SetWidth(b2 and half or INNER_W); b1:Show()
    if b2 then
        b2:ClearAllPoints(); b2:SetPoint("BOTTOMRIGHT", P, "BOTTOMRIGHT", -PAD, y); b2:SetWidth(half); b2:Show()
    end
    return y + BTN_H + 4
end

-- Positions everything for a mode. Touches secure buttons: out of combat only
-- (the main file's ApplyLayout guarantees that).
function CR.Relayout(m)
    if not P or InCombatLockdown() then return end
    m = m or mode
    UpdateTiles()

    -- Where the panel sits
    P:ClearAllPoints()
    if m == "center" then
        P:SetPoint("TOPLEFT", EC, "TOPLEFT", 8, -COVER_TOP)
        P:SetPoint("BOTTOMLEFT", EC, "BOTTOMLEFT", 8, COVER_BOTTOM)
    else
        P:SetPoint("TOPLEFT", LFGListPVEStub, "TOPRIGHT", GAP, -30)
        P:SetPoint("BOTTOMLEFT", LFGListPVEStub, "BOTTOMRIGHT", GAP, 8)
    end

    local y = -PAD
    -- Presets
    y = PlaceHeader(P.hPresets, y)
    Place(P.presetDD, PAD, y)
    y = y - BTN_H - 6
    local pinned = PinnedPresets()
    local bw = floor((INNER_W - (L.QUICK_SLOTS - 1) * 4) / L.QUICK_SLOTS)
    for i, b in ipairs(P.quick) do
        local p = pinned[i]
        b.preset = p
        if p then
            b:SetText(p.name)
            b:SetWidth(bw)
            Place(b, PAD + (i - 1) * (bw + 4), y)
        else
            b:Hide()
        end
    end
    if #pinned > 0 then y = y - BTN_H - 6 end
    if P.editMode then
        P.nameBox:ClearAllPoints()
        P.nameBox:SetPoint("TOPLEFT", P, "TOPLEFT", PAD + 6, y)
        P.nameBox:SetPoint("TOPRIGHT", P, "TOPRIGHT", -PAD - 64, y)
        P.nameBox:Show()
        P.nameOK:SetWidth(58)
        P.nameOK:SetText(P.editMode == "rename" and "Rename" or "Save")
        P.nameOK:ClearAllPoints(); P.nameOK:SetPoint("TOPRIGHT", P, "TOPRIGHT", -PAD, y); P.nameOK:Show()
        y = y - BTN_H - 6
    else
        P.nameBox:Hide(); P.nameOK:Hide()
    end
    y = y - SECTION_GAP

    -- Dungeon: My key, your key, tiles
    P.myKey:ClearAllPoints(); P.myKey:SetPoint("TOPRIGHT", P, "TOPRIGHT", -PAD, y + 1); P.myKey:Show()
    y = PlaceHeader(P.hDungeon, y)
    Place(P.keyHolder, PAD, y)
    P.keyText:ClearAllPoints(); P.keyText:SetPoint("LEFT", P.keyHolder, "RIGHT", 6, 0); P.keyText:Show()
    y = y - 16 - 6
    for i, t in ipairs(P.tiles) do
        if i <= #P.groups then
            local col, row = (i - 1) % 2, floor((i - 1) / 2)
            Place(t, PAD + col * (COL_W + COL_GAP), y - row * (TILE_H + 2))
        end
    end
    y = y - ceil(#P.groups / 2) * (TILE_H + 2) - SECTION_GAP

    -- Difficulty | Playstyle (required by Blizzard), side by side
    local x2 = PAD + COL_W + COL_GAP
    Place(P.hDiff, PAD, y)
    Place(P.hStyle, x2, y)
    Place(P.diffDD, PAD, y - HEADER_H - 4)
    Place(P.styleDD, x2, y - HEADER_H - 4)
    y = y - HEADER_H - 4 - BTN_H - SECTION_GAP

    -- Looking for (only marks applicants)
    y = PlaceHeader(P.hLook, y)
    Place(P.lookLust, PAD, y)
    Place(P.lookBrez, x2, y)
    y = y - CHECK_H - 2 - SECTION_GAP

    -- Requirements and options
    y = PlaceHeader(P.hReq, y)
    y = PlaceRequirement(P.reqRating, y)
    y = PlaceRequirement(P.reqIlvl, y)
    Place(P.optPrivate, PAD, y)
    Place(P.optFaction, PAD + COL_W + COL_GAP, y)
    y = y - CHECK_H - 2

    -- Bottom: buttons of the mode, status line above them
    P.btnRelist:Hide()
    local by = PAD
    if m == "side" then by = PlaceRow(P.btnRelist, nil, by) end
    P.status:ClearAllPoints()
    P.status:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", PAD, by + 2)
    P.status:SetPoint("BOTTOMRIGHT", P, "BOTTOMRIGHT", -PAD, by + 2)
    P.status:SetHeight(STATUS_H)

    CR.contentH = -y
    CR.bottomH = by + STATUS_H + 4
    if m == "center" then
        CR.neededH = CR.contentH + CR.bottomH + COVER_TOP + COVER_BOTTOM + 2
    else
        CR.neededH = CR.contentH + CR.bottomH + L.SIDEBAR_INSET_H
    end
end

-------------------------------------------------------------------------------
--  Refresh (draft -> our controls)
-------------------------------------------------------------------------------
local function Lock(b, locked)
    b.locked = locked
    b:SetEnabled(not locked)
end

-- Mythic+ title without a key level? Blizzard only builds the title ("+12
-- Relaxed") when a keystone for that dungeon is known (yours, or one
-- GetKeystoneForActivity knows); otherwise the level has to be typed.
-- Runs on every keystroke (Blizzard's OnTextChanged validates the form and
-- our UpdateValidState hook refreshes). Returns the hint text or nil.
local function TitleHint(ai)
    if not (ai and ai.isMythicPlusActivity and EC) then return nil end
    local text
    local ok, t = pcall(EC.Name.GetText, EC.Name)
    if ok and type(t) == "string" and not issecretvalue(t) then text = t end
    if text then
        if text:find("%+%s*%d") then return nil end
    elseif Num(C_LFGList.GetKeystoneForActivity and C_LFGList.GetKeystoneForActivity(draft.activity)) then
        return nil   -- title not readable, but Blizzard builds it from the key
    end
    local example = "+12"
    if draft.playstyle then
        example = example .. " " .. (PlaystyleLabel(draft.playstyle) or "")
    end
    return ("Add the key level, e.g. \"%s\""):format(example)
end

function CR.Refresh()
    if not (P and P:IsShown()) then return end
    local lockActivity = (mode == "center" and EditMode())

    -- Presets
    local list = Presets()
    local cur = CurrentPreset()
    ns.SetDropdownText(P.presetDD, cur and cur.name or (#list > 0 and "Custom settings" or "No listing presets yet"))
    for _, b in ipairs(P.quick) do
        if b.preset and PresetMatches(b.preset) then b:LockHighlight() else b:UnlockHighlight() end
    end

    -- Your key
    local keyAct, keyLvl, keyName, keyTex = MyKey()
    local keyGroup = GroupOf(keyAct)
    if keyAct then
        P.keyIcon:SetTexture(keyTex or "Interface\\Icons\\INV_Relics_Hourglass")
        P.keyIcon:SetDesaturated(false)
        P.keyText:SetText(("Your key: |cffffffff%s +%d|r"):format(keyName or "?", keyLvl or 0))
    else
        P.keyIcon:SetTexture("Interface\\Icons\\INV_Relics_Hourglass")
        P.keyIcon:SetDesaturated(true)
        P.keyText:SetText("|cff999999No keystone in your bags|r")
    end
    Lock(P.myKey, lockActivity or not keyAct or draft.activity == keyAct)

    -- Dungeon tiles
    local gid = GroupOf(draft.activity)
    for i = 1, #P.groups do
        local t = P.tiles[i]
        t.selected = (t.groupID == gid)
        t.locked = lockActivity
        t.mine:SetShown(keyGroup ~= nil and t.groupID == keyGroup)
        PaintTile(t)
    end

    -- Difficulty (fixed while editing a listing) and playstyle
    local ai = Info(draft.activity)
    ns.SetDropdownText(P.diffDD, ai and ai.shortName or "|cff999999Pick a dungeon|r")
    P.diffDD:SetEnabled(not lockActivity and #ActivitiesOf(gid) > 0)
    ns.SetDropdownText(P.styleDD, draft.playstyle and PlaystyleLabel(draft.playstyle) or "|cffff5555Required|r")

    -- Looking for
    P.lookLust:SetChecked(draft.lust)
    P.lookBrez:SetChecked(draft.brez)

    -- Requirements (rating only for Mythic+)
    local isMPlus = ai and ai.isMythicPlusActivity or false
    for _, f in ipairs({ P.reqRating.box, P.reqRating.minus, P.reqRating.mine }) do f:SetEnabled(isMPlus) end
    P.reqRating.label:SetAlpha(isMPlus and 1 or 0.4)
    P.reqRating.box.Sync()
    P.reqIlvl.box.Sync()
    P.optPrivate:SetChecked(draft.private)
    P.optFaction:SetChecked(draft.ownFaction)

    -- Status
    local name = ai and (ai.fullName or ai.shortName) or "?"
    if mode == "center" then
        local err = EC.ListGroupButton and EC.ListGroupButton.errorText
        local hint = TitleHint(ai)
        cover.titleWarn:SetText(hint and ("|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14|t |cffffb000" .. hint .. "|r") or "")
        if type(err) == "string" and not issecretvalue(err) and err ~= "" then
            P.status:SetText("|cffffb000" .. err .. "|r")
        elseif hint then
            P.status:SetText("|cffffb000Title has no key level|r  |cff999999- see Title|r")
        elseif EditMode() then
            P.status:SetText("|cff40ff40Editing your listing|r  |cff999999- Done Editing below|r")
        else
            P.status:SetText("|cff40ff40Ready to list|r  |cff999999- List Group below|r")
        end
        RefreshPreview()
    elseif mode == "side" then
        local listed = ListedActivity()
        local otherDungeon = listed and draft.activity and listed ~= draft.activity
        if otherDungeon then
            P.status:SetText("|cffffb000Other dungeon: " .. name .. "|r\n|cff999999Needs Relist; Edit keeps the listed dungeon.|r")
        elseif staged then
            P.status:SetText("|cffffb000Changed|r - click Edit below to apply\n|cff999999(then Done Editing)|r")
        else
            local li = Info(listed)
            P.status:SetText("Listed: |cffffffff" .. (li and (li.fullName or li.shortName) or name) .. "|r\n|cff999999Change here, then Edit below or Relist.|r")
        end
        if not InCombatLockdown() then
            if otherDungeon then P.btnRelist:LockHighlight() else P.btnRelist:UnlockHighlight() end
        end
        -- Blizzard's own Edit button carries the staged changes.
        if staged and not otherDungeon then AV.EditButton:LockHighlight() else AV.EditButton:UnlockHighlight() end
    end
end

-------------------------------------------------------------------------------
--  Applicant list: lust / brez marks (post-hook, like the search rows)
-------------------------------------------------------------------------------
-- Only our own font strings / textures on Blizzard's member rows, kept in an
-- external weak table; the class is read with an issecretvalue guard. Rows
-- that bring something you are looking for get a green tint.
local AFD = setmetatable({}, { __mode = "k" })

local function DecorateMember(member, appID, memberIdx)
    if type(member) ~= "table" or not Num(appID) or not Num(memberIdx) then return end
    local fd = AFD[member]
    local db = ns.DB()
    local _, class = C_LFGList.GetApplicantMemberInfo(appID, memberIdx)
    local lust, brez = false, false
    if type(class) == "string" and not issecretvalue(class) then
        lust, brez = ns.LUST_CLASS[class] or false, ns.BREZ_CLASS[class] or false
    end
    local text = ""
    if db and db.showBadges then
        if lust then text = ns.LUST_ICON end
        if brez then text = text .. (text ~= "" and " " or "") .. ns.BREZ_ICON end
    end
    local wanted = (draft.lust and lust) or (draft.brez and brez)
    if text == "" and not wanted and not fd then return end
    if not fd then
        fd = {}
        fd.badge = member:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fd.badge:SetPoint("RIGHT", member, "LEFT", 101, 0)   -- end of the name column (role icons start at 104)
        fd.tint = member:CreateTexture(nil, "BACKGROUND")
        fd.tint:SetAllPoints()
        fd.tint:SetColorTexture(0.25, 1, 0.25, 0.12)
        AFD[member] = fd
    end
    fd.badge:SetText(text)
    fd.badge:SetShown(text ~= "")
    fd.tint:SetShown(wanted and true or false)
end

local function RefreshApplicants()
    local sb = AV and AV.ScrollBox
    if not (sb and sb.ForEachFrame and AV:IsVisible()) then return end
    sb:ForEachFrame(function(button)
        if type(button.Members) == "table" then
            for _, m in ipairs(button.Members) do
                if m:IsShown() then DecorateMember(m, button.applicantID, m.memberIdx) end
            end
        end
    end)
end

function CR.SetLookingFor(lust, brez)
    draft.lust, draft.brez = lust and true or false, brez and true or false
    local db = ns.DB()
    db.createLust, db.createBrez = draft.lust, draft.brez
    RefreshApplicants()
end

-------------------------------------------------------------------------------
--  Hooks for the main file
-------------------------------------------------------------------------------
local function IsLeader()
    return not IsInGroup() or UnitIsGroupLeader("player")
end

local function ListedDungeon()
    local e = C_LFGList.HasActiveEntryInfo() and C_LFGList.GetActiveEntryInfo()
    if type(e) ~= "table" or issecretvalue(e) then return false end
    local ids = e.activityIDs
    local ai = Info(type(ids) == "table" and not issecretvalue(ids) and ids[1] or e.activityID)
    return ai and ai.categoryID == DUNGEON or false
end

function CR.Mode()
    if not (EC and P) then return nil end
    if EC:IsVisible() then
        return (Num(EC.selectedCategory) == DUNGEON) and "center" or nil
    end
    if AV:IsVisible() and IsLeader() and ListedDungeon() then return "side" end
    return nil
end

function CR.Show(m)
    if not P then return end
    if m ~= mode then
        if m == "center" then EnterCenter() else LeaveCenter() end
        if m == "side" then PullListing(); staged = false end
        if m ~= "side" then AV.EditButton:UnlockHighlight() end
    end
    mode = m
    if not P:IsShown() then P:Show() end
    CR.Refresh()
end

function CR.Hide()
    if P and P:IsShown() then P:Hide() end
    if AV then AV.EditButton:UnlockHighlight() end
    LeaveCenter()
    mode = nil
    StretchForm()
end

function CR.ApplySkin()
    local skin = ns.Skin()
    if not (skin and P) or P.euiSkinned then return end
    P.euiSkinned = true
    skin.Inset(P)
    skin.Panel(P, { inset = true })
end

local function Layout()
    if PVEFrame:IsShown() then applyLayout() end
end

function CR.Init(apply)
    applyLayout = apply
    EC = LFGListFrame and LFGListFrame.EntryCreation
    AV = LFGListFrame and LFGListFrame.ApplicationViewer
    CS = LFGListFrame and LFGListFrame.CategorySelection
    if not (EC and AV and CS) or P then return end
    local db = ns.DB()
    draft.lust, draft.brez = db.createLust or false, db.createBrez or false
    Build()
    if LFGListApplicationViewer_UpdateApplicantMember then
        hooksecurefunc("LFGListApplicationViewer_UpdateApplicantMember", DecorateMember)
    end

    -- The form opened: Blizzard has filled it in (last listing, or your
    -- keystone). A relist fills in the draft instead.
    EC:HookScript("OnShow", function()
        if pendingRelist and not EditMode() then
            pendingRelist = false
            CS.StartGroupButton:UnlockHighlight()
            if Num(EC.selectedCategory) == DUNGEON then Push() end
        elseif staged and EditMode() then
            -- Edit listing after changes in the listed view: they go into
            -- Blizzard's edit form. The dungeon is fixed there (Blizzard
            -- disables it), so a different one stays a relist.
            staged = false
            local want = draft.activity
            Push()
            local listed = Num(EC.selectedActivity)
            if want and listed and want ~= listed then
                local ai = Info(want)
                ns.Print(("Edit keeps the listed dungeon (Blizzard). For %s use \"Relist with these settings\".")
                    :format(ai and (ai.fullName or ai.shortName) or "another dungeon"))
                draft.activity = listed
            end
        else
            PullForm()
        end
        applyLayout()
    end)
    EC:HookScript("OnHide", Layout)
    EC:HookScript("OnSizeChanged", function()
        if centered then SizeColumn2() else StretchForm() end
    end)
    -- The details box's inner edit box is sized once by Blizzard (InputScrollFrame_OnLoad).
    EC.Description:HookScript("OnSizeChanged", function(d, w)
        if w and w > 18 then
            d.EditBox:SetWidth(w - 18)
            if d.EditBox.Instructions then d.EditBox.Instructions:SetWidth(w) end
        end
    end)
    AV:HookScript("OnShow", applyLayout)
    AV:HookScript("OnHide", Layout)
    CS:HookScript("OnShow", applyLayout)
    CS:HookScript("OnHide", Layout)

    -- Blizzard changed the form itself (edit mode, auto keystone, validation).
    if LFGListEntryCreation_Select then
        hooksecurefunc("LFGListEntryCreation_Select", function()
            if not pushing and EC:IsVisible() then PullForm() end
            CR.Refresh()
        end)
    end
    if LFGListEntryCreation_UpdateValidState then
        hooksecurefunc("LFGListEntryCreation_UpdateValidState", function() CR.Refresh() end)
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    f:RegisterEvent("PARTY_LEADER_CHANGED")
    f:SetScript("OnEvent", function(_, event)
        -- Relist: delisted, Blizzard shows its category page. Point at Start a Group.
        if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" and pendingRelist == true and not C_LFGList.HasActiveEntryInfo() then
            pendingRelist = "delisted"   -- still pending (truthy), hint only once
            CS.StartGroupButton:LockHighlight()
            ns.Print("delisted. Click |cffffd100Start a Group|r: the form opens with your settings.")
        end
        -- The panel switch happens in Blizzard's handler of the same event.
        C_Timer.After(0, Layout)
    end)
end
