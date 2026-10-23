-------------------------------------------------------------------------------
--  UI/Keystone.lua  --  the keystone window at the Font of Power
--
--  Blizzard's keystone window opens: ours shows instead, with the key's
--  level in a ring whose five points are the group (gold once ready), the
--  dungeon, the timer with its +3 / +2 / +1 times, the affixes, the group
--  with ratings and ready state, and a pull timer slider (3 - 30 s, the last
--  value is kept). Activate runs it all in one go: a ready check (leader or
--  assistant), then Blizzard's countdown (C_PartyInfo.DoCountdown), then the
--  key starts (C_ChallengeMode.StartChallengeMode). Each step can be off.
--  The keystone goes in by itself (from the bags); drag and click still work.
--
--  Blizzard's window stays open, unseen and unclickable: closing it would
--  close the Font of Power (its OnHide calls CloseKeystoneFrame). Closing
--  ours closes it. Should WoW ever block our start, it is shown again as it
--  was and answers from then on (ADDON_ACTION_BLOCKED).
--  Settings: "keystoneWindow" (default on), "keystoneAutoStart",
--  "keystoneReadyFirst", "pullTimer", "keystoneWide".
-------------------------------------------------------------------------------
local ADDON, ns = ...
local UI = ns.UI
local T, W, A, D = UI.Theme, UI.W, UI.Anim, UI.Data
local C = T.C
local floor, min, max = math.floor, math.min, math.max
local issecret = issecretvalue or function() return false end

local KS = {}
UI.Keystone = KS

local PAD, INNER = 18, 380   -- INNER: a column's width
-- One column (like the design) or two side by side (fits a 768 high screen
-- at full size); the header switches it, setting "keystoneWide".
local TALL_W, WIDE_W = INNER + 2 * PAD, 2 * INNER + 4 * PAD
local RING, NODE = 200, 28
local PULL_MIN, PULL_MAX, PULL_DEFAULT = 3, 30, 10
local QUICK = { 5, 10, 15, 20 }
local UNITS = { "player", "party1", "party2", "party3", "party4" }
local ROLE_GLYPH = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local READY_TEXT = { ready = "Ready", waiting = "Waiting", notready = "Not ready" }
-- The timer's parts: +3 up to 60 %, +2 up to 80 %, +1 up to the limit.
local TIERS = { { "+3", 0.6, { 0.36, 0.80, 0.52, 1 } }, { "+2", 0.8, { 0.90, 0.72, 0.36, 1 } },
                { "+1", 1, { 0.93, 0.48, 0.30, 1 } } }
local READY_VALID = 90   -- s a finished ready check counts for Activate

local frame
local blocked = false            -- WoW blocked our start this session: Blizzard's window answers
local ready, readyAt = {}, nil   -- unit -> "ready" / "waiting" / "notready"; when the last check ended
local flow                       -- what Activate waits for: "ready" or "pull"
local count                      -- the countdown: { endAt, total, start = true when the key starts at 0 }
local autoInserted = false

local function DB() return ns.DB and ns.DB() end
local function Opt(key) local db = DB(); return not (db and db[key] == false) end

function KS.Active() return Opt("keystoneWindow") and not blocked end

-------------------------------------------------------------------------------
--  Blizzard's window: open but unseen while ours shows
-------------------------------------------------------------------------------
local function Blizz() return ChallengesKeystoneFrame end

local function SetSeen(seen)
    local b = Blizz()
    if not b then return end
    b:SetAlpha(seen and 1 or 0)
    b:EnableMouse(seen)
    for _, key in ipairs({ "KeystoneSlot", "StartButton", "CloseButton" }) do
        if b[key] then b[key]:EnableMouse(seen) end
    end
    for _, af in ipairs(b.Affixes or {}) do af:EnableMouse(seen) end
end

