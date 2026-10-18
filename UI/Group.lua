-------------------------------------------------------------------------------
--  UI/Group.lua  --  the Your Group tab: your listing and its applicants
--
--  Banner with the listed dungeon's journal art, key, requirements; Delist
--  and Edit requirements (UpdateListing, keeping the title Blizzard wrote).
--  Your party's slots, then the applicants: rating, item level, best run in
--  the listed dungeon, lust / battle res, Invite / Decline - all direct
--  calls (they work from a click, with Blizzard's window closed).
--  The waiting count shows as the tab's badge.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A, D = UI.Theme, UI.W, UI.Anim, UI.Data
local C, S = T.C, T.S
local floor, max, min = math.floor, math.max, math.min

local G = { rows = {}, slots = {} }
UI.Group = G

local ROLE_NAME = { TANK = TANK or "Tank", HEALER = HEALER or "Healer", DAMAGER = DAMAGER or "Damage" }
local LINE_H, ROW_PAD = 40, 7
-- Column x of a member line (row width 944).
local X = { name = 40, role = 252, rating = 302, ilvl = 432, best = 562, brings = 652 }
local SORTS = { { "rating", "Rating" }, { "ilvl", "Item level" }, { "best", "Best here" } }

-- An applicant who isn't waiting for an answer any more.
local STATUS_LABEL = { invited = "Invited · waiting", inviteaccepted = "Joined", declined = "Declined",
                       declined_full = "Declined", declined_delisted = "Declined", timedout = "Timed out",
                       cancelled = "Cancelled", failed = "Failed", invitedeclined = "Said no" }

local Render   -- forward

local function State()
    local db = ns.DB and ns.DB()
    local st = G.tmp or {}
    if db then
        db.ui = db.ui or {}
        if type(db.ui.group) ~= "table" then db.ui.group = {} end
        st = db.ui.group
    end
    G.tmp = st
    st.sort = st.sort or "rating"
    return st
end

local function Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.Print("that didn't work (" .. tostring(err) .. ")") end
end

-------------------------------------------------------------------------------
--  Banner and requirements editor
-------------------------------------------------------------------------------
local function BuildBanner(page)
    local b = W.Banner(page)
    b:SetPoint("TOPLEFT", S.pad, -14)
    b:SetPoint("TOPRIGHT", -S.pad, -14)
    b:SetHeight(124)
    b.name = W.Text(b, "display")
    b.name:SetPoint("TOPLEFT", 20, -18)
    b.name:SetShadowOffset(0, -2); b.name:SetShadowColor(0, 0, 0, 0.5)
    b.key = W.Pill(b, "", { 1, 0.54, 0.16, 0.6 }, { 1, 0.54, 0.16, 0.16 })
    b.key.text:SetFontObject(T.Font.h2)
    b.key:SetHeight(28)
    b.key:SetPoint("LEFT", b.name, "RIGHT", 12, 0)
    b.pills = {}
    for i = 1, 4 do
        local p = W.Pill(b, "")
        if i == 1 then p:SetPoint("BOTTOMLEFT", 20, 16) else p:SetPoint("LEFT", b.pills[i - 1], "RIGHT", 6, 0) end
        b.pills[i] = p
    end
    b.live = W.Pill(b, "", { 0.24, 0.69, 0.38, 0.4 }, { 0.04, 0.055, 0.08, 0.6 })
    b.live.text:SetTextColor(unpack(C.goodText))
    b.live:SetHeight(28)
    b.live:SetPoint("TOPRIGHT", -20, -16)
    local dot = W.Circle(b.live, "ARTWORK", C.good, 8)
    dot:SetPoint("LEFT", 11, 0)
    A.Ping(b.live, dot, C.good, 8)

    b.edit = W.Button(b, "Edit requirements", "ghost", 150)
    b.edit:SetPoint("BOTTOMRIGHT", -20, 14)
    b.edit:SetScript("OnClick", function()
        G.editOpen = not G.editOpen
        if G.editOpen and G.entry then
            G.edit.Open(G.entry)
        end
        Render()
    end)
    b.delist = W.Button(b, "Delist", "quiet", 90)
    b.delist:SetPoint("RIGHT", b.edit, "LEFT", -8, 0)
    b.delist:SetScript("OnClick", function() Try(D.Delist) end)
    G.banner = b
end

local function BuildEditor(page)
    local e = W.Panel(page, C.panel, { 0.82, 0.64, 0.30, 0.32 })
    e:SetPoint("TOPLEFT", G.banner, "BOTTOMLEFT", 0, -10)
    e:SetPoint("TOPRIGHT", G.banner, "BOTTOMRIGHT", 0, -10)
    e:SetHeight(92)
    local mine = C_ChallengeMode.GetOverallDungeonScore and D.Num(C_ChallengeMode.GetOverallDungeonScore()) or 0
    mine = floor(mine)
    local _, myIlvl = GetAverageItemLevel()
    myIlvl = floor(D.Num(myIlvl) or 0)

    -- Each column's parts, so a raid listing can hide the rating column.
    e.parts = {}
    local function Column(x, w, label, slider, valueText, marks)
        local parts = { slider }
        e.parts[label] = parts
        local l = W.Label(e, label); l:SetPoint("TOPLEFT", x, -10)
        local v = W.Text(e, "h2"); v:SetPoint("TOPRIGHT", e, "TOPLEFT", x + w, -8)
        parts[#parts + 1] = l; parts[#parts + 1] = v
        slider:SetPoint("TOPLEFT", x, -32); slider:SetWidth(w)
        local mx = x
        for _, m in ipairs(marks) do
            local b = W.Button(e, m[1], "mark", nil, 22, "tiny")
            b:SetWidth(b.label:GetStringWidth() + 18)
            b:SetPoint("TOPLEFT", mx, -60)
            -- m[2]: a value, or a function giving it at click time.
            b:SetScript("OnClick", function() slider:SetValue(type(m[2]) == "function" and m[2]() or m[2], true) end)
            mx = mx + b:GetWidth() + 4
            parts[#parts + 1] = b
        end
        slider.onChange = function(val) valueText(v, val) end
        valueText(v, slider.value)
    end

    e.rating = W.Slider(e, { min = 0, max = 3600, step = 50, value = 0, stops = T.RATING_STOPS,
                             marker = mine > 0 and mine or nil })
    local rMarks = { { "Any", 0 } }
    if mine >= 200 then rMarks[#rMarks + 1] = { "Mine −200", mine - 200 } end
    if mine > 0 then rMarks[#rMarks + 1] = { "Mine " .. mine, mine } end
    Column(14, 330, "Minimum rating", e.rating, function(v, val)
        v:SetText(val > 0 and (val .. "+") or "Any")
        v:SetTextColor(unpack(val > 0 and T.RatingColor(val) or C.label))
    end, rMarks)

    -- Blizzard refuses an item level above your own (as in + Create).
    local lo = max(0, myIlvl - 40)
    e.ilvl = W.Slider(e, { min = lo, max = max(lo + 1, myIlvl), step = 1, value = lo, fill = true })
    Column(372, 300, "Minimum item level", e.ilvl, function(v, val)
        v:SetText(val > e.ilvl.lo and (val .. "+") or "Any")
    end, { { "Any", function() return e.ilvl.lo end },   -- the range's bottom, which e.Open may lower
           { "Mine −10", myIlvl - 10 }, { "Mine " .. myIlvl, myIlvl } })

    -- Opening shows the listing's values; the item level range grows to hold
    -- a requirement outside it, so saving never changes what wasn't touched.
    function e.Open(entry)
        -- One below the listing's value: "Any" is the bottom of the range.
        e.ilvl.lo = min(lo, entry.ilvl > 0 and entry.ilvl - 1 or lo)
        e.ilvl.hi = max(myIlvl, entry.ilvl, e.ilvl.lo + 1)
        e.rating:SetValue(entry.rating, true)
        for _, part in ipairs(e.parts["Minimum rating"]) do part:SetShown(entry.mplus and true or false) end
        e.ilvl:SetValue(entry.ilvl > 0 and entry.ilvl or e.ilvl.lo, true)
        e.ilvl:Layout()
    end

    local save = W.Button(e, "Update listing", "gold", 180, 40, "h2")
    save:SetPoint("RIGHT", -14, 0)
    save:SetScript("OnClick", function()
        if not G.entry then return end
        -- Blizzard refuses a minimum rating above your own (as in + Create);
        -- your rating now, not when the editor was built.
        local now = floor(C_ChallengeMode.GetOverallDungeonScore and D.Num(C_ChallengeMode.GetOverallDungeonScore()) or 0)
        if e.rating.value > now and e.rating.value ~= G.entry.rating then
            ns.Print("the minimum rating can't be above your own (" .. now .. ").")
            return
        end
        local ilvl = e.ilvl.value > e.ilvl.lo and e.ilvl.value or 0
        Try(D.UpdateListing, G.entry, e.rating.value, ilvl)
        G.editOpen = false
        Render()
    end)
    e:Hide()
    G.edit = e
end

local function FillBanner(entry)
    local b = G.banner
    -- A raid or a dungeon without a key: that section's instance facts.
    local RB = entry.raid and UI.RaidBrowse or entry.isDungeon and UI.DungeonBrowse or nil
    local raid = RB and entry.gid and RB.Raid(entry.gid)
    local art = T.DungeonArt(entry.cid)
    if raid and raid.art then b:SetArt(raid.art, 175 / 95, { 0.048, 0.636, 0, 0.742 })
    elseif raid then b:SetArt(art.bg or art.lore, 2)
    elseif art.bg then b:SetArt(art.bg, 2)
    else b:SetArt(art.lore or art.framed, 2.13, { 0.06, 0.70, 0.10, 0.70 }) end
    b.name:SetText(raid and raid.name or entry.dungeon)
    local diff = raid and RB.DIFF[entry.diff]
    if diff then
        b.key:SetText(diff.name)   -- the difficulty where a key's level goes
        b.key.text:SetTextColor(unpack(diff.color))
    elseif entry.keyLevel then
        b.key:SetText("+" .. entry.keyLevel)
        b.key.text:SetTextColor(unpack(T.KeyColor(entry.keyLevel)))
    else
        pcall(b.key.SetText, b.key, entry.title)   -- the title Blizzard wrote ("+12 Relaxed")
        b.key.text:SetTextColor(unpack(C.textHi))
    end
    local texts = {}
    local ps = D.PlaystyleLabel(entry.playstyle)
    if ps then texts[#texts + 1] = ps end
    if entry.mplus then
        texts[#texts + 1] = entry.rating > 0 and ("Rating " .. T.ColorCode(T.RatingColor(entry.rating)) .. entry.rating .. "+|r")
                            or "No rating needed"
    end
    texts[#texts + 1] = entry.ilvl > 0 and ("Item level |cfff5f7fa" .. entry.ilvl .. "+|r") or "Any item level"
    if entry.private then texts[#texts + 1] = "Private" end
    if raid then   -- your lockout there (the group's progress)
        local mine, color = RB.Lockout(raid)
        texts[#texts + 1] = mine and ("Lockout " .. T.ColorCode(color) .. mine .. "|r") or "Fresh lockout"
    end
    for i, p in ipairs(b.pills) do
        p:SetShown(texts[i] ~= nil)
        if texts[i] then p:SetText(texts[i]) end
    end
    b.edit:SetLabel(G.editOpen and "Close" or "Edit requirements")
    local manage = D.CanManage()
    b.edit:SetEnabled(manage); b.delist:SetEnabled(manage)
end

local function LiveText()
    if G.listedAt then return "      Listed " .. T.Clock(GetTime() - G.listedAt) end
    return "      Listed"
end

-------------------------------------------------------------------------------
--  Party slots
-------------------------------------------------------------------------------
local function BuildSlots(page)
    local row = CreateFrame("Frame", nil, page)
    row:SetHeight(58)
    G.slotRow = row
    for i = 1, 5 do
        local s = W.Panel(row, C.panel, C.line)
        s.badge = W.RoleBadge(s, 30)
        s.badge:SetPoint("LEFT", 12, 0)
        s.name = W.Text(s, "h2")
        s.name:SetPoint("TOPLEFT", s.badge, "TOPRIGHT", 10, 1)
        s.name:SetPoint("TOPRIGHT", s, "TOPRIGHT", -8, -13)
        s.sub = W.Text(s, "tiny")
        s.sub:SetPoint("TOPLEFT", s.name, "BOTTOMLEFT", 0, -3)
        s.sub:SetPoint("TOPRIGHT", s.name, "BOTTOMRIGHT", 0, -3)
        G.slots[i] = s
    end
    row:SetScript("OnSizeChanged", function(self, w)
        local sw = (w - 4 * 8) / 5
        for i, s in ipairs(G.slots) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", (i - 1) * (sw + 8), 0)
            s:SetSize(sw, 58)
        end
    end)
end

-- A raid: the five panels count roles instead (up to 30 players), then
-- Lust / battle res and the raid's size.
local function FillRaidSlots(entry)
    local members = D.GroupMembers()
    local n = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    local lust, brez = false, false
    for _, m in ipairs(members) do
        n[m.role] = n[m.role] + 1
        if m.class and ns.LUST_CLASS[m.class] then lust = true end
        if m.class and ns.BREZ_CLASS[m.class] then brez = true end
    end
    local healers = entry.diff == 16 and 4 or 6
    local rows = {
        { "TANK", n.TANK .. " " .. (n.TANK == 1 and ROLE_NAME.TANK or "Tanks"), "a raid usually takes 2", n.TANK >= 2 },
        { "HEALER", n.HEALER .. " " .. (n.HEALER == 1 and ROLE_NAME.HEALER or "Healers"), "usually " .. healers, n.HEALER >= healers },
        { "DAMAGER", n.DAMAGER .. " " .. ROLE_NAME.DAMAGER, "the rest of the raid", false },
        { nil, (lust and "|cffff9a4dBloodlust|r" or "|cff4e5a6bNo Bloodlust|r"),
          brez and "Battle res: |cff86e0a2yes|r" or "Battle res: none yet", lust },
        { nil, #members .. " / " .. (entry.max or 30), "players in your raid", false },
    }
    for i, s in ipairs(G.slots) do
        local r = rows[i]
        s.badge:SetShown(r[1] ~= nil)
        if r[1] then s.badge:Set(r[1], n[r[1]] > 0 and true or nil) end
        s.name:SetText(r[2])
        s.name:SetTextColor(unpack(C.textHi))
        s.sub:SetText(r[3])
        s.bg:SetVertexColor(unpack(C.raised))
        W.SetBorder(s, r[4] and { 0.24, 0.69, 0.38, 0.45 } or C.lineStrong)
        s:Show()
    end
end

local function FillSlots(entry)
    if entry and entry.raid then FillRaidSlots(entry); return end
    for _, s in ipairs(G.slots) do s.badge:Show() end
    local members = D.GroupMembers()
    local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
    for _, m in ipairs(members) do table.insert(byRole[m.role], m) end
    -- Members first (by role), then open spots while there is room.
    local list = {}
    for _, role in ipairs(D.ROLE_KEYS) do
        for _, m in ipairs(byRole[role]) do list[#list + 1] = { role = role, m = m } end
    end
    for _, role in ipairs(D.ROLE_KEYS) do
        local want = role == "DAMAGER" and 3 or 1
        for _ = #byRole[role] + 1, want do
            if #list < 5 then list[#list + 1] = { role = role } end
        end
    end
    local order = { TANK = 1, HEALER = 2, DAMAGER = 3 }
    table.sort(list, function(a, b)
        if order[a.role] ~= order[b.role] then return order[a.role] < order[b.role] end
        return (a.m and 0 or 1) < (b.m and 0 or 1)
    end)
    for i, s in ipairs(G.slots) do
        local e = list[i]
        if e and e.m then
            local m = e.m
            s.badge:Set(e.role, m.class or true)
            s.name:SetText(m.name)
            s.name:SetTextColor(unpack(T.ClassColor(m.class)))
            local sub = {}
            if m.spec then sub[#sub + 1] = m.spec end
            if m.rating then sub[#sub + 1] = T.ColorCode(T.RatingColor(m.rating)) .. floor(m.rating) .. "|r" end
            if m.ilvl then sub[#sub + 1] = "ilvl " .. m.ilvl end
            s.sub:SetText(table.concat(sub, "  ·  "))
            s.bg:SetVertexColor(unpack(C.raised))
            W.SetBorder(s, C.lineStrong)
        elseif e then
            s.badge:Set(e.role, nil)
            s.name:SetText(ROLE_NAME[e.role])
            s.name:SetTextColor(unpack(C.faint))
            s.sub:SetText("Open spot")
            s.bg:SetVertexColor(0, 0, 0, 0)
            W.SetBorder(s, C.line)
        end
        s:SetShown(e ~= nil)
    end
end

-------------------------------------------------------------------------------
--  Applicant rows
-------------------------------------------------------------------------------
local function NewLine(row)
    local l = {}
    l.name = W.Text(row, "h2")
    l.sub = W.Text(row, "tiny")
    l.sub:SetWidth(X.role - X.name - 6)   -- spec, LOOKING FOR, MAIN: cut before the role column
    l.badge = W.RoleBadge(row, 26)
    l.rating = W.Text(row, "numSm")
    l.rmeter = W.Meter(row, 110)
    l.ilvl = W.Text(row, "numSm")
    l.imeter = W.Meter(row, 110)
    l.best = W.Text(row, "bodySm")
    l.lust = W.Glyph(row, "lust", 24, C.lust)
    l.brez = W.Glyph(row, "brez", 24, C.brez)
    return l
end

local function PlaceLine(row, l, i)
    local y = -(ROW_PAD + (i - 1) * LINE_H)
    l.name:ClearAllPoints(); l.name:SetPoint("TOPLEFT", row, "TOPLEFT", X.name, y - 2)
    l.sub:ClearAllPoints(); l.sub:SetPoint("TOPLEFT", l.name, "BOTTOMLEFT", 0, -2)
    l.badge:ClearAllPoints(); l.badge:SetPoint("TOPLEFT", row, "TOPLEFT", X.role, y - 6)
    l.rating:ClearAllPoints(); l.rating:SetPoint("TOPLEFT", row, "TOPLEFT", X.rating, y - 3)
    l.rmeter:ClearAllPoints(); l.rmeter:SetPoint("TOPLEFT", l.rating, "BOTTOMLEFT", 0, -5)
    l.ilvl:ClearAllPoints(); l.ilvl:SetPoint("TOPLEFT", row, "TOPLEFT", X.ilvl, y - 3)
    l.imeter:ClearAllPoints(); l.imeter:SetPoint("TOPLEFT", l.ilvl, "BOTTOMLEFT", 0, -5)
    l.best:ClearAllPoints(); l.best:SetPoint("TOPLEFT", row, "TOPLEFT", X.best, y - 10)
    l.lust:ClearAllPoints(); l.lust:SetPoint("TOPLEFT", row, "TOPLEFT", X.brings, y - 6)
end

local function ShowLine(l, shown)
    for _, k in ipairs({ "name", "sub", "badge", "rating", "rmeter", "ilvl", "imeter", "best", "lust", "brez" }) do
        l[k]:SetShown(shown)
    end
end

local function RowTooltip(row)
    local a = row.a
    if not a then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(#a.members > 1 and ("Group of " .. #a.members) or a.members[1].name, 1, 1, 1)
    local c = a.comment
    local empty = c == nil or (type(c) == "string" and not (issecretvalue and issecretvalue(c)) and c == "")
    if empty or not pcall(GameTooltip.AddLine, GameTooltip, c, 0.85, 0.85, 0.85, true) then
        GameTooltip:AddLine("No note", 0.55, 0.6, 0.68)
    end
    -- Raider.IO profile of each member (if installed).
    for _, m in ipairs(a.members) do
        if m.fullName then
            GameTooltip:AddLine(" ")
            if #a.members > 1 then GameTooltip:AddLine(m.name, unpack(T.ClassColor(m.class))) end
            D.RaiderIOTooltip(GameTooltip, m.fullName)
        end
    end
    GameTooltip:Show()
end

local function NewRow(parent)
    local row = W.Card(parent)
    row.lines = {}
    row.dot = W.Circle(row, "ARTWORK", C.gold, 8)
    row.dot:SetPoint("TOPLEFT", 14, -(ROW_PAD + 15))
    row.dotPulse = A.Pulse(row.dot, 0.25, 1.4)
    row.invite = W.Button(row, "Invite", "gold", 86)
    row.invite:SetPoint("RIGHT", -104, 0)
    row.invite:SetScript("OnClick", function(self) local a = self:GetParent().a; if a then Try(D.Invite, a.id) end end)
    row.decline = W.Button(row, "Decline", "quiet", 86)
    row.decline:SetPoint("RIGHT", -12, 0)
    row.decline:SetScript("OnClick", function(self) local a = self:GetParent().a; if a then Try(D.Decline, a.id) end end)
    row.waiting = W.Button(row, "Invited · waiting", "done", 178)
    row.waiting:SetPoint("RIGHT", -12, 0)
    row.waiting:EnableMouse(false)   -- a status, not a button (Disable would wash it out)
    row.waitPulse = A.Pulse(row.waiting, 0.6, 1.6)
    row.onEnter = RowTooltip
    row.onLeave = function() GameTooltip:Hide() end
    return row
end

local function FillRow(row, a)
    row.a = a
    local n = #a.members
    row:SetHeight(n * LINE_H + ROW_PAD * 2 - 4)
    for i, m in ipairs(a.members) do
        local l = row.lines[i] or NewLine(row)
        row.lines[i] = l
        PlaceLine(row, l, i)
        ShowLine(l, true)
        l.name:SetText(m.name)
        l.name:SetTextColor(unpack(T.ClassColor(m.class)))
        local sub = m.spec or (m.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class]) or ""
        -- What Create's "Looking for" asks for (the raid page's for a raid).
        -- Not Mythic+ (a raid, a dungeon without a key): no rating, no best run.
        local raidListing = G.entry and not G.entry.mplus
        local create = G.entry and (G.entry.raid and UI.RaidCreate or G.entry.isDungeon and UI.DungeonCreate) or UI.Create
        local want = create and create.State()
        if want and ((want.lust and m.lust) or (want.brez and m.brez)) then
            sub = sub .. "  |cffe0b868LOOKING FOR|r"
        end
        sub = sub .. D.MainTag(m.fullName, m.rating)   -- Raider.IO: an alt with a stronger main
        l.sub:SetText(sub)
        l.badge:Set(m.role, m.class or true)
        local rc = T.RatingColor(m.rating)
        l.rating:SetText(floor(m.rating)); l.rating:SetTextColor(unpack(rc))
        l.rmeter:SetValue(m.rating / 3600, rc)
        l.ilvl:SetText(("%.1f"):format(m.ilvl))
        l.imeter:SetValue((m.ilvl - (G.ilvlBase - 40)) / 50)   -- your item level -40 .. +10
        if m.best then
            l.best:SetText(T.ColorCode(T.KeyColor(m.best, m.timed)) .. "+" .. m.best .. "|r |cff8d98a8" .. (m.timed and "in time" or "over") .. "|r")
        else
            l.best:SetText("|cff8d98a8no run|r")
        end
        -- A raid listing: no Mythic+ rating or best run.
        l.rating:SetShown(not raidListing); l.rmeter:SetShown(not raidListing); l.best:SetShown(not raidListing)
        l.lust:SetShown(m.lust)
        l.brez:ClearAllPoints()
        l.brez:SetPoint("TOPLEFT", row, "TOPLEFT", X.brings + (m.lust and 26 or 0), -(ROW_PAD + (i - 1) * LINE_H) - 6)
        l.brez:SetShown(m.brez)
    end
    for i = n + 1, #row.lines do ShowLine(row.lines[i], false) end

    row.dot:SetShown(a.isNew and a.status == "applied")
    if row.dot:IsShown() then row.dotPulse:Play() else row.dotPulse:Stop() end
    local waiting = a.status == "applied"
    row.invite:SetShown(waiting); row.decline:SetShown(waiting)
    row.waiting:SetShown(not waiting)
    row.waiting:SetLabel(STATUS_LABEL[a.status] or "Pending")
    if row.waiting:IsShown() and a.status == "invited" then row.waitPulse:Play() else row.waitPulse:Stop() end
    local manage = D.CanManage()
    row.invite:SetEnabled(manage); row.decline:SetEnabled(manage)
end

local ORDER = {
    -- Ties by applicant ID: equal rows keep their places between renders.
    rating = function(a, b)
        local x, y = a.members[1].rating, b.members[1].rating
        if x ~= y then return x > y end
        return a.id < b.id
    end,
    ilvl   = function(a, b)
        local x, y = a.members[1].ilvl, b.members[1].ilvl
        if x ~= y then return x > y end
        return a.id < b.id
    end,
    best   = function(a, b)
        local x, y = a.members[1].best or 0, b.members[1].best or 0
        if x ~= y then return x > y end
        return a.id < b.id
    end,
}

-------------------------------------------------------------------------------
--  Render
-------------------------------------------------------------------------------
local function UpdateBadge(list)
    local n = 0
    for _, a in ipairs(list or {}) do if a.status == "applied" then n = n + 1 end end
    if UI.SetTabBadge then UI.SetTabBadge(2, n) end
    return n
end

Render = function(animate)
    if not G.page then return end
    local entry = D.Entry()
    G.entry = entry
    local listed = entry ~= nil
    G.banner:SetShown(listed)
    G.emptyBox:SetShown(not listed)
    if not listed then
        G.editOpen = false
        G.edit:Hide()
        G.content:Hide()
        UpdateBadge(nil)
        return
    end
    FillBanner(entry)
    G.banner.live:SetText(LiveText())
    G.edit:SetShown(G.editOpen and true or false)
    G.content:ClearAllPoints()
    G.content:SetPoint("TOPLEFT", G.editOpen and G.edit or G.banner, "BOTTOMLEFT", 0, -12)
    G.content:SetPoint("BOTTOMRIGHT", G.page, "BOTTOMRIGHT", -S.pad, 10)
    G.content:Show()
    FillSlots(entry)
    -- Mythic+ columns (rating, best run here) only for a Mythic+ listing.
    local mplus = entry.mplus
    for k, h in pairs(G.heads) do h:SetShown(mplus or (k ~= "rating" and k ~= "best")) end

    local _, myIlvl = GetAverageItemLevel()
    G.ilvlBase = math.floor(D.Num(myIlvl) or 300)
    local list = D.Applicants(entry.act)
    table.sort(list, ORDER[G.st.sort] or ORDER.rating)
    local waiting = UpdateBadge(list)
    -- Rise only for rows that weren't there before (or all, on opening).
    local seen = G.seen or {}
    G.seen = {}
    G.count:SetText(waiting == 1 and "1 waiting" or (waiting .. " waiting"))
    local y = 0
    for i, a in ipairs(list) do
        local row = G.rows[i] or NewRow(G.child)
        G.rows[i] = row
        FillRow(row, a)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", G.child, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", G.child, "TOPRIGHT", 0, -y)
        row:Show()
        if i <= 8 and (animate or not seen[a.id]) then A.Rise(row, (i - 1) * 0.05, 8, 0.35) end
        G.seen[a.id] = true
        y = y + row:GetHeight() + 6
    end
    for i = #list + 1, #G.rows do G.rows[i]:Hide() end
    G.child:SetHeight(max(1, y))
    G.scroll:SetVerticalScroll(min(G.scroll:GetVerticalScroll(), max(0, y - G.scroll:GetHeight())))
    G.noApps:SetShown(#list == 0)
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local queued = false
local function Queue(animate)
    if queued then return end
    queued = true
    C_Timer.After(0.1, function()
        queued = false
        if G.page and G.page:IsVisible() then Render(animate) else UpdateBadge(G.page and D.Applicants() or nil) end
    end)
end

-- Applicants and roster: only while the window is open (ns.Live). Your own
-- listing's changes always (rare): they date the "listed for" clock.
local events = CreateFrame("Frame")
ns.Live(events, { "LFG_LIST_APPLICANT_LIST_UPDATED", "LFG_LIST_APPLICANT_UPDATED", "GROUP_ROSTER_UPDATE",
                  "PLAYER_SPECIALIZATION_CHANGED" })
pcall(events.RegisterEvent, events, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        if arg1 == true then
            G.listedAt = GetTime()
            -- Just listed (Mythic+ or raid, from + Create): straight to the applicants.
            if UI.ActiveTab and UI.ActiveTab() == 3 and UI.SelectTab then UI.SelectTab(2) end
        end
        if not C_LFGList.HasActiveEntryInfo() then G.listedAt = nil end
        if not (G.page and G.page:GetParent():IsVisible()) then return end   -- closed: caught up on open
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 ~= "player" then
        return
    end
    Queue()
end)

-- The window opened: the tab's badge, whichever tab shows.
function G.Refresh() Queue() end

-------------------------------------------------------------------------------
--  Build
-------------------------------------------------------------------------------
function UI.BuildGroup(page)
    G.st = State()
    BuildBanner(page)
    BuildEditor(page)

    -- Not listed.
    local empty = W.Panel(page)
    empty:SetPoint("TOPLEFT", S.pad, -14); empty:SetPoint("TOPRIGHT", -S.pad, -14)
    empty:SetHeight(124)
    local et = W.Text(empty, "h2"); et:SetPoint("TOPLEFT", 20, -24); et:SetText("No group listed")
    local es = W.Text(empty, "bodySm", C.muted); es:SetPoint("TOPLEFT", et, "BOTTOMLEFT", 0, -8)
    es:SetText("List your keystone or a raid in + Create; your applicants show up here.")
    local eb = W.Button(empty, "Create a group", "gold", 170, 40, "h2")
    eb:SetPoint("RIGHT", -20, 0)
    eb:SetScript("OnClick", function() if UI.SelectTab then UI.SelectTab(3) end end)
    -- A secure overlay (UI/Window.lua) makes it prepare the listing, like the tab.
    UI.createTargets = UI.createTargets or {}
    table.insert(UI.createTargets, eb)
    G.emptyBox = empty

    -- Listed: slots, applicant header, list.
    local content = CreateFrame("Frame", nil, page)
    G.content = content
    BuildSlots(content)
    G.slotRow:SetPoint("TOPLEFT"); G.slotRow:SetPoint("TOPRIGHT")

    local lbl = W.Label(content, "Applicants")
    lbl:SetPoint("TOPLEFT", G.slotRow, "BOTTOMLEFT", 0, -16)
    G.count = W.Text(content, "small")
    G.count:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    G.sorts = {}
    local right
    for i = #SORTS, 1, -1 do
        local s = SORTS[i]
        local b = W.Button(content, s[2], "mark", nil, 24, "tiny")
        b:SetWidth(b.label:GetStringWidth() + 18)
        if right then b:SetPoint("RIGHT", right, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", G.slotRow, "BOTTOMRIGHT", 0, -11) end
        b.key = s[1]
        b:SetScript("OnClick", function()
            G.st.sort = s[1]
            for _, o in ipairs(G.sorts) do o:SetVariant(G.st.sort == o.key and "ghost" or "mark") end
            Render()
        end)
        G.sorts[#G.sorts + 1] = b
        right = b
    end
    for _, o in ipairs(G.sorts) do o:SetVariant(G.st.sort == o.key and "ghost" or "mark") end

    local heads = { { "name", "Player" }, { "role", "Role" }, { "rating", "Rating" }, { "ilvl", "Item level" },
                    { "best", "Best here" }, { "brings", "Brings" } }
    G.heads = {}
    for _, h in ipairs(heads) do
        local t = W.Text(content, "tiny", C.faint)
        t:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", X[h[1]], -14)
        t:SetText(h[2]:upper())
        G.heads[h[1]] = t
    end

    local scroll = CreateFrame("ScrollFrame", nil, content)
    scroll:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -34)
    scroll:SetPoint("BOTTOMRIGHT")
    G.scroll = scroll
    G.child = CreateFrame("Frame", nil, scroll)
    G.child:SetSize(944, 1)
    scroll:SetScrollChild(G.child)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then G.child:SetWidth(w) end end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, d)
        local limit = max(0, G.child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(limit, max(0, self:GetVerticalScroll() - d * 60)))
    end)
    G.noApps = W.Text(content, "body", C.muted)
    G.noApps:SetPoint("TOP", scroll, "TOP", 0, -40)
    G.noApps:SetText("No applicants right now. New ones appear here on their own.")

    page:SetScript("OnShow", function()
        Render(true)
        if UI.SetStatus then UI.SetStatus("Applicants update live") end
        G.ticker = C_Timer.NewTicker(1, function()
            if G.entry then G.banner.live:SetText(LiveText()) end
        end)
    end)
    page:SetScript("OnHide", function()
        if G.ticker then G.ticker:Cancel(); G.ticker = nil end
    end)
    G.page = page   -- last: events only act on a finished page
end
