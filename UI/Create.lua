-------------------------------------------------------------------------------
--  UI/Create.lua  --  the + Create tab: list your keystone
--
--  Two clicks: the "+ Create" tab is a secure button that clicks
--  Blizzard's Start a Group (UI/Window.lua), so Blizzard's own code picks
--  your keystone and writes the title; "List group" here then sends
--  CreateListing with the playstyle, requirements and options set below.
--  The title keeps what Blizzard wrote (its playstyle word included): addon
--  code writing the title gets the listing blocked.
--  Settings persist in GottaQueueEmAllDB.ui.create; "Looking for" marks
--  matching applicants in Your Group.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A, D = UI.Theme, UI.W, UI.Anim, UI.Data
local C, S = T.C, T.S
local floor, max, min = math.floor, math.max, math.min

local CR = {}
UI.Create = CR

local E = Enum and Enum.LFGEntryGeneralPlaystyle or {}
local STYLES = { E.Learning or 1, E.FunRelaxed or 2, E.FunSerious or 3, E.Expert or 4 }

local function State()
    local db = ns.DB and ns.DB()
    local st = CR.tmp or {}
    if db then
        db.ui = db.ui or {}
        if type(db.ui.create) ~= "table" then db.ui.create = {} end
        st = db.ui.create
    end
    CR.tmp = st
    if st.playstyle == nil then st.playstyle = E.FunRelaxed or 2 end
    if st.rating == nil then st.rating = 0 end
    if st.ilvl == nil then st.ilvl = 0 end
    return st
end
-- For Your Group's "looking for" marks.
function CR.State() return State() end

local Refresh   -- forward

-------------------------------------------------------------------------------
--  Build
-------------------------------------------------------------------------------
local function Section(parent, text, anchor, dy)
    local l = W.Label(parent, text)
    l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, dy or -16)
    return l
end