-------------------------------------------------------------------------------
--  The keystone
-------------------------------------------------------------------------------
-- Slotted: mapID, affix IDs, level, true. Else the one in your bags.
local function KeyInfo()
    local cm = C_ChallengeMode
    if cm.HasSlottedKeystone and cm.HasSlottedKeystone() then
        local mapID, affixes, level = cm.GetSlottedKeystoneInfo()
        if mapID then return mapID, affixes or {}, level, true end
    end
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
    local affixes = {}
    for _, a in ipairs(C_MythicPlus.GetCurrentAffixes and C_MythicPlus.GetCurrentAffixes() or {}) do
        if a.id then affixes[#affixes + 1] = a.id end
    end
    return D.Num(mapID), affixes, D.Num(level), false
end

local function FindKeystone()
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and D.Num(info.itemID)
            if id and C_Item.IsItemKeystoneByID(id) then return bag, slot end
        end
    end
end

-- From the bags into the Font of Power; true when it went in.
local function Insert()
    if InCombatLockdown() or CursorHasItem() or C_ChallengeMode.HasSlottedKeystone() then return end
    local bag, slot = FindKeystone()
    if not bag then return end
    local ok = pcall(function()
        C_Container.PickupContainerItem(bag, slot)
        if CursorHasItem() then C_ChallengeMode.SlotKeystone() end
    end)
    if CursorHasItem() then ClearCursor() end   -- not taken: back to the bag
    return ok
end

-------------------------------------------------------------------------------
--  Building blocks
-------------------------------------------------------------------------------
local function Round(parent, icon, size, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetSize(size, size)
    t:SetTexture(icon)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(T.TEX .. "circle", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(t)
    t:AddMaskTexture(mask)
    return t
end

-- A thin circle drawn from short lines (crisp at any size, unlike a
-- stretched ring texture). Returns the lines, to recolor them.
local function LineCircle(parent, r, color, thick, layer, sub)
    local lines, n = {}, 72
    for i = 0, n - 1 do
        local a, b = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        local l = parent:CreateLine(nil, layer or "BORDER", nil, sub or 0)
        l:SetThickness(thick or 1)
        l:SetColorTexture(unpack(color))
        l:SetStartPoint("CENTER", parent, math.cos(a) * r, math.sin(a) * r)
        l:SetEndPoint("CENTER", parent, math.cos(b) * r, math.sin(b) * r)
        lines[#lines + 1] = l
    end
    return lines
end

local function Recolor(lines, color)
    for _, l in ipairs(lines) do l:SetColorTexture(unpack(color)) end
end

-- A section: a line on top, an uppercase label, a muted note on the right.
local function Section(parent)
    local f = CreateFrame("Frame", nil, parent)
    local line = W.Tex(f, "BORDER", C.line)
    line:SetPoint("TOPLEFT", -PAD, 0); line:SetPoint("TOPRIGHT", PAD, 0); PixelUtil.SetHeight(line, 1, 1)
    f.label = W.Text(f, "label")
    f.label:SetPoint("TOPLEFT", 0, -14)
    f.right = W.Text(f, "small")
    f.right:SetPoint("TOPRIGHT", 0, -14)
    function f:SetLabel(t) self.label:SetText(t:upper()) end
    return f
end

-- A rounded pill in a state color: { text color, fill, border }.
local TONE = {
    good = { C.goodText, { 0.24, 0.69, 0.38, 0.12 }, { 0.24, 0.69, 0.38, 0.45 } },
    gold = { C.goldText, { 0.82, 0.64, 0.30, 0.08 }, { 0.82, 0.64, 0.30, 0.45 } },
    bad  = { C.badText, { 1, 0.62, 0.59, 0.08 }, { 1, 0.62, 0.59, 0.45 } },
    none = { C.muted, { 0, 0, 0, 0 }, C.line },
}
local function StatePill(parent, height, dot)
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(height)
    p.bg = W.Round(p, "BACKGROUND")
    p.bg:SetAllPoints()
    W.Border(p)
    p.text = W.Text(p, height > 22 and "label" or "tiny")
    if dot then
        p.dot = W.Circle(p, "ARTWORK", C.good, 6)
        p.dot:SetPoint("LEFT", 10, 0)
        p.text:SetPoint("LEFT", p.dot, "RIGHT", 6, 0)
    else
        p.text:SetPoint("CENTER")
    end
    p.minW = 0
    function p:Set(text, tone)
        local t = TONE[tone] or TONE.none
        self.text:SetText(text)
        self.text:SetTextColor(unpack(t[1]))
        W.Fill(self.bg, t[2])
        W.SetBorder(self, t[3])
        if self.dot then self.dot:SetVertexColor(unpack(tone == "good" and C.good or t[1])) end
        local w = math.ceil(self.text:GetStringWidth()) + (self.dot and 32 or 18)
        self:SetWidth(max(self.minW, w))
    end
    return p
end

-- An affix: round icon and name; the description on hover.
local function AffixChip(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(32)
    c.bg = W.Round(c, "BACKGROUND", C.panel)
    c.bg:SetAllPoints()
    W.Border(c, C.line)
    c.icon = Round(c, nil, 24)
    c.icon:SetPoint("LEFT", 4, 0)
    c.text = W.Text(c, "label", C.text)
    c.text:SetPoint("LEFT", c.icon, "RIGHT", 8, 0)
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(unpack(C.raised)); W.SetBorder(self, { 0.82, 0.64, 0.30, 0.4 })
        if not self.name then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.name, 1, 1, 1)
        if self.desc and self.desc ~= "" then GameTooltip:AddLine(self.desc, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(unpack(C.panel)); W.SetBorder(self, C.line)
        GameTooltip:Hide()
    end)
    -- "Xal'atath's Bargain: Voidbound" shows as "Voidbound"; the tooltip has it all.
    function c:Set(icon, name, desc)
        self.icon:SetTexture(icon)
        self.text:SetText(name:match(":%s*(.+)$") or name)
        self.name, self.desc = name, desc
        self:SetWidth(math.ceil(self.text:GetStringWidth()) + 46)
    end
    return c
end

-- A member: role, name in the class color with the spec, rating, ready state.
local function MemberRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(32)
    r.bg = W.Round(r, "BACKGROUND", C.panel)
    r.bg:SetAllPoints()
    W.Border(r, C.line)
    local rc = r:CreateTexture(nil, "BORDER")
    rc:SetTexture(T.TEX .. "ring"); rc:SetSize(22, 22); rc:SetPoint("LEFT", 9, 0)
    rc:SetVertexColor(unpack(C.faint))
    r.role = W.Glyph(r, "dps", 14, C.label)
    r.role:SetPoint("CENTER", rc, "CENTER")
    r.state = StatePill(r, 22)
    r.state.minW = 66
    r.state:SetPoint("RIGHT", -8, 0)
    r.rating = W.Text(r, "button")
    r.rating:SetPoint("RIGHT", r.state, "LEFT", -10, 0)
    r.name = W.Text(r, "button")
    r.name:SetPoint("LEFT", rc, "RIGHT", 10, 0)
    r.spec = W.Text(r, "small")
    r.spec:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.spec:SetPoint("RIGHT", r.rating, "LEFT", -8, 0)
    return r
end

-------------------------------------------------------------------------------
--  Painting
-------------------------------------------------------------------------------
local function SpecName(unit)
    local id
    if unit == "player" then
        local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
        local info = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
        local i = getSpec and getSpec()
        id = i and info and D.Num((info(i)))
    elseif C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization then
        id = D.Num(C_SpecializationInfo.GetInspectSpecialization(unit))   -- known for group members, else 0
    end
    if id and id > 0 then return D.Str((select(2, GetSpecializationInfoByID(id)))) end
end

local function Members()
    local out = {}
    for _, unit in ipairs(UNITS) do
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            local role = D.Str(UnitGroupRolesAssigned(unit))
            if unit == "player" and (not role or role == "NONE") then role = D.PlayerRole() end
            if role ~= "TANK" and role ~= "HEALER" then role = "DAMAGER" end
            local s = C_PlayerInfo.GetPlayerMythicPlusRatingSummary and D.Tab(C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit))
            out[#out + 1] = { unit = unit, name = UnitName(unit), class = D.Str(class), role = role,
                              spec = SpecName(unit), rating = s and D.Num(s.currentSeasonScore) }
        end
    end
    return out
end

local function AllReady()
    if not readyAt or GetTime() - readyAt > READY_VALID then return false end
    for _, m in ipairs(Members()) do if ready[m.unit] ~= "ready" then return false end end
    return true
end

local function CanCheck() return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") end

local function Hint(text, warn)
    if not frame then return end
    frame.hint:SetText(text or "")
    frame.hint:SetTextColor(unpack(warn and C.goldText or C.muted))
    if frame:IsShown() then KS.Refresh() end   -- the footer grows with a long hint
end

-- Puts the sections below each other and sizes the window (scaled down
-- when the screen is too short for it).
local function Layout()
    local wide = Opt("keystoneWide")
    local y = { 52 + 14, 52 + 14 }
    local function Put(region, h, col, gap)
        col = wide and col or 1
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", frame, "TOPLEFT", col == 2 and (INNER + 3 * PAD) or PAD, -y[col])
        region:SetSize(INNER, h)
        y[col] = y[col] + h + (gap or 0)
    end
    Put(frame.hero, RING + 30, 1, 6)
    Put(frame.dg, frame.best:GetText() ~= "" and 56 or 38, 1, 14)
    if frame.timer:IsShown() then Put(frame.timer, 14 + 13 + 12 + 6 + 6 + 12 + 14, 1) end
    if frame.affixes:IsShown() then Put(frame.affixes, 14 + 13 + 12 + frame.affixH + 14, 1) end
    if wide then y[2] = y[2] - 14 end   -- the right column starts with its section line at the top
    Put(frame.group, 14 + 13 + 12 + frame.groupN * 36 - 4 + 14, 2)
    Put(frame.pull, frame.pullH, 2)
    local w = wide and WIDE_W or TALL_W
    local bottom = max(y[1], wide and y[2] or 0)
    frame.divider:SetShown(wide)
    frame.divider:SetHeight(bottom - 52 - 14)
    -- Footer: one row of 1 : 1 : 1.25 when wide; in one column Activate
    -- gets a row of its own below the other two.
    local foot, rb, pb, go = frame.foot, frame.readyBtn, frame.pullBtn, frame.go
    rb:ClearAllPoints(); pb:ClearAllPoints(); go:ClearAllPoints()
    rb:SetPoint("TOPLEFT", foot, "TOPLEFT", PAD, -14)
    if wide then
        local unit = floor((w - 2 * PAD - 16) / 3.25)
        rb:SetWidth(unit); pb:SetWidth(unit)
        go:SetWidth(w - 2 * PAD - 16 - 2 * unit)
        pb:SetPoint("LEFT", rb, "RIGHT", 8, 0)
        go:SetPoint("LEFT", pb, "RIGHT", 8, 0)
    else
        local half = floor((w - 2 * PAD - 8) / 2)
        rb:SetWidth(half); pb:SetWidth(w - 2 * PAD - 8 - half)
        pb:SetPoint("LEFT", rb, "RIGHT", 8, 0)
        go:SetPoint("TOPLEFT", rb, "BOTTOMLEFT", 0, -8)
        go:SetWidth(w - 2 * PAD)
    end
    local rows = wide and 32 or 32 + 8 + 36
    go:SetHeight(wide and 32 or 36)
    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("TOP", foot, "TOP", 0, -14 - rows - 8)
    frame.hint:SetWidth(w - 2 * PAD)   -- long hints wrap inside the band
    foot:SetHeight(14 + rows + 8 + max(14, math.ceil(frame.hint:GetStringHeight())) + 14)
    frame.sub:SetShown(wide)   -- one column: no room next to the layout switch
    frame:SetSize(w, bottom + frame.foot:GetHeight())
    frame.layout:SetValue(wide and "wide" or "tall")
    frame:SetScale(min(1, (UIParent:GetHeight() - 40) / frame:GetHeight()))
end

local function PaintGroup()
    local list = Members()
    local n = 0
    for i, row in ipairs(frame.rows) do
        local m = list[i]
        local node = frame.nodes[i]
        row:SetShown(m ~= nil)
        local st = m and ready[m.unit]
        if m then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.group, "TOPLEFT", 0, -(14 + 13 + 12) - (i - 1) * 36)
            row:SetPoint("RIGHT", frame.group, "RIGHT")
            row.role:SetTexture(T.TEX .. "glyph-" .. ROLE_GLYPH[m.role])
            row.name:SetText(m.name or "?")   -- may be a secret value: shown, not read
            row.name:SetTextColor(unpack(T.ClassColor(m.class)))
            row.spec:SetText(m.spec or "")
            row.rating:SetText(m.rating and (T.ColorCode(T.RatingColor(m.rating)) .. floor(m.rating) .. "|r") or "")
            row.state:Set(READY_TEXT[st] or "–", st == "ready" and "good" or st == "waiting" and "gold" or st == "notready" and "bad" or "none")
            if st == "ready" then n = n + 1 end
            node.glyph:SetTexture(T.TEX .. "glyph-" .. ROLE_GLYPH[m.role])
        end
        -- The ring's points: gold when ready, rose when not, dim when empty.
        node.ring:SetVertexColor(unpack(st == "ready" and C.gold or st == "waiting" and C.goldDark
            or st == "notready" and C.badText or (m and C.faint) or C.track))
        node.glyph:SetShown(m ~= nil)
        node.glyph:SetVertexColor(unpack(st == "ready" and C.goldLight or st == "notready" and C.badText or C.muted))
        node.glow:SetShown(st == "ready")
        node.disc:SetVertexColor(unpack(st == "ready" and { 0.16, 0.13, 0.06, 1 } or C.panel))
    end
    frame.groupN = max(1, #list)
    frame.group.right:SetText(#list > 1 and ("%d / %d ready"):format(n, #list) or "Solo")
end

local function PaintKey()
    local mapID, affixes, level, slotted = KeyInfo()
    frame.slotted = slotted
    frame.level:SetText(level and ("+" .. level) or "–")
    frame.level:SetTextColor(unpack(level and T.KeyColor(level) or C.faint))

    local name, _, timeLimit
    if mapID then name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID) end
    frame.dungeon:SetText(name or "No keystone")
    local lvl, timed = ns.BestKey(mapID)
    frame.best:SetText(lvl and ("Your best here  " .. T.ColorCode(T.KeyColor(lvl, timed)) .. "+" .. lvl .. "|r  "
        .. (timed and "timed" or "over time")) or (mapID and "No run here yet this season" or ""))

    if slotted then
        frame.state:Set(autoInserted and "Keystone inserted automatically" or "Keystone inserted", "good")
    elseif mapID then
        frame.state:Set("Keystone in your bags", "gold")
    else
        frame.state:Set("No keystone in your bags", "none")
    end

    -- Timer: +3 at 60 %, +2 at 80 %, +1 at the limit.
    frame.timer:SetShown(timeLimit ~= nil)
    if timeLimit then
        frame.timer.right:SetText(T.Clock(timeLimit) .. " total")
        for i, p in ipairs(TIERS) do
            frame.tiers[i]:SetText(T.ColorCode(p[3]) .. p[1] .. "|r  " .. T.Clock(timeLimit * p[2]))
        end
    end

    -- Affixes; the key's extra health and damage on the right.
    local extra = ""
    if level and level >= 3 and C_ChallengeMode.GetPowerLevelDamageHealthMod then
        local dmg, health = C_ChallengeMode.GetPowerLevelDamageHealthMod(level)
        dmg, health = D.Num(dmg), D.Num(health)
        if dmg and health then
            extra = dmg == health and ("|cffff9a4d+%d%%|r health and damage"):format(health)
                or ("|cffff9a4d+%d%%|r health  ·  |cffff9a4d+%d%%|r damage"):format(health, dmg)
        end
    end
    frame.affixes.right:SetText(extra)
    local list = {}
    for _, id in ipairs(affixes or {}) do
        local an, desc, icon = C_ChallengeMode.GetAffixInfo(id)
        if an then list[#list + 1] = { icon, an, desc } end
    end
    local x, y = 0, 0
    for i = 1, max(#list, #frame.affixChips) do
        local c = frame.affixChips[i]
        if list[i] then
            if not c then c = AffixChip(frame.affixes); frame.affixChips[i] = c end
            c:Set(unpack(list[i]))
            if x > 0 and x + c:GetWidth() > INNER then x, y = 0, y + 40 end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", frame.affixes, "TOPLEFT", x, -(14 + 13 + 12) - y)
            x = x + c:GetWidth() + 8
            c:Show()
        elseif c then
            c:Hide()
        end
    end
    frame.affixH = y + 32
    frame.affixes:SetShown(#list > 0 or extra ~= "")

    frame.go:SetEnabled(slotted and not count)
end

local function PaintPull()
    local v = (DB() and DB().pullTimer) or PULL_DEFAULT
    frame.pullValue:SetText(v .. "|cff8d98a8 s|r")
    frame.saved:SetText("Saved for your account:  |cffe0b868" .. v .. " s|r  next time too")
    for _, b in ipairs(frame.marks) do b:SetVariant(b.value == v and "ghost" or "mark") end
    if count then
        frame.pullBtn:SetLabel("Cancel"); frame.pullBtn:SetVariant("quiet")
    else
        frame.pullBtn:SetLabel("Pull Timer  ·  " .. v .. " s"); frame.pullBtn:SetVariant("ghost")
    end
    for key, s in pairs(frame.switches) do s:SetChecked(Opt(key)) end
end

-- The dot circle fills clockwise from the top while the countdown runs.
local function PaintCount()
    local f = count and count.total and count.endAt and min(1, max(0, 1 - (count.endAt - GetTime()) / count.total)) or 0
    local lit = floor(f * #frame.dots + 0.5)
    for i, d in ipairs(frame.dots) do
        if i <= lit then d:SetVertexColor(unpack(C.goldLight)); d:SetSize(4, 4)
        else d:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.35); d:SetSize(3, 3) end
    end
    Recolor(frame.core, count and C.goldLight or { C.gold[1], C.gold[2], C.gold[3], 0.55 })
end

function KS.Refresh()
    if not (frame and frame:IsShown()) then return end
    PaintKey()
    PaintGroup()
    PaintPull()
    PaintCount()
    Layout()
end

-------------------------------------------------------------------------------
--  Ready check, countdown, start
-------------------------------------------------------------------------------
local function StartKey()
    if not C_ChallengeMode.HasSlottedKeystone() then Hint("Put your keystone in first.", true); return end
    local ok, started = pcall(C_ChallengeMode.StartChallengeMode)
    if not ok or started == false then
        ns.Print("WoW didn't let the window start the key: press Activate in Blizzard's window.")
        KS.Block()
        return
    end
    PlaySound(SOUNDKIT.UI_70_CHALLENGE_MODE_SOCKET_PAGE_ACTIVATE_BUTTON)
    if frame then frame:Hide() end   -- as Blizzard's window does once started
end

local function StopCount(text)
    if count and count.ticker then count.ticker:Cancel() end
    count = nil
    if not frame then return end
    frame.countText:Hide(); frame.countLabel:Hide()
    frame.level:Show(); frame.levelLabel:Show()
    if text then Hint(text) end
    KS.Refresh()
end

local function Tick()
    if not count then return end
    local left = count.endAt - GetTime()
    if left <= 0 then
        local start = count.start
        StopCount(start and nil or "Pull!")
        if start then StartKey() end
        return
    end
    frame.countText:SetText(math.ceil(left))
    PaintCount()
end

-- total: the countdown's length; start: activate the key at 0.
local function StartCount(left, total, start)
    if count and count.ticker then count.ticker:Cancel() end
    count = { endAt = GetTime() + left, total = total, start = start }
    count.ticker = C_Timer.NewTicker(0.1, Tick)
    frame.level:Hide(); frame.levelLabel:Hide()
    frame.countText:SetText(math.ceil(left))
    frame.countText:Show(); frame.countLabel:Show()
    A.FadeIn(frame.countText, 0.2)
    Hint(start and ("Pulling in %d s, the key starts at 0."):format(left) or ("Pulling in %d s."):format(left))
    KS.Refresh()
end

-- Blizzard's countdown, the same as typing /pull: BigWigs and DBM show it
-- as their pull bar (BigWigs even puts its /pull in C_PartyInfo.DoCountdown).
-- Solo too. When it's refused or never comes, our own count runs.
local function Pull(start)
    local v = (DB() and DB().pullTimer) or PULL_DEFAULT
    local sent = false
    if C_PartyInfo and C_PartyInfo.DoCountdown then
        local ok, res = pcall(C_PartyInfo.DoCountdown, v)
        sent = ok and res ~= false
    end
    -- Our count starts with the click, like the /pull bar; START_PLAYER_COUNTDOWN
    -- only corrects it when its times are readable (they're secret in lockdown).
    StartCount(v, v, start)
    if not sent then Hint(("Pulling in %d s (only you see this count)."):format(v)) end
end

local function CancelPull()
    local mine = count and count.start ~= nil
    if C_PartyInfo and C_PartyInfo.DoCountdown then pcall(C_PartyInfo.DoCountdown, 0) end
    if mine then flow = nil end
    StopCount("Pull timer cancelled.")
end

local function ReadyCheck()
    if not IsInGroup() then Hint("You're alone: no ready check needed."); return false end
    if not CanCheck() then Hint("Only the leader or an assistant can start a ready check.", true); return false end
    local fn = C_PartyInfo and C_PartyInfo.DoReadyCheck
    local ok = fn and pcall(fn)
    if not ok then Hint("The ready check didn't start.", true); return false end
    return true
end

-- After the ready check (or without one): the countdown, then the key.
local function Continue()
    if IsInGroup() and Opt("keystoneAutoStart") then
        flow = "pull"
        Pull(true)
    else
        flow = nil
        StartKey()
    end
end

local function Activate()
    if count then return end
    if not C_ChallengeMode.HasSlottedKeystone() then Hint("Put your keystone in first.", true); return end
    if IsInGroup() and Opt("keystoneReadyFirst") and CanCheck() and not AllReady() then
        flow = "ready"
        if not ReadyCheck() then flow = nil end
        return
    end
    Continue()
end

-------------------------------------------------------------------------------
--  Build
-------------------------------------------------------------------------------
local function Build()
    local f = CreateFrame("Frame", "GottaQueueEmAllKeystone", UIParent)
    frame = f
    f:SetSize(WIDE_W, 700)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:Hide()
    tinsert(UISpecialFrames, "GottaQueueEmAllKeystone")   -- Escape closes it
    local bg = W.Round(f, "BACKGROUND", C.bg)
    bg:SetAllPoints()
    local top = W.Tex(f, "BACKGROUND", nil, 1)
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(140)
    W.Gradient(top, "VERTICAL", { C.bg[1], C.bg[2], C.bg[3], 0 }, { C.bgTop[1], C.bgTop[2], C.bgTop[3], 1 })
    W.Border(f, C.lineStrong, "OVERLAY", 2)

    -- Header: title, MYTHIC+, close; drag to move.
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT")
    head:SetHeight(52)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() f:StartMoving() end)
    head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local hl = W.Tex(head, "BORDER", C.line)
    hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT"); PixelUtil.SetHeight(hl, 1, 1)
    local title = W.Text(head, "title")
    title:SetPoint("LEFT", PAD, 0)
    title:SetText("Start Keystone")
    local sub = W.Text(head, "tiny")
    f.sub = sub
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText("MYTHIC+")
    local close = CreateFrame("Button", nil, head)
    close:SetSize(28, 28)
    close:SetPoint("RIGHT", -12, 0)
    close.bg = W.Round(close, "BACKGROUND", { 0.63, 0.71, 0.84, 0 })
    close.bg:SetAllPoints()
    local bars = {}
    for i, a in ipairs({ 45, -45 }) do
        local t = W.Tex(close, "ARTWORK", C.muted)
        t:SetSize(14, 2); t:SetPoint("CENTER"); t:SetRotation(math.rad(a))
        bars[i] = t
    end
    close:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(0.63, 0.71, 0.84, 0.07)
        for _, t in ipairs(bars) do t:SetVertexColor(unpack(C.textHi)) end
    end)
    close:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(0.63, 0.71, 0.84, 0)
        for _, t in ipairs(bars) do t:SetVertexColor(unpack(C.muted)) end
    end)
    close:SetScript("OnClick", function() f:Hide() end)
    f.layout = W.Segmented(head, { { "tall", "1 column" }, { "wide", "2 columns" } }, 24)
    f.layout:SetPoint("RIGHT", close, "LEFT", -10, 0)
    f.layout.onChange = function(v)
        local d = DB()
        if d then d.keystoneWide = v == "wide" end
        KS.Refresh()
    end
    f.divider = W.Tex(f, "BORDER", C.line)
    f.divider:SetPoint("TOP", f, "TOPLEFT", INNER + 2 * PAD, -52 - 14)
    PixelUtil.SetWidth(f.divider, 1, 1)

    -- Hero: the ring, the key's state below it.
    local hero = CreateFrame("Frame", nil, f)
    f.hero = hero
    local ring = CreateFrame("Button", nil, hero)
    ring:SetSize(RING, RING)
    ring:SetPoint("TOP")
    ring:RegisterForClicks("LeftButtonUp")
    local R = RING / 2 - NODE / 2
    LineCircle(ring, R, C.line, 1, "BACKGROUND", 1)
    -- Pentagon between the points (top first, clockwise).
    local pts = {}
    for i = 1, 5 do
        local a = math.rad(90 - (i - 1) * 72)
        pts[i] = { math.cos(a) * R, math.sin(a) * R }
    end
    for i = 1, 5 do
        local a, b = pts[i], pts[i % 5 + 1]
        local l = ring:CreateLine(nil, "BACKGROUND", nil, 2)
        l:SetThickness(1)
        l:SetColorTexture(C.lineStrong[1], C.lineStrong[2], C.lineStrong[3], 0.14)
        l:SetStartPoint("CENTER", ring, a[1], a[2])
        l:SetEndPoint("CENTER", ring, b[1], b[2])
    end
    -- Dotted circle: fills gold during the countdown.
    f.dots = {}
    local DOTS, DR = 48, R * 0.82
    for i = 1, DOTS do
        local a = math.rad(90 - (i - 1) * 360 / DOTS)
        local d = W.Circle(ring, "BORDER", nil, 3)
        d:SetPoint("CENTER", ring, "CENTER", math.cos(a) * DR, math.sin(a) * DR)
        f.dots[i] = d
    end
    -- Core: a navy disc in a gold line, the level in the middle.
    local CR = R * 0.62
    local core = W.Circle(ring, "BORDER", C.navy, CR * 2, 1)
    core:SetPoint("CENTER")
    f.core = LineCircle(ring, CR, { C.gold[1], C.gold[2], C.gold[3], 0.55 }, 1.5, "ARTWORK")
    f.level = W.Text(ring, "key")
    f.level:SetPoint("CENTER", 0, 7)
    f.levelLabel = W.Text(ring, "tiny")
    f.levelLabel:SetPoint("TOP", f.level, "BOTTOM", 0, -1)
    f.levelLabel:SetText("KEYSTONE LEVEL")
    f.countText = W.Text(ring, "key", C.goldLight)
    f.countText:SetPoint("CENTER", 0, 7)
    f.countText:Hide()
    f.countLabel = W.Text(ring, "tiny", C.goldText)
    f.countLabel:SetPoint("TOP", f.countText, "BOTTOM", 0, -1)
    f.countLabel:SetText("PULL")
    f.countLabel:Hide()
    -- The five points: the group, gold once ready.
    f.nodes = {}
    for i = 1, 5 do
        local n = CreateFrame("Frame", nil, ring)
        n:SetSize(NODE, NODE)
        n:SetPoint("CENTER", ring, "CENTER", pts[i][1], pts[i][2])
        n.glow = W.Circle(n, "BACKGROUND", { C.gold[1], C.gold[2], C.gold[3], 0.22 }, NODE + 12)
        n.glow:SetPoint("CENTER")
        n.disc = W.Circle(n, "BORDER", C.panel, NODE)
        n.disc:SetPoint("CENTER")
        n.ring = n:CreateTexture(nil, "ARTWORK")
        n.ring:SetTexture(T.TEX .. "ring"); n.ring:SetAllPoints()
        n.glyph = W.Glyph(n, "dps", 14, C.muted, "OVERLAY")
        n.glyph:SetPoint("CENTER")
        f.nodes[i] = n
    end
    -- The keystone goes in by drag or click, like on Blizzard's slot.
    local function Slot() if CursorHasItem() then pcall(C_ChallengeMode.SlotKeystone) end end
    ring:SetScript("OnReceiveDrag", Slot)
    ring:SetScript("OnClick", Slot)
    ring:SetScript("OnEnter", function(self)
        if C_ChallengeMode.HasSlottedKeystone() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSlottedKeystone()
            GameTooltip:Show()
        end
    end)
    ring:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.state = StatePill(hero, 24, true)
    f.state:SetPoint("BOTTOM")

    -- The dungeon and your best there.
    local dg = CreateFrame("Frame", nil, f)
    f.dg = dg
    f.dungeon = W.Text(dg, "display", C.goldText)
    f.dungeon:SetPoint("TOP")
    f.dungeon:SetWidth(INNER)
    f.dungeon:SetJustifyH("CENTER")
    f.best = W.Text(dg, "bodySm", C.text2)
    f.best:SetPoint("TOP", f.dungeon, "BOTTOM", 0, -6)

    -- Timer: three parts for +3 / +2 / +1.
    local timer = Section(f)
    timer:SetLabel("Timer")
    f.timer = timer
    local x, labels, from = 0, {}, 0
    for i, p in ipairs(TIERS) do
        local w = floor(INNER * (p[2] - from)) - (i < 3 and 2 or 0)
        from = p[2]
        local t = W.Tex(timer, "ARTWORK", p[3])
        t:SetSize(w, 6)
        t:SetPoint("TOPLEFT", x, -(14 + 13 + 12))
        local l = W.Text(timer, "label", C.text2)
        l:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, -6)
        labels[i] = l
        x = x + w + 2
    end
    f.tiers = labels

    f.affixes = Section(f)
    f.affixes:SetLabel("Affixes")
    f.affixChips, f.affixH = {}, 32

    -- The group.
    f.group = Section(f)
    f.group:SetLabel("Group")
    f.rows, f.groupN = {}, 1
    for i = 1, 5 do f.rows[i] = MemberRow(f.group) end

    -- Pull timer: the slider, quick picks, what Activate does.
    local pull = Section(f)
    f.pull = pull
    pull.label:SetPoint("TOPLEFT", 0, -20)
    pull:SetLabel("Pull timer")
    f.pullValue = W.Text(pull, "num")
    f.pullValue:SetPoint("TOPRIGHT", 0, -12)
    local db = DB()
    local slider = W.Slider(pull, { min = PULL_MIN, max = PULL_MAX, step = 1, fill = "left",
                                    value = (db and db.pullTimer) or PULL_DEFAULT })
    slider:SetPoint("TOPLEFT", 8, -48); slider:SetPoint("TOPRIGHT", -8, -48)
    slider.onChange = function(v)
        local d = DB()
        if d then d.pullTimer = v end
        PaintPull()
    end
    f.slider = slider
    for _, v in ipairs({ 3, 10, 20, 30 }) do
        local l = W.Text(pull, "tiny", C.faint)
        l:SetPoint("TOP", slider, "BOTTOMLEFT", (v - PULL_MIN) / (PULL_MAX - PULL_MIN) * (INNER - 16), 0)
        l:SetText(v)
    end
    f.marks = {}
    local mw = floor((INNER - 3 * 6) / 4)
    for i, v in ipairs(QUICK) do
        local b = W.Button(pull, v .. " s", "mark", mw, 28, "label")
        b:SetPoint("TOPLEFT", (i - 1) * (mw + 6), -94)
        b.value = v
        b:SetScript("OnClick", function() slider:SetValue(v, true) end)
        f.marks[i] = b
    end
    f.switches = {}
    local opts = {
        { "keystoneAutoStart", "Start the key when the pull timer ends" },
        { "keystoneReadyFirst", "Ready check first, start only when all are ready" },
    }
    local sy = -136
    for _, o in ipairs(opts) do
        local s = W.Switch(pull)
        s:SetPoint("TOPLEFT", 0, sy)
        s.onChange = function(on)
            local d = DB()
            if d then d[o[1]] = on end
        end
        local l = W.Text(pull, "bodySm", C.text2)
        l:SetPoint("LEFT", s, "RIGHT", 10, 0)
        l:SetText(o[2])
        f.switches[o[1]] = s
        sy = sy - 28
    end
    f.saved = W.Text(pull, "small")
    f.saved:SetPoint("TOPLEFT", 0, sy - 6)
    f.pullH = -sy + 6 + 13 + 16

    -- Footer: a darker band with the three steps and a line on what happens.
    local foot = CreateFrame("Frame", nil, f)
    f.foot = foot
    foot:SetPoint("BOTTOMLEFT", 1, 1); foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(14 + 32 + 8 + 14 + 14)
    local fb = W.Tex(foot, "BACKGROUND", { 0, 0, 0, 0.18 })
    fb:SetAllPoints()
    local fl = W.Tex(foot, "BORDER", C.line)
    fl:SetPoint("TOPLEFT"); fl:SetPoint("TOPRIGHT"); PixelUtil.SetHeight(fl, 1, 1)
    local rc = W.Button(foot, "Ready Check", "ghost", 120, 32)
    f.readyBtn = rc
    rc:SetPoint("TOPLEFT", PAD - 1, -14)
    rc:SetScript("OnClick", function() flow = nil; ReadyCheck() end)
    f.pullBtn = W.Button(foot, "Pull Timer", "ghost", 120, 32)
    f.pullBtn:SetPoint("LEFT", rc, "RIGHT", 8, 0)
    f.pullBtn:SetScript("OnClick", function() if count then CancelPull() else flow = nil; Pull(false) end end)
    f.go = W.Button(foot, "Activate", "gold", 150, 32, "h2")
    f.go:SetPoint("LEFT", f.pullBtn, "RIGHT", 8, 0)
    f.go:SetScript("OnClick", Activate)
    f.hint = W.Text(foot, "small")
    f.hint:SetPoint("TOP", 0, -14 - 32 - 8)

    f:SetScript("OnHide", function(self)
        if count then CancelPull() end
        flow = nil
        if self.keepOpen then self.keepOpen = nil; return end   -- Blizzard's window takes over
        local b = Blizz()
        if b and b:IsShown() then b:Hide() end   -- closes the Font of Power
    end)
end

-------------------------------------------------------------------------------
--  Showing
-------------------------------------------------------------------------------
-- Painted before the rise starts: colors set while its fade runs came out
-- without their alpha on the first open (opaque pills, switches, dots), so
-- they are painted once more when it ends.
local function Appear()
    A.Rise(frame, 0, -12, 0.35)
    C_Timer.After(0.4, KS.Refresh)
end

function KS.Open()
    if InCombatLockdown() then SetSeen(true); return end
    if not frame then Build() end
    autoInserted = false
    if not C_ChallengeMode.HasSlottedKeystone() then
        autoInserted = Insert() or false
    end
    Hint(IsInGroup() and "Ready check, pull timer and start in one go: press Activate." or "Activate starts the key.")
    if not frame:IsShown() then
        frame:Show()
        KS.Refresh()
        Appear()
    else
        KS.Refresh()
    end
end

-- /gotta keystone: the window with the key from your bags, away from the
-- Font of Power (nothing can be put in or started there).
function KS.Preview()
    if InCombatLockdown() then ns.Print("the keystone window opens after combat."); return end
    if not frame then Build() end
    autoInserted = false
    frame:Show()
    KS.Refresh()
    Appear()
    Hint("Preview: at the Font of Power, Activate starts the key.")
end

local hooked = false
local function Hook()
    local b = Blizz()
    if hooked or not b then return end
    hooked = true
    b:HookScript("OnShow", function()
        if KS.Active() then SetSeen(false); KS.Open() else SetSeen(true) end
    end)
    b:HookScript("OnHide", function()
        SetSeen(true)
        if frame and frame:IsShown() then frame:Hide() end
    end)
    if b:IsShown() and KS.Active() then SetSeen(false); KS.Open() end
end

-- WoW blocked our start: Blizzard's window answers from now on.
function KS.Block()
    blocked = true
    SetSeen(true)
    if frame and frame:IsShown() then
        frame.keepOpen = true   -- Blizzard's window and the Font of Power stay open
        frame:Hide()
    end
end

-- The setting changed: ours or Blizzard's window.
function KS.SettingChanged()
    local b = Blizz()
    if not (b and b:IsShown()) then return end
    if KS.Active() then SetSeen(false); KS.Open()
    else
        SetSeen(true)
        if frame and frame:IsShown() then frame.keepOpen = true; frame:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Events (few and rare: the Font of Power, ready checks, countdowns)
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN", "CHALLENGE_MODE_KEYSTONE_SLOTTED", "CHALLENGE_MODE_START",
                     "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED", "START_PLAYER_COUNTDOWN",
                     "CANCEL_PLAYER_COUNTDOWN", "GROUP_ROSTER_UPDATE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(events.RegisterEvent, events, e)   -- unknown events are skipped
end
events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_ChallengesUI" then Hook() end
        return
    elseif event == "PLAYER_LOGIN" or event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
        Hook()
        return
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg1 == ADDON and type(arg2) == "string" and frame and frame:IsShown()
           and (arg2:find("StartChallengeMode") or arg2:find("SlotKeystone")) then
            ns.Print("WoW didn't let the window start the key: Blizzard's keystone window takes over.")
            KS.Block()
        end
        return
    end
    if not (frame and frame:IsShown()) then return end

    if event == "CHALLENGE_MODE_START" then
        frame:Hide()
    elseif event == "READY_CHECK" then
        wipe(ready)
        for _, unit in ipairs(UNITS) do
            if UnitExists(unit) then ready[unit] = D.Str(GetReadyCheckStatus(unit)) or "waiting" end
        end
        Hint("Ready check running…")
    elseif event == "READY_CHECK_CONFIRM" then
        for _, unit in ipairs(UNITS) do
            local st = UnitExists(unit) and D.Str(GetReadyCheckStatus(unit))
            if st then ready[unit] = st end
        end
        if type(arg1) == "string" and not issecret(arg1) then
            for _, unit in ipairs(UNITS) do
                if UnitExists(unit) and UnitIsUnit(unit, arg1) then ready[unit] = arg2 and "ready" or "notready" end
            end
        end
    elseif event == "READY_CHECK_FINISHED" then
        readyAt = GetTime()
        local missing = {}
        for _, m in ipairs(Members()) do
            if ready[m.unit] ~= "ready" then
                ready[m.unit] = "notready"
                missing[#missing + 1] = m.name
            end
        end
        if #missing == 0 then
            Hint("Everyone is ready.")
            if flow == "ready" then Continue() end
        else
            flow = nil
            local ok, names = pcall(table.concat, missing, ", ")
            Hint(ok and ("Not ready: " .. names) or "Not everyone is ready.", true)
        end
    elseif event == "START_PLAYER_COUNTDOWN" then
        local left, total = D.Num(arg2), D.Num(arg3)
        if left and left > 0 then
            if count and math.abs(count.endAt - (GetTime() + left)) < 1 then
                count.endAt, count.total = GetTime() + left, total or left   -- ours: just in step
            else
                StartCount(left, total or left, count and count.start or false)
            end
        end
        return
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        if count then flow = nil; StopCount("Pull timer cancelled.") end
        return
    end
    KS.Refresh()
end)
