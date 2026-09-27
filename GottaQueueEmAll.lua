-------------------------------------------------------------------------------
--  GottaQueueEmAll.lua  --  "Gotta Queue 'Em All"
--  Standalone Premade Groups (LFGList) quality of life:
--   - enlarges PVEFrame while the Premade Groups panel is open (more rows,
--     wider rows),
--   - docks a filter sidebar next to the result list that exposes Blizzard's
--     advanced filter (dungeons, roles, rating, difficulty, playstyle,
--     languages) without nested dropdowns,
--   - presets: unlimited in a dropdown, up to QUICK_SLOTS pinned ones as
--     one-click "load and search" buttons,
--   - dungeon tiles with the player's best keystone of the season,
--   - leader M+ score and the leader's best key in the listed dungeon on
--     each row, plus Bloodlust / battle res / declined badges,
--   - client-side fit filters (party fit, lust, brez, not declined) and a
--     leader-best-key range: rows that don't fit are dimmed, never removed,
--   - "N of M match" counter, rarely used filters folded under "More filters".
--
--  A group's title, description and voice chat are secret strings in
--  Midnight (kstringLfgListSearch): addons can show them but not read them,
--  so nothing here parses the title (the key level lives only there).
--
--  Widgets are Blizzard's own templates (UIPanelButtonTemplate,
--  UICheckButtonTemplate, InputBoxTemplate, WowStyle1DropdownTemplate), so
--  the sidebar matches the stock window. When EllesmereUI's Blizzard skin is
--  active, it registers through EllesmereUI's public skinning API
--  (EllesmereUI.RegisterSkin, see EllesmereUI\SKINNING_API.md) and those
--  widgets get the EllesmereUI look. EllesmereUI is optional.
--  Settings live in Blizzard's options (Options > AddOns > Gotta Queue 'Em All).
--
--  Server filtering goes through Blizzard's own API
--  (C_LFGList.Get/SaveAdvancedFilter); the server applies it. Blizzard's
--  filter dropdown and this sidebar always show the same state. The fit
--  filters and the leader-best-key range have no server equivalent: they
--  only dim rows, from values Blizzard hands every addon.
--
--  Taint / secret-value safety (read before editing):
--   - PVEFrame and LFGListPVEStub are PROTECTED (they parent the LFGList
--     applicant viewer, which compares secret values). They are only resized
--     inside a SecureHandler snippet, out of combat.
--   - C_LFGList.Search is restricted. We never call it or
--     LFGListSearchPanel_DoSearch; "Search" and the quick preset buttons are
--     SecureActionButtons that click Blizzard's own RefreshButton, so the
--     search runs in Blizzard's untainted code. (Menu items are not secure,
--     so loading a preset from the dropdown only marks Search as pending.)
--   - The result list is never mutated (no removing entries from
--     SearchPanel.results; it is only read, for the match counter). Rows are
--     only decorated by a post-hook: alpha, widths of their own font
--     strings, and font strings of ours.
--   - Per-row state lives in an external weak table (FFD), never as keys on
--     Blizzard frames. Every value read from GetSearchResultInfo is checked
--     with issecretvalue before any comparison.
-------------------------------------------------------------------------------
local TITLE = "Gotta Queue 'Em All"
-- Shared with GottaQueueEmAll_Create.lua (the Start a Group sidebar). Kept in
-- one table: this file is close to Lua 5.1's 200-locals limit.
local _, ns = ...

local issecretvalue = issecretvalue or function() return false end
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local DUNGEON_CATEGORY = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2

-- Stock geometry (Blizzard_GroupFinder/Mainline/PVEFrame.xml + LFGList.xml)
local BASE_W, BASE_H = 563, 428   -- PVEFrame
local STUB_W         = 338        -- LFGListPVEStub
local RAIL_W         = 224        -- left category rail (stub x offset)

-- Size limits for the settings sliders
local MIN_W, MAX_W = BASE_W + 300, 1800
local MIN_H, MAX_H = BASE_H, 1200

-- Sidebar layout
local SIDEBAR_W   = 290
local GAP         = 8
local PAD         = 10
local COL_GAP     = 6
local COL_W       = floor((SIDEBAR_W - PAD * 2 - COL_GAP) / 2)
local BTN_H       = 22
local CHECK_H     = 20
local TILE_H      = 36
local HEADER_H    = 14
local SECTION_GAP = 6
local BOTTOM_AREA = PAD + 26 + 5 + 14 + 8   -- match counter + Search / Reset under the content
local SIDEBAR_INSET_H = 38                   -- sidebar sits 30px below the stub's top, 8px above its bottom
local QUICK_SLOTS = 3
local MAX_PRESETS = 40
local RATING_MAX  = 9999

local DEFAULTS = {
    enabled         = true,
    width           = 1020,
    height          = 700,
    dimPercent      = 30,
    showLeaderScore = true,
    showDungeonIcon = true,
    showBadges      = true,
    fitParty        = false,
    fitLust         = false,
    fitBrez         = false,
    fitNotDeclined  = false,
    presets         = {},
}

-- Client-side filters stored in db and in presets (not part of Blizzard's filter).
local FIT_KEYS = { "fitParty", "fitLust", "fitBrez", "fitNotDeclined" }

-- Classes that bring Bloodlust / Heroism and a battle res.
local LUST_CLASS = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local BREZ_CLASS = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }
local LUST_ICON  = "|TInterface\\Icons\\Spell_Nature_Bloodlust:14:14:0:0:64:64:5:59:5:59|t"
local BREZ_ICON  = "|TInterface\\Icons\\Spell_Nature_Reincarnation:14:14:0:0:64:64:5:59:5:59|t"
ns.LUST_CLASS, ns.BREZ_CLASS, ns.LUST_ICON, ns.BREZ_ICON = LUST_CLASS, BREZ_CLASS, LUST_ICON, BREZ_ICON

local FILTER_KEYS = {
    "needsTank", "needsHealer", "needsDamage", "needsMyClass", "hasTank", "hasHealer",
    "minimumRating",
    "difficultyNormal", "difficultyHeroic", "difficultyMythic", "difficultyMythicPlus",
    "generalPlaystyle1", "generalPlaystyle2", "generalPlaystyle3", "generalPlaystyle4",
}

local db
local SP                    -- LFGListFrame.SearchPanel
local sidebar
local skin                  -- EllesmereUI skin API table, only while its skin is active
local settingsCategory
local built, enlarged, layoutPending, searchPending = false, false, false, false
local FFD = setmetatable({}, { __mode = "k" })   -- external per-row state

local function Print(msg)
    print("|cffffd100Gotta Queue 'Em All|r " .. msg)
end

-------------------------------------------------------------------------------
--  Widgets: Blizzard templates, handed to the EllesmereUI skin when present
-------------------------------------------------------------------------------
local W = { buttons = {}, checks = {}, edits = {}, dropdowns = {}, texts = {} }

local function Accent()
    if skin then return skin.GetAccentColor() end
    return 1, 0.82, 0          -- Blizzard gold
end

