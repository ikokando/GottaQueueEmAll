-------------------------------------------------------------------------------
--  UI/RaidCreate.lua  --  the + Create page of the Raid and Dungeons sections
--
--  One page, built twice from a config (bottom of the file): list a raid,
--  or a Mythic 0 dungeon (no keystone).
--  Two clicks, as for Mythic+: the "+ Create" tab prepares Blizzard's Start
--  a Group form (a secure click, UI/Window.lua) and its title box moves in
--  here (UI/TitleBox.lua): the title is typed by the player, addons can't
--  write it. "List group" then sends CreateListing with the instance,
--  difficulty, playstyle, requirements and options chosen below (tested in
--  12.1.5: any activity of the category works, the typed title stays).
--  Settings persist in GottaQueueEmAllDB.ui.raidCreate / .ui.dungeonCreate.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, D = UI.Theme, UI.W, UI.Data
local C, S = T.C, T.S
local floor, max = math.floor, math.max

local E = Enum and Enum.LFGEntryGeneralPlaystyle or {}
local STYLES = { E.Learning or 1, E.FunRelaxed or 2, E.FunSerious or 3, E.Expert or 4 }

local function New(cfg)
    local BR = cfg.browse   -- the section's Browse page: instances, difficulties, lockouts
    -- The category whose Start a Group form holds the title. Mythic 0 uses
    -- Custom: on Dungeons Blizzard would pick your keystone and title it "+14".
    local FORM = cfg.formCategory or cfg.category
    local RC = { cfg = cfg }

    local function State()
        local db = ns.DB and ns.DB()
        local st = RC.tmp or {}
        if db then
            db.ui = db.ui or {}
            if type(db.ui[cfg.key]) ~= "table" then db.ui[cfg.key] = {} end
            st = db.ui[cfg.key]
        end
        RC.tmp = st
        local RB = BR
        if st.gid == nil then st.gid = RB.CURRENT[1] end
        if st.diff == nil then st.diff = cfg.defaultDiff end
        if st.playstyle == nil then st.playstyle = E.FunRelaxed or 2 end
        if st.ilvl == nil then st.ilvl = 0 end
        return st
    end
    -- For Your Group's "looking for" marks on a raid listing.
    function RC.State() return State() end

    local Refresh   -- forward

    -- The Group Finder activity of a raid at a difficulty, or nil.
    local actCache = {}
    local function Activity(gid, diff)
        if not (gid and diff) then return end
        local key = gid .. ":" .. diff
        -- Hits only: right after login the Group Finder may not know them yet.
        if actCache[key] then return actCache[key] end
        local found
        local ok, acts = pcall(C_LFGList.GetAvailableActivities, cfg.category, gid)
        for _, act in ipairs(ok and type(acts) == "table" and acts or {}) do
            local ai = C_LFGList.GetActivityInfoTable(act)
            if type(ai) == "table" and D.Num(ai.difficultyID) == diff then found = act; break end
        end
        actCache[key] = found
        return found
    end

    -------------------------------------------------------------------------------
    --  Title: Blizzard's own title box, borrowed (UI/TitleBox.lua)
    -------------------------------------------------------------------------------
    local TB = UI.TitleBox

    local function PaintHolder()
        if RC.titleHolder then RC.titleHolder:Paint(RC.tried and (D.FormTitle(FORM) or "") == "") end
    end

    local function TitleOpts()
        return { onEnter = function() if RC.TryList then RC.TryList() end end, onFocus = PaintHolder }
    end

    function RC.IsBorrowed() return TB.IsBorrowed(RC.titleHolder) end

    -- After the + Create tab's secure click: Blizzard's form is prepared; its
    -- window closes again and its title box moves in here.
    function RC.AfterStart()
        if InCombatLockdown() or not (RC.page and RC.page:IsVisible()) then return end
        if D.FormTitle(FORM) ~= nil then
            TB.TakeOver(RC.titleHolder, TitleOpts())
            TB.Focus()
        end
        RC.Refresh()
    end
    -------------------------------------------------------------------------------
    --  Build
    -------------------------------------------------------------------------------
    local function Section(parent, text, anchor, dy)
        local l = W.Label(parent, text)
        l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, dy or -16)
        return l
    end

    -- Equal-width buttons across a row (difficulty, playstyle).
    local function Segments(col, anchor, list, height, onPick)
        local holder = CreateFrame("Frame", nil, col)
        holder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        holder:SetPoint("RIGHT", col, "RIGHT")
        holder:SetHeight(height)
        holder.buttons = {}
        holder:SetScript("OnSizeChanged", function(self, w)
            local n = #self.buttons
            local bw = (w - (n - 1) * 6) / n
            for i, b in ipairs(self.buttons) do
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", (i - 1) * (bw + 6), 0)
                b:SetSize(bw, height)
            end
        end)
        for i, item in ipairs(list) do
            local b = W.Button(holder, item[2], "mark", 120, height, "h2")
            b.value = item[1]
            b:SetScript("OnClick", function() onPick(item[1]) end)
            holder.buttons[i] = b
        end
        return holder
    end

    local function BuildChips(col, anchor, st)
        local RB = BR
        local row = CreateFrame("Frame", nil, col)
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        row:SetPoint("RIGHT", col, "RIGHT")
        row:SetHeight(S.chipH)
        RC.chipRow = row
        RC.chips = {}
        local function Add(gid, season1)
            local raid = RB.Raid(gid)
            local c = W.Chip(row, raid.short, raid.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            c.gid, c.season1 = gid, season1
            c.onClick = function() st.gid = gid; Refresh() end
            c:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(raid.name, 1, 1, 1)
                GameTooltip:Show()
            end)
            c:HookScript("OnLeave", function() GameTooltip:Hide() end)
            RC.chips[#RC.chips + 1] = c
        end
        for _, gid in ipairs(RB.CURRENT) do Add(gid) end
        -- For Refresh, when the list was still empty here.
        function RC.AddChips() for _, gid in ipairs(RB.CURRENT) do Add(gid) end end
        row:SetScript("OnSizeChanged", function() RC.LayoutChips() end)
        if #RB.SEASON1 == 0 then return end   -- nothing older to offer
        local s1 = W.Toggle(row, "Season 1 raids")
        s1:SetHeight(S.chipH)
        s1:SetChecked(st.showS1)
        s1.onChange = function(v)
            st.showS1 = v
            if not v then
                local old = false
                for _, gid in ipairs(RB.SEASON1) do if st.gid == gid then old = true end end
                if old then st.gid = RB.CURRENT[1] end
            end
            RC.LayoutChips(); Refresh()
        end
        s1.gap = 0
        RC.chips[#RC.chips + 1] = s1
        for i, gid in ipairs(RB.SEASON1) do
            Add(gid, true)
            if i == 1 then RC.chips[#RC.chips].newRow = true end
        end
        row:SetScript("OnSizeChanged", function() RC.LayoutChips() end)
    end

    function RC.LayoutChips()
        local row, st = RC.chipRow, RC.st
        local w = row:GetWidth() > 0 and row:GetWidth() or 560
        local x, y = 0, 0
        for i, c in ipairs(RC.chips) do
            local shown = not c.season1 or st.showS1
            c:SetShown(shown)
            if shown then
                if (c.newRow and x > 0) or (x > 0 and x + c:GetWidth() > w) then x, y = 0, y + S.chipH + 6 end
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", x, -y)
                x = x + c:GetWidth() + (i == #BR.CURRENT and 16 or 6)
            end
        end
        row:SetHeight(y + S.chipH)
    end

    local function BuildLeft(col, st)
        -- Raid plaque: journal art, difficulty, the raid, your lockout.
        local plaque = W.Banner(col)
        plaque:SetPoint("TOPLEFT"); plaque:SetPoint("TOPRIGHT")
        plaque:SetHeight(118)
        plaque.diff = W.Text(plaque, "key")
        plaque.diff:SetPoint("LEFT", 22, 0)
        plaque.diff:SetShadowOffset(0, -2); plaque.diff:SetShadowColor(0, 0, 0, 0.6)
        plaque.over = W.Text(plaque, "label", C.text)
        plaque.over:SetPoint("TOPLEFT", plaque.diff, "TOPRIGHT", 18, -2)
        plaque.name = W.Text(plaque, "display")
        plaque.name:SetPoint("TOPLEFT", plaque.over, "BOTTOMLEFT", 0, -4)
        plaque.name:SetShadowOffset(0, -2); plaque.name:SetShadowColor(0, 0, 0, 0.5)
        plaque.lock = W.Text(plaque, "bodySm")
        plaque.lock:SetPoint("TOPLEFT", plaque.name, "BOTTOMLEFT", 0, -6)
        RC.plaque = plaque

        RC.status = W.Text(col, "small")
        RC.status:SetPoint("TOPLEFT", plaque, "BOTTOMLEFT", 2, -8)
        RC.status:SetPoint("TOPRIGHT", plaque, "BOTTOMRIGHT", -2, -8)
        RC.status:SetHeight(16)

        local lr = Section(col, cfg.kind == "raid" and "Raid" or "Dungeon", RC.status, -14)
        BuildChips(col, lr, st)

        -- Difficulty, when there is a choice (Mythic 0 has one).
        local above = RC.chipRow
        if #BR.DIFF_ORDER > 1 then
            local ld = Section(col, "Difficulty", RC.chipRow, -16)
            local diffs = {}
            for _, id in ipairs(BR.DIFF_ORDER) do diffs[#diffs + 1] = { id, BR.DIFF[id].name } end
            RC.diffs = Segments(col, ld, diffs, 40, function(v) st.diff = v; Refresh() end)
            above = RC.diffs
        else
            st.diff = BR.DIFF_ORDER[1]
        end

        local lp = Section(col, "Playstyle", above, -16)
        local styles = {}
        for _, v in ipairs(STYLES) do styles[#styles + 1] = { v, D.PlaystyleLabel(v) or "?" } end
        RC.styles = Segments(col, lp, styles, 40, function(v) st.playstyle = v; Refresh() end)

        -- Minimum item level, up to your own (Blizzard refuses more).
        local _, myIlvl = GetAverageItemLevel()
        myIlvl = floor(D.Num(myIlvl) or 0)
        local lo = max(0, myIlvl - 40)
        if st.ilvl > 0 and (st.ilvl <= lo or st.ilvl > myIlvl) then st.ilvl = 0 end
        local p2 = W.Panel(col)
        p2:SetPoint("TOPLEFT", RC.styles, "BOTTOMLEFT", 0, -14)
        p2:SetPoint("TOPRIGHT", RC.styles, "BOTTOMRIGHT", 0, -14)
        p2:SetHeight(100)
        local l2 = W.Label(p2, "Minimum item level"); l2:SetPoint("TOPLEFT", 14, -12)
        RC.ilvlValue = W.Text(p2, "num"); RC.ilvlValue:SetPoint("TOPRIGHT", -14, -8)
        RC.ilvl = W.Slider(p2, { min = lo, max = max(lo + 1, myIlvl), step = 1, value = max(lo, st.ilvl), fill = true })
        RC.ilvl:SetPoint("TOPLEFT", 14, -42); RC.ilvl:SetPoint("TOPRIGHT", -14, -42)
        RC.ilvl.onChange = function(v) st.ilvl = v > lo and v or 0; Refresh() end
        local mx = 14
        for _, m in ipairs({ { "Any", lo }, { "Mine −10", myIlvl - 10 }, { "Mine " .. myIlvl, myIlvl } }) do
            local b = W.Button(p2, m[1], "mark", nil, 24, "tiny")
            b:SetWidth(b.label:GetStringWidth() + 18)
            b:SetPoint("TOPLEFT", mx, -70)
            b:SetScript("OnClick", function() RC.ilvl:SetValue(m[2], true) end)
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

        -- Title: Blizzard's own title box, borrowed into this panel (addons
        -- can't write a title; you type it here, into Blizzard's field).
        local tl = W.Label(col, "Title"); tl:SetPoint("TOPLEFT", priv, "BOTTOMLEFT", 0, -18)
        local req = W.Text(col, "tiny", C.goldText); req:SetPoint("LEFT", tl, "RIGHT", 8, 0); req:SetText("REQUIRED")
        local holder = TB.Holder(col)
        holder:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, -8)
        holder:SetPoint("RIGHT", col, "RIGHT")
        RC.titleHolder = holder
        RC.titleNote = W.Text(col, "bodySm")
        RC.titleNote:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -8)
        RC.titleNote:SetPoint("RIGHT", col, "RIGHT")
        RC.titleNote:SetWordWrap(true)

        -- How others see it.
        local pv = W.Label(col, "How others see it"); pv:SetPoint("TOPLEFT", RC.titleNote, "BOTTOMLEFT", 0, -18)
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
        card.diff = W.Text(card, "numSm"); card.diff:SetPoint("TOPRIGHT", card.strip, "BOTTOMRIGHT", -12, -6)
        card.req = W.Text(card, "small"); card.req:SetPoint("TOPLEFT", card.leader, "BOTTOMLEFT", 0, -10)
        card.req:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        RC.card = card

        RC.list = W.Button(col, "List group", "gold", nil, 52, "h2")
        RC.list:SetPoint("BOTTOMLEFT", 0, 22); RC.list:SetPoint("BOTTOMRIGHT", 0, 22)
        -- List group: without a title it leads to the title box instead of
        -- refusing (the button never sits there grey and silent).
        function RC.TryList()
            local act = Activity(st.gid, st.diff)
            local title = D.FormTitle(FORM)
            if not act or not title or C_LFGList.HasActiveEntryInfo() or RC.pending then Refresh(); return end
            if title == "" then
                RC.tried = true
                if RC.IsBorrowed() then TB.Focus() end
                RC.titleHolder:Flash()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                Refresh()
                return
            end
            RC.pending = true
            local seq = (RC.seq or 0) + 1
            RC.seq = seq
            local ok, err = pcall(D.CreateRaidListing, act, st)
            if not ok then RC.pending = false; ns.Print("could not list (" .. tostring(err) .. ")") end
            C_Timer.After(5, function()
                if RC.pending and RC.seq == seq then RC.pending = false; Refresh() end
            end)
            Refresh()
        end
        RC.list:SetScript("OnClick", function() RC.TryList() end)
        RC.listNote = W.Text(col, "tiny")
        RC.listNote:SetPoint("TOP", RC.list, "BOTTOM", 0, -6)
    end

    -------------------------------------------------------------------------------
    --  Refresh
    -------------------------------------------------------------------------------
    Refresh = function()
        if not (RC.page and RC.page:IsVisible()) then return end
        local st, RB = RC.st, BR
        -- The Browse page loaded its instance list again (a stand-in was
        -- replaced, on LFG_LIST_AVAILABILITY_UPDATE or its OnShow): the same
        -- chips here.
        if RC.version ~= RB.version and RC.AddChips then
            local keep = {}
            for _, c in ipairs(RC.chips) do
                if c.gid and not c.season1 then c:Hide() else keep[#keep + 1] = c end
            end
            RC.chips = keep
            RC.AddChips()
            RC.version = RB.version
        end
        -- A saved pick no longer offered (new season, other list): the first one.
        local known = false
        for _, gid in ipairs(RB.CURRENT) do if gid == st.gid then known = true end end
        for _, gid in ipairs(RB.SEASON1) do if gid == st.gid then known = true end end
        if not known then st.gid = nil end
        st.gid = st.gid or RB.CURRENT[1]
        if not st.gid then
            RC.status:SetText("|cffe0b868Blizzard's Group Finder isn't ready yet:|r open it once (I), then come back.")
            RC.list:SetEnabled(false)
            return
        end
        local raid = RB.Raid(st.gid)
        local diff = RB.DIFF[st.diff]
        local act = Activity(st.gid, st.diff)
        local listed = C_LFGList.HasActiveEntryInfo()
        if listed then RC.pending = false end
        local title = D.FormTitle(FORM)   -- nil: Blizzard's raid form isn't open

        -- Plaque.
        local p = RC.plaque
        p:SetArt(raid.art, 175 / 95, { 0.048, 0.636, 0, 0.742 })
        p.diff:SetText(diff.key)
        p.diff:SetTextColor(unpack(diff.color))
        p.over:SetText(diff.name:upper() .. " " .. cfg.kind:upper())
        p.name:SetText(raid.name)
        local mine, color = RB.Lockout(raid)
        p.lock:SetText(mine and ("Your lockout this week: " .. T.ColorCode(color) .. mine .. "|r")
            or "|cff8d98a8No lockout here this week|r")

        -- Status line under the plaque.
        if listed then
            RC.status:SetText("|cff96e3adYour group is listed.|r  See Your Group for applicants.")
        elseif title and title ~= "" then
            RC.status:SetText("|cff96e3adReady.|r  List group when you are.")
        elseif title then
            RC.status:SetText("|cff96e3adPrepared.|r  Type a title, then List group.")
        elseif not D.CanStart(FORM) then
            RC.status:SetText("|cffe0b868Blizzard's Group Finder isn't ready:|r open it once (I), then click + Create again.")
        else
            RC.status:SetText("|cffe0b868Click the + Create tab|r to prepare the listing.")
        end

        -- Controls.
        for _, c in ipairs(RC.chips) do if c.gid then c:SetOn(c.gid == st.gid) end end
        RC.LayoutChips()
        for _, b in ipairs(RC.diffs and RC.diffs.buttons or {}) do b:SetVariant(st.diff == b.value and "ghost" or "mark") end
        for _, b in ipairs(RC.styles.buttons) do b:SetVariant(st.playstyle == b.value and "ghost" or "mark") end
        RC.ilvlValue:SetText(st.ilvl > 0 and (st.ilvl .. "+") or "Any")

        -- Title.
        if title and title ~= "" then RC.tried = false end
        if RC.IsBorrowed() and RC.tried then
            RC.titleNote:SetText("|cffff9f96A title is needed to list.|r  |cff8d98a8Type it above: only players may write it.|r")
        elseif RC.IsBorrowed() and title and title ~= "" then
            RC.titleNote:SetText("|cff8d98a8Press Enter or List group.|r")
        elseif RC.IsBorrowed() and (TB.Text() or ""):find("|K", 1, true) then
            RC.titleNote:SetText("|cffe0b868Blizzard put your keystone's title in.|r  |cff8d98a8Replace it with your own: select it, then type.|r")
        elseif RC.IsBorrowed() then
            RC.titleNote:SetText("|cff8d98a8Only you can write the title (Blizzard's rule). Type it above; Enter lists.|r")
        elseif title then
            RC.titleNote:SetText("|cff8d98a8The title box is in Blizzard's window right now; type it there.|r")
        else
            RC.titleNote:SetText("|cff8d98a8Click the + Create tab: the title box appears here.|r")
        end

        -- Preview card.
        local card = RC.card
        card.strip:SetTexture(raid.art or raid.icon)
        local w, h = max(1, card:GetWidth()), 54
        if raid.art then
            local vh = 175 * h / w / 128
            card.strip:SetTexCoord(0, 0.684, 47.5 / 128 - vh / 2, 47.5 / 128 + vh / 2)
        else
            local vh = 0.84 * h / w
            card.strip:SetTexCoord(0.08, 0.92, 0.5 - vh / 2, 0.5 + vh / 2)
        end
        card.name:SetText(raid.name)
        card.title:SetText(title and title ~= "" and title or "|cff8d98a8[your title]|r")
        local _, class = UnitClass("player")
        card.leader:SetText(T.ColorCode(T.ClassColor(class)) .. (UnitName("player") or "") .. "|r")
        card.diff:SetText(diff.name)
        card.diff:SetTextColor(unpack(diff.color))
        local req = { D.PlaystyleLabel(st.playstyle) or "?" }
        req[#req + 1] = st.ilvl > 0 and ("Item level |cfff5f7fa" .. st.ilvl .. "+|r") or "Any item level"
        if st.private then req[#req + 1] = "|cffe0b868Private|r" end
        if st.ownFaction then req[#req + 1] = "Own faction" end
        card.req:SetText(table.concat(req, "   ·   "))

        -- List group.
        local can = act and title and not listed and not RC.pending and D.CanApply()
        RC.list:SetEnabled(can and true or false)
        -- Without a title the button stays clickable and leads to the title box.
        RC.list:SetLabel(listed and "Listed" or RC.pending and "Listing…"
            or (title == "" and RC.IsBorrowed()) and "Add a title to list" or "List group")
        local note = ""
        if listed then note = ""
        elseif not D.CanApply() then note = "Only the group leader can list."
        elseif not act then note = "This " .. cfg.kind .. " can't be listed at that difficulty."
        elseif not title then note = "Click the + Create tab first: it prepares the listing."
        end
        RC.listNote:SetText(note)
        PaintHolder()
    end

    -------------------------------------------------------------------------------
    --  Events
    -------------------------------------------------------------------------------
    local events = CreateFrame("Frame")
    ns.Live(events, { "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_ENTRY_CREATION_FAILED", "GROUP_ROSTER_UPDATE",
                      "UPDATE_INSTANCE_INFO", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" })
    events:SetScript("OnEvent", function(_, event, arg1, arg2)
        if not RC.page then return end
        if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
            if RC.pending and C_LFGList.HasActiveEntryInfo() then
                RC.pending = false
                if UI.SelectTab then UI.SelectTab(2) end
            end
        elseif event == "LFG_LIST_ENTRY_CREATION_FAILED" then
            if RC.pending then
                RC.pending = false
                ns.Print("listing failed. Click the + Create tab again, type the title, then List group.")
            end
        elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
            if RC.pending and (arg1 == "GottaQueueEmAll" or tostring(arg2):find("CreateListing")) then
                RC.pending = false
                ns.Print("listing was blocked (" .. tostring(arg2) .. "). Click + Create again, then List group.")
            end
        end
        Refresh()
    end)

    function RC.Refresh() Refresh() end

    function RC.Build(page)
        RC.st = State()
        local left = CreateFrame("Frame", nil, page)
        left:SetPoint("TOPLEFT", S.pad, -14)
        left:SetPoint("BOTTOMLEFT", S.pad, 10)
        left:SetWidth(560)
        local right = CreateFrame("Frame", nil, page)
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", 24, 0)
        right:SetPoint("BOTTOMRIGHT", -S.pad, 10)
        BuildLeft(left, RC.st)
        RC.version = BR.version   -- chips built from this list
        BuildRight(right, RC.st)
        page:SetScript("OnShow", function()
            Refresh()
            C_Timer.After(0.2, Refresh)
            if UI.SetStatus then UI.SetStatus("Lists a " .. cfg.kind .. " group") end
            -- The title is typed in Blizzard's form: no event tells us, so look.
            RC.ticker = C_Timer.NewTicker(0.5, function()
                local t = D.FormTitle(FORM)
                if t ~= RC.lastTitle then RC.lastTitle = t; Refresh() end
            end)
        end)
        page:SetScript("OnHide", function()
            if RC.ticker then RC.ticker:Cancel(); RC.ticker = nil end
            if RC.IsBorrowed() then TB.Return() end   -- Blizzard's title box goes home
        end)
        page:SetScript("OnSizeChanged", function(self) if self:IsVisible() then Refresh() end end)
        RC.page = page
    end

    return RC
end   -- New

-------------------------------------------------------------------------------
--  The two pages
-------------------------------------------------------------------------------
UI.RaidCreate = New({ key = "raidCreate", kind = "raid", browse = UI.RaidBrowse,
                      category = D.RAID_CATEGORY, defaultDiff = 15 })
UI.DungeonCreate = New({ key = "dungeonCreate", kind = "dungeon", browse = UI.DungeonBrowse, formCategory = D.CUSTOM_CATEGORY,
                         category = D.CATEGORY, defaultDiff = 23 })
UI.BuildRaidCreate = UI.RaidCreate.Build
UI.BuildDungeonCreate = UI.DungeonCreate.Build