local function BuildLeft(col, st)
    -- Key plaque: journal art, your key, the dungeon.
    local plaque = W.Banner(col)
    plaque:SetPoint("TOPLEFT"); plaque:SetPoint("TOPRIGHT")
    plaque:SetHeight(118)
    plaque.key = W.Text(plaque, "key")
    plaque.key:SetPoint("LEFT", 22, 0)
    plaque.key:SetShadowOffset(0, -2); plaque.key:SetShadowColor(0, 0, 0, 0.6)
    plaque.over = W.Text(plaque, "label", C.text)
    plaque.over:SetPoint("TOPLEFT", plaque.key, "TOPRIGHT", 18, -2)
    plaque.over:SetText("YOUR KEYSTONE")
    plaque.name = W.Text(plaque, "display")
    plaque.name:SetPoint("TOPLEFT", plaque.over, "BOTTOMLEFT", 0, -4)
    plaque.name:SetShadowOffset(0, -2); plaque.name:SetShadowColor(0, 0, 0, 0.5)
    plaque.best = W.Text(plaque, "bodySm")
    plaque.best:SetPoint("TOPLEFT", plaque.name, "BOTTOMLEFT", 0, -6)
    A.Pulse(plaque.key, 0.75, 3)
    CR.plaque = plaque

    CR.status = W.Text(col, "small")
    CR.status:SetPoint("TOPLEFT", plaque, "BOTTOMLEFT", 2, -8)
    CR.status:SetPoint("TOPRIGHT", plaque, "BOTTOMRIGHT", -2, -8)
    CR.status:SetHeight(16)   -- fixed: the layout below must not jump when it is empty

    -- Playstyle: four segments.
    local ps = Section(col, "Playstyle", CR.status, -14)
    CR.styles = {}
    local holder = CreateFrame("Frame", nil, col)
    holder:SetPoint("TOPLEFT", ps, "BOTTOMLEFT", 0, -8)
    holder:SetPoint("RIGHT", col, "RIGHT")
    holder:SetHeight(40)
    holder:SetScript("OnSizeChanged", function(self, w)
        local bw = (w - 3 * 6) / 4
        for i, b in ipairs(CR.styles) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", (i - 1) * (bw + 6), 0)
            b:SetSize(bw, 40)
        end
    end)
    for i, v in ipairs(STYLES) do
        local b = W.Button(holder, D.PlaystyleLabel(v) or "?", "mark", 120, 40, "h2")
        b.value = v
        b:SetScript("OnClick", function() st.playstyle = v; Refresh() end)
        CR.styles[i] = b
    end

    -- Minimum rating: market histogram from Browse's last search.
    local mine = C_ChallengeMode.GetOverallDungeonScore and D.Num(C_ChallengeMode.GetOverallDungeonScore()) or 0
    mine = floor(mine)
    local p1 = W.Panel(col)
    p1:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -14)
    p1:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -14)
    p1:SetHeight(150)
    local l1 = W.Label(p1, "Minimum rating"); l1:SetPoint("TOPLEFT", 14, -12)
    CR.ratingValue = W.Text(p1, "num"); CR.ratingValue:SetPoint("TOPRIGHT", -14, -8)
    CR.hist = W.Histogram(p1, 18)
    CR.hist:SetPoint("TOPLEFT", 14, -40); CR.hist:SetPoint("TOPRIGHT", -14, -40); CR.hist:SetHeight(46)
    CR.rating = W.Slider(p1, { min = 0, max = 3600, step = 50, value = st.rating, stops = T.RATING_STOPS,
                               marker = mine > 0 and mine or nil })
    CR.rating:SetPoint("TOPLEFT", CR.hist, "BOTTOMLEFT"); CR.rating:SetPoint("TOPRIGHT", CR.hist, "BOTTOMRIGHT")
    CR.rating.onChange = function(v) st.rating = v; Refresh() end
    local mx = 14
    local marks = { { "Any", 0 } }
    if mine >= 200 then marks[#marks + 1] = { "Mine −200", mine - 200 } end
    if mine > 0 then marks[#marks + 1] = { "Mine " .. mine, mine } end
    for _, m in ipairs(marks) do
        local b = W.Button(p1, m[1], "mark", nil, 24, "tiny")
        b:SetWidth(b.label:GetStringWidth() + 18)
        b:SetPoint("TOPLEFT", mx, -118)
        b:SetScript("OnClick", function() CR.rating:SetValue(m[2], true) end)
        mx = mx + b:GetWidth() + 4
    end
    CR.share = W.Text(p1, "small")
    CR.share:SetPoint("TOPRIGHT", -14, -122)

    -- Minimum item level, up to your own (Blizzard refuses more). Settings
    -- are account-wide: a value from another character outside this range
    -- is dropped.
    local _, myIlvl = GetAverageItemLevel()
    myIlvl = floor(D.Num(myIlvl) or 0)
    local lo = max(0, myIlvl - 40)
    if st.ilvl > 0 and (st.ilvl <= lo or st.ilvl > myIlvl) then st.ilvl = 0 end
    local p2 = W.Panel(col)
    p2:SetPoint("TOPLEFT", p1, "BOTTOMLEFT", 0, -14)
    p2:SetPoint("TOPRIGHT", p1, "BOTTOMRIGHT", 0, -14)
    p2:SetHeight(100)
    local l2 = W.Label(p2, "Minimum item level"); l2:SetPoint("TOPLEFT", 14, -12)
    CR.ilvlValue = W.Text(p2, "num"); CR.ilvlValue:SetPoint("TOPRIGHT", -14, -8)
    CR.ilvl = W.Slider(p2, { min = lo, max = max(lo + 1, myIlvl), step = 1, value = max(lo, st.ilvl), fill = true })
    CR.ilvl:SetPoint("TOPLEFT", 14, -42); CR.ilvl:SetPoint("TOPRIGHT", -14, -42)
    CR.ilvl.onChange = function(v) st.ilvl = v > lo and v or 0; Refresh() end
    mx = 14
    for _, m in ipairs({ { "Any", lo }, { "Mine −10", myIlvl - 10 }, { "Mine " .. myIlvl, myIlvl } }) do
        local b = W.Button(p2, m[1], "mark", nil, 24, "tiny")
        b:SetWidth(b.label:GetStringWidth() + 18)
        b:SetPoint("TOPLEFT", mx, -70)
        b:SetScript("OnClick", function() CR.ilvl:SetValue(m[2], true) end)
        mx = mx + b:GetWidth() + 4
    end
end

local function BuildRight(col, st)
    local lf = W.Label(col, "Looking for"); lf:SetPoint("TOPLEFT")
    local lust = W.Toggle(col, "Bloodlust", "lust", C.lust, 34)
    lust:SetPoint("TOPLEFT", lf, "BOTTOMLEFT", 0, -8)
    lust:SetChecked(st.lust); lust.onChange = function(v) st.lust = v; Refresh() end
    local brez = W.Toggle(col, "Battle res", "brez", C.brez, 34)
    brez:SetPoint("LEFT", lust, "RIGHT", 6, 0)
    brez:SetChecked(st.brez); brez.onChange = function(v) st.brez = v; Refresh() end
    local lfn = W.Text(col, "small")
    lfn:SetPoint("TOPLEFT", lust, "BOTTOMLEFT", 0, -8)
    lfn:SetText("Applicants who bring it are marked in Your Group.")

    local op = W.Label(col, "Options"); op:SetPoint("TOPLEFT", lfn, "BOTTOMLEFT", 0, -18)
    local priv = W.Toggle(col, "Private group", nil, nil, 34)
    priv:SetPoint("TOPLEFT", op, "BOTTOMLEFT", 0, -8)
    priv:SetChecked(st.private); priv.onChange = function(v) st.private = v; Refresh() end
    local fac = W.Toggle(col, "Own faction only", nil, nil, 34)
    fac:SetPoint("LEFT", priv, "RIGHT", 6, 0)
    fac:SetChecked(st.ownFaction); fac.onChange = function(v) st.ownFaction = v; Refresh() end

    -- How others see it: a Browse card in small.
    local pv = W.Label(col, "How others see it"); pv:SetPoint("TOPLEFT", priv, "BOTTOMLEFT", 0, -18)
    local card = W.Card(col)
    card:SetPoint("TOPLEFT", pv, "BOTTOMLEFT", 0, -8)
    card:SetPoint("RIGHT", col, "RIGHT")
    card:SetHeight(128)
    card:EnableMouse(false)
    card.strip = card:CreateTexture(nil, "ARTWORK")
    card.strip:SetPoint("TOPLEFT"); card.strip:SetPoint("TOPRIGHT"); card.strip:SetHeight(54)
    W.CornerCaps(card, card.strip, C.bg, { TL = true, TR = true })
    card.shade = W.Tex(card, "ARTWORK", nil, 1)
    card.shade:SetAllPoints(card.strip)
    W.Gradient(card.shade, "VERTICAL", { 0, 0, 0, 0.55 }, { 0, 0, 0, 0 })
    card.name = W.Text(card, "h2"); card.name:SetPoint("BOTTOMLEFT", card.strip, "BOTTOMLEFT", 12, 8)
    card.name:SetShadowOffset(0, -1); card.name:SetShadowColor(0, 0, 0, 0.8)
    card.title = W.Text(card, "body", C.text); card.title:SetPoint("BOTTOMRIGHT", card.strip, "BOTTOMRIGHT", -12, 9)
    card.leader = W.Text(card, "bodySm"); card.leader:SetPoint("TOPLEFT", card.strip, "BOTTOMLEFT", 12, -8)
    card.rating = W.Text(card, "numSm"); card.rating:SetPoint("TOPRIGHT", card.strip, "BOTTOMRIGHT", -12, -6)
    card.req = W.Text(card, "small"); card.req:SetPoint("TOPLEFT", card.leader, "BOTTOMLEFT", 0, -10)
    card.req:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    CR.card = card

    -- List group: the primary action.
    CR.list = W.Button(col, "List group", "gold", nil, 52, "h2")
    CR.list:SetPoint("BOTTOMLEFT", 0, 22); CR.list:SetPoint("BOTTOMRIGHT", 0, 22)
    CR.list:SetScript("OnClick", function()
        -- Check again: form, key or listing may have changed since the last refresh.
        local key = D.OwnKey()
        if not key or not D.FormReady(key.act) or C_LFGList.HasActiveEntryInfo() then Refresh(); return end
        CR.pending = true
        local seq = (CR.seq or 0) + 1
        CR.seq = seq
        local ok, err = pcall(D.CreateListing, key, st)
        if not ok then CR.pending = false; ns.Print("could not list (" .. tostring(err) .. ")") end
        -- No answer at all: release the button.
        C_Timer.After(5, function()
            if CR.pending and CR.seq == seq then CR.pending = false; Refresh() end
        end)
        Refresh()
    end)
    CR.listNote = W.Text(col, "tiny")
    CR.listNote:SetPoint("TOP", CR.list, "BOTTOM", 0, -6)
end

-------------------------------------------------------------------------------
--  Refresh
-------------------------------------------------------------------------------
Refresh = function()
    if not (CR.page and CR.page:IsVisible()) then return end   -- OnShow refreshes
    local st = CR.st
    local key = D.OwnKey()
    local listed = C_LFGList.HasActiveEntryInfo()
    if listed then CR.pending = false end
    local ready = key and D.FormReady(key.act)

    -- Plaque.
    local p = CR.plaque
    if key then
        p.over:ClearAllPoints()
        p.over:SetPoint("TOPLEFT", p.key, "TOPRIGHT", 18, -2)
        local art = T.DungeonArt(key.cid)
        if art.bg then p:SetArt(art.bg, 2) else p:SetArt(art.lore or art.framed, 2.13, { 0.06, 0.70, 0.10, 0.70 }) end
        p.key:SetText(key.level and ("+" .. key.level) or "")
        p.key:SetTextColor(unpack(T.KeyColor(key.level or 0)))
        p.name:SetText(key.dungeon)
        local level, timed
        if ns.BestKey and key.cid then level, timed = ns.BestKey(key.cid) end
        p.best:SetText(level and ("Your best here: " .. T.ColorCode(T.KeyColor(level, timed)) .. "+" .. level
            .. "|r " .. (timed and "in time" or "over time")) or "|cff8d98a8No run here this season|r")
        p.over:Show()
    else
        p:SetArt(nil)
        p.key:SetText("")
        p.over:ClearAllPoints()
        p.over:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -24)   -- the empty key has no height to hang from
        p.over:Hide()
        p.name:SetText("No keystone")
        p.best:SetText("|cff8d98a8You need a Mythic Keystone in your bags to list a group.|r")
    end

    -- Status line under the plaque.
    if listed then
        CR.status:SetText("|cff96e3adYour group is listed.|r  See Your Group for applicants.")
    elseif not key then
        CR.status:SetText("")
    elseif ready then
        CR.status:SetText("|cff96e3adReady.|r  Blizzard prepared the listing for your keystone.")
    elseif not D.CanStart() then
        CR.status:SetText("|cffe0b868Blizzard's Group Finder isn't ready:|r open it once (I), then click + Create again.")
    else
        CR.status:SetText("|cffe0b868Click the + Create tab|r to prepare the listing for your keystone.")
    end

    -- Controls.
    for _, b in ipairs(CR.styles) do b:SetVariant(st.playstyle == b.value and "ghost" or "mark") end
    CR.ratingValue:SetText(st.rating > 0 and (st.rating .. "+") or "Any")
    CR.ratingValue:SetTextColor(unpack(st.rating > 0 and T.RatingColor(st.rating) or C.label))
    CR.ilvlValue:SetText(st.ilvl > 0 and (st.ilvl .. "+") or "Any")

    -- Histogram: leaders of Browse's last search.
    local ratings = {}
    for _, r in ipairs(UI.Browse and UI.Browse.results or {}) do ratings[#ratings + 1] = r.rating end
    local counts = {}
    for i = 1, 18 do counts[i] = 0 end
    for _, r in ipairs(ratings) do local i = min(18, floor(r / 200) + 1); counts[i] = counts[i] + 1 end
    CR.hist:SetData(counts, function(i) return T.RatingColor((i - 1) * 200 + 100) end,
        function(i) return i * 200 <= st.rating end)
    if #ratings > 0 then
        local q = 0
        for _, r in ipairs(ratings) do if r >= st.rating then q = q + 1 end end
        CR.share:SetText(("|cfff5f7fa%d%%|r of leaders in your last search qualify"):format(floor(q / #ratings * 100 + 0.5)))
    else
        CR.share:SetText("Search in Browse to see who qualifies")
    end

    -- Preview card.
    local card = CR.card
    local art = key and T.DungeonArt(key.cid) or {}
    card.strip:SetTexture(art.button or art.icon)
    -- Cropped to the strip's aspect (no stretching).
    local w, h = max(1, card:GetWidth()), 54
    if art.button then
        local vh = 175 * h / w / 128
        card.strip:SetTexCoord(0, 0.684, 47.5 / 128 - vh / 2, 47.5 / 128 + vh / 2)
    else
        local vh = 0.84 * h / w
        card.strip:SetTexCoord(0.08, 0.92, 0.5 - vh / 2, 0.5 + vh / 2)
    end
    card.name:SetText(key and key.dungeon or "")
    -- The title shows Blizzard's playstyle word (its form's choice).
    local ec = LFGListFrame and LFGListFrame.EntryCreation
    local titleStyle = ec and D.Num(ec.generalPlaystyle)
    titleStyle = (titleStyle and titleStyle > 0) and titleStyle or nil
    card.title:SetText(key and key.level and ("+" .. key.level .. " " .. (D.PlaystyleLabel(titleStyle or st.playstyle) or "")) or "")
    CR.titleStyle = titleStyle
    local _, class = UnitClass("player")
    local mine = C_ChallengeMode.GetOverallDungeonScore and D.Num(C_ChallengeMode.GetOverallDungeonScore()) or 0
    card.leader:SetText(T.ColorCode(T.ClassColor(class)) .. (UnitName("player") or "") .. "|r")
    card.rating:SetText(floor(mine)); card.rating:SetTextColor(unpack(T.RatingColor(mine)))
    local req = {}
    req[#req + 1] = st.rating > 0 and ("Rating " .. T.ColorCode(T.RatingColor(st.rating)) .. st.rating .. "+|r") or "No rating needed"
    req[#req + 1] = st.ilvl > 0 and ("Item level |cfff5f7fa" .. st.ilvl .. "+|r") or "Any item level"
    if st.private then req[#req + 1] = "|cffe0b868Private|r" end
    if st.ownFaction then req[#req + 1] = "Own faction" end
    card.req:SetText(table.concat(req, "   ·   "))

    -- List group (only the leader, or you alone, can list).
    local tooHigh = st.rating > floor(mine)   -- your rating now, not when the tab was built
    local can = key and ready and not listed and not CR.pending and D.CanApply() and not tooHigh
    CR.list:SetEnabled(can and true or false)
    CR.list:SetLabel(listed and "Listed" or CR.pending and "Listing…" or "List group")
    local note = "The title is Blizzard's: your key and a playstyle word."
    if listed then note = ""
    elseif not D.CanApply() then note = "Only the group leader can list."
    elseif tooHigh then note = "The minimum rating can't be above your own."
    elseif CR.titleStyle and CR.titleStyle ~= st.playstyle then
        note = ("The title will say %s (Blizzard's choice); listed as %s."):format(
            D.PlaystyleLabel(CR.titleStyle) or "?", D.PlaystyleLabel(st.playstyle) or "?")
    end
    CR.listNote:SetText(note)
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
-- Only while the window is open (ns.Live); the page's OnShow refreshes.
local events = CreateFrame("Frame")
ns.Live(events, { "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_ENTRY_CREATION_FAILED", "BAG_UPDATE_DELAYED",
                  "GROUP_ROSTER_UPDATE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" })
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not CR.page then return end
    if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        if CR.pending and C_LFGList.HasActiveEntryInfo() then
            CR.pending = false
            if UI.SelectTab then UI.SelectTab(2) end   -- straight to your applicants
        end
    elseif event == "LFG_LIST_ENTRY_CREATION_FAILED" then
        if CR.pending then
            CR.pending = false
            ns.Print("listing failed. Click + Create again so Blizzard prepares it, then List group.")
        end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if CR.pending and (arg1 == "GottaQueueEmAll" or tostring(arg2):find("CreateListing")) then
            CR.pending = false
            ns.Print("listing was blocked (" .. tostring(arg2) .. "). Click + Create again, then List group.")
        end
    end
    Refresh()
end)

function CR.Refresh() Refresh() end

function UI.BuildCreate(page)
    CR.st = State()
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", S.pad, -14)
    left:SetPoint("BOTTOMLEFT", S.pad, 10)
    left:SetWidth(560)
    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 24, 0)
    right:SetPoint("BOTTOMRIGHT", -S.pad, 10)
    BuildLeft(left, CR.st)
    BuildRight(right, CR.st)
    page:SetScript("OnShow", function()
        Refresh()
        -- Blizzard's form fills in right after the tab's secure click.
        C_Timer.After(0.2, Refresh)
        if UI.SetStatus then UI.SetStatus("Lists the keystone in your bags") end
    end)
    -- The preview's art crop follows the card's new width.
    page:SetScript("OnSizeChanged", function(self) if self:IsVisible() then Refresh() end end)
    CR.page = page
end