local function ShowTip(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if type(self.tip) == "function" then
        self.tip(GameTooltip)
    else
        GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function HideTip(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function AddTip(frame, tip)
    frame.tip = tip
    frame:HookScript("OnEnter", ShowTip)
    frame:HookScript("OnLeave", HideTip)
end

local function MakeText(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    W.texts[#W.texts + 1] = fs
    if skin then skin.Font(fs) end
    return fs
end

local function MakeButton(parent, text, name, secure)
    -- UIPanelButtonTemplate first so SecureActionButtonTemplate's OnClick wins.
    local b = CreateFrame("Button", name, parent,
        secure and "UIPanelButtonTemplate,SecureActionButtonTemplate" or "UIPanelButtonTemplate")
    b:SetHeight(BTN_H)
    b:SetText(text)
    W.buttons[#W.buttons + 1] = b
    if skin then skin.Button(b); skin.WhiteButtonLabel(b) end
    return b
end

local function MakeCheck(parent, label, onClick, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(CHECK_H, CHECK_H)
    local fs = cb.Text or cb.text or cb:CreateFontString(nil, "OVERLAY")
    -- Fixed gap to the box: the template's own offset is ~1px, which the
    -- EllesmereUI checkbox skin covers completely.
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    fs:SetFontObject(GameFontHighlightSmall)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetWidth(COL_W - CHECK_H - 8)
    fs:SetText(label)
    cb.label = fs
    cb:SetHitRectInsets(0, -(COL_W - CHECK_H), 0, 0)   -- label is clickable too
    cb:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        onClick(self)
    end)
    if tip then AddTip(cb, tip) end
    W.checks[#W.checks + 1] = cb
    if skin then skin.Checkbox(cb); skin.Font(fs) end
    return cb
end

-- Numeric input with an "any" placeholder. commit(number or nil) on Enter /
-- focus loss; get() returns the current value (0 = any).
local function MakeNumberBox(parent, width, maxLetters, get, commit, tip)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width, BTN_H)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(maxLetters)
    eb:SetJustifyH("CENTER")
    local ph = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("CENTER")
    ph:SetText("any")
    eb.placeholder = ph
    local function UpdatePH()
        ph:SetShown(eb:GetText() == "" and not eb:HasFocus())
    end
    function eb.Sync()
        if eb:HasFocus() then return end
        local v = get()
        eb:SetText(v > 0 and tostring(v) or "")
        UpdatePH()
    end
    local cancelled = false
    eb:SetScript("OnEditFocusGained", function() cancelled = false; ph:Hide(); eb:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function()
        if not cancelled then commit(tonumber(eb:GetText())) end
        cancelled = false
        eb.Sync()
    end)
    eb:SetScript("OnEnterPressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function() cancelled = true; eb:ClearFocus() end)
    eb:SetScript("OnTextChanged", UpdatePH)
    if tip then AddTip(eb, tip) end
    W.edits[#W.edits + 1] = eb
    if skin then skin.EditBox(eb) end
    return eb
end

local function MakeDropdown(parent, width)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(width)
    W.dropdowns[#W.dropdowns + 1] = dd
    if skin then skin.Dropdown(dd) end
    return dd
end

local function SetDropdownText(dd, text)
    if dd.OverrideText then dd:OverrideText(text)
    elseif dd.SetDefaultText then dd:SetDefaultText(text) end
end

-- 1px border from four textures (PixelUtil keeps it crisp at any UI scale).
local function CreateBorder(f, layer)
    local b = {}
    for i = 1, 4 do b[i] = f:CreateTexture(nil, layer or "BORDER") end
    b[1]:SetPoint("TOPLEFT");    b[1]:SetPoint("TOPRIGHT");    PixelUtil.SetHeight(b[1], 1)
    b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); PixelUtil.SetHeight(b[2], 1)
    b[3]:SetPoint("TOPLEFT");    b[3]:SetPoint("BOTTOMLEFT");  PixelUtil.SetWidth(b[3], 1)
    b[4]:SetPoint("TOPRIGHT");   b[4]:SetPoint("BOTTOMRIGHT"); PixelUtil.SetWidth(b[4], 1)
    f.borderTex = b
end

local function SetBorderColor(f, r, g, b, a)
    for _, t in ipairs(f.borderTex) do t:SetColorTexture(r, g, b, a) end
end

-- Building blocks for GottaQueueEmAll_Create.lua: same widgets, same skin.
ns.TITLE, ns.W, ns.Print = TITLE, W, Print
ns.AddTip, ns.ShowTip, ns.HideTip = AddTip, ShowTip, HideTip
ns.MakeText, ns.MakeButton, ns.MakeCheck = MakeText, MakeButton, MakeCheck
ns.MakeNumberBox, ns.MakeDropdown, ns.SetDropdownText = MakeNumberBox, MakeDropdown, SetDropdownText
ns.Accent, ns.CreateBorder, ns.SetBorderColor = Accent, CreateBorder, SetBorderColor
ns.L = { SIDEBAR_W = SIDEBAR_W, GAP = GAP, PAD = PAD, COL_W = COL_W, COL_GAP = COL_GAP, BTN_H = BTN_H,
         CHECK_H = CHECK_H, HEADER_H = HEADER_H, SECTION_GAP = SECTION_GAP, QUICK_SLOTS = QUICK_SLOTS,
         MAX_PRESETS = MAX_PRESETS, BOTTOM_AREA = BOTTOM_AREA, SIDEBAR_INSET_H = SIDEBAR_INSET_H,
         DUNGEON_CATEGORY = DUNGEON_CATEGORY }
function ns.DB() return db end
function ns.Skin() return skin end

-- Secure buttons click Blizzard's RefreshButton (attributes set once, out of combat).
local function MakeSearchClicker(btn)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "click")
    btn:SetAttribute("clickbutton", SP.RefreshButton)
end

-------------------------------------------------------------------------------
--  Secure resize (protected frames only inside a restricted snippet)
-------------------------------------------------------------------------------
local secureSizer = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local resizeWarned = false

local function SecureSize(frame, w, h)
    if not frame then return end
    if math.abs(frame:GetWidth() - w) < 0.5 and math.abs(frame:GetHeight() - h) < 0.5 then return end
    if not frame:IsProtected() then frame:SetSize(w, h); return end
    if InCombatLockdown() then layoutPending = true; return end
    secureSizer:SetFrameRef("f", frame)
    secureSizer:SetAttribute("w", w)
    secureSizer:SetAttribute("h", h)
    local ok, err = pcall(secureSizer.Execute, secureSizer, [[
        local f = self:GetFrameRef("f")
        if not f then return end
        f:SetWidth(self:GetAttribute("w"))
        f:SetHeight(self:GetAttribute("h"))
    ]])
    if not ok and not resizeWarned then
        resizeWarned = true
        Print("could not resize the window (" .. tostring(err) .. ")")
    end
end

-------------------------------------------------------------------------------
--  Filter helpers (Blizzard advanced filter)
-------------------------------------------------------------------------------
local function IsDungeonCategory()
    return SP and SP.categoryID == DUNGEON_CATEGORY
end

local function CopyFilter(f)
    local c = {}
    for _, k in ipairs(FILTER_KEYS) do c[k] = f[k] end
    c.activities = {}
    for i, v in ipairs(f.activities or {}) do c.activities[i] = v end
    return c
end

local function CopyTable(t)
    if type(t) ~= "table" then return nil end
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local function ActivitySet(f)
    local set = {}
    for _, id in ipairs(f.activities or {}) do set[id] = true end
    return set
end

local function SetToList(set)
    local list = {}
    for id in pairs(set) do list[#list + 1] = id end
    table.sort(list)
    return list
end

local function LanguagesAvailable()
    if not (C_LFGList.GetAvailableLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter) then return false end
    if LFGListCanChangeLanguages then return LFGListCanChangeLanguages() and true or false end
    return true
end

local RefreshUI, RefreshRows, Relayout, ApplyLayout   -- forward

local function MarkPending()
    searchPending = true
    if sidebar and sidebar.search then sidebar.search:LockHighlight() end
end

local function SaveFilter(f)
    C_LFGList.SaveAdvancedFilter(f)
    MarkPending()
    RefreshUI()
end

local function ToggleFilterKey(key)
    local f = C_LFGList.GetAdvancedFilter()
    f[key] = not f[key]
    SaveFilter(f)
end

-- Same values Blizzard's filter reset button writes.
local function ResetFilter()
    local f = C_LFGList.GetAdvancedFilter()
    f.needsTank, f.needsHealer, f.needsDamage, f.needsMyClass = false, false, false, false
    f.hasTank, f.hasHealer = false, false
    f.minimumRating = 0
    f.difficultyNormal, f.difficultyHeroic, f.difficultyMythic, f.difficultyMythicPlus = true, true, true, true
    f.generalPlaystyle1, f.generalPlaystyle2, f.generalPlaystyle3, f.generalPlaystyle4 = true, true, true, true
    f.activities = {}
    for _, k in ipairs(FIT_KEYS) do db[k] = false end
    SaveFilter(f)
    RefreshRows()
end

-------------------------------------------------------------------------------
--  Dungeons: season groups + the player's best keystone per dungeon
-------------------------------------------------------------------------------
local challengeByInstance, challengeByName = {}, {}
local challengeByActivity = {}   -- activityID -> challenge map ID, or false

local function BuildChallengeLookup()
    wipe(challengeByInstance); wipe(challengeByName); wipe(challengeByActivity)
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return end
    for _, cid in ipairs(C_ChallengeMode.GetMapTable() or {}) do
        local name, _, _, _, _, instanceMapID = C_ChallengeMode.GetMapUIInfo(cid)
        if name then challengeByName[name] = cid end
        if instanceMapID then challengeByInstance[instanceMapID] = cid end
    end
end

local function ChallengeMapForGroup(groupID, groupName)
    if C_LFGList.GetAvailableActivities then
        for _, act in ipairs(C_LFGList.GetAvailableActivities(DUNGEON_CATEGORY, groupID) or {}) do
            local ai = C_LFGList.GetActivityInfoTable(act)
            local cid = ai and ai.mapID and challengeByInstance[ai.mapID]
            if cid then return cid end
        end
    end
    return challengeByName[groupName]
end

-- Challenge map of a Mythic+ activity (search result rows), cached.
local function ChallengeForActivity(act, ai)
    local c = challengeByActivity[act]
    if c ~= nil then return c or nil end
    if not next(challengeByName) then BuildChallengeLookup() end
    local cid
    if ai and ai.isMythicPlusActivity then
        cid = ai.mapID and challengeByInstance[ai.mapID]
        if not cid and ai.groupFinderActivityGroupID then
            local gname = C_LFGList.GetActivityGroupInfo(ai.groupFinderActivityGroupID)
            cid = gname and not issecretvalue(gname) and challengeByName[gname]
        end
    end
    challengeByActivity[act] = cid or false
    return cid or nil
end

-- Keystone number colors: Blizzard's rarity colors (Mythic+ tab), gray when
-- the best run was over time.
local function ColorKeyText(fs, level, timed)
    local col = C_ChallengeMode.GetKeystoneLevelRarityColor and C_ChallengeMode.GetKeystoneLevelRarityColor(level)
    if not timed then fs:SetTextColor(0.6, 0.6, 0.6)
    elseif col then fs:SetTextColor(col.r, col.g, col.b)
    else fs:SetTextColor(1, 1, 1) end
end

-- level, inTime (bool), score or nil
local function BestKey(cid)
    if not (cid and C_MythicPlus and C_MythicPlus.GetSeasonBestForMap) then return end
    local inTime, overTime = C_MythicPlus.GetSeasonBestForMap(cid)
    local level, timed
    if inTime and inTime.level then level, timed = inTime.level, true end
    if overTime and overTime.level and (not level or overTime.level > level) then level, timed = overTime.level, false end
    local score
    if C_MythicPlus.GetSeasonBestAffixScoreInfoForMap then
        local _, bonus = C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(cid)
        if type(bonus) == "number" and bonus > 0 then score = bonus end
    end
    return level, timed, score
end

ns.BestKey, ns.ColorKeyText = BestKey, ColorKeyText

function ns.SeasonGroups()
    local out = {}
    if not (Enum and Enum.LFGListFilter) then return out end
    BuildChallengeLookup()
    local flags = bit.bor(Enum.LFGListFilter.CurrentSeason, Enum.LFGListFilter.PvE)
    for _, id in ipairs(C_LFGList.GetAvailableActivityGroups(DUNGEON_CATEGORY, flags) or {}) do
        local name = C_LFGList.GetActivityGroupInfo(id)
        if name and not issecretvalue(name) then
            out[#out + 1] = { id = id, name = name, cid = ChallengeMapForGroup(id, name) }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-------------------------------------------------------------------------------
--  Presets
-------------------------------------------------------------------------------
local function CurrentPresetData(name)
    local p = {
        name   = name,
        filter = CopyFilter(C_LFGList.GetAdvancedFilter()),
        fit    = {},
    }
    for _, k in ipairs(FIT_KEYS) do p.fit[k] = db[k] or false end
    if LanguagesAvailable() then p.languages = CopyTable(C_LFGList.GetLanguageSearchFilter()) end
    return p
end

-- Presets saved before the fit filters existed count as "all off".
local function PresetFit(p, k)
    return type(p.fit) == "table" and p.fit[k] or false
end

local function FiltersEqual(a, b)
    for _, k in ipairs(FILTER_KEYS) do
        if (a[k] or false) ~= (b[k] or false) then return false end
    end
    local sa, sb = ActivitySet(a), ActivitySet(b)
    for id in pairs(sa) do if not sb[id] then return false end end
    for id in pairs(sb) do if not sa[id] then return false end end
    return true
end

local function PresetMatches(p)
    for _, k in ipairs(FIT_KEYS) do
        if PresetFit(p, k) ~= (db[k] or false) then return false end
    end
    return FiltersEqual(p.filter, C_LFGList.GetAdvancedFilter())
end

local function CurrentPreset()
    for _, p in ipairs(db.presets) do
        if PresetMatches(p) then return p end
    end
end

local function PinnedPresets()
    local out = {}
    for _, p in ipairs(db.presets) do
        if p.pinned then out[#out + 1] = p end
        if #out == QUICK_SLOTS then break end
    end
    return out
end

local function ApplyPreset(p)
    local f = C_LFGList.GetAdvancedFilter()
    for _, k in ipairs(FILTER_KEYS) do f[k] = p.filter[k] end
    f.activities = {}
    for i, v in ipairs(p.filter.activities or {}) do f.activities[i] = v end
    C_LFGList.SaveAdvancedFilter(f)
    if p.languages and LanguagesAvailable() then
        C_LFGList.SaveLanguageSearchFilter(CopyTable(p.languages))
    end
    for _, k in ipairs(FIT_KEYS) do db[k] = PresetFit(p, k) end
    RefreshUI()
    RefreshRows()
end

-- Quick bar buttons are secure: re-layout only out of combat, else after it.
local function PresetsChanged()
    if InCombatLockdown() then layoutPending = true else Relayout() end
    RefreshUI()
end

local function FindPreset(name)
    for i, p in ipairs(db.presets) do
        if p.name == name then return p, i end
    end
end

-------------------------------------------------------------------------------
--  Fit evaluation (client side; only reads what Blizzard gives every addon)
-------------------------------------------------------------------------------
local canaccesstable = canaccesstable or function() return true end

local function Readable(v) return v ~= nil and not issecretvalue(v) end
local function Accessible(t) return type(t) == "table" and not issecretvalue(t) and canaccesstable(t) end
local function Num(v) return type(v) == "number" and not issecretvalue(v) and v or nil end

local ROLE_REMAINING = { TANK = "TANK_REMAINING", HEALER = "HEALER_REMAINING", DAMAGER = "DAMAGER_REMAINING" }
local ACTIVE_APP = { applied = true, invited = true, inviteaccepted = true }
local DECLINED   = { declined = true, declined_delisted = true, declined_full = true }

-- The player's own group: roles it needs and what it already brings. Cached
-- until the roster or the spec changes.
local party
local function PlayerRole()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local spec = getSpec and getSpec()
    local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
    if role == "TANK" or role == "HEALER" then return role end
    return "DAMAGER"
end

local function Party()
    if party then return party end
    local p = { roles = { TANK = 0, HEALER = 0, DAMAGER = 0 }, lust = false, brez = false }
    local function Add(unit, role)
        if not Readable(role) or (role ~= "TANK" and role ~= "HEALER") then role = "DAMAGER" end
        p.roles[role] = p.roles[role] + 1
        local _, class = UnitClass(unit)
        if Readable(class) then
            if LUST_CLASS[class] then p.lust = true end
            if BREZ_CLASS[class] then p.brez = true end
        end
    end
    local n = GetNumGroupMembers()
    if n == 0 then
        Add("player", PlayerRole())
    elseif IsInRaid() then
        for i = 1, n do Add("raid" .. i, UnitGroupRolesAssigned("raid" .. i)) end
    else
        Add("player", UnitGroupRolesAssigned("player"))
        for i = 1, n - 1 do Add("party" .. i, UnitGroupRolesAssigned("party" .. i)) end
    end
    party = p
    return p
end

-- Raw facts per listing, cached until the listing or the search changes.
-- The pass/fail answer is not cached: it depends on the current toggles.
local facts = {}

local function Facts(id)
    local e = facts[id]
    if e then return e end
    e = {}
    facts[id] = e
    local info = C_LFGList.GetSearchResultInfo(id)
    if not Accessible(info) then return e end

    local ids = info.activityIDs
    local act = Accessible(ids) and ids[1]
    local ai = Readable(act) and C_LFGList.GetActivityInfoTable(act)
    e.mplus = Accessible(ai) and ai.isMythicPlusActivity and true or false

    local n = Num(info.numMembers) or 0
    for i = 1, n do
        local pi = C_LFGList.GetSearchResultPlayerInfo(id, i)
        local class = Accessible(pi) and pi.classFilename
        if Readable(class) then
            if LUST_CLASS[class] then e.lust = true end
            if BREZ_CLASS[class] then e.brez = true end
        end
    end

    local mc = C_LFGList.GetSearchResultMemberCounts(id)
    if Accessible(mc) then
        e.left = { TANK = Num(mc.TANK_REMAINING), HEALER = Num(mc.HEALER_REMAINING), DAMAGER = Num(mc.DAMAGER_REMAINING) }
    end

    -- Declined: this session's application status, or Blizzard's own decline list.
    local _, status, pending = C_LFGList.GetApplicationInfo(id)
    if Readable(status) then
        e.activeApp = ACTIVE_APP[status] or false
        e.declined = DECLINED[status] or false
    end
    if Readable(pending) and pending then e.activeApp = true end
    local guid = info.partyGUID
    if not e.declined and Readable(guid) and LFGListFrame and type(LFGListFrame.declines) == "table"
       and LFGListFrame.declines[guid] then
        e.declined = true
    end

    -- Leader's best run in the listed dungeon this season (not the key being listed).
    local si = info.leaderDungeonScoreInfo
    local s = Accessible(si) and si[1]
    if Accessible(s) then
        e.key = Num(s.bestRunLevel)
        e.timed = Readable(s.finishedSuccess) and s.finishedSuccess and true or false
    end
    return e
end

local function InvalidateFacts(id)
    if id then facts[id] = nil else wipe(facts) end
end

-- Would a role still be free after the player's group joined?
local function SlotAfterJoin(e, role)
    local left = e.left and e.left[role]
    return left == nil or left - Party().roles[role] > 0
end

local FIT = {}

function FIT.fitParty(e)
    if not e.left then return true end
    for role in pairs(ROLE_REMAINING) do
        local left = e.left[role]
        if left and left < Party().roles[role] then return false end
    end
    return true
end

-- Bringing lust yourself: groups without one. Otherwise: groups that have one
-- or still have a healer / dps spot after you join.
function FIT.fitLust(e)
    if Party().lust then return not e.lust end
    return e.lust or SlotAfterJoin(e, "HEALER") or SlotAfterJoin(e, "DAMAGER")
end

function FIT.fitBrez(e)
    if Party().brez then return not e.brez end
    return e.brez or SlotAfterJoin(e, "TANK") or SlotAfterJoin(e, "HEALER") or SlotAfterJoin(e, "DAMAGER")
end

function FIT.fitNotDeclined(e)
    return not e.declined
end

local function ClientFiltersActive()
    for _, k in ipairs(FIT_KEYS) do if db[k] then return true end end
    return false
end

local function Passes(e)
    for _, k in ipairs(FIT_KEYS) do
        if db[k] and not FIT[k](e) then return false end
    end
    return true
end

-- "N of M match" under the sidebar. Reads SearchPanel.results, never writes it.
local function UpdateMatchCount()
    if not (sidebar and sidebar.matchText and sidebar:IsShown()) then return end
    local results = SP and SP.results
    if not Accessible(results) or #results == 0 then
        sidebar.matchText:SetText("")
        return
    end
    if not ClientFiltersActive() then
        sidebar.matchText:SetText(("%d groups"):format(#results))
        return
    end
    local n = 0
    for _, id in ipairs(results) do
        if Readable(id) then
            local e = Facts(id)
            if e.activeApp or Passes(e) then n = n + 1 end
        end
    end
    sidebar.matchText:SetText(("%d of %d groups match"):format(n, #results))
end

-- LFG_LIST_SEARCH_RESULT_UPDATED can fire in bursts: one count per burst.
local countQueued = false
local function QueueMatchCount()
    if countQueued then return end
    countQueued = true
    C_Timer.After(0.2, function()
        countQueued = false
        UpdateMatchCount()
    end)
end

local function KeyColorCode(level, timed)
    if not timed then return "ff999999" end
    local col = C_ChallengeMode.GetKeystoneLevelRarityColor and C_ChallengeMode.GetKeystoneLevelRarityColor(level)
    return col and col.GenerateHexColor and col:GenerateHexColor() or "ffffffff"
end

-------------------------------------------------------------------------------
--  Row decoration (post-hook on LFGListSearchEntry_Update)
-------------------------------------------------------------------------------

local ROW_ICON   = 38    -- dungeon icon at the left edge of a result row
local NAME_X     = 10    -- Blizzard's Name anchor: TOPLEFT (10, -6)
local NAME_SHIFT = ROW_ICON + 8

-- Dungeon icon with the player's season best on it, at the row's left edge.
-- Name is only re-anchored (SetPoint on its single TOPLEFT point), never
-- resized or read: it carries the secret group title.
local function SetRowIcon(row, fd, cid)
    if cid then
        if not fd.icon then
            local ic = row:CreateTexture(nil, "ARTWORK")
            ic:SetSize(ROW_ICON, ROW_ICON)
            ic:SetPoint("LEFT", row, "LEFT", 8, 0)
            ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local edge = row:CreateTexture(nil, "BORDER")
            edge:SetColorTexture(0, 0, 0, 0.85)
            edge:SetPoint("TOPLEFT", ic, "TOPLEFT", -1, 1)
            edge:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 1, -1)
            local key = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            key:SetPoint("BOTTOM", ic, "BOTTOM", 0, 2)
            fd.icon, fd.iconEdge, fd.iconKey = ic, edge, key
        end
        fd.icon:SetTexture(select(4, C_ChallengeMode.GetMapUIInfo(cid)) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local level, timed = BestKey(cid)
        if level then
            fd.iconKey:SetText("+" .. level)
            ColorKeyText(fd.iconKey, level, timed)
            fd.iconKey:Show()
        else
            fd.iconKey:Hide()
        end
        fd.icon:Show(); fd.iconEdge:Show()
        if not fd.shifted and row.Name then
            row.Name:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_X + NAME_SHIFT, -6)
            fd.shifted = true
        end
    else
        if fd.icon then fd.icon:Hide(); fd.iconEdge:Hide(); fd.iconKey:Hide() end
        if fd.shifted and row.Name then
            row.Name:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_X, -6)
            fd.shifted = false
        end
    end
end

local function DecorateRow(row)
    if type(row) ~= "table" or type(row.resultID) ~= "number" then return end
    local fd = FFD[row]
    if not fd then fd = {}; FFD[row] = fd end
    local on = db and db.enabled and enlarged

    local alpha, score, cid, e = 1, nil, nil, nil
    if on and IsDungeonCategory() then
        local id = row.resultID
        local info = C_LFGList.GetSearchResultInfo(id)
        if Accessible(info) then
            local ids = info.activityIDs
            local act = type(ids) == "table" and not issecretvalue(ids) and ids[1]
            local ai = act and not issecretvalue(act) and C_LFGList.GetActivityInfoTable(act)
            local isMPlus = ai and ai.isMythicPlusActivity
            if isMPlus and db.showDungeonIcon then cid = ChallengeForActivity(act, ai) end
            -- Leader score, M+ listings only.
            local s = info.leaderOverallDungeonScore
            if isMPlus and db.showLeaderScore and s and not issecretvalue(s) and s > 0 then score = s end
            -- Fit filters / leader key range: dim, never while an application is running.
            e = Facts(id)
            if ClientFiltersActive() and not e.activeApp and not Passes(e) then
                alpha = db.dimPercent / 100
            end
        end
    end
    row:SetAlpha(alpha)
    SetRowIcon(row, fd, cid)

    -- Badges bottom right, under Blizzard's role icons: lust, brez, declined.
    local badge = ""
    if e and db.showBadges then
        if e.lust then badge = badge .. LUST_ICON end
        if e.brez then badge = badge .. (badge ~= "" and " " or "") .. BREZ_ICON end
        if e.declined then badge = badge .. (badge ~= "" and "  " or "") .. "|cffff5555declined|r" end
    end
    if badge ~= "" then
        if not fd.badge then
            fd.badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            if skin then skin.Font(fd.badge) end
            fd.badge:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 5)
            fd.badge:SetJustifyH("RIGHT")
        end
        fd.badge:SetText(badge)
        fd.badge:Show()
    elseif fd.badge then
        fd.badge:Hide()
    end

    -- Wider activity line now that the row is wider (Blizzard caps it at 176).
    -- row.Name is never resized: it holds the secret group title, and
    -- resizing it from addon code made it disappear.
    if on and row.ActivityName then
        local extra = LFGListPVEStub:GetWidth() - STUB_W - (fd.shifted and NAME_SHIFT or 0)
        if extra > 1 then row.ActivityName:SetWidth(176 + extra) end
    end

    if score then
        if not fd.score then
            fd.score = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            if skin then skin.Font(fd.score) end
            fd.score:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -5)
        end
        local r, g, b = 1, 1, 1
        local col = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
                    and C_ChallengeMode.GetDungeonScoreRarityColor(score)
        if col then r, g, b = col.r, col.g, col.b end
        -- Leader's best key in this dungeon next to the score (gray = over time).
        local text = tostring(floor(score))
        if e and e.key and e.key > 0 then
            text = text .. ("  |c%s+%d|r"):format(KeyColorCode(e.key, e.timed), e.key)
        end
        fd.score:SetText(text)
        fd.score:SetTextColor(r, g, b)
        fd.score:Show()
    elseif fd.score then
        fd.score:Hide()
    end
end

RefreshRows = function()
    if SP and SP.ScrollBox and SP.ScrollBox.ForEachFrame then
        SP.ScrollBox:ForEachFrame(DecorateRow)
    end
    UpdateMatchCount()
end

-- One listing changed: Blizzard may have redrawn its row before our cache was
-- cleared, so decorate just that row again.
local function RefreshRow(id)
    if SP and SP.ScrollBox and SP.ScrollBox.ForEachFrame then
        SP.ScrollBox:ForEachFrame(function(row)
            if row.resultID == id then DecorateRow(row) end
        end)
    end
end

-------------------------------------------------------------------------------
--  Settings (Blizzard options: Options > AddOns > Gotta Queue 'Em All)
-------------------------------------------------------------------------------
local function OpenSettings()
    if InCombatLockdown() then Print("settings can't be opened in combat."); return end
    if settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    end
end

local function RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local cat, layout = Settings.RegisterVerticalLayoutCategory(TITLE)

    local function Header(text)
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    local function Register(key, name, varType, onChange)
        local var = "GottaQueueEmAll_" .. key
        local s = Settings.RegisterAddOnSetting(cat, var, key, db, varType, name, DEFAULTS[key])
        if onChange then Settings.SetOnValueChangedCallback(var, function() onChange() end) end
        return s
    end

    local function Checkbox(key, name, tip, onChange)
        Settings.CreateCheckbox(cat, Register(key, name, "boolean", onChange), tip)
    end

    local function Slider(key, name, lo, hi, step, tip, onChange)
        local opts = Settings.CreateSliderOptions(lo, hi, step)
        if MinimalSliderWithSteppersMixin then
            opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
        Settings.CreateSlider(cat, Register(key, name, "number", onChange), opts, tip)
    end

    local function Relaid() ApplyLayout() end

    Header("Premade Groups window")
    Checkbox("enabled", "Enable",
        "Enlarges the Premade Groups window and docks the filter sidebar next to the result list.\n\nOff: Blizzard's window stays untouched.",
        Relaid)
    Slider("width", "Window width", MIN_W, MAX_W, 10,
        "Width of the window while Premade Groups is open. Applied out of combat.", Relaid)
    Slider("height", "Window height", MIN_H, MAX_H, 10,
        "Height of the window while Premade Groups is open. Applied out of combat.", Relaid)

    Header("Result rows")
    Checkbox("showDungeonIcon", "Dungeon icon on rows",
        "Shows the dungeon's icon at the left of each Mythic+ listing, with your season best in that dungeon on it (Blizzard's keystone colors, gray = over time).",
        function() RefreshRows() end)
    Checkbox("showLeaderScore", "Leader score on rows",
        "Shows the group leader's Mythic+ rating in the top right corner of each Mythic+ listing, in its rarity color, followed by the leader's best key in that dungeon this season (gray = over time).",
        function() RefreshRows() end)
    Checkbox("showBadges", "Lust / brez / declined badges",
        "Shows a Bloodlust and a battle res icon at the bottom right of a listing when someone in it brings one, and \"declined\" when the group declined you.",
        function() RefreshRows() end)
    Slider("dimPercent", "Opacity of non-matching groups", 0, 100, 5,
        "Opacity of listings that don't match the sidebar's fit filters or the leader's best key range. They are dimmed, never removed from Blizzard's list.\n\n0 = invisible, 100 = no dimming.",
        function() RefreshRows() end)

    if layout and CreateSettingsButtonInitializer then
        Header("Presets")
        layout:AddInitializer(CreateSettingsButtonInitializer("Saved presets", "Delete all", function()
            wipe(db.presets)
            if sidebar then PresetsChanged() end
            Print("all presets deleted.")
        end, "Deletes every saved preset. Single presets: sidebar > preset menu > Delete.", true))
    end

    Settings.RegisterAddOnCategory(cat)
    settingsCategory = cat
end

-------------------------------------------------------------------------------
--  Sidebar
-------------------------------------------------------------------------------
local function CreateHeader(text)
    local fs = MakeText(sidebar, "GameFontNormal")
    fs:SetText(text)
    return fs
end

local function PlaceHeader(fs, y)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", sidebar, "TOPLEFT", PAD, y)
    fs:Show()
    return y - HEADER_H - 4
end

-- Two-column grid of frames (checkboxes / tiles). Returns new y.
local function Grid(list, y, rowH)
    local i = 0
    for _, f in ipairs(list) do
        if f.gridShown ~= false then
            local col, row = i % 2, floor(i / 2)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", sidebar, "TOPLEFT", PAD + col * (COL_W + COL_GAP), y - row * (rowH + 2))
            f:Show()
            i = i + 1
        else
            f:Hide()
        end
    end
    return y - ceil(i / 2) * (rowH + 2)
end

-- Preset name editor (new / rename), shown inline under the preset row.
local function StartNameEdit(mode, target)
    if InCombatLockdown() then Print("presets can't be edited in combat."); return end
    local S = sidebar
    S.editMode, S.editTarget = mode, target
    Relayout()
    S.nameBox:SetText(mode == "rename" and target.name or "")
    S.nameBox:SetFocus()
    S.nameBox:HighlightText()
end

local function CommitNameEdit()
    local S = sidebar
    local name = strtrim(S.nameBox:GetText() or "")
    local mode, target = S.editMode, S.editTarget
    S.editMode, S.editTarget = nil, nil
    S.nameBox:ClearFocus()
    if name ~= "" then
        local existing = FindPreset(name)
        if mode == "rename" and target then
            if existing and existing ~= target then
                Print("a preset named \"" .. name .. "\" already exists.")
            else
                target.name = name
            end
        elseif existing then
            local keepPin = existing.pinned
            local p = CurrentPresetData(name)
            p.pinned = keepPin
            local _, idx = FindPreset(name)
            db.presets[idx] = p
            Print("updated \"" .. name .. "\".")
        elseif #db.presets >= MAX_PRESETS then
            Print("maximum of " .. MAX_PRESETS .. " presets reached.")
        else
            db.presets[#db.presets + 1] = CurrentPresetData(name)
        end
    end
    PresetsChanged()
end

local function SetupPresetMenu(dd)
    dd:SetupMenu(function(_, root)
        if #db.presets == 0 then
            root:CreateTitle("No presets yet")
        end
        for _, p in ipairs(db.presets) do
            local label = p.pinned and ("|A:auctionhouse-icon-favorite:12:12|a " .. p.name) or p.name
            root:CreateRadio(label, function() return PresetMatches(p) end, function()
                ApplyPreset(p); MarkPending()
            end)
        end
        root:CreateDivider()
        root:CreateButton("Save current filter as new preset...", function() StartNameEdit("new") end)
        local cur = CurrentPreset()
        if cur then
            local sub = root:CreateButton("Manage \"" .. cur.name .. "\"")
            sub:CreateCheckbox("Pin to quick bar", function() return cur.pinned end, function()
                if not cur.pinned and #PinnedPresets() >= QUICK_SLOTS then
                    Print("the quick bar holds " .. QUICK_SLOTS .. " presets; unpin one first.")
                    return
                end
                cur.pinned = not cur.pinned
                PresetsChanged()
            end)
            sub:CreateButton("Rename...", function() StartNameEdit("rename", cur) end)
            local del = sub:CreateButton("Delete")
            del:CreateButton("|cffff5555Delete \"" .. cur.name .. "\"|r", function()
                if InCombatLockdown() then Print("presets can't be edited in combat."); return end
                local _, idx = FindPreset(cur.name)
                if idx then table.remove(db.presets, idx) end
                PresetsChanged()
            end)
        end
    end)
end

local function BuildPresetSection()
    local S = sidebar
    S.hPresets = CreateHeader("Presets")

    S.presetDD = MakeDropdown(S, SIDEBAR_W - PAD * 2)
    SetupPresetMenu(S.presetDD)

    S.quick = {}
    for i = 1, QUICK_SLOTS do
        local b = MakeButton(S, "", "GottaQueueEmAllQuick" .. i, true)
        MakeSearchClicker(b)
        b:SetScript("PreClick", function(self, button)
            if button ~= "LeftButton" or not self.preset then return end
            local now = GetTime()
            if self.lastApply and now - self.lastApply < 0.4 then return end
            self.lastApply = now
            ApplyPreset(self.preset)
        end)
        AddTip(b, function(tt)
            tt:SetText(b.preset and b.preset.name or "", 1, 1, 1)
            tt:AddLine("Click: load and search", 0.8, 0.8, 0.8)
        end)
        b:Hide()
        S.quick[i] = b
    end

    local box = CreateFrame("EditBox", "GottaQueueEmAllPresetName", S, "InputBoxTemplate")
    box:SetHeight(BTN_H)
    box:SetAutoFocus(false)
    box:SetMaxLetters(32)
    box:SetScript("OnEnterPressed", CommitNameEdit)
    box:SetScript("OnEscapePressed", function()
        S.editMode, S.editTarget = nil, nil
        box:ClearFocus()
        PresetsChanged()
    end)
    box:Hide()
    W.edits[#W.edits + 1] = box
    S.nameBox = box
    S.nameOK = MakeButton(S, "Save")
    S.nameOK:SetScript("OnClick", CommitNameEdit)
    S.nameOK:Hide()
end

-- Dungeon tile: icon with the best keystone on it, name next to it.
local function PaintTile(t)
    local ar, ag, ab = Accent()
    local all = sidebar.allDungeons
    if t.selected and not all then
        t.bg:SetColorTexture(ar, ag, ab, t.hover and 0.28 or 0.18)
        SetBorderColor(t, ar, ag, ab, 0.95)
    elseif skin then
        t.bg:SetColorTexture(0.061, 0.095, 0.120, t.hover and 0.85 or 0.6)
        SetBorderColor(t, 1, 1, 1, t.hover and 0.35 or 0.1)
    else
        t.bg:SetColorTexture(0, 0, 0, t.hover and 0.55 or 0.4)
        SetBorderColor(t, 0.5, 0.5, 0.5, t.hover and 0.9 or 0.45)
    end
    local dim = not all and not t.selected
    t.icon:SetDesaturated(dim)
    t.icon:SetAlpha(dim and 0.55 or 1)
    t.name:SetAlpha(dim and 0.6 or 1)
end

local function TileTooltip(t)
    return function(tt)
        tt:SetText(t.dungeonName, 1, 1, 1)
        if t.bestLevel then
            local timed = t.bestTimed and "|cff40ff40in time|r" or "|cffff8040over time|r"
            tt:AddLine(("Season best: +%d (%s)"):format(t.bestLevel, timed), 1, 0.82, 0)
        else
            tt:AddLine("No run this season", 0.6, 0.6, 0.6)
        end
        if t.bestScore then tt:AddLine(("Dungeon score: %d"):format(floor(t.bestScore)), 0.8, 0.8, 0.8) end
        tt:AddLine(" ")
        tt:AddLine("Click: add to / remove from the filter\nNothing selected = all dungeons", 0.6, 0.6, 0.6, true)
    end
end

local function CreateTile()
    local S = sidebar
    local t = CreateFrame("Button", nil, S)
    t:SetSize(COL_W, TILE_H)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    CreateBorder(t)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(TILE_H - 6, TILE_H - 6)
    t.icon:SetPoint("LEFT", 3, 0)
    t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    t.key = t:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    t.key:SetPoint("BOTTOM", t.icon, "BOTTOM", 0, 1)
    t.name = MakeText(t, "GameFontHighlightSmall")
    t.name:SetPoint("LEFT", t.icon, "RIGHT", 5, 0)
    t.name:SetPoint("RIGHT", t, "RIGHT", -4, 0)
    t.name:SetJustifyH("LEFT")
    t.name:SetWordWrap(true)
    t.name:SetMaxLines(2)
    t:SetScript("OnEnter", function(self) self.hover = true; PaintTile(self); ShowTip(self) end)
    t:SetScript("OnLeave", function(self) self.hover = false; PaintTile(self); HideTip(self) end)
    t:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        local f = C_LFGList.GetAdvancedFilter()
        local set = sidebar.allDungeons and {} or ActivitySet(f)
        if set[self.groupID] then set[self.groupID] = nil else set[self.groupID] = true end
        f.activities = SetToList(set)
        SaveFilter(f)
    end)
    t.tip = TileTooltip(t)
    return t
end

local function UpdateTiles()
    local S = sidebar
    local groups = ns.SeasonGroups()
    S.groups = groups
    for i, g in ipairs(groups) do
        local t = S.tiles[i] or CreateTile()
        S.tiles[i] = t
        t.groupID, t.dungeonName = g.id, g.name
        t.gridShown = true
        t.name:SetText(g.name)
        local tex = g.cid and select(4, C_ChallengeMode.GetMapUIInfo(g.cid))
        t.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        local level, timed, score = BestKey(g.cid)
        t.bestLevel, t.bestTimed, t.bestScore = level, timed, score
        if level then
            t.key:SetText("+" .. level)
            ColorKeyText(t.key, level, timed)
            t.key:Show()
        else
            t.key:Hide()
        end
    end
    for i = #groups + 1, #S.tiles do S.tiles[i].gridShown = false; S.tiles[i]:Hide() end
end

local function BuildDungeonSection()
    local S = sidebar
    S.hDungeons = CreateHeader("Dungeons")
    S.clearDungeons = MakeButton(S, "All")
    S.clearDungeons:SetSize(48, 18)
    AddTip(S.clearDungeons, "Search all dungeons")
    S.clearDungeons:SetScript("OnClick", function()
        local f = C_LFGList.GetAdvancedFilter()
        f.activities = {}
        SaveFilter(f)
    end)
    S.tiles = {}
end

local function BuildCheckSection(key, header, defs)
    local S = sidebar
    S[key .. "Header"] = CreateHeader(header)
    local list = {}
    for _, d in ipairs(defs) do
        local cb = MakeCheck(S, d.label, function() ToggleFilterKey(d.key) end, d.tip)
        cb.filterKey = d.key
        list[#list + 1] = cb
    end
    S[key] = list
end

local function BuildNumbers()
    local S = sidebar
    S.hNumbers = CreateHeader("Mythic+")

    S.ratingLabel = MakeText(S)
    S.ratingLabel:SetText("Min. leader rating")
    S.rating = MakeNumberBox(S, 56, 4,
        function() return C_LFGList.GetAdvancedFilter().minimumRating or 0 end,
        function(v)
            v = v and max(0, min(RATING_MAX, floor(v))) or 0
            local f = C_LFGList.GetAdvancedFilter()
            if (f.minimumRating or 0) ~= v then f.minimumRating = v; SaveFilter(f) end
        end,
        "Minimum Mythic+ rating of the group leader.\nEmpty = any.")

    -- The listed key level only exists in the group title. Blizzard's server
    -- searches titles through its own search box, which addons may neither
    -- fill in nor read: this only puts the cursor there.
    S.keyLabel = MakeText(S)
    S.keyLabel:SetText("Key level")
    S.keyBtn = MakeButton(S, "Type in search box")
    S.keyBtn:SetWidth(128)
    S.keyBtn:SetScript("OnClick", function()
        local box = SP and SP.SearchBox
        if box then pcall(box.SetFocus, box) end
    end)
    AddTip(S.keyBtn, function(tt)
        tt:SetText("Key level", 1, 1, 1)
        tt:AddLine("Type the key into Blizzard's search box above the list, e.g. |cffffffff+12|r, then search.", 0.85, 0.85, 0.85, true)
        tt:AddLine(" ")
        tt:AddLine("The key level only exists in the group title. Blizzard lets its own search box search titles, but no addon may fill that box in or read titles, so there is no key range filter.", 0.6, 0.6, 0.6, true)
    end)
end

-- Difficulty and playstyle: Blizzard's multi-select filters, as two compact
-- dropdowns side by side. All or none ticked = no restriction.
local SCOPES = {
    { key = "diffDD", label = "Difficulty", all = "All difficulties", items = {
        { key = "difficultyNormal", label = "Normal" },
        { key = "difficultyHeroic", label = "Heroic" },
        { key = "difficultyMythic", label = "Mythic" },
        { key = "difficultyMythicPlus", label = "Mythic+" },
    } },
    { key = "styleDD", label = "Playstyle", all = "All playstyles", items = {
        { key = "generalPlaystyle1", label = "Learning" },
        { key = "generalPlaystyle2", label = "Relaxed" },
        { key = "generalPlaystyle3", label = "Competitive" },
        { key = "generalPlaystyle4", label = "Carry offered" },
    } },
}

local function ScopeText(scope, f)
    local on = {}
    for _, it in ipairs(scope.items) do if f[it.key] then on[#on + 1] = it.label end end
    if #on == 0 or #on == #scope.items then return scope.all end
    if #on == 1 then return on[1] end
    return ("%d selected"):format(#on)
end

local function BuildScopes()
    local S = sidebar
    for _, scope in ipairs(SCOPES) do
        local lbl = MakeText(S, "GameFontNormal")
        lbl:SetText(scope.label)
        local dd = MakeDropdown(S, COL_W)
        dd:SetupMenu(function(_, root)
            for _, it in ipairs(scope.items) do
                root:CreateCheckbox(it.label,
                    function() return C_LFGList.GetAdvancedFilter()[it.key] and true or false end,
                    function() ToggleFilterKey(it.key) end)
            end
        end)
        S[scope.key], S[scope.key .. "Label"] = dd, lbl
    end
end

-- Fit toggles: client-side, they only dim rows (no new search needed).
local function FitTip(title, lines)
    return function(tt)
        tt:SetText(title, 1, 1, 1)
        for _, l in ipairs(lines()) do tt:AddLine(l, 0.85, 0.85, 0.85, true) end
        tt:AddLine(" ")
        tt:AddLine("Groups that don't fit are dimmed, not hidden.", 0.6, 0.6, 0.6, true)
    end
end

local function BuildFitChecks()
    local S = sidebar
    local function Toggle(key)
        return function(cb)
            db[key] = cb:GetChecked() and true or false
            RefreshRows(); RefreshUI()
        end
    end
    local defs = {
        { key = "fitParty", label = "Party fit",
          tip = FitTip("Party fit", function()
              return { "Only groups with a free spot for every role in your group (or for your own spec when you are alone)." }
          end) },
        { key = "fitLust", label = LUST_ICON .. " Lust",
          tip = FitTip("Bloodlust / Heroism", function()
              if Party().lust then
                  return { "Your group brings lust: only groups that don't have one yet." }
              end
              return { "Your group has no lust: only groups that have one, or still have a healer or dps spot free after you join." }
          end) },
        { key = "fitBrez", label = BREZ_ICON .. " Brez",
          tip = FitTip("Battle res", function()
              if Party().brez then
                  return { "Your group brings a battle res: only groups that don't have one yet." }
              end
              return { "Your group has no battle res: only groups that have one, or still have a spot free after you join." }
          end) },
        { key = "fitNotDeclined", label = "Not declined",
          tip = FitTip("Not declined", function()
              return { "Dims groups that declined your application (Blizzard's own decline list)." }
          end) },
    }
    local list = {}
    for _, d in ipairs(defs) do
        local cb = MakeCheck(S, d.label, Toggle(d.key), d.tip)
        cb.fitKey = d.key
        list[#list + 1] = cb
    end
    S.fitChecks = list
end


local function LanguageLabel(lang)
    return _G["LFG_LIST_LANGUAGE_" .. string.upper(lang)] or lang
end

local function BuildLanguages()
    local S = sidebar
    S.hLang = CreateHeader("Languages")
    S.langDD = MakeDropdown(S, SIDEBAR_W - PAD * 2)
    S.langDD:SetupMenu(function(_, root)
        local defaults = C_LFGList.GetDefaultLanguageSearchFilter and C_LFGList.GetDefaultLanguageSearchFilter() or {}
        for _, lang in ipairs(C_LFGList.GetAvailableLanguageSearchFilter() or {}) do
            local cb = root:CreateCheckbox(LanguageLabel(lang), function()
                local enabled = C_LFGList.GetLanguageSearchFilter() or {}
                return enabled[lang] or defaults[lang]
            end, function()
                if defaults[lang] then return end
                local enabled = C_LFGList.GetLanguageSearchFilter() or {}
                enabled[lang] = not enabled[lang]
                C_LFGList.SaveLanguageSearchFilter(enabled)
                MarkPending(); RefreshUI()
            end)
            if defaults[lang] and cb.SetEnabled then cb:SetEnabled(false) end
        end
    end)
end

local function BuildBottom()
    local S = sidebar
    local search = MakeButton(S, "Search", "GottaQueueEmAllSearch", true)
    MakeSearchClicker(search)
    search:SetHeight(26)
    AddTip(search, "Search with the current filter.\nHighlighted: the filter changed since the last search.")
    search:SetPoint("BOTTOMLEFT", S, "BOTTOMLEFT", PAD, PAD)
    search:SetPoint("BOTTOMRIGHT", S, "BOTTOM", -3, PAD)
    S.search = search

    local reset = MakeButton(S, "Reset")
    reset:SetHeight(26)
    AddTip(reset, "Reset every filter to Blizzard's defaults")
    reset:SetPoint("BOTTOMLEFT", S, "BOTTOM", 3, PAD)
    reset:SetPoint("BOTTOMRIGHT", S, "BOTTOMRIGHT", -PAD, PAD)
    reset:SetScript("OnClick", ResetFilter)
    S.reset = reset

    S.matchText = MakeText(S, "GameFontDisableSmall")
    S.matchText:SetPoint("BOTTOM", S, "BOTTOM", 0, PAD + 26 + 5)
end

local function BuildGear()
    local S = sidebar
    local g = CreateFrame("Button", nil, S)
    g:SetSize(16, 16)
    local icon = g:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("GM-icon-settings") then
        icon:SetAtlas("GM-icon-settings")
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetDesaturated(true)
    end
    icon:SetAlpha(0.7)
    g:SetScript("OnEnter", function(self) icon:SetAlpha(1); ShowTip(self) end)
    g:SetScript("OnLeave", function(self) icon:SetAlpha(0.7); HideTip(self) end)
    g.tip = "Gotta Queue 'Em All settings"
    g:SetScript("OnClick", OpenSettings)
    S.gear = g
end

local function RepaintAll()
    if not sidebar then return end
    for _, t in ipairs(sidebar.tiles) do PaintTile(t) end
end

-- EllesmereUI look via its public skinning API. Runs once `skin` is known and
-- the sidebar exists, whichever comes last.
local function ApplyEUISkin()
    if not (skin and sidebar) or sidebar.euiSkinned then return end
    sidebar.euiSkinned = true
    skin.Inset(sidebar)
    skin.Panel(sidebar, { inset = true })
    for _, b in ipairs(W.buttons) do skin.Button(b); skin.WhiteButtonLabel(b) end
    for _, cb in ipairs(W.checks) do skin.Checkbox(cb); skin.Font(cb.label) end
    for _, eb in ipairs(W.edits) do skin.EditBox(eb) end
    for _, dd in ipairs(W.dropdowns) do skin.Dropdown(dd) end
    for _, fs in ipairs(W.texts) do skin.Font(fs) end
    RepaintAll()
end

local function BuildSidebar()
    local S = CreateFrame("Frame", "GottaQueueEmAllSidebar", SP, "InsetFrameTemplate")
    sidebar = S
    S:SetWidth(SIDEBAR_W)
    S:SetPoint("TOPLEFT", LFGListPVEStub, "TOPRIGHT", GAP, -30)
    S:SetPoint("BOTTOMLEFT", LFGListPVEStub, "BOTTOMRIGHT", GAP, 8)
    S:SetFrameLevel(SP:GetFrameLevel() + 5)

    BuildPresetSection()
    BuildDungeonSection()
    local className = UnitClass("player") or "my class"
    BuildCheckSection("roleChecks", "Roles", {
        { key = "needsTank",    label = "Tank spot open",   tip = "Tank role available" },
        { key = "needsHealer",  label = "Healer spot open", tip = "Healer role available" },
        { key = "needsDamage",  label = "DPS spot open",    tip = "Damage role available" },
        { key = "hasTank",      label = "Has tank" },
        { key = "hasHealer",    label = "Has healer" },
        { key = "needsMyClass", label = "No " .. className, tip = "No " .. className .. " already in group" },
    })
    BuildNumbers()
    BuildFitChecks()
    BuildScopes()
    BuildLanguages()
    BuildBottom()
    BuildGear()

    S:SetScript("OnShow", function() RefreshUI() end)
    ApplyEUISkin()
    S:Hide()
end

-- Blizzard's search box (the only place the key level can be searched) is
-- docked into the "Key level" row. Only its position and frame level change;
-- its text is typed by the player as always and read by Blizzard's server
-- directly (the box refuses SetText from addons, and we never try). The
-- refresh button and the autocomplete list are anchored to it and follow.
-- If moving it ever fails, the "Type in search box" button stays instead.
local KEY_LABEL_W = 64
local boxDocked, dockFailed = false, false
local boxLevel, refreshLevel, autoLevel

local function RestoreSearchBox()
    if not boxDocked then return end
    local box, rb, ac = SP.SearchBox, SP.RefreshButton, SP.AutoCompleteFrame
    pcall(function()
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", SP.CategoryName, "BOTTOMLEFT", 4, -7)      -- LFGList.xml
        box:SetPoint("RIGHT", SP.FilterButton, "LEFT", -42, 0)
        if boxLevel then box:SetFrameLevel(boxLevel) end
        if rb and refreshLevel then rb:SetFrameLevel(refreshLevel) end
        if ac and autoLevel then ac:SetFrameLevel(autoLevel) end
    end)
    boxDocked = false
end

-- Returns true when the box sits in the sidebar at height y.
local function DockSearchBox(y)
    local box, rb, ac = SP and SP.SearchBox, SP and SP.RefreshButton, SP and SP.AutoCompleteFrame
    if dockFailed or not box then return false end
    if not boxDocked then
        boxLevel = box:GetFrameLevel()
        refreshLevel = rb and rb:GetFrameLevel()
        autoLevel = ac and ac:GetFrameLevel()
    end
    local base = sidebar:GetFrameLevel()
    local ok, err = pcall(function()
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", sidebar, "TOPLEFT", PAD + KEY_LABEL_W, y - 2)
        box:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -PAD - 32, y - 2)   -- 32 = refresh button
        box:SetFrameLevel(base + 3)
        if rb then rb:SetFrameLevel(base + 3) end
        if ac then ac:SetFrameLevel(base + 20) end
    end)
    boxDocked = true
    if not ok then
        dockFailed = true
        RestoreSearchBox()
        Print("could not move Blizzard's search box (" .. tostring(err) .. "); it stays above the list.")
        return false
    end
    return true
end

-- Positions everything. Touches secure buttons, so out of combat only.
Relayout = function()
    if not sidebar or InCombatLockdown() then return end
    local S = sidebar
    local innerW = SIDEBAR_W - PAD * 2
    UpdateTiles()

    local y = -PAD
    -- Presets: dropdown + gear, quick bar, name editor
    y = PlaceHeader(S.hPresets, y)
    S.gear:ClearAllPoints()
    S.gear:SetPoint("TOPRIGHT", S, "TOPRIGHT", -PAD, -PAD)
    S.presetDD:ClearAllPoints()
    S.presetDD:SetPoint("TOPLEFT", S, "TOPLEFT", PAD, y)
    y = y - BTN_H - 6

    local pinned = PinnedPresets()
    if #pinned > 0 then
        local bw = floor((innerW - (QUICK_SLOTS - 1) * 4) / QUICK_SLOTS)
        for i, b in ipairs(S.quick) do
            local p = pinned[i]
            b.preset = p
            if p then
                b:SetText(p.name)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", S, "TOPLEFT", PAD + (i - 1) * (bw + 4), y)
                b:SetWidth(bw)
                b:Show()
            else
                b:Hide()
            end
        end
        y = y - BTN_H - 6
    else
        for _, b in ipairs(S.quick) do b.preset = nil; b:Hide() end
    end

    if S.editMode then
        S.nameBox:ClearAllPoints()
        S.nameBox:SetPoint("TOPLEFT", S, "TOPLEFT", PAD + 6, y)
        S.nameBox:SetPoint("TOPRIGHT", S, "TOPRIGHT", -PAD - 64, y)
        S.nameBox:Show()
        S.nameOK:ClearAllPoints()
        S.nameOK:SetPoint("TOPRIGHT", S, "TOPRIGHT", -PAD, y)
        S.nameOK:SetWidth(58)
        S.nameOK:SetText(S.editMode == "rename" and "Rename" or "Save")
        S.nameOK:Show()
        y = y - BTN_H - 6
    else
        S.nameBox:Hide(); S.nameOK:Hide()
    end
    y = y - SECTION_GAP

    -- Difficulty | Playstyle, side by side: they decide what is searched at all.
    for i, scope in ipairs(SCOPES) do
        local x = PAD + (i - 1) * (COL_W + COL_GAP)
        local lbl, dd = S[scope.key .. "Label"], S[scope.key]
        lbl:ClearAllPoints(); lbl:SetPoint("TOPLEFT", S, "TOPLEFT", x, y)
        dd:ClearAllPoints();  dd:SetPoint("TOPLEFT", S, "TOPLEFT", x, y - HEADER_H - 4)
    end
    y = y - HEADER_H - 4 - BTN_H - 6 - SECTION_GAP

    -- Dungeons
    if #S.groups > 0 then
        S.clearDungeons:ClearAllPoints()
        S.clearDungeons:SetPoint("TOPRIGHT", S, "TOPRIGHT", -PAD, y + 1)
        S.clearDungeons:Show()
        y = PlaceHeader(S.hDungeons, y)
        y = Grid(S.tiles, y, TILE_H) - SECTION_GAP
    else
        S.hDungeons:Hide(); S.clearDungeons:Hide()
    end

    -- Roles (only those the player can queue as)
    local canTank, canHeal, canDPS = C_LFGList.GetAvailableRoles()
    for _, cb in ipairs(S.roleChecks) do
        local k = cb.filterKey
        cb.gridShown = not ((k == "needsTank" and not canTank) or (k == "needsHealer" and not canHeal)
                           or (k == "needsDamage" and not canDPS))
    end
    y = PlaceHeader(S.roleChecksHeader, y)
    y = Grid(S.roleChecks, y, CHECK_H) - SECTION_GAP

    -- Mythic+: leader rating, key level hint, fit toggles
    y = PlaceHeader(S.hNumbers, y)
    S.ratingLabel:ClearAllPoints(); S.ratingLabel:SetPoint("TOPLEFT", S, "TOPLEFT", PAD + 2, y - 5)
    S.rating:ClearAllPoints();      S.rating:SetPoint("TOPRIGHT", S, "TOPRIGHT", -PAD, y)
    y = y - BTN_H - 4
    S.keyLabel:ClearAllPoints();    S.keyLabel:SetPoint("TOPLEFT", S, "TOPLEFT", PAD + 2, y - 5)
    if DockSearchBox(y) then
        S.keyBtn:Hide()
    else
        S.keyBtn:ClearAllPoints();  S.keyBtn:SetPoint("TOPRIGHT", S, "TOPRIGHT", -PAD, y)
        S.keyBtn:Show()
    end
    y = y - BTN_H - 6
    y = Grid(S.fitChecks, y, CHECK_H) - SECTION_GAP

    -- Languages
    if LanguagesAvailable() then
        y = PlaceHeader(S.hLang, y)
        S.langDD:ClearAllPoints()
        S.langDD:SetPoint("TOPLEFT", S, "TOPLEFT", PAD, y)
        S.langDD:Show()
        y = y - BTN_H - SECTION_GAP
    else
        S.hLang:Hide(); S.langDD:Hide()
    end

    -- Height the content needs; ApplyLayout keeps the window at least this tall.
    -- Content grown outside ApplyLayout (preset bar, name editor): resize once.
    S.contentH = -y
    if enlarged and ceil(S.contentH + BOTTOM_AREA + SIDEBAR_INSET_H) > LFGListPVEStub:GetHeight() + 0.5 then
        C_Timer.After(0, ApplyLayout)
    end
end

RefreshUI = function()
    if not sidebar or not sidebar:IsShown() then return end
    local S = sidebar
    local f = C_LFGList.GetAdvancedFilter()

    -- Presets
    local cur = CurrentPreset()
    SetDropdownText(S.presetDD, cur and cur.name
        or (#db.presets > 0 and "Custom filter" or "No presets yet"))
    for _, b in ipairs(S.quick) do
        if b.preset and PresetMatches(b.preset) then b:LockHighlight() else b:UnlockHighlight() end
    end

    -- Dungeons: "all" when none or every season dungeon is selected.
    local set = ActivitySet(f)
    local n = 0
    for _, g in ipairs(S.groups or {}) do if set[g.id] then n = n + 1 end end
    S.allDungeons = (n == 0 or n == #(S.groups or {}))
    for i = 1, #(S.groups or {}) do
        local t = S.tiles[i]
        t.selected = set[t.groupID] and true or false
        PaintTile(t)
    end
    if S.allDungeons then S.clearDungeons:LockHighlight() else S.clearDungeons:UnlockHighlight() end

    for _, cb in ipairs(S.roleChecks) do cb:SetChecked(f[cb.filterKey] and true or false) end
    for _, cb in ipairs(S.fitChecks) do cb:SetChecked(db[cb.fitKey] and true or false) end
    for _, scope in ipairs(SCOPES) do SetDropdownText(S[scope.key], ScopeText(scope, f)) end

    S.rating.Sync()

    if LanguagesAvailable() then
        local enabled = C_LFGList.GetLanguageSearchFilter() or {}
        local defaults = C_LFGList.GetDefaultLanguageSearchFilter and C_LFGList.GetDefaultLanguageSearchFilter() or {}
        local langs = C_LFGList.GetAvailableLanguageSearchFilter() or {}
        local on = {}
        for _, lang in ipairs(langs) do
            if enabled[lang] or defaults[lang] then on[#on + 1] = LanguageLabel(lang) end
        end
        SetDropdownText(S.langDD, (#on == #langs and "All languages")
            or (#on <= 2 and table.concat(on, ", "))
            or (("%d of %d languages"):format(#on, #langs)))
    end

    if searchPending then S.search:LockHighlight() else S.search:UnlockHighlight() end
    UpdateMatchCount()
end

-------------------------------------------------------------------------------
--  Layout (window size + sidebar visibility)
-------------------------------------------------------------------------------
-- Blizzard's own filter dropdown duplicates the sidebar, so it goes while the
-- sidebar is up. Blizzard hides it itself in some cases; the search box is
-- anchored to its left edge, so moving the hidden button right by its width
-- lets the search box (key numbers are searched there) grow into the gap.
-- The search box itself is never touched: it is protected against addons.
local FILTER_X, FILTER_Y = -8, -58   -- LFGList.xml anchor of SearchPanel.FilterButton
local filterMoved = false

local function HideBlizzardFilter()
    local fb = SP and SP.FilterButton
    if not fb then return end
    fb:Hide()
    if not filterMoved then
        fb:ClearAllPoints()
        fb:SetPoint("TOPRIGHT", SP, "TOPRIGHT", FILTER_X + fb:GetWidth(), FILTER_Y)
        filterMoved = true
    end
end

local function RestoreBlizzardFilter()
    local fb = SP and SP.FilterButton
    if not (fb and filterMoved) then return end
    fb:ClearAllPoints()
    fb:SetPoint("TOPRIGHT", SP, "TOPRIGHT", FILTER_X, FILTER_Y)
    filterMoved = false
    -- Same condition as LFGListSearchPanel_OnShow.
    local canFilter = (LFGListCanChangeLanguages and LFGListCanChangeLanguages())
        or (GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel and GameRulesUtil.IsPlayerAtEffectiveMaxLevel())
    fb:SetShown(canFilter and true or false)
end

ApplyLayout = function()
    if not built then return end
    if InCombatLockdown() then layoutPending = true; return end
    layoutPending = false

    local large = db.enabled and LFGListPVEStub:IsVisible()
    local side  = large and SP:IsVisible() and IsDungeonCategory()

    -- Start a Group / own listing (GottaQueueEmAll_Create.lua): "center" = our
    -- form in the panel itself, "side"/"relist" = a sidebar next to it.
    local CR = ns.Create
    local cmode = large and not side and CR and CR.Mode() or nil

    -- Lay the sidebar out first: its content decides the minimum window height.
    if side then Relayout() end
    if cmode then CR.Relayout(cmode) end

    if large then
        local Wd = max(db.width, BASE_W)
        local H  = max(db.height, BASE_H)
        if side and sidebar.contentH then
            H = max(H, ceil(sidebar.contentH + BOTTOM_AREA + SIDEBAR_INSET_H))
        end
        if cmode and CR.neededH then H = max(H, ceil(CR.neededH)) end
        local listW = Wd - RAIL_W - 1
        if side or (cmode and cmode ~= "center") then listW = Wd - RAIL_W - SIDEBAR_W - GAP * 2 end
        SecureSize(PVEFrame, Wd, H)
        SecureSize(LFGListPVEStub, listW, H)
        enlarged = true
    elseif enlarged then
        SecureSize(PVEFrame, BASE_W, BASE_H)
        SecureSize(LFGListPVEStub, STUB_W, BASE_H)
        enlarged = false
    end

    if side then
        if not sidebar:IsShown() then sidebar:Show() end
        HideBlizzardFilter()
        RefreshUI()
    else
        if sidebar:IsShown() then sidebar:Hide() end
        RestoreBlizzardFilter()   -- first: the restored search box anchors to it
        RestoreSearchBox()
    end
    if cmode then CR.Show(cmode) elseif CR then CR.Hide() end
    RefreshRows()
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local function Build()
    if built or not (LFGListFrame and LFGListFrame.SearchPanel and LFGListPVEStub and PVEFrame) then return end
    if InCombatLockdown() then layoutPending = true; return end
    SP = LFGListFrame.SearchPanel
    BuildSidebar()
    built = true
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end

    LFGListPVEStub:HookScript("OnShow", ApplyLayout)
    LFGListPVEStub:HookScript("OnHide", function()
        -- Only shrink when switching away inside the window; a closed window
        -- is resized by PVEFrame_ShowFrame's hook on the next open.
        if PVEFrame:IsShown() then ApplyLayout() end
    end)
    SP:HookScript("OnShow", ApplyLayout)
    SP:HookScript("OnHide", function() if PVEFrame:IsShown() then ApplyLayout() end end)
    hooksecurefunc("PVEFrame_ShowFrame", ApplyLayout)
    if LFGListSearchPanel_SetCategory then hooksecurefunc("LFGListSearchPanel_SetCategory", ApplyLayout) end
    hooksecurefunc("LFGListSearchEntry_Update", DecorateRow)
    if ns.Create then ns.Create.Init(ApplyLayout) end

    if PVEFrame:IsShown() then ApplyLayout() end
end

-- EllesmereUI (optional): the callback only runs while its Blizzard skin is
-- enabled for this addon; otherwise the sidebar keeps the Blizzard look.
if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin("GottaQueueEmAll", function(S)
        skin = S
        if S.OnLooksChanged then S.OnLooksChanged(RepaintAll) end
        ApplyEUISkin()
        if ns.Create and ns.Create.ApplySkin then ns.Create.ApplySkin() end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
events:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        if type(GottaQueueEmAllDB) ~= "table" then GottaQueueEmAllDB = {} end
        db = GottaQueueEmAllDB
        if db.dimAlpha then db.dimPercent = floor(db.dimAlpha * 100 + 0.5); db.dimAlpha = nil end
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = type(v) == "table" and {} or v end
        end
        local ok, err = pcall(RegisterSettings)
        if not ok then Print("settings page unavailable (" .. tostring(err) .. ")") end
        Build()
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_GroupFinder" and db then Build() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if db and not built then Build() end
        if layoutPending then ApplyLayout() end
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        searchPending = false
        InvalidateFacts()
        if sidebar and sidebar:IsShown() then
            RefreshUI()
            -- Next frame: Blizzard has rebuilt SearchPanel.results and its rows by then.
            C_Timer.After(0, RefreshRows)
        end
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        if Readable(arg1) then InvalidateFacts(arg1) end
        if sidebar and sidebar:IsShown() then
            if Readable(arg1) then RefreshRow(arg1) end
            QueueMatchCount()
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then return end
        party = nil
        if sidebar and sidebar:IsShown() and ClientFiltersActive() then RefreshRows() end
    elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
        if sidebar and sidebar:IsShown() and not InCombatLockdown() then Relayout(); RefreshUI() end
    end
end)

-------------------------------------------------------------------------------
--  Slash command: /gotta opens the settings, /gotta toggle switches on/off
-------------------------------------------------------------------------------
SLASH_GOTTAQUEUEEMALL1 = "/gotta"
SLASH_GOTTAQUEUEEMALL2 = "/gqea"
SlashCmdList.GOTTAQUEUEEMALL = function(msg)
    if not db then return end
    msg = strtrim((msg or ""):lower())
    if msg == "toggle" then
        db.enabled = not db.enabled
        Print(db.enabled and "enabled." or "disabled.")
        ApplyLayout()
    else
        OpenSettings()
    end
end
