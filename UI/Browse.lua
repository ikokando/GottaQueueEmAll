-------------------------------------------------------------------------------
--  UI/Browse.lua  --  the Browse tab: search, filter, sign up
--
--  Server-side filters (sent with the search): dungeons, minimum leader
--  rating, a free spot for your role. Client-side (hide what doesn't fit):
--  the key level (measured from the title, UI/KeyRead.lua), the leader's
--  best key in that dungeon, lust / battle res fit, declined.
--  Changing a server-side filter marks Search as pending; nothing searches
--  on its own (a search needs a click).
--  Settings persist in GottaQueueEmAllDB.ui.browse.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A, D = UI.Theme, UI.W, UI.Anim, UI.Data
local C, S = T.C, T.S
local floor, max, min = math.floor, math.max, math.min

local CARD_H, CARD_GAP = 86, 8
local STRIP_W = 136
local ROLE_NAME = { TANK = TANK or "Tank", HEALER = HEALER or "Healer", DAMAGER = DAMAGER or "Damage" }
local SORTS = { { "key", "Key" }, { "rating", "Rating" }, { "best", "Leader best" }, { "age", "Newest" } }

local B = { results = {}, cards = {}, chips = {} }
UI.Browse = B

local DEFAULT = { dungeons = {}, minRating = 0, keyMin = 2, keyMax = 20, expMin = 2, expMax = 20, spot = true,
                  fitLust = false, fitBrez = false, notDeclined = true, sort = "rating" }

local function State()
    local db = ns.DB and ns.DB()
    local st
    if db then
        db.ui = db.ui or {}
        if type(db.ui.browse) ~= "table" then db.ui.browse = {} end
        st = db.ui.browse
    else
        B.tmp = B.tmp or {}
        st = B.tmp
    end
    for k, v in pairs(DEFAULT) do
        if st[k] == nil then st[k] = type(v) == "table" and {} or v end
    end
    return st
end

local Render, MarkDirty   -- forward

-------------------------------------------------------------------------------
--  Dungeon chips
-------------------------------------------------------------------------------
local function BuildChips()
    local st = B.st
    local groups = ns.SeasonGroups and ns.SeasonGroups() or {}
    -- Rebuild only when the season's dungeons changed (the event fires often).
    local ids = {}
    for _, g in ipairs(groups) do ids[#ids + 1] = g.id end
    local key = table.concat(ids, ",")
    if B.chipKey == key and #B.chips > 0 then return end
    B.chipKey = key
    -- Picks from an earlier season would filter every search to nothing.
    local current = {}
    for _, id in ipairs(ids) do current[id] = true end
    for id in pairs(st.dungeons) do if not current[id] then st.dungeons[id] = nil end end

    for _, c in ipairs(B.chips) do c:Hide() end
    B.chips = {}
    local row = B.chipRow
    local all = W.Chip(row, "All dungeons")
    B.chips[1] = all
    for _, g in ipairs(groups) do
        local tex = g.cid and select(4, C_ChallengeMode.GetMapUIInfo(g.cid))
        local level, timed
        if ns.BestKey then level, timed = ns.BestKey(g.cid) end
        local c = W.Chip(row, T.Short(g.name), tex or "Interface\\Icons\\INV_Misc_QuestionMark",
            level and ("+" .. level) or nil, level and T.KeyColor(level, timed) or nil)
        c.groupID = g.id
        c:SetScript("OnEnter", nil)
        c:HookScript("OnEnter", function(self)
            self.hot = true; self:SetOn(self.on)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(g.name, 1, 1, 1)
            if level then
                GameTooltip:AddLine(("Your season best: +%d (%s)"):format(level, timed and "in time" or "over time"), 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        c:HookScript("OnLeave", function() GameTooltip:Hide() end)
        B.chips[#B.chips + 1] = c
    end

    local function Sync()
        local any = false
        for i = 2, #B.chips do
            local c = B.chips[i]
            c:SetOn(st.dungeons[c.groupID] and true or false)
            any = any or c.on
        end
        all:SetOn(not any)
    end
    all.onClick = function()
        wipe(st.dungeons)
        Sync(); MarkDirty()
    end
    for i = 2, #B.chips do
        B.chips[i].onClick = function(self)
            st.dungeons[self.groupID] = not st.dungeons[self.groupID] or nil
            Sync(); MarkDirty()
        end
    end
    Sync()
    B.LayoutChips()
end

-- Chips flow into rows by the row's width (again when the window resizes).
function B.LayoutChips()
    local row = B.chipRow
    local x, y, w = 0, 0, row:GetWidth() > 0 and row:GetWidth() or 944
    for _, c in ipairs(B.chips) do
        if x > 0 and x + c:GetWidth() > w then x, y = 0, y + T.S.chipH + 6 end
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", x, -y)
        c:Show()
        x = x + c:GetWidth() + 6
    end
    row:SetHeight(y + T.S.chipH)
end

-------------------------------------------------------------------------------
--  Filter bar
-------------------------------------------------------------------------------
local function UpdateHistogram()
    local counts = {}
    for i = 1, 12 do counts[i] = 0 end
    for _, r in ipairs(B.results) do
        local i = min(12, floor(r.rating / 300) + 1)
        counts[i] = counts[i] + 1
    end
    local st = B.st
    B.hist:SetData(counts, function(i) return T.RatingColor((i - 1) * 300 + 150) end,
        function(i) return i * 300 <= st.minRating end)
end

local function RatingText(v)
    B.ratingValue:SetText(v > 0 and (v .. "+") or "Any")
    B.ratingValue:SetTextColor(unpack(v > 0 and T.RatingColor(v) or C.label))
end

-- A +2 .. +20 range as the sliders show it; the top end is open (+20 = +20 and up).
local function RangeLabel(a, b)
    if a == 2 and b == 20 then return "Any" end
    if b == 20 then return "+" .. a .. " and up" end
    if a == b then return "+" .. a end
    return "+" .. a .. " – +" .. b
end

local function RangeText(a, b) B.rangeValue:SetText(RangeLabel(a, b)) end

local function PaintSorts()
    for _, s in ipairs(B.sorts) do s:SetVariant(B.st.sort == s.key and "ghost" or "mark") end
end

local function PaintSearch()
    local b = B.searchBtn
    if B.searching then
        b:SetLabel("Searching…"); b:Disable()
        B.pulse:Stop()
    else
        b:Enable()
        b:SetLabel(B.dirty and "Search again" or "Search")
        if B.dirty then B.pulse:Play() else B.pulse:Stop() end
    end
end

MarkDirty = function()
    B.dirty = true
    PaintSearch()
end

local function DoSearch()
    if B.searching then return end
    local ok, err = pcall(D.Search, B.st)
    if not ok then
        ns.Print("search failed (" .. tostring(err) .. ")")
        return
    end
    B.searching, B.dirty, B.ownSearch = true, false, true
    B.searchSeq = (B.searchSeq or 0) + 1
    local seq = B.searchSeq
    PaintSearch()
    -- No answer at all (throttled): release the button after a while, unless
    -- a newer search is running by then.
    C_Timer.After(6, function()
        if B.searching and seq == B.searchSeq then B.searching = false; PaintSearch() end
    end)
end

local function KeyText(a, b) B.keyValue:SetText(RangeLabel(a, b)) end

-- Key level: read from each group's title (UI/KeyRead.lua), filtered here.
-- When WoW stops giving the measure away, the slider says so and rests.
local function PaintKeyPanel()
    local works = UI.KeyRead and UI.KeyRead.Works() or false
    B.keySlider:SetAlpha(works and 1 or 0.35)
    B.keySlider:EnableMouse(works)
    B.keyNote:SetText(works and "The listed key, read from each group's title."
        or "Key levels can't be read right now: groups show their title.")
end

local function BuildFilters(bar, row2)
    local st = B.st

    -- Key level: client-side, so it filters the results right away.
    local pk = W.Panel(bar)
    pk:SetPoint("TOPLEFT"); pk:SetSize(220, 106)
    local lk = W.Label(pk, "Key level"); lk:SetPoint("TOPLEFT", 12, -10)
    B.keyValue = W.Text(pk, "h2"); B.keyValue:SetPoint("TOPRIGHT", -12, -8)
    B.keyNote = W.Text(pk, "tiny")
    B.keyNote:SetPoint("TOPLEFT", 12, -32); B.keyNote:SetPoint("TOPRIGHT", -12, -32)
    B.keyNote:SetWordWrap(true)
    B.keySlider = W.RangeSlider(pk, { min = 2, max = 20, step = 1, from = st.keyMin, to = st.keyMax })
    B.keySlider:SetPoint("BOTTOMLEFT", 12, 12); B.keySlider:SetPoint("BOTTOMRIGHT", -12, 12)
    B.keySlider.onChange = function(lo, hi)
        st.keyMin, st.keyMax = lo, hi
        KeyText(lo, hi); Render()
    end
    KeyText(st.keyMin, st.keyMax)

    -- Min. leader rating: histogram of the results, gradient track, your rating.
    local p1 = W.Panel(bar)
    p1:SetPoint("TOPLEFT", pk, "TOPRIGHT", 14, 0); p1:SetSize(300, 106)
    local l1 = W.Label(p1, "Min. leader rating"); l1:SetPoint("TOPLEFT", 12, -10)
    B.ratingValue = W.Text(p1, "h2"); B.ratingValue:SetPoint("TOPRIGHT", -12, -8)
    B.hist = W.Histogram(p1, 12)
    B.hist:SetPoint("TOPLEFT", 12, -32); B.hist:SetPoint("TOPRIGHT", -12, -32); B.hist:SetHeight(32)
    local mine = C_ChallengeMode.GetOverallDungeonScore and D.Num(C_ChallengeMode.GetOverallDungeonScore()) or 0
    local s1 = W.Slider(p1, { min = 0, max = 3600, step = 50, value = st.minRating,
                              stops = T.RATING_STOPS, marker = mine > 0 and mine or nil })
    s1:SetPoint("TOPLEFT", B.hist, "BOTTOMLEFT"); s1:SetPoint("TOPRIGHT", B.hist, "BOTTOMRIGHT")
    s1.onChange = function(v)
        st.minRating = v
        RatingText(v); UpdateHistogram(); MarkDirty()
    end
    local a = W.Text(p1, "tiny"); a:SetPoint("TOPLEFT", s1, "BOTTOMLEFT", 0, -1); a:SetText("0")
    if s1.marker then   -- under your own rating's mark
        local m = W.Text(p1, "tiny"); m:SetPoint("TOP", s1.marker, "BOTTOM", 0, -4); m:SetText(("You %d"):format(floor(mine)))
    end
    local z = W.Text(p1, "tiny"); z:SetPoint("TOPRIGHT", s1, "BOTTOMRIGHT", 0, -1); z:SetText("3600")
    RatingText(st.minRating)

    -- Leader's best in that dungeon.
    local p2 = W.Panel(bar)
    p2:SetPoint("TOPLEFT", p1, "TOPRIGHT", 14, 0); p2:SetSize(240, 106)
    local l2 = W.Label(p2, "Leader's best here"); l2:SetPoint("TOPLEFT", 12, -10)
    B.rangeValue = W.Text(p2, "h2"); B.rangeValue:SetPoint("TOPRIGHT", -12, -8)
    local note = W.Text(p2, "tiny")
    note:SetPoint("TOPLEFT", 12, -32); note:SetPoint("TOPRIGHT", -12, -32)
    note:SetWordWrap(true)
    note:SetText("The leader's season best in that dungeon.")
    local s2 = W.RangeSlider(p2, { min = 2, max = 20, step = 1, from = st.expMin, to = st.expMax })
    s2:SetPoint("BOTTOMLEFT", 12, 12); s2:SetPoint("BOTTOMRIGHT", -12, 12)
    s2.onChange = function(lo, hi)
        st.expMin, st.expMax = lo, hi
        RangeText(lo, hi); Render()
    end
    RangeText(st.expMin, st.expMax)

    -- Search: the primary action, right of the panels.
    B.searchBtn = W.Button(bar, "Search", "gold", nil, 44, "h2")
    B.searchBtn:SetPoint("TOPLEFT", p2, "TOPRIGHT", 14, 0)
    B.searchBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    B.searchBtn:SetScript("OnClick", DoSearch)
    B.pulse = A.Pulse(B.searchBtn, 0.55)
    B.pulse:Stop()
    local hint = W.Text(bar, "tiny")
    hint:SetPoint("TOPLEFT", B.searchBtn, "BOTTOMLEFT", 2, -8)
    hint:SetPoint("TOPRIGHT", B.searchBtn, "BOTTOMRIGHT", -2, -8)
    hint:SetWordWrap(true)
    hint:SetText("Dungeons, rating and your role go to the server; the rest filters here.")

    -- Row 2: client-side toggles, sort.
    local role = D.PlayerRole()
    local toggles = {
        { "spot", "Spot for " .. ROLE_NAME[role], nil, nil, true },
        { "fitLust", "Lust fit", "lust", C.lust },
        { "fitBrez", "B-Res fit", "brez", C.brez },
        { "notDeclined", "Not declined" },
    }
    local x = 0
    for _, d in ipairs(toggles) do
        local t = W.Toggle(row2, d[2], d[3], d[4])
        t:SetPoint("LEFT", x, 0)
        x = x + t:GetWidth() + 6
        t:SetChecked(st[d[1]])
        if d[1] == "spot" then B.spotToggle = t end
        local server = d[5]
        t.onChange = function(v)
            st[d[1]] = v
            if server then MarkDirty() else Render() end
        end
    end

    -- Sort, right-aligned in row 2.
    B.sorts = {}
    local right
    for i = #SORTS, 1, -1 do
        local s = SORTS[i]
        local b = W.Button(row2, s[2], "mark", nil, 26, "tiny")
        b:SetWidth(b.label:GetStringWidth() + 18)
        if right then b:SetPoint("RIGHT", right, "LEFT", -4, 0) else b:SetPoint("RIGHT") end
        b.key = s[1]
        b:SetScript("OnClick", function() st.sort = s[1]; PaintSorts(); Render() end)
        B.sorts[#B.sorts + 1] = b
        right = b
    end
    local sl = W.Text(row2, "small"); sl:SetPoint("RIGHT", right, "LEFT", -8, 0); sl:SetText("Sort")
    PaintSorts()
    PaintSearch()
end

-------------------------------------------------------------------------------
--  Result cards
-------------------------------------------------------------------------------
local function Tooltip(card)
    local r = card.r
    if not r then return end
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:SetText(r.dungeon, 1, 1, 1)
    pcall(GameTooltip.AddLine, GameTooltip, r.title, 0.85, 0.85, 0.85, true)
    GameTooltip:AddLine(" ")
    for _, m in ipairs(r.members) do
        local col = T.ClassColor(m.class)
        GameTooltip:AddDoubleLine(
            (m.spec and (m.spec .. " ") or "") .. (m.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class] or m.class) or "?")
                .. (m.leader and "  |cffd2a24c(leader)|r" or ""),
            ROLE_NAME[m.role], col[1], col[2], col[3], 0.6, 0.65, 0.72)
    end
    -- The leader's Raider.IO profile (if installed).
    if r.leaderFull then
        GameTooltip:AddLine(" ")
        D.RaiderIOTooltip(GameTooltip, r.leaderFull)
    end
    GameTooltip:Show()
end

local function OnApplyClick(btn)
    local r = btn:GetParent().r
    if not r then return end
    if not D.CanApply() then ns.Print("only the group leader can sign up."); return end
    local ok, err
    if r.status == "applied" then
        ok, err = pcall(D.Cancel, r.id)
    else
        ok, err = pcall(D.Apply, r.id)
    end
    if not ok then ns.Print("could not sign up (" .. tostring(err) .. ")") end
end

local function NewCard(parent)
    local c = W.Card(parent)
    c:SetHeight(CARD_H)
    c.strip = c:CreateTexture(nil, "ARTWORK")
    c.strip:SetPoint("TOPLEFT"); c.strip:SetPoint("BOTTOMLEFT"); c.strip:SetWidth(STRIP_W)
    W.CornerCaps(c, c.strip, C.bg, { TL = true, BL = true })
    c.fade = W.Tex(c, "ARTWORK", nil, 1)
    c.fade:SetPoint("TOPRIGHT", c.strip, "TOPRIGHT"); c.fade:SetPoint("BOTTOMRIGHT", c.strip, "BOTTOMRIGHT"); c.fade:SetWidth(60)
    W.Gradient(c.fade, "HORIZONTAL", { C.panel[1], C.panel[2], C.panel[3], 0 }, C.panel)
    c.short = W.Text(c, "label", C.textHi); c.short:SetPoint("TOPLEFT", c.strip, "TOPLEFT", 10, -8)
    c.short:SetShadowOffset(0, -1); c.short:SetShadowColor(0, 0, 0, 0.8)
    -- Key level on the art. The title can't be cut by addons, so it sits in
    -- a frame one line high and as wide as "+20", word-wrapped: Blizzard's
    -- titles start with the key, so the break falls right after it and
    -- the second line is clipped away. "+N" in its key color when the level
    -- could be measured (UI/KeyRead.lua).
    c.keyClip = CreateFrame("Frame", nil, c)
    c.keyClip:SetPoint("BOTTOMLEFT", c.strip, "BOTTOMLEFT", 8, 6)
    c.keyClip:SetSize(B.keyClipW or 52, B.keyLineH or 34)
    c.keyClip:SetClipsChildren(true)
    c.key = W.Text(c.keyClip, "keyArt")
    c.key:SetPoint("TOPLEFT")
    c.key:SetWidth(B.keyClipW or 52)
    c.key:SetWordWrap(true)
    c.key:SetJustifyV("TOP")
    c.key:SetShadowOffset(1, -2); c.key:SetShadowColor(0, 0, 0, 0.9)

    c.name = W.Text(c, "h2"); c.name:SetPoint("TOPLEFT", c.strip, "TOPRIGHT", 14, -10)
    c.title = W.Text(c, "body", C.text2); c.title:SetPoint("BOTTOMLEFT", c.name, "BOTTOMRIGHT", 10, 0)
    c.line2 = W.Text(c, "bodySm"); c.line2:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -6)
    c.slots = {}
    for i = 1, 5 do
        local rb = W.RoleBadge(c, 24)
        if i == 1 then rb:SetPoint("TOPLEFT", c.line2, "BOTTOMLEFT", 0, -6)
        else rb:SetPoint("LEFT", c.slots[i - 1], "RIGHT", 4, 0) end
        c.slots[i] = rb
    end
    c.lust = W.Glyph(c, "lust", 24, C.lust)
    c.brez = W.Glyph(c, "brez", 24, C.brez)
    c.style = W.Pill(c, "")
    c.style:SetHeight(20)

    c.btn = W.Button(c, "Sign up", "ghost", 100)
    c.btn:SetPoint("RIGHT", -14, 0)
    c.btn:SetScript("OnClick", OnApplyClick)
    local div = W.Tex(c, "BORDER", C.line)
    div:SetPoint("TOPRIGHT", c, "TOPRIGHT", -128, -1); div:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -128, 1)
    PixelUtil.SetWidth(div, 1, 1)
    c.rating = W.Text(c, "num"); c.rating:SetPoint("TOPRIGHT", div, "TOPLEFT", -16, -16)
    c.meter = W.Meter(c, 72); c.meter:SetPoint("TOPRIGHT", c.rating, "BOTTOMRIGHT", 0, -5)
    c.age = W.Text(c, "tiny"); c.age:SetPoint("TOPRIGHT", c.meter, "BOTTOMRIGHT", 0, -5)

    c.onEnter = Tooltip
    c.onLeave = function() GameTooltip:Hide() end
    return c
end

local STATUS_BUTTON = {
    applied  = { "Applied", "done" },                 -- click cancels
    invited  = { "Invited", "done", true },           -- Blizzard's invite popup answers it
    inviteaccepted = { "Joined", "done", true },
    declined = { "Declined", "quiet", true },
    declined_full = { "Group full", "quiet", true },
    declined_delisted = { "Delisted", "quiet", true },
}

local function Clock(r) return T.Clock(r.age + (GetTime() - r.readAt)) end

local function FillCard(c, r)
    c.r = r
    local art = T.DungeonArt(r.cid)
    if art.button then
        c.strip:SetTexture(art.button)
        c.strip:SetTexCoord(0.048, 0.636, 0, 0.742)   -- journal button: 175 x 95 of 256 x 128
    else
        c.strip:SetTexture(art.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        c.strip:SetTexCoord(0.08, 0.92, 0.2, 0.8)
    end
    c.short:SetText(T.Short(r.dungeon))
    if r.key then
        c.key:SetText("+" .. r.key)
        c.key:SetTextColor(unpack(T.KeyColor(r.key)))
    else
        pcall(c.key.SetText, c.key, r.title)
        c.key:SetTextColor(unpack(C.textHi))
    end
    c.name:SetText(r.dungeon)
    pcall(c.title.SetText, c.title, r.title)
    c.title:SetWidth(max(40, c:GetWidth() - STRIP_W - 14 - c.name:GetStringWidth() - 10 - 260))

    local leader = r.leader or "?"
    local line = T.ColorCode(T.ClassColor(r.leaderClass)) .. leader .. "|r"
    if r.leaderSpec then line = line .. "  |cff8d98a8" .. r.leaderSpec .. "|r" end
    line = line .. D.MainTag(r.leaderFull, r.rating)   -- Raider.IO: an alt with a stronger main
    if r.best then
        line = line .. "  |cff8d98a8·  best here|r  " .. T.ColorCode(T.KeyColor(r.best, r.timed)) .. "+" .. r.best
            .. "|r |cff8d98a8" .. (r.timed and "in time" or "over time") .. "|r"
    else
        line = line .. "  |cff8d98a8·  no run here this season|r"
    end
    c.line2:SetText(line)

    -- Members by role, then open spots.
    local slots = {}
    for _, role in ipairs(D.ROLE_KEYS) do
        -- true = filled, class unreadable.
        for _, m in ipairs(r.members) do if m.role == role then slots[#slots + 1] = { role, m.class or true } end end
    end
    local open = D.OpenSpots(r)
    for _, role in ipairs(D.ROLE_KEYS) do
        for _ = 1, open[role] or 0 do slots[#slots + 1] = { role } end
    end
    for i, rb in ipairs(c.slots) do
        local s = slots[i]
        if s then rb:Set(s[1], s[2]); rb:Show() else rb:Hide() end
    end
    local anchor = c.slots[min(5, max(1, #slots))]
    c.lust:ClearAllPoints(); c.brez:ClearAllPoints(); c.style:ClearAllPoints()
    local x = anchor
    c.lust:SetShown(r.lust or false)
    if r.lust then c.lust:SetPoint("LEFT", x, "RIGHT", 6, 0); x = c.lust end
    c.brez:SetShown(r.brez or false)
    if r.brez then c.brez:SetPoint("LEFT", x, "RIGHT", r.lust and 0 or 6, 0); x = c.brez end
    local ps = D.PlaystyleLabel(r.playstyle)
    c.style:SetShown(ps ~= nil)
    if ps then c.style:SetText(ps); c.style:SetPoint("LEFT", x, "RIGHT", 8, 0) end

    c.rating:SetText(floor(r.rating))
    c.rating:SetTextColor(unpack(T.RatingColor(r.rating)))
    c.meter:SetValue(r.rating / 3600, T.RatingColor(r.rating))
    c.age:SetText(Clock(r))

    local sb = STATUS_BUTTON[r.status]
    c.btn:SetLabel(sb and sb[1] or "Sign up")
    c.btn:SetVariant(sb and sb[2] or "ghost")
    c.btn:SetEnabled(not (sb and sb[3]) and D.CanApply())

    c:SetAlpha(1)   -- a card reused halfway through its rise animation
end

local ORDER = {
    -- Lowest key first; unread titles last.
    key    = function(a, b)
        local ka, kb = a.key or 99, b.key or 99
        if ka ~= kb then return ka < kb end
        if a.rating ~= b.rating then return a.rating > b.rating end
        return a.id < b.id
    end,
    rating = function(a, b) if a.rating ~= b.rating then return a.rating > b.rating end return a.id < b.id end,
    best   = function(a, b) if (a.best or 0) ~= (b.best or 0) then return (a.best or 0) > (b.best or 0) end return a.rating > b.rating end,
    -- Listing time, not age: ages were read at different moments.
    age    = function(a, b)
        local la, lb = a.readAt - a.age, b.readAt - b.age
        if la ~= lb then return la > lb end
        return a.id < b.id
    end,
}

Render = function(animate)
    -- Hidden tab or closed window: nothing to draw; the page's OnShow renders.
    if not (B.child and B.page and B.page:IsVisible()) then return end
    local st = B.st
    -- Groups that don't fit the client-side filters are left out entirely.
    local list, hidden = {}, 0
    for _, r in ipairs(B.results) do
        if D.Fits(r, st) then list[#list + 1] = r else hidden = hidden + 1 end
    end
    table.sort(list, ORDER[st.sort] or ORDER.rating)
    for i, r in ipairs(list) do
        local c = B.cards[i] or NewCard(B.child)
        B.cards[i] = c
        local y = -(i - 1) * (CARD_H + CARD_GAP)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", B.child, "TOPLEFT", 0, y)
        c:SetPoint("TOPRIGHT", B.child, "TOPRIGHT", 0, y)
        c:Show()
        FillCard(c, r)
        if animate and i <= 8 then A.Rise(c, (i - 1) * 0.04, 8, 0.35) end
    end
    for i = #list + 1, #B.cards do B.cards[i]:Hide() end
    B.child:SetHeight(max(1, #list * (CARD_H + CARD_GAP)))
    local limit = max(0, B.child:GetHeight() - B.scroll:GetHeight())
    if B.scroll:GetVerticalScroll() > limit then B.scroll:SetVerticalScroll(limit) end

    local hiddenText = hidden > 0 and ("  ·  %d hidden by your filters"):format(hidden) or ""
    -- The server found more than it sent: say so, it is easy to miss groups.
    if B.total and B.sent and B.total > B.sent then
        hiddenText = hiddenText .. ("  ·  |cffe0b868server sent %d of %d found, narrow the search to see the rest|r")
            :format(B.sent, B.total)
    end
    if B.boxText then
        hiddenText = hiddenText .. ("  ·  |cffe0b868Blizzard's search box holds \"%s\" and narrows the search|r")
            :format(B.boxText)
    end
    if #list == 0 then
        B.count:SetText(hidden > 0 and ("%d %s found, all hidden by your filters"):format(hidden,
            hidden == 1 and "group" or "groups") or "")
        B.empty:SetText(B.searched and "No Mythic+ groups to show." or "Pick your filters and press Search.")
        B.empty:Show()
    else
        B.empty:Hide()
        B.count:SetText(("|cfff5f7fa%d|r %s%s"):format(#list, #list == 1 and "group" or "groups", hiddenText))
    end
    if B.hist then UpdateHistogram() end
end

-------------------------------------------------------------------------------
--  Data in
-------------------------------------------------------------------------------
local function Load()
    if B.keySlider then PaintKeyPanel() end   -- the reader may have come on since
    if UI.KeyRead then UI.KeyRead.Reset() end
    wipe(B.results)
    local ids, total = D.ResultIDs()
    B.sent, B.total = #ids, total
    for _, id in ipairs(ids) do
        local r = D.Read(id)
        if r then B.results[#B.results + 1] = r end
    end
    -- A search from Blizzard's window lands here too; only
    -- our own makes "nothing found" the message.
    B.searched = B.ownSearch or false
    -- Text typed into Blizzard's own search box narrows every search, ours
    -- too (the client reads the box itself): the count line says so.
    local box = LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.SearchBox
    local ok, text = false, nil
    if box then ok, text = pcall(box.GetText, box) end
    text = ok and D.Str(text) and strtrim(text) or ""
    B.boxText = text ~= "" and text or nil
    B.ownSearch = false
    B.lastSearch = GetTime()
    if B.scroll then B.scroll:SetVerticalScroll(0) end
    Render(true)
end

local pendingUpdate = {}
local function Flush()
    B.flushQueued = false
    for id in pairs(pendingUpdate) do
        for i, r in ipairs(B.results) do
            if r.id == id then
                local fresh = D.Read(id)
                if fresh then B.results[i] = fresh else table.remove(B.results, i) end
                break
            end
        end
    end
    wipe(pendingUpdate)
    Render()
end

local function Queue(id)
    if not D.Num(id) then return end
    pendingUpdate[id] = true
    if not B.flushQueued then
        B.flushQueued = true
        C_Timer.After(0.15, Flush)
    end
end

local function PaintSpot()
    local t = B.spotToggle
    if not t then return end
    t.label:SetText("Spot for " .. ROLE_NAME[D.PlayerRole()])
    t:SetWidth(math.ceil(30 + t.label:GetStringWidth() + 12))   -- W.Toggle without glyph: label at 30
end

-- Only while the window is open (ns.Live); OnShow catches up on the rest.
local events = CreateFrame("Frame")
ns.Live(events, { "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED",
                  "LFG_LIST_APPLICATION_STATUS_UPDATED", "GROUP_ROSTER_UPDATE", "PLAYER_SPECIALIZATION_CHANGED",
                  "CHALLENGE_MODE_MAPS_UPDATE" })
events:SetScript("OnEvent", function(_, event, arg1)
    if not B.page then return end
    if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        B.searching = false
        PaintSearch()
        -- Next frame: the result list is complete by then.
        C_Timer.After(0, Load)
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        B.searching = false
        PaintSearch()
        ns.Print("search failed" .. (D.Str(arg1) and (" (" .. arg1 .. ")") or "") .. ".")
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        Queue(arg1)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 ~= "player" then return end
        D.ResetParty()
        PaintSpot()
        Render()
    elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
        D.ResetMaps()
        if not InCombatLockdown() then BuildChips() end
    end
end)

-------------------------------------------------------------------------------
--  Build
-------------------------------------------------------------------------------
function UI.BuildBrowse(page)
    B.st = State()

    B.chipRow = CreateFrame("Frame", nil, page)
    B.chipRow:SetPoint("TOPLEFT", S.pad, -14)
    B.chipRow:SetPoint("TOPRIGHT", -S.pad, -14)
    B.chipRow:SetHeight(T.S.chipH)
    BuildChips()
    -- Resizing: chips re-flow, cards re-fit their title width (once per burst).
    local resizeQueued = false
    B.chipRow:SetScript("OnSizeChanged", function()
        B.LayoutChips()
        if resizeQueued then return end
        resizeQueued = true
        C_Timer.After(0.15, function() resizeQueued = false; if B.page then Render() end end)
    end)

    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("TOPLEFT", B.chipRow, "BOTTOMLEFT", 0, -12)
    bar:SetPoint("TOPRIGHT", B.chipRow, "BOTTOMRIGHT", 0, -12)
    bar:SetHeight(106)
    local row2 = CreateFrame("Frame", nil, page)
    row2:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -10)
    row2:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -10)
    row2:SetHeight(30)
    BuildFilters(bar, row2)

    -- The widest key ("+20") and one line of the art's key font: the size of
    -- the frame that shows only a title's first word.
    local probe = W.Text(page, "keyArt")
    probe:SetText("+20")
    B.keyClipW = math.ceil(probe:GetStringWidth()) + 4
    B.keyLineH = math.ceil(probe:GetStringHeight()) + 2
    probe:Hide()

    B.count = W.Text(page, "small")
    B.count:SetPoint("TOPLEFT", row2, "BOTTOMLEFT", 0, -10)

    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:SetPoint("TOPLEFT", row2, "BOTTOMLEFT", 0, -32)
    scroll:SetPoint("BOTTOMRIGHT", -S.pad, 10)
    scroll:SetClipsChildren(true)
    B.child = CreateFrame("Frame", nil, scroll)
    B.child:SetSize(944, 1)
    scroll:SetScrollChild(B.child)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then B.child:SetWidth(w) end end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, d)
        local limit = max(0, B.child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(limit, max(0, self:GetVerticalScroll() - d * (CARD_H + CARD_GAP))))
    end)
    B.scroll = scroll

    B.empty = W.Text(page, "body", C.muted)
    B.empty:SetPoint("TOP", scroll, "TOP", 0, -60)

    -- Ages and "last search" tick while the tab is visible.
    page:SetScript("OnShow", function()
        PaintKeyPanel()   -- first: it tests the key reader before any title is read
        if B.stale then
            -- The window was closed (no events then; Window.lua sets B.stale): catch up.
            B.stale = false
            D.ResetParty(); D.ResetMaps()
            PaintSpot()
            if B.searching then   -- the answer may have come in meanwhile
                B.searching = false
                PaintSearch()
                Load()
            else
                for i = #B.results, 1, -1 do   -- application status, delisted groups
                    local fresh = D.Read(B.results[i].id)
                    if fresh then B.results[i] = fresh else table.remove(B.results, i) end
                end
                if #B.results == 0 and #D.ResultIDs() > 0 then Load() else Render() end
            end
        elseif #B.results == 0 and #D.ResultIDs() > 0 then
            Load()
        else
            Render()
        end
        B.ticker = C_Timer.NewTicker(1, function()
            for _, c in ipairs(B.cards) do if c:IsShown() and c.r then c.age:SetText(Clock(c.r)) end end
            if B.lastSearch and UI.SetStatus then
                UI.SetStatus("Last search " .. T.Clock(GetTime() - B.lastSearch) .. " ago")
            end
        end)
    end)
    page:SetScript("OnHide", function()
        if B.ticker then B.ticker:Cancel(); B.ticker = nil end
    end)
    B.page = page   -- last: events only act on a finished page
    Render()
end
