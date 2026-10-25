-------------------------------------------------------------------------------
--  UI/Browse.lua  --  the Browse tab: search, filter, sign up
--
--  Server-side filters (sent with the search): dungeons, minimum leader
--  rating, a free spot for your role. Client-side (hide what doesn't fit):
--  the key level (measured from the title, UI/KeyRead.lua), the leader's
--  best key in that dungeon, lust / battle res fit, declined, upgrades for
--  your score. Filter presets: saved sets of all of these (one click).
--  Changing a server-side filter marks Search as pending; nothing searches
--  on its own (a search needs a click).
--  Settings persist in GottaQueueEmAllDB.ui.browse, presets in
--  GottaQueueEmAllDB.filterPresets.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A, D = UI.Theme, UI.W, UI.Anim, UI.Data
local C, S = T.C, T.S
local floor, max, min = math.floor, math.max, math.min

local CARD_H, CARD_GAP = 86, 8
local SPEC_H = 14     -- the spec names under the role glyphs (Spec view)
local SPEC_GAP = 18   -- between glyphs in the Spec view: each name gets 24 + 18 px, centered
local STRIP_W = 136
local ROLE_NAME = { TANK = TANK or "Tank", HEALER = HEALER or "Healer", DAMAGER = DAMAGER or "Damage" }
local SORTS = { { "key", "Key" }, { "rating", "Rating" }, { "best", "Leader best" }, { "age", "Newest" } }

local B = { results = {}, cards = {}, chips = {} }
UI.Browse = B

local KEY_TOP = D.KEY_TOP   -- the key slider's open top end (+30 and up)
local DEFAULT = { dungeons = {}, minRating = 0, keyMin = 2, keyMax = KEY_TOP, expMin = 2, expMax = 20, spot = true,
                  fitLust = false, fitBrez = false, notDeclined = true, upgrades = false, sort = "rating" }

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
    -- The key slider ended at +20 before (= +20 and up): open it to the new top.
    if st.keyTop ~= KEY_TOP then
        if st.keyMax == 20 then st.keyMax = KEY_TOP end
        st.keyTop = KEY_TOP
    end
    return st
end

local Render, MarkDirty   -- forward

-- Members with their spec (W.SpecView): the cards grow by a line.
local function CardH() return CARD_H + (W.SpecView() and SPEC_H or 0) end

-------------------------------------------------------------------------------
--  Dungeon chips
-------------------------------------------------------------------------------
-- A run as on the chip: "15++" in time (one "+" per level it upgraded the
-- key), "15" over time (grey).
local function RunText(run)
    return run.level .. ("+"):rep(run.up or 0)
end

local function Clock(sec)
    sec = floor((sec or 0) + 0.5)
    return ("%d:%02d"):format(floor(sec / 60), sec % 60)
end

-- One run in the chip's tooltip: level, time against the timer.
local function RunLine(label, run, limit)
    local line = label .. T.ColorCode(T.KeyColor(run.level, run.timed)) .. RunText(run) .. "|r"
    if run.sec then
        line = line .. "   " .. Clock(run.sec)
        if limit then
            local d = run.sec - limit
            line = line .. " / " .. Clock(limit) .. (d > 0 and ("  |cffd06a5a" .. Clock(d) .. " over|r")
                or ("  |cff96e3ad" .. Clock(-d) .. " left|r"))
        end
    end
    GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
end

local function BuildChips()
    local st = B.st
    local groups = ns.SeasonGroups and ns.SeasonGroups() or {}
    -- Rebuild only when the season's dungeons or your best keys changed (the
    -- events fire often).
    local ids, parts = {}, {}
    for _, g in ipairs(groups) do
        ids[#ids + 1] = g.id
        local runs = ns.BestRuns and ns.BestRuns(g.cid)
        local c, o = runs and runs.counted, runs and runs.over
        parts[#parts + 1] = g.id .. ":" .. (c and (c.level .. "/" .. c.up .. "/" .. tostring(c.sec)) or "-")
            .. ":" .. (o and o.level or "-") .. ":" .. tostring(runs and runs.score)
    end
    local key = table.concat(parts, ",")
    if B.chipKey == key and #B.chips > 0 then return end
    B.chipKey = key
    -- Picks from an earlier season would filter every search to nothing (an
    -- empty list: not loaded yet, keep them).
    if #ids > 0 then
        local current = {}
        for _, id in ipairs(ids) do current[id] = true end
        for id in pairs(st.dungeons) do if not current[id] then st.dungeons[id] = nil end end
    end

    for _, c in ipairs(B.chips) do c:Hide() end
    B.chips = {}
    local row = B.chipRow
    local all = W.Chip(row, "All dungeons")
    B.chips[1] = all
    for _, g in ipairs(groups) do
        local tex = g.cid and select(4, C_ChallengeMode.GetMapUIInfo(g.cid))
        local runs = ns.BestRuns and ns.BestRuns(g.cid)
        local best = runs and runs.counted
        local c = W.Chip(row, T.Short(g.name), tex or "Interface\\Icons\\INV_Misc_QuestionMark",
            best and RunText(best) or nil, best and T.KeyColor(best.level, best.timed) or nil)
        c.groupID = g.id
        c:SetScript("OnEnter", nil)
        c:HookScript("OnEnter", function(self)
            self.hot = true; self:SetOn(self.on)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(g.name, 1, 1, 1)
            if runs then
                if runs.score then
                    GameTooltip:AddLine("Your score here: " .. T.ColorCode(T.C.goldText)
                        .. floor(runs.score + 0.5) .. "|r", 0.8, 0.8, 0.8)
                end
                if runs.inTime then RunLine("Best in time:  ", runs.inTime, runs.limit) end
                if runs.over then RunLine("Best over time:  ", runs.over, runs.limit) end
                if not runs.inTime and not runs.over then RunLine("Your best:  ", best, runs.limit) end
                if runs.limit then
                    GameTooltip:AddLine(("Timer %s  ·  ++ under %s  ·  +++ under %s"):format(Clock(runs.limit),
                        Clock(runs.limit * 0.8), Clock(runs.limit * 0.6)), 0.55, 0.6, 0.66)
                end
            else
                GameTooltip:AddLine("No run here yet this season", 0.55, 0.6, 0.66)
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

-- A +2 .. top range as the sliders show it; the top end is open (+20 = +20 and up).
local function RangeLabel(a, b, top)
    top = top or 20
    if a == 2 and b == top then return "Any" end
    if b == top then return "+" .. a .. " and up" end
    if a == b then return "+" .. a end
    return "+" .. a .. " – +" .. b
end

local function RangeText(a, b) B.rangeValue:SetText(RangeLabel(a, b)) end

local function PaintSorts()
    for _, s in ipairs(B.sorts) do s:SetVariant(B.st.sort == s.key and "ghost" or "mark") end
end

local HINT = "Dungeons, rating and your role go to the server; the rest filters here."
local COOL = 5   -- s to wait after the server didn't answer

-- The line under the button: what the search does, or what went wrong.
local function Note(text, warn)
    if not B.hint then return end
    B.hint:SetText(text or HINT)
    B.hint:SetTextColor(unpack(warn and C.goldText or B.hintColor))
end

local function PaintSearch()
    local b = B.searchBtn
    local wait = B.coolUntil and math.ceil(B.coolUntil - GetTime())
    if B.searching then
        b:SetLabel("Searching…"); b:Disable()
        B.pulse:Stop()
    elseif wait and wait > 0 then
        b:SetLabel(("Search again in %d s"):format(wait)); b:Disable()
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
        D.SearchAs(nil)
        ns.Print("search failed (" .. tostring(err) .. ")")
        return
    end
    B.searching, B.dirty, B.ownSearch = true, false, true
    Note()
    B.searchedMin = B.st.minRating or 0   -- the server left out groups below this
    B.searchSeq = (B.searchSeq or 0) + 1
    local seq = B.searchSeq
    PaintSearch()
    -- No answer at all (throttled): release the button after a while, unless
    -- a newer search is running by then.
    C_Timer.After(6, function()
        if not (B.searching and seq == B.searchSeq) then return end
        B.searching = false
        B.coolUntil = GetTime() + COOL
        Note("No answer from the server: too many searches in a row. The button is free again in a few seconds.", true)
        C_Timer.NewTicker(1, function(t)
            PaintSearch()
            if GetTime() >= B.coolUntil then t:Cancel(); B.coolUntil = nil; PaintSearch() end
        end)
        PaintSearch()
    end)
end

local function KeyText(a, b) B.keyValue:SetText(RangeLabel(a, b, KEY_TOP)) end

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
    pk:SetPoint("TOPLEFT"); pk:SetSize(250, 106)
    B.keyValue = W.Text(pk, "h2"); B.keyValue:SetPoint("TOPRIGHT", -12, -8)
    local lk = W.Label(pk, "Key level"); lk:SetPoint("TOPLEFT", 12, -10)
    lk:SetPoint("RIGHT", B.keyValue, "LEFT", -8, 0); lk:SetWordWrap(false)
    B.keyNote = W.Text(pk, "tiny")
    B.keyNote:SetPoint("TOPLEFT", 12, -32); B.keyNote:SetPoint("TOPRIGHT", -12, -32)
    B.keyNote:SetWordWrap(true)
    B.keySlider = W.RangeSlider(pk, { min = 2, max = KEY_TOP, step = 1, from = st.keyMin, to = st.keyMax })
    B.keySlider:SetPoint("BOTTOMLEFT", 12, 12); B.keySlider:SetPoint("BOTTOMRIGHT", -12, 12)
    B.keySlider.onChange = function(lo, hi)
        st.keyMin, st.keyMax = lo, hi
        KeyText(lo, hi); Render()
    end
    KeyText(st.keyMin, st.keyMax)

    -- Min. leader rating: histogram of the results, gradient track, your rating.
    local p1 = W.Panel(bar)
    p1:SetPoint("TOPLEFT", pk, "TOPRIGHT", 14, 0); p1:SetSize(330, 106)
    B.ratingValue = W.Text(p1, "h2"); B.ratingValue:SetPoint("TOPRIGHT", -12, -8)
    local l1 = W.Label(p1, "Min. leader rating"); l1:SetPoint("TOPLEFT", 12, -10)
    l1:SetPoint("RIGHT", B.ratingValue, "LEFT", -8, 0); l1:SetWordWrap(false)
    B.hist = W.Histogram(p1, 12)
    B.hist:SetPoint("TOPLEFT", 12, -32); B.hist:SetPoint("TOPRIGHT", -12, -32); B.hist:SetHeight(32)
    local mine = C_ChallengeMode.GetOverallDungeonScore and D.Num(C_ChallengeMode.GetOverallDungeonScore()) or 0
    local s1 = W.Slider(p1, { min = 0, max = 3600, step = 50, value = st.minRating,
                              stops = T.RATING_STOPS, marker = mine > 0 and mine or nil })
    s1:SetPoint("TOPLEFT", B.hist, "BOTTOMLEFT"); s1:SetPoint("TOPRIGHT", B.hist, "BOTTOMRIGHT")
    s1.onChange = function(v)
        st.minRating = v
        RatingText(v); UpdateHistogram()
        -- Raised: the groups found are filtered here at once. Lowered below the
        -- last search's minimum: groups the server left out need a new search.
        if v < (B.searchedMin or 0) then MarkDirty() end
        Render()
    end
    local a = W.Text(p1, "tiny"); a:SetPoint("TOPLEFT", s1, "BOTTOMLEFT", 0, -1); a:SetText("0")
    local z = W.Text(p1, "tiny"); z:SetPoint("TOPRIGHT", s1, "BOTTOMRIGHT", 0, -1); z:SetText("3600")
    if s1.marker then
        -- Under your own rating's mark, kept inside the track; the "0" or "3600"
        -- it would run into steps aside.
        local m = W.Text(p1, "tiny"); m:SetText(("You %d"):format(floor(mine)))
        local function PlaceMine()
            local w = s1:GetWidth()
            if w <= 0 then return end
            local half = m:GetStringWidth() / 2
            local x = min(max(mine / 3600 * w, half), w - half)
            m:ClearAllPoints(); m:SetPoint("TOP", s1, "BOTTOMLEFT", x, -1)
            a:SetShown(x - half > a:GetStringWidth() + 6)
            z:SetShown(x + half < w - z:GetStringWidth() - 6)
        end
        s1:HookScript("OnSizeChanged", PlaceMine)
        PlaceMine()
    end
    RatingText(st.minRating)
    B.ratingSlider = s1

    -- Leader's best in that dungeon.
    local p2 = W.Panel(bar)
    p2:SetPoint("TOPLEFT", p1, "TOPRIGHT", 14, 0); p2:SetSize(300, 106)
    B.rangeValue = W.Text(p2, "h2"); B.rangeValue:SetPoint("TOPRIGHT", -12, -8)
    -- The label gives way to the value ("+14 and up"), never under it.
    local l2 = W.Label(p2, "Leader's best here"); l2:SetPoint("TOPLEFT", 12, -10)
    l2:SetPoint("RIGHT", B.rangeValue, "LEFT", -8, 0); l2:SetWordWrap(false)
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
    B.expSlider = s2

    -- Search: the primary action, right of the panels.
    B.searchBtn = W.Button(bar, "Search", "gold", nil, 44, "h2")
    B.searchBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    -- The panels share the width; the button keeps a fixed share of it
    -- (narrow windows: panels at 29 / 38 / 33 %).
    local function Fit()
        local w = bar:GetWidth()
        if w <= 0 then return end
        local bw = min(max(floor(w * 0.17), 170), 240)
        B.searchBtn:SetWidth(bw)
        local room = w - bw - 3 * 14
        pk:SetWidth(floor(room * 0.29)); p1:SetWidth(floor(room * 0.38)); p2:SetWidth(floor(room * 0.33))
    end
    bar:HookScript("OnSizeChanged", Fit)
    Fit()
    B.searchBtn:SetScript("OnClick", DoSearch)
    B.pulse = A.Pulse(B.searchBtn, 0.55)
    B.pulse:Stop()
    local hint = W.Text(bar, "tiny")
    hint:SetPoint("TOPLEFT", B.searchBtn, "BOTTOMLEFT", 2, -8)
    hint:SetPoint("TOPRIGHT", B.searchBtn, "BOTTOMRIGHT", -2, -8)
    hint:SetWordWrap(true)
    B.hint, B.hintColor = hint, { hint:GetTextColor() }
    Note()

    -- Row 2: client-side toggles, sort.
    local role = D.PlayerRole()
    local toggles = {
        { "spot", "Spot for " .. ROLE_NAME[role], nil, nil, true },
        { "fitLust", "Lust fit", "lust", C.lust },
        { "fitBrez", "B-Res fit", "brez", C.brez },
        { "notDeclined", "Not declined" },
    }
    local x = 0
    B.toggles = {}
    for _, d in ipairs(toggles) do
        local t = W.Toggle(row2, d[2], d[3], d[4])
        t:SetPoint("LEFT", x, 0)
        x = x + t:GetWidth() + 6
        t:SetChecked(st[d[1]])
        if d[1] == "spot" then B.spotToggle = t end
        B.toggles[d[1]] = t
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
    -- Members: role glyphs, or with their specs.
    local view = W.ViewSwitch(row2, function() Render() end)
    view:SetPoint("RIGHT", sl, "LEFT", -16, 0)
    PaintSorts()
    PaintSearch()
end

-------------------------------------------------------------------------------
--  Filter presets: all of the tab's filters under a name, back in one click
-------------------------------------------------------------------------------
local PRESET_KEYS = { "minRating", "keyMin", "keyMax", "expMin", "expMax", "spot", "fitLust", "fitBrez",
                      "notDeclined", "upgrades", "sort" }
local MAX_PRESETS = 20

-- Account-wide: GottaQueueEmAllDB.filterPresets = { { name = ..., <filters> }, ... }.
local function Presets()
    local db = ns.DB and ns.DB()
    if not db then B.tmpPresets = B.tmpPresets or {}; return B.tmpPresets end
    if type(db.filterPresets) ~= "table" then db.filterPresets = {} end
    return db.filterPresets
end

local function SameSet(a, b)
    for id in pairs(a) do if not b[id] then return false end end
    for id in pairs(b) do if not a[id] then return false end end
    return true
end

local function Matches(p, st)
    for _, k in ipairs(PRESET_KEYS) do if p[k] ~= st[k] then return false end end
    return SameSet(p.dungeons or {}, st.dungeons)
end

-- A name from what the filters do, e.g. "+10 and up · 2500+ · 3 dungeons".
local function AutoName(st)
    local parts = {}
    if not (st.keyMin == 2 and st.keyMax == KEY_TOP) then parts[#parts + 1] = RangeLabel(st.keyMin, st.keyMax, KEY_TOP) end
    if (st.minRating or 0) > 0 then parts[#parts + 1] = st.minRating .. "+" end
    local n = 0
    for _ in pairs(st.dungeons) do n = n + 1 end
    if n > 0 then parts[#parts + 1] = n == 1 and "1 dungeon" or (n .. " dungeons") end
    if st.upgrades then parts[#parts + 1] = "upgrades" end
    return #parts > 0 and table.concat(parts, " · ") or "All groups"
end

-- Panels, toggles, chips and sort show st again.
local function Repaint()
    local st = B.st
    B.keySlider:SetValues(st.keyMin, st.keyMax)
    st.keyMin, st.keyMax = B.keySlider.va, B.keySlider.vb   -- kept inside the slider
    KeyText(st.keyMin, st.keyMax)
    B.ratingSlider:SetValue(st.minRating); RatingText(st.minRating)
    B.expSlider:SetValues(st.expMin, st.expMax)
    st.expMin, st.expMax = B.expSlider.va, B.expSlider.vb
    RangeText(st.expMin, st.expMax)
    for k, t in pairs(B.toggles) do t:SetChecked(st[k]) end
    local any = false
    for i = 2, #B.chips do
        local c = B.chips[i]
        c:SetOn(st.dungeons[c.groupID] and true or false)
        any = any or c.on
    end
    if B.chips[1] then B.chips[1]:SetOn(not any) end
    PaintSorts()
end

local function LoadPreset(p)
    local st = B.st
    -- Dungeons of this season only (a preset from an earlier one would
    -- filter every search to nothing).
    local current = {}
    for i = 2, #B.chips do current[B.chips[i].groupID] = true end
    local dungeons = {}
    for id in pairs(p.dungeons or {}) do
        if current[id] or #B.chips < 2 then dungeons[id] = true end
    end
    -- What goes to the server: a new search (rating raised filters here).
    local server = not SameSet(dungeons, st.dungeons) or (p.spot ~= nil and p.spot ~= st.spot)
        or (p.minRating or 0) < (B.searchedMin or 0)
    for _, k in ipairs(PRESET_KEYS) do
        if p[k] ~= nil then st[k] = p[k] end
    end
    wipe(st.dungeons)
    for id in pairs(dungeons) do st.dungeons[id] = true end
    Repaint()
    if server then MarkDirty() end
    Render()
end

local function SavePreset(name)
    local list, st = Presets(), B.st
    name = (name or ""):gsub("|", "||")
    if name == "" then name = AutoName(st) end
    local p = { name = name, dungeons = {} }
    for id in pairs(st.dungeons) do p.dungeons[id] = true end
    for _, k in ipairs(PRESET_KEYS) do p[k] = st[k] end
    for i, o in ipairs(list) do
        if o.name == name then list[i] = p; return true end
    end
    if #list >= MAX_PRESETS then
        ns.Print(("up to %d presets: delete one first."):format(MAX_PRESETS))
        return false
    end
    list[#list + 1] = p
    return true
end

local function DeletePreset(p)
    local list = Presets()
    for i = #list, 1, -1 do if list[i] == p then table.remove(list, i) end end
end

-------------------------------------------------------------------------------
--  Presets popover: under the Presets button, in the window's look
-------------------------------------------------------------------------------
local POP_W, ROW_H = 290, 28
local pop, FillPop

local function PaintRow(row)
    local on = row.p and Matches(row.p, B.st)
    W.Fill(row.bg, row.hot and C.badge or (on and { 0.82, 0.64, 0.30, 0.10 } or { 0, 0, 0, 0 }))
    row.dot:SetVertexColor(unpack(on and C.gold or C.faint))
    row.name:SetTextColor(unpack((on or row.hot) and C.textHi or C.text2))
    row.x:SetTextColor(unpack(row.xHot and C.badText or C.muted))
end

-- One preset: click loads it, the x on the right deletes it.
local function NewRow()
    local row = CreateFrame("Button", nil, pop)
    row:SetHeight(ROW_H)
    row.bg = W.Round(row, "BACKGROUND")
    row.bg:SetAllPoints()
    row.dot = W.Circle(row, "ARTWORK", nil, 8)
    row.dot:SetPoint("LEFT", 10, 0)
    row.name = W.Text(row, "bodySm")
    row.name:SetPoint("LEFT", 26, 0); row.name:SetPoint("RIGHT", -32, 0)
    row.del = CreateFrame("Button", nil, row)
    row.del:SetSize(26, 24); row.del:SetPoint("RIGHT", -3, 0)
    row.x = W.Text(row.del, "button"); row.x:SetPoint("CENTER"); row.x:SetText("×")
    row:SetScript("OnEnter", function(self) self.hot = true; PaintRow(self) end)
    row:SetScript("OnLeave", function(self) self.hot = false; PaintRow(self) end)
    -- Loads and searches at once (unless the server still wants a pause).
    row:SetScript("OnClick", function(self)
        LoadPreset(self.p); pop:Hide()
        if not (B.coolUntil and GetTime() < B.coolUntil) then DoSearch() end
    end)
    row.del:SetScript("OnEnter", function() row.hot, row.xHot = true, true; PaintRow(row) end)
    row.del:SetScript("OnLeave", function() row.hot, row.xHot = false, false; PaintRow(row) end)
    row.del:SetScript("OnClick", function() DeletePreset(row.p); FillPop() end)
    return row
end

FillPop = function()
    local list = Presets()
    local y = -34
    for i, p in ipairs(list) do
        local row = pop.rows[i] or NewRow()
        pop.rows[i] = row
        row.p = p
        row.hot, row.xHot = false, false
        row.name:SetText(p.name)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, y); row:SetPoint("TOPRIGHT", -6, y)
        row:Show()
        PaintRow(row)
        y = y - ROW_H
    end
    for i = #list + 1, #pop.rows do pop.rows[i]:Hide() end
    pop.none:SetShown(#list == 0)
    if #list == 0 then y = y - 22 end
    pop.line:ClearAllPoints()
    pop.line:SetPoint("TOPLEFT", 12, y - 8); pop.line:SetPoint("TOPRIGHT", -12, y - 8)
    pop.saveLabel:ClearAllPoints()
    pop.saveLabel:SetPoint("TOPLEFT", 14, y - 20)
    pop.box:ClearAllPoints()
    pop.box:SetPoint("TOPLEFT", 12, y - 40); pop.box:SetPoint("RIGHT", pop.save, "LEFT", -8, 0)
    pop.save:ClearAllPoints()
    pop.save:SetPoint("TOPRIGHT", -12, y - 40)
    pop.hint:SetText(AutoName(B.st))   -- the name an empty box saves under
    pop:SetHeight(-(y - 40) + 28 + 12)
end

local function BuildPop()
    pop = CreateFrame("Frame", nil, B.page)
    pop:SetSize(POP_W, 120)
    pop:SetPoint("TOPRIGHT", B.presetBtn, "BOTTOMRIGHT", 0, -6)
    pop:SetFrameStrata("DIALOG")
    pop:SetToplevel(true)
    pop:SetClampedToScreen(true)
    pop:EnableMouse(true)
    pop.bg = W.Round(pop, "BACKGROUND", C.raised)
    pop.bg:SetAllPoints()
    W.Border(pop, C.lineStrong)
    pop.rows = {}
    local title = W.Label(pop, "Filter presets"); title:SetPoint("TOPLEFT", 14, -12)
    pop.none = W.Text(pop, "small")
    pop.none:SetPoint("TOPLEFT", 14, -36)
    pop.none:SetText("None saved yet.")
    pop.line = W.Tex(pop, "ARTWORK", C.line)
    PixelUtil.SetHeight(pop.line, 1, 1)
    pop.saveLabel = W.Label(pop, "Save current filters")

    pop.box = CreateFrame("Frame", nil, pop)
    pop.box:SetHeight(28)
    local bg = W.Round(pop.box, "BACKGROUND", C.bg); bg:SetAllPoints()
    W.Border(pop.box, C.lineStrong)
    local eb = CreateFrame("EditBox", nil, pop.box)
    eb:SetAllPoints()
    eb:SetFontObject(T.Font.bodySm)
    eb:SetTextColor(unpack(C.textHi))
    eb:SetTextInsets(10, 10, 0, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(40)
    pop.hint = W.Text(pop.box, "bodySm", C.faint)
    pop.hint:SetPoint("LEFT", 10, 0); pop.hint:SetPoint("RIGHT", -10, 0)
    pop.save = W.Button(pop, "Save", "gold", 74, 28)

    local function Save()
        if SavePreset(strtrim(eb:GetText() or "")) then
            eb:SetText(""); eb:ClearFocus()
            FillPop()
        end
    end
    pop.save:SetScript("OnClick", Save)
    eb:SetScript("OnEnterPressed", Save)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); pop:Hide() end)
    eb:SetScript("OnTextChanged", function(self) pop.hint:SetShown(self:GetText() == "") end)
    eb:SetScript("OnEditFocusGained", function() W.SetBorder(pop.box, C.gold) end)
    eb:SetScript("OnEditFocusLost", function() W.SetBorder(pop.box, C.lineStrong) end)
    pop.edit = eb

    -- A click anywhere else closes it (the button toggles it itself).
    pop:SetScript("OnEvent", function(self)
        if not (self:IsMouseOver() or B.presetBtn:IsMouseOver()) then self:Hide() end
    end)
    pop:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    pop:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        eb:ClearFocus()
    end)
    pop:Hide()
end

local function TogglePresets()
    if pop and pop:IsShown() then pop:Hide(); return end
    if not pop then BuildPop() end
    FillPop()
    pop:Show()
end

-- Right of the count line: Upgrades only (client-side) and Presets.
local function BuildTools(page, scroll)
    local st = B.st
    local tools = CreateFrame("Frame", nil, page)
    tools:SetHeight(22)
    tools:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", 0, 4)
    local pb = W.Button(tools, "Presets", "mark", nil, 22, "tiny")
    pb:SetWidth(pb.label:GetStringWidth() + 18)
    pb:SetPoint("RIGHT")
    pb:SetScript("OnClick", TogglePresets)
    B.presetBtn = pb
    local up = W.Toggle(tools, "Upgrades only", nil, nil, 22)
    up:SetPoint("RIGHT", pb, "LEFT", -6, 0)
    up:SetChecked(st.upgrades)
    up.onChange = function(v) st.upgrades = v; Render() end
    up:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Upgrades only", 1, 1, 1)
        GameTooltip:AddLine("Keys that could raise your Mythic+ score, timed: above your best in-time run in "
            .. "that dungeon. An estimate. Groups whose key can't be read stay.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    up:HookScript("OnLeave", function() GameTooltip:Hide() end)
    B.toggles.upgrades = up
    -- Groups of leaders you rated Bad (UI/Ratings.lua); the same switch as on
    -- Settings › Player ratings, saved for your account.
    local bad = W.Toggle(tools, "Hide rated Bad", nil, nil, 22)
    bad:SetPoint("RIGHT", up, "LEFT", -6, 0)
    bad.onChange = function(v)
        local db = ns.DB and ns.DB()
        if db then db.rateHideBad = v end
        Render()
    end
    bad:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Hide rated Bad", 1, 1, 1)
        GameTooltip:AddLine("Leaves out groups whose leader you rated Bad. Your ratings: Settings › Player ratings "
            .. "(/gotta ratings).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    bad:HookScript("OnLeave", function() GameTooltip:Hide() end)
    B.rateToggle = bad
    tools:SetWidth(bad:GetWidth() + 6 + up:GetWidth() + 6 + pb:GetWidth())
    B.tools = tools
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
                .. (m.leader and "  |cffd2a24c(leader)|r" or "") .. (m.leaver and ("  " .. T.ColorCode(C.deserter) .. "DESERTER|r") or ""),
            ROLE_NAME[m.role], col[1], col[2], col[3], 0.6, 0.65, 0.72)
    end
    local open, spots = D.OpenSpots(r), {}
    for _, role in ipairs(D.ROLE_KEYS) do
        local n = open[role] or 0
        if n > 0 then spots[#spots + 1] = (n > 1 and (n .. " ") or "") .. ROLE_NAME[role] end
    end
    if #spots > 0 then GameTooltip:AddLine("Open: " .. table.concat(spots, ", "), 0.6, 0.65, 0.72) end
    local up, timed = D.Upgrade(r)
    if up then
        GameTooltip:AddLine("Upgrade for you, timed: " .. (timed > 0 and ("your best here in time is +" .. timed)
            or "no timed run here yet"), C.goodText[1], C.goodText[2], C.goodText[3])
    elseif up == false then
        GameTooltip:AddLine("No upgrade for you: your best here is higher", 0.6, 0.65, 0.72)
    end
    UI.Region.AddTooltipLine(GameTooltip, r.leaderFull)   -- the leader's country and realm
    UI.Ratings.AddTooltip(GameTooltip, r.leaderFull)       -- your rating of the leader and its note
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
    c:SetHeight(CardH())
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
    c.rate = UI.Ratings.Tag(c)   -- your rating of the leader (UI/Ratings.lua)
    c.rate:SetPoint("LEFT", c.line2, "RIGHT", 10, 0)
    c.deserter = W.DeserterTag(c)
    c.deserter:SetPoint("LEFT", c.line2, "RIGHT", 10, 0)
    c.deserter:Hide()
    c.slots, c.specs = {}, {}
    for i = 1, 5 do
        local rb = W.RoleBadge(c, 24)
        if i == 1 then rb:SetPoint("TOPLEFT", c.line2, "BOTTOMLEFT", 0, -6) end   -- the others: FillCard (gap by view)
        c.slots[i] = rb
        local sp = W.Text(c, "tiny")
        sp:SetPoint("TOP", rb, "BOTTOM", 0, -2)
        sp:SetWidth(24 + SPEC_GAP - 2)   -- its own column: never runs into the next name
        sp:SetJustifyH("CENTER")
        c.specs[i] = sp
    end
    c.lust = W.Glyph(c, "lust", 24, C.lust)
    c.brez = W.Glyph(c, "brez", 24, C.brez)
    c.style = W.Pill(c, "")
    c.style:SetHeight(20)
    c.stalePill = W.Pill(c, "Listed a while", { C.stale[1], C.stale[2], C.stale[3], 0.45 }, { 0, 0, 0, 0 })
    c.stalePill:SetHeight(20)
    c.stalePill.text:SetTextColor(unpack(C.stale))
    c.stalePill:Hide()
    -- This key, timed, would raise your score (D.Upgrade).
    c.upPill = W.Pill(c, "Upgrade", { C.good[1], C.good[2], C.good[3], 0.5 }, { 0, 0, 0, 0 })
    c.upPill:SetHeight(20)
    c.upPill.text:SetTextColor(unpack(C.goodText))
    c.upPill:Hide()

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

-- "Listed a while": up 20 minutes or more with 2 players or fewer (a hint,
-- the group stays in the list). Setting "markStale".
local STALE_AGE, STALE_MEMBERS = 20 * 60, 2
local function IsStale(r)
    local db = ns.DB and ns.DB()
    if db and db.markStale == false then return false end
    return r.age + (GetTime() - r.readAt) >= STALE_AGE and #r.members <= STALE_MEMBERS
end

-- The age clock, amber with its pill once the group counts as listed a while.
local function PaintAge(c)
    local r = c.r
    c.age:SetText(Clock(r))
    local stale = IsStale(r)
    c.age:SetTextColor(unpack(stale and C.stale or C.muted))
    c.stalePill:SetShown(stale)
end

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
    local line = UI.Region.Markup(r.leaderFull) .. T.ColorCode(T.ClassColor(r.leaderClass)) .. leader .. "|r"
    if r.leaderSpec then line = line .. "  |cff8d98a8" .. r.leaderSpec .. "|r" end
    line = line .. D.MainTag(r.leaderFull, r.rating)   -- Raider.IO: an alt with a stronger main
    if r.best then
        line = line .. "  |cff8d98a8·  best here|r  " .. T.ColorCode(T.KeyColor(r.best, r.timed)) .. "+" .. r.best
            .. "|r |cff8d98a8" .. (r.timed and "in time" or "over time") .. "|r"
    else
        line = line .. "  |cff8d98a8·  no run here this season|r"
    end
    c.line2:SetText(line)
    -- Your rating of the leader: GOOD / BAD, then the deserter tag after it.
    local rated = UI.Ratings.PaintTag(c.rate, r.leaderFull)
    c.deserter:ClearAllPoints()
    c.deserter:SetPoint("LEFT", rated and c.rate or c.line2, "RIGHT", 10, 0)
    -- Keystone Deserters: the leader ("DESERTER", "+N" for more), else how
    -- many of the others. Who exactly: the card's tooltip.
    local others = (r.leavers or 0) - (r.leaderLeaver and 1 or 0)
    if r.leaderLeaver or others > 0 then
        c.deserter:SetText(r.leaderLeaver and ("DESERTER" .. (others > 0 and ("  +" .. others) or ""))
            or ("%d DESERTER%s IN GROUP"):format(others, others == 1 and "" or "S"))
        c.deserter:Show()
    else
        c.deserter:Hide()
    end

    -- Members by role, then open spots.
    local slots = {}
    for _, role in ipairs(D.ROLE_KEYS) do
        -- true = filled, class unreadable.
        for _, m in ipairs(r.members) do if m.role == role then slots[#slots + 1] = { role, m.class or true, m.spec } end end
    end
    local open = D.OpenSpots(r)
    for _, role in ipairs(D.ROLE_KEYS) do
        for _ = 1, open[role] or 0 do slots[#slots + 1] = { role } end
    end
    local spec = W.SpecView()
    c:SetHeight(CardH())
    for i, rb in ipairs(c.slots) do
        local s = slots[i]
        if i > 1 then
            rb:ClearAllPoints()
            rb:SetPoint("LEFT", c.slots[i - 1], "RIGHT", spec and SPEC_GAP or 4, 0)   -- room for the names
        end
        if s then rb:Set(s[1], s[2]); rb:Show() else rb:Hide() end
        local sp = c.specs[i]
        sp:SetShown(spec and s and s[3] ~= nil or false)
        if s and s[3] then
            sp:SetText(W.SpecShort(s[3]))
            sp:SetTextColor(unpack(type(s[2]) == "string" and T.ClassColor(s[2]) or C.muted))
        end
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
    if ps then c.style:SetText(ps); c.style:SetPoint("LEFT", x, "RIGHT", 8, 0); x = c.style end
    local up = D.Upgrade(r)
    c.upPill:ClearAllPoints()
    c.upPill:SetShown(up or false)
    if up then c.upPill:SetPoint("LEFT", x, "RIGHT", 8, 0); x = c.upPill end
    c.stalePill:ClearAllPoints()
    c.stalePill:SetPoint("LEFT", x, "RIGHT", 8, 0)

    c.rating:SetText(floor(r.rating))
    c.rating:SetTextColor(unpack(T.RatingColor(r.rating)))
    c.meter:SetValue(r.rating / 3600, T.RatingColor(r.rating))
    PaintAge(c)

    local sb = STATUS_BUTTON[r.status]
    -- All sign-ups used: this one waits until you cancel one (the bar above).
    local full = not sb and B.appsBar and B.appsBar:FullLabel()
    c.btn:SetLabel(sb and sb[1] or full or "Sign up")
    c.btn:SetVariant(sb and sb[2] or (full and "quiet") or "ghost")
    c.btn:SetEnabled(not (sb and sb[3]) and not full and D.CanApply())

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
    best   = function(a, b)
        if (a.best or 0) ~= (b.best or 0) then return (a.best or 0) > (b.best or 0) end
        if a.rating ~= b.rating then return a.rating > b.rating end
        return a.id < b.id
    end,
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
    if B.appsBar then B.appsBar:Paint(true) end
    if B.rateToggle then   -- also switched on the settings page
        local db = ns.DB and ns.DB()
        B.rateToggle:SetChecked(not (db and db.rateHideBad == false))
    end
    -- Groups that don't fit the client-side filters are left out entirely,
    -- and those of leaders you rated Bad (when that is on, UI/Ratings.lua).
    local list, hidden, rated = {}, 0, 0
    for _, r in ipairs(B.results) do
        if not D.Fits(r, st) then hidden = hidden + 1
        elseif UI.Ratings.Hides(r.leaderFull) then rated = rated + 1
        else list[#list + 1] = r end
    end
    table.sort(list, ORDER[st.sort] or ORDER.rating)
    for i, r in ipairs(list) do
        local c = B.cards[i] or NewCard(B.child)
        B.cards[i] = c
        local y = -(i - 1) * (CardH() + CARD_GAP)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", B.child, "TOPLEFT", 0, y)
        c:SetPoint("TOPRIGHT", B.child, "TOPRIGHT", 0, y)
        c:Show()
        FillCard(c, r)
        if animate and i <= 8 then A.Rise(c, (i - 1) * 0.04, 8, 0.35) end
    end
    for i = #list + 1, #B.cards do B.cards[i]:Hide() end
    B.child:SetHeight(max(1, #list * (CardH() + CARD_GAP)))
    local limit = max(0, B.child:GetHeight() - B.scroll:GetHeight())
    if B.scroll:GetVerticalScroll() > limit then B.scroll:SetVerticalScroll(limit) end

    local hiddenText = hidden > 0 and ("  ·  %d hidden by your filters"):format(hidden) or ""
    if rated > 0 then hiddenText = hiddenText .. ("  ·  %d hidden: leader rated Bad"):format(rated) end
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
        local all = hidden + rated
        B.count:SetText(all > 0 and ("%d %s found, all hidden by your filters%s"):format(all,
            all == 1 and "group" or "groups", rated > 0 and (" or ratings (%d leader rated Bad)"):format(rated) or "") or "")
        B.empty:SetText(B.searched and "No Mythic+ groups to show." or "Pick your filters and press Search.")
        B.empty:Show()
    else
        B.empty:Hide()
        B.count:SetText(("|cfff5f7fa%d|r %s%s"):format(#list, #list == 1 and "group" or "groups", hiddenText))
    end
    -- The line ends before the tools on its right (Upgrades only, Presets).
    if B.tools then B.count:SetWidth(max(120, B.scroll:GetWidth() - B.tools:GetWidth() - 16)) end
    if B.hist then UpdateHistogram() end
end

-------------------------------------------------------------------------------
--  Data in
-------------------------------------------------------------------------------
local function Load()
    -- Hidden (another section or tab): read the results when shown.
    if not (B.page and B.page:IsVisible()) then B.loadPending = true; return end
    B.loadPending = false
    -- Another section searched (Raid, Mythic 0): the client holds one result
    -- list, so ours is gone (its IDs may now point at other groups). Empty
    -- until the next Mythic+ search.
    if not D.OwnsResults("mplus", D.CATEGORY, true) then
        wipe(B.results)
        B.searched, B.total, B.sent = false, nil, nil
        Render()
        return
    end
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

-- The groups read again in place (/gotta deserter switched).
function B.Reread()
    if not B.page then return end
    for i = #B.results, 1, -1 do
        local fresh = D.Read(B.results[i].id)
        if fresh then B.results[i] = fresh else table.remove(B.results, i) end
    end
    Render()
end

local pendingUpdate = {}
local function Flush()
    B.flushQueued = false
    local changed = false
    for id in pairs(pendingUpdate) do
        for i, r in ipairs(B.results) do
            if r.id == id then
                local fresh = D.Read(id)
                if fresh then B.results[i] = fresh else table.remove(B.results, i) end
                changed = true
                break
            end
        end
    end
    wipe(pendingUpdate)
    if changed then Render() end   -- updates come in all the time, most for other lists
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
        if B.searching then
            ns.Print("search failed" .. (D.Str(arg1) and (" (" .. arg1 .. ")") or "") .. ".")
            Note("The search failed. Try again in a moment.", true)
        end
        B.searching = false
        PaintSearch()
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        Queue(arg1)
        -- Your sign-ups changed: the bar (also for groups not in the list), Sign up at 5 / 5.
        if event == "LFG_LIST_APPLICATION_STATUS_UPDATED" and B.appsBar then B.appsBar.dirty = true; Render() end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 ~= "player" then return end
        D.ResetParty()
        PaintSpot()
        -- "Spot for <role>" goes to the server: a new role wants a new search.
        if event == "PLAYER_SPECIALIZATION_CHANGED" and B.st.spot then MarkDirty() end
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
    -- Your applications, between the filters and the list (UI/AppsBar.lua).
    B.appsBar = UI.AppsBar.New(page, row2, B.count, scroll)
    scroll:SetClipsChildren(true)
    B.child = CreateFrame("Frame", nil, scroll)
    B.child:SetSize(944, 1)
    scroll:SetScrollChild(B.child)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then B.child:SetWidth(w) end end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, d)
        local limit = max(0, B.child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(limit, max(0, self:GetVerticalScroll() - d * (CardH() + CARD_GAP))))
    end)
    B.scroll = scroll
    B.count:SetWordWrap(false)
    BuildTools(page, scroll)

    B.empty = W.Text(page, "body", C.muted)
    B.empty:SetPoint("TOP", scroll, "TOP", 0, -60)

    -- Ages and "last search" tick while the tab is visible.
    page:SetScript("OnShow", function()
        PaintKeyPanel()   -- first: it tests the key reader before any title is read
        if B.loadPending then   -- a search answered while this page was hidden
            B.stale = false
            D.ResetParty(); D.ResetMaps()
            PaintSpot()
            Load()
        elseif B.stale then
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
            for _, c in ipairs(B.cards) do if c:IsShown() and c.r then PaintAge(c) end end
            B.appsBar:Paint()
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
