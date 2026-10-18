-------------------------------------------------------------------------------
--  UI/RaidBrowse.lua  --  the Browse page of the Raid and Dungeons sections
--
--  One page, built twice from a config (bottom of the file):
--   - Raid: this season's raids (and Season 1's on request),
--   - Mythic 0: this season's dungeons at Mythic (no keystone).
--  Each card: which bosses the group's lockout has killed, its size by role,
--  Lust / B-Res, the item level it asks for. A search fetches the category
--  and everything filters here (tested in 12.1.5).
--  Settings persist in GottaQueueEmAllDB.ui.raid / .ui.dungeon.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A, D = UI.Theme, UI.W, UI.Anim, UI.Data
local C, S = T.C, T.S
local floor, max, min = math.floor, math.max, math.min

local CARD_H, CARD_GAP = 86, 8
local SPEC_H = 20     -- raids: the members' specs, a line under the bosses (Spec view)
local SLOT_SPEC_H = 14   -- dungeons: spec names under the role glyphs, as in Mythic+
local SPEC_GAP = 18      -- between those glyphs in the Spec view
local STRIP_W = 136

-- Raids always have the members' line (role glyphs or specs); dungeons grow
-- only for the spec names under their glyphs.
local function CardH(isRaid)
    if isRaid then return CARD_H + SPEC_H end
    return CARD_H + (W.SpecView() and SLOT_SPEC_H or 0)
end

-- Spec view: every role, its glyph and the specs in it, the most frequent
-- first, counted ("Resto ×2"), each in its class color; a role nobody plays
-- yet says "none". Roles apart by a dot.
local ROLE_TAG = {}
for role, g in pairs({ TANK = "tank", HEALER = "healer", DAMAGER = "dps" }) do
    ROLE_TAG[role] = "|T" .. T.TEX .. "glyph-" .. g .. ":16:16|t"
end
local function SpecLine(members)
    local parts = {}
    for _, role in ipairs(D.ROLE_KEYS) do
        local seen, order = {}, {}
        for _, m in ipairs(members) do
            if m.role == role then
                local key = (m.class or "?") .. "|" .. (m.spec or "")
                if not seen[key] then seen[key] = { m = m, n = 0, first = #order }; order[#order + 1] = key end
                seen[key].n = seen[key].n + 1
            end
        end
        table.sort(order, function(a, b)
            if seen[a].n ~= seen[b].n then return seen[a].n > seen[b].n end
            return seen[a].first < seen[b].first   -- stable: first seen first
        end)
        local names = {}
        for _, key in ipairs(order) do
            local e = seen[key]
            local name = e.m.spec and W.SpecShort(e.m.spec)
                or (e.m.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[e.m.class]) or "?"
            names[#names + 1] = T.ColorCode(T.ClassColor(e.m.class)) .. name .. "|r"
                .. (e.n > 1 and ("|cff8d98a8 ×" .. e.n .. "|r") or "")
        end
        parts[#parts + 1] = ROLE_TAG[role] .. " " .. (#names > 0 and table.concat(names, "  ") or "|cff4e5a6bnone|r")
    end
    return table.concat(parts, "  |cff4e5a6b·|r  ")
end

-- Role view: one role glyph per member in its class color, by role, as the
-- Mythic+ cards show them (smaller: up to 30 in a line).
local GLYPH = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local function RoleLine(members)
    local parts = {}
    for _, role in ipairs(D.ROLE_KEYS) do
        local glyphs = {}
        for _, m in ipairs(members) do
            if m.role == role then
                local c = T.ClassColor(m.class)
                glyphs[#glyphs + 1] = ("|T%sglyph-%s:16:16:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(T.TEX, GLYPH[role],
                    floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255))
            end
        end
        if #glyphs > 0 then parts[#parts + 1] = table.concat(glyphs, "") end
    end
    return table.concat(parts, "  |cff4e5a6b·|r  ")
end
local ROLE_NAME = { TANK = TANK or "Tank", HEALER = HEALER or "Healer", DAMAGER = DAMAGER or "Damage" }
local SORTS = { { "age", "Newest" }, { "kills", "Fewest kills" }, { "size", "Most players" } }

local function New(cfg)
    local KILLS_ANY = cfg.killsAny   -- the slider's top: any number of kills

    -- Instances by Group Finder activity group: current, then older (filled on build).
    local CURRENT, SEASON1, SEASON = {}, {}, {}

    -- Difficulties (difficultyID).
    local DIFF = cfg.diffs
    local DIFF_ORDER = cfg.order

    local RB = { results = {}, cards = {}, chips = {}, cfg = cfg }

    local DEFAULT = { raids = {}, showS1 = false, diff = cfg.defaultDiff, maxKills = KILLS_ANY,
                      minSize = 1, spot = true, ilvlFits = true, lust = false, notDeclined = true, sort = "age" }

    local function State()
        local db = ns.DB and ns.DB()
        local st
        if db then
            db.ui = db.ui or {}
            if type(db.ui[cfg.key]) ~= "table" then db.ui[cfg.key] = {} end
            st = db.ui[cfg.key]
        else
            RB.tmp = RB.tmp or {}
            st = RB.tmp
        end
        for k, v in pairs(DEFAULT) do
            if st[k] == nil then
                if type(v) == "table" then
                    st[k] = {}
                    for a, b in pairs(v) do st[k][a] = b end
                else
                    st[k] = v
                end
            end
        end
        return st
    end

    local Render   -- forward

    -------------------------------------------------------------------------------
    --  Raid facts: name, journal art and bosses, your lockout
    -------------------------------------------------------------------------------
    local raidCache = {}

    -- { id, name, short, art, icon, bosses = { names } } for an activity group.
    local function Raid(gid)
        local r = raidCache[gid]
        if r then return r end
        local name = D.Str((C_LFGList.GetActivityGroupInfo(gid))) or "?"
        r = { id = gid, name = name, groupName = name, short = T.Short(name), bosses = {} }
        -- The Group Finder and the journal don't always agree on "The":
        -- "Voidspire" is "The Voidspire" in the journal.
        local jid
        if T.JournalInstance then
            local bare = name:gsub("^The ", "")
            for _, n in ipairs({ name, "The " .. bare, bare }) do
                jid = T.JournalInstance(n, nil, cfg.isRaid)
                if jid then break end
            end
        end
        if jid and EJ_GetInstanceInfo then
            local jname, _, _, button, _, small = EJ_GetInstanceInfo(jid)
            r.journalName, r.art, r.icon = jname, button, small
            if D.Str(jname) then r.name, r.short = jname, T.Short(jname) end   -- the journal's full name
            if EJ_GetEncounterInfoByIndex then
                local i = 1
                while true do
                    local boss = EJ_GetEncounterInfoByIndex(i, jid)
                    if not boss then break end
                    r.bosses[#r.bosses + 1] = boss
                    i = i + 1
                end
            end
        end
        raidCache[gid] = r
        return r
    end

    -- Your lockout this week: the hardest difficulty you're saved to, "4/8 H".
    local function Lockout(raid)
        if not (GetNumSavedInstances and GetSavedInstanceInfo) then return end
        local best
        for i = 1, GetNumSavedInstances() do
            local name, _, _, diffID, locked, _, _, isRaid, _, _, numBosses, killed = GetSavedInstanceInfo(i)
            if (isRaid and true or false) == cfg.isRaid and locked and DIFF[diffID]
               and (name == raid.name or name == raid.groupName) then
                if not best or (DIFF[diffID].rank or diffID) > (DIFF[best.diff].rank or best.diff) then
                    best = { diff = diffID, killed = killed or 0, total = numBosses or 0 }
                end
            end
        end
        if best then
            return ("%d/%d %s"):format(best.killed, best.total, DIFF[best.diff].key), DIFF[best.diff].color
        end
    end

    -- For the Create pages and Your Group.
    RB.Raid, RB.Lockout, RB.DIFF, RB.DIFF_ORDER, RB.CURRENT, RB.SEASON1 = Raid, Lockout, DIFF, DIFF_ORDER, CURRENT, SEASON1

    -- The instance lists (from cfg.groups: they may need the Group Finder's data).
    function RB.LoadGroups()
        if #CURRENT > 0 then return end
        local cur, old, standIn = cfg.groups()
        for _, id in ipairs(cur or {}) do CURRENT[#CURRENT + 1] = id; SEASON[id] = 2 end
        for _, id in ipairs(old or {}) do SEASON1[#SEASON1 + 1] = id; SEASON[id] = 1 end
        RB.standIn = standIn
        -- A new version only when the list changed: the Create page rebuilds
        -- its chips on a new version.
        local key = table.concat(CURRENT, ",") .. "/" .. table.concat(SEASON1, ",")
        if key ~= RB.groupsKey then
            RB.groupsKey = key
            RB.version = (RB.version or 0) + 1
        end
    end

    -- The list loaded first was a stand-in: load it again; chips with it,
    -- only if it changed.
    function RB.ReloadGroups()
        local before = RB.version
        wipe(CURRENT); wipe(SEASON1); wipe(SEASON)
        RB.LoadGroups()
        if RB.version == before or not RB.chipRow then return end
        local keep = {}
        for _, c in ipairs(RB.chips) do
            if c.gid then c:Hide() else keep[#keep + 1] = c end
        end
        RB.chips = keep
        local st = RB.st
        for gid in pairs(st.raids) do if not SEASON[gid] then st.raids[gid] = nil end end
        for _, gid in ipairs(CURRENT) do
            local c = RB.MakeChip(RB.chipRow, gid)
            c.onClick = function(self) st.raids[self.gid] = not st.raids[self.gid] or nil; RB.SyncChips(); RB.Render() end
            RB.chips[#RB.chips + 1] = c
        end
        RB.SyncChips(); RB.LayoutChips(); RB.Render()
    end

    -------------------------------------------------------------------------------
    --  Search results
    -------------------------------------------------------------------------------
    local LUST, BREZ = ns.LUST_CLASS, ns.BREZ_CLASS

    -- One raid listing of our raids as a plain table, or nil.
    local function Read(id)
        if not D.Num(id) then return end
        local info = C_LFGList.GetSearchResultInfo(id)
        if type(info) ~= "table" or issecretvalue and issecretvalue(info) or info.isDelisted == true then return end
        local ids = type(info.activityIDs) == "table" and info.activityIDs
        local act = ids and D.Num(ids[1])
        local ai = act and C_LFGList.GetActivityInfoTable(act)
        if type(ai) ~= "table" or D.Num(ai.categoryID) ~= cfg.category then return end
        local gid = D.Num(ai.groupFinderActivityGroupID)
        local diff = D.Num(ai.difficultyID)
        if not (gid and SEASON[gid] and DIFF[diff]) then return end

        local r = {
            id = id, gid = gid, diff = diff, season = SEASON[gid],
            max = D.Num(ai.maxNumPlayers) or 30,
            title = info.name,   -- K-string: shown, not read
            leader = D.Str(info.leaderName),
            ilvl = D.Num(info.requiredItemLevel) or 0,
            playstyle = D.Num(info.generalPlaystyle),
            size = D.Num(info.numMembers) or 0,
            age = D.Num(info.age) or 0,
            readAt = GetTime(),
            partyGUID = D.Str(info.partyGUID),
            killed = {},
            T = 0, H = 0, D = 0,
        }
        if r.leader then r.leader = Ambiguate(r.leader, "short") end
        local li = C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(id)
        if type(li) == "table" then r.leaderClass, r.leaderSpec = D.Str(li.classFilename), D.Str(li.specName) end

        -- Members by role and class (counts; only the leader is named).
        local mc = C_LFGList.GetSearchResultMemberCounts(id)
        if type(mc) == "table" then
            r.T, r.H, r.D = D.Num(mc.TANK) or 0, D.Num(mc.HEALER) or 0, D.Num(mc.DAMAGER) or 0
            for class in pairs(LUST) do if (D.Num(mc[class]) or 0) > 0 then r.lust = true end end
            for class in pairs(BREZ) do if (D.Num(mc[class]) or 0) > 0 then r.brez = true end end
        end
        -- Each member's role, class and spec (the Spec view).
        r.members = {}
        for i = 1, min(r.size, 40) do
            local pi = D.Tab(C_LFGList.GetSearchResultPlayerInfo and C_LFGList.GetSearchResultPlayerInfo(id, i))
            if pi then
                local role = D.Str(pi.assignedRole)
                r.members[#r.members + 1] = { role = (role == "TANK" or role == "HEALER") and role or "DAMAGER",
                                              class = D.Str(pi.classFilename), spec = D.Str(pi.specName) }
            end
        end

        -- Bosses this group's lockout has killed (nil: a fresh lockout).
        local killed = C_LFGList.GetSearchResultEncounterInfo and C_LFGList.GetSearchResultEncounterInfo(id)
        if type(killed) == "table" then
            for _, boss in ipairs(killed) do
                local n = D.Str(boss)
                if n then r.killed[n] = true; r.kills = (r.kills or 0) + 1 end
            end
        end
        r.kills = r.kills or 0

        D.UpdateStatus(r)
        return r
    end

    local function Fits(r, st)
        if next(st.raids) then
            if not st.raids[r.gid] then return false end
        elseif r.season == 1 and not st.showS1 then
            return false
        end
        if not st.diff[r.diff] then return false end
        if st.maxKills < KILLS_ANY and r.kills > st.maxKills then return false end
        if r.size < st.minSize then return false end
        if st.spot then
            -- How many of a role a group of this kind usually takes (cfg.caps).
            local role, caps = D.PlayerRole(), cfg.caps(r)
            if role == "TANK" and r.T >= caps.TANK then return false end
            if role == "HEALER" and r.H >= caps.HEALER then return false end
            if role == "DAMAGER" and caps.DAMAGER and r.D >= caps.DAMAGER then return false end
            if r.size >= r.max then return false end
        end
        if st.ilvlFits and r.ilvl > 0 then
            local _, mine = GetAverageItemLevel()
            if r.ilvl > (D.Num(mine) or 0) then return false end
        end
        if st.lust and not r.lust then return false end
        if st.notDeclined and r.declined then return false end
        return true
    end

    -------------------------------------------------------------------------------
    --  Raid chips
    -------------------------------------------------------------------------------
    -- The chip's "4/8 H" (your lockout), or nothing; the chip fits its width.
    local function SetLockout(c)
        local mine, color = Lockout(Raid(c.gid))
        c.mine = mine
        c.extra:SetText(mine or "")
        if color then c.extra:SetTextColor(unpack(color)) end
        c:SetWidth(math.ceil(33 + c.label:GetStringWidth() + 12 + (mine and (6 + c.extra:GetStringWidth()) or 0)))
    end

    local function MakeChip(row, gid)
        local raid = Raid(gid)
        local c = W.Chip(row, raid.short, raid.icon or "Interface\\Icons\\INV_Misc_QuestionMark", " ")
        c.gid = gid
        SetLockout(c)
        c:SetScript("OnEnter", nil)
        c:HookScript("OnEnter", function(self)
            self.hot = true; self:SetOn(self.on)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(raid.name, 1, 1, 1)
            if self.mine then GameTooltip:AddLine("Your lockout this week: " .. self.mine, 0.8, 0.8, 0.8) end
            if #raid.bosses > 0 then GameTooltip:AddLine(#raid.bosses .. " bosses", 0.55, 0.6, 0.68) end
            GameTooltip:Show()
        end)
        c:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return c
    end

    local function SyncChips()
        local st = RB.st
        local any = false
        for _, c in ipairs(RB.chips) do
            if c.gid then
                c:SetOn(st.raids[c.gid] and true or false)
                any = any or c.on
            end
        end
        RB.allChip:SetOn(not any)
    end
    -- For RB.ReloadGroups (defined above them).
    RB.MakeChip, RB.SyncChips = MakeChip, SyncChips
    function RB.Render(...) Render(...) end

    -- Chips flow into rows; Season 1's start on a row of their own.
    function RB.LayoutChips()
        local row = RB.chipRow
        local w = row:GetWidth() > 0 and row:GetWidth() or 944
        local x, y = 0, 0
        for _, c in ipairs(RB.chips) do
            if not c.season1 or RB.st.showS1 then
                if (c.newRow and x > 0) or (x > 0 and x + c:GetWidth() > w) then x, y = 0, y + S.chipH + 6 end
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", x, -y)
                x = x + c:GetWidth() + (c.gap or 6)
            end
        end
        row:SetHeight(y + S.chipH)
    end

    local function ShowSeason1()
        for _, c in ipairs(RB.chips) do
            if c.season1 then c:SetShown(RB.st.showS1) end
        end
        RB.LayoutChips()
    end

    local function BuildChips()
        local st, row = RB.st, RB.chipRow
        local all = W.Chip(row, cfg.allLabel)
        RB.allChip = all
        RB.chips[1] = all
        all.onClick = function() wipe(st.raids); SyncChips(); Render() end
        for _, gid in ipairs(CURRENT) do RB.chips[#RB.chips + 1] = MakeChip(row, gid) end
        RB.chips[#RB.chips].gap = 16
        if #SEASON1 == 0 then   -- nothing older to offer
            for _, c in ipairs(RB.chips) do
                if c.gid then c.onClick = function(self) st.raids[self.gid] = not st.raids[self.gid] or nil; SyncChips(); Render() end end
            end
            SyncChips(); RB.LayoutChips()
            return
        end
        local s1 = W.Toggle(row, "Season 1 raids")
        s1:SetHeight(S.chipH)
        s1:SetChecked(st.showS1)
        s1.onChange = function(v)
            st.showS1 = v
            if not v then for _, gid in ipairs(SEASON1) do st.raids[gid] = nil end end
            ShowSeason1(); SyncChips(); Render()
        end
        RB.chips[#RB.chips + 1] = s1
        local label = CreateFrame("Frame", nil, row)
        label:SetSize(76, S.chipH)
        local lt = W.Text(label, "label"); lt:SetPoint("LEFT"); lt:SetText("SEASON 1")
        label.season1, label.newRow = true, true
        RB.chips[#RB.chips + 1] = label
        for _, gid in ipairs(SEASON1) do
            local c = MakeChip(row, gid)
            c.season1 = true
            RB.chips[#RB.chips + 1] = c
        end
        for _, c in ipairs(RB.chips) do
            if c.gid then
                c.onClick = function(self)
                    st.raids[self.gid] = not st.raids[self.gid] or nil
                    SyncChips(); Render()
                end
            end
        end
        SyncChips()
        ShowSeason1()
    end

    -------------------------------------------------------------------------------
    --  Filter bar
    -------------------------------------------------------------------------------
    local function PaintSearch()
        local b = RB.searchBtn
        if RB.searching then
            b:SetLabel("Searching…"); b:Disable()
        else
            b:Enable()
            b:SetLabel(RB.searched and "Search again" or "Search")
        end
    end

    local function DoSearch()
        if RB.searching then return end
        D.SearchAs(cfg.key)
        local ok, err = pcall(cfg.search, RB.st)
        if not ok then D.SearchAs(nil); ns.Print("search failed (" .. tostring(err) .. ")"); return end
        RB.searching, RB.ownSearch = true, true
        RB.searchSeq = (RB.searchSeq or 0) + 1
        local seq = RB.searchSeq
        PaintSearch()
        C_Timer.After(6, function()
            if RB.searching and seq == RB.searchSeq then RB.searching = false; PaintSearch() end
        end)
    end

    local function PaintDiffs()
        local st = RB.st
        local on = {}
        for _, id in ipairs(DIFF_ORDER) do
            local b, d = RB.diffs[id], DIFF[id]
            b:SetVariant(st.diff[id] and "ghost" or "mark")
            if st.diff[id] then on[#on + 1] = d.key end
        end
        RB.diffValue:SetText(#on == #DIFF_ORDER and "All" or #on > 0 and table.concat(on, " + ") or "None")
    end

    local function KillText(v)
        RB.killValue:SetText(v == 0 and "Fresh only" or v >= KILLS_ANY and "Any" or ("Up to " .. v))
    end

    local function SizeText(v) RB.sizeValue:SetText(v <= 1 and "Any" or (v .. "+")) end

    local function PaintSorts()
        for _, s in ipairs(RB.sorts) do s:SetVariant(RB.st.sort == s.key and "ghost" or "mark") end
    end

    local function PaintSpot()
        local t = RB.spotToggle
        if not t then return end
        t.label:SetText("Spot for " .. ROLE_NAME[D.PlayerRole()])
        t:SetWidth(math.ceil(30 + t.label:GetStringWidth() + 12))
    end

    local function Panel(bar, anchor, w, label)
        local p = W.Panel(bar)
        if anchor then p:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 14, 0) else p:SetPoint("TOPLEFT") end
        p:SetSize(w, 106)
        local l = W.Label(p, label); l:SetPoint("TOPLEFT", 12, -10)
        local v = W.Text(p, "h2"); v:SetPoint("TOPRIGHT", -12, -8)
        return p, v
    end

    local function Note(p, text)
        local n = W.Text(p, "tiny")
        n:SetPoint("TOPLEFT", 12, -32); n:SetPoint("TOPRIGHT", -12, -32)
        n:SetWordWrap(true)
        n:SetText(text)
    end

    local function Ends(p, slider, left, right)
        local a = W.Text(p, "tiny"); a:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -1); a:SetText(left)
        local z = W.Text(p, "tiny"); z:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -1); z:SetText(right)
    end

    local function BuildFilters(bar, row2)
        local st = RB.st

        -- Difficulty (only when there is a choice: Mythic 0 has one).
        local pd
        if #DIFF_ORDER > 1 then
            pd, RB.diffValue = Panel(bar, nil, 220, "Difficulty")
            RB.diffs = {}
            local prev
            local bw = floor((196 - (#DIFF_ORDER - 1) * 6) / #DIFF_ORDER)
            for _, id in ipairs(DIFF_ORDER) do
                local b = W.Button(pd, DIFF[id].name, "mark", bw, 34, "button")
                if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("BOTTOMLEFT", 12, 14) end
                b:SetScript("OnClick", function() st.diff[id] = not st.diff[id]; PaintDiffs(); Render() end)
                RB.diffs[id] = b
                prev = b
            end
            PaintDiffs()
        else
            st.diff[DIFF_ORDER[1]] = true
        end

        -- Bosses killed
        local pk
        pk, RB.killValue = Panel(bar, pd, 300, "Bosses killed")
        Note(pk, "How far the group's lockout already is.")
        local sk = W.Slider(pk, { min = 0, max = KILLS_ANY, step = 1, value = st.maxKills, fill = "left" })
        sk:SetPoint("BOTTOMLEFT", 12, 20); sk:SetPoint("BOTTOMRIGHT", -12, 20)
        sk.onChange = function(v) st.maxKills = v; KillText(v); Render() end
        Ends(pk, sk, "Fresh", "Any")
        KillText(st.maxKills)

        -- Players in group
        local ps
        ps, RB.sizeValue = Panel(bar, pk, 240, "Players in group")
        Note(ps, "Fuller groups start sooner.")
        local ss = W.Slider(ps, { min = 1, max = cfg.sizeMax, step = 1, value = min(st.minSize, cfg.sizeMax), fill = true })
        ss:SetPoint("BOTTOMLEFT", 12, 20); ss:SetPoint("BOTTOMRIGHT", -12, 20)
        ss.onChange = function(v) st.minSize = v; SizeText(v); Render() end
        Ends(ps, ss, "1", cfg.sizeMax .. "+")
        SizeText(st.minSize)

        -- Search
        RB.searchBtn = W.Button(bar, "Search", "gold", nil, 44, "h2")
        RB.searchBtn:SetPoint("TOPLEFT", ps, "TOPRIGHT", 14, 0)
        RB.searchBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        RB.searchBtn:SetScript("OnClick", DoSearch)
        local hint = W.Text(bar, "tiny")
        hint:SetPoint("TOPLEFT", RB.searchBtn, "BOTTOMLEFT", 2, -8)
        hint:SetPoint("TOPRIGHT", RB.searchBtn, "BOTTOMRIGHT", -2, -8)
        hint:SetWordWrap(true)
        hint:SetText(cfg.hint)

        -- Row 2: toggles, sort.
        local toggles = {
            { "spot", "Spot for " .. ROLE_NAME[D.PlayerRole()] },
            { "ilvlFits", "My item level fits" },
            { "lust", "Has Lust", "lust", C.lust },
            { "notDeclined", "Not declined" },
        }
        local prevT
        for _, d in ipairs(toggles) do
            local t = W.Toggle(row2, d[2], d[3], d[4])
            if prevT then t:SetPoint("LEFT", prevT, "RIGHT", 6, 0) else t:SetPoint("LEFT") end
            prevT = t
            t:SetChecked(st[d[1]])
            if d[1] == "spot" then RB.spotToggle = t end
            t.onChange = function(v) st[d[1]] = v; Render() end
        end
        RB.sorts = {}
        local right
        for i = #SORTS, 1, -1 do
            local s = SORTS[i]
            local b = W.Button(row2, s[2], "mark", nil, 26, "tiny")
            b:SetWidth(b.label:GetStringWidth() + 18)
            if right then b:SetPoint("RIGHT", right, "LEFT", -4, 0) else b:SetPoint("RIGHT") end
            b.key = s[1]
            b:SetScript("OnClick", function() st.sort = s[1]; PaintSorts(); Render() end)
            RB.sorts[#RB.sorts + 1] = b
            right = b
        end
        local sl = W.Text(row2, "small"); sl:SetPoint("RIGHT", right, "LEFT", -8, 0); sl:SetText("Sort")
        -- Members: role counts, or each member's spec.
        local view = W.ViewSwitch(row2, function() Render() end)
        view:SetPoint("RIGHT", sl, "LEFT", -16, 0)
        PaintSorts()
        PaintSearch()
    end

    -------------------------------------------------------------------------------
    --  Result cards
    -------------------------------------------------------------------------------
    local STATUS_BUTTON = {
        applied  = { "Applied", "done" },
        invited  = { "Invited", "done", true },
        inviteaccepted = { "Joined", "done", true },
        declined = { "Declined", "quiet", true },
        declined_full = { "Group full", "quiet", true },
        declined_delisted = { "Delisted", "quiet", true },
    }

    local function Clock(r) return T.Clock(r.age + (GetTime() - r.readAt)) end

    local function Tooltip(card)
        local r = card.r
        if not r then return end
        local raid = Raid(r.gid)
        GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
        GameTooltip:SetText(raid.name .. " (" .. DIFF[r.diff].name .. ")", 1, 1, 1)
        pcall(GameTooltip.AddLine, GameTooltip, r.title, 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(" ")
        if #raid.bosses > 0 then
            for _, boss in ipairs(raid.bosses) do
                local dead = r.killed[boss]
                GameTooltip:AddDoubleLine(boss, dead and "killed" or "alive", 0.85, 0.85, 0.85,
                    dead and 0.55 or 0.59, dead and 0.6 or 0.89, dead and 0.68 or 0.68)
            end
        elseif r.kills > 0 then
            for boss in pairs(r.killed) do GameTooltip:AddLine(boss .. ": killed", 0.55, 0.6, 0.68) end
        else
            GameTooltip:AddLine("Fresh lockout", 0.59, 0.89, 0.68)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("%d %s · %d %s · %d %s"):format(r.T, ROLE_NAME.TANK, r.H, ROLE_NAME.HEALER, r.D, ROLE_NAME.DAMAGER),
            0.8, 0.8, 0.8)
        GameTooltip:Show()
    end

    local function OnApplyClick(btn)
        local r = btn:GetParent().r
        if not r then return end
        if not D.CanApply() then ns.Print("only the group leader can sign up."); return end
        local ok, err = pcall(r.status == "applied" and D.Cancel or D.Apply, r.id)
        if not ok then ns.Print("could not sign up (" .. tostring(err) .. ")") end
    end

    local MAX_PIPS = 12

    local function NewCard(parent)
        local c = W.Card(parent)
        c:SetHeight(CardH(cfg.isRaid))
        c.strip = c:CreateTexture(nil, "ARTWORK")
        c.strip:SetPoint("TOPLEFT"); c.strip:SetPoint("BOTTOMLEFT"); c.strip:SetWidth(STRIP_W)
        W.CornerCaps(c, c.strip, C.bg, { TL = true, BL = true })
        c.fade = W.Tex(c, "ARTWORK", nil, 1)
        c.fade:SetPoint("TOPRIGHT", c.strip, "TOPRIGHT"); c.fade:SetPoint("BOTTOMRIGHT", c.strip, "BOTTOMRIGHT"); c.fade:SetWidth(60)
        W.Gradient(c.fade, "HORIZONTAL", { C.panel[1], C.panel[2], C.panel[3], 0 }, C.panel)
        c.short = W.Text(c, "label", C.textHi); c.short:SetPoint("TOPLEFT", c.strip, "TOPLEFT", 10, -8)
        c.short:SetShadowOffset(0, -1); c.short:SetShadowColor(0, 0, 0, 0.8)
        c.diff = W.Text(c, "keyArt"); c.diff:SetPoint("BOTTOMLEFT", c.strip, "BOTTOMLEFT", 9, 6)
        c.diff:SetShadowOffset(1, -2); c.diff:SetShadowColor(0, 0, 0, 0.9)

        c.name = W.Text(c, "h2"); c.name:SetPoint("TOPLEFT", c.strip, "TOPRIGHT", 14, -10)
        c.title = W.Text(c, "body", C.text2); c.title:SetPoint("BOTTOMLEFT", c.name, "BOTTOMRIGHT", 10, 0)
        c.line2 = W.Text(c, "bodySm"); c.line2:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -6)
        c.brings = W.Pill(c, "You bring their B-Res", { 0.53, 0.88, 0.64, 0.4 }, { 0.53, 0.88, 0.64, 0.10 })
        c.brings:SetHeight(20)
        c.brings.text:SetTextColor(unpack(C.goodText))
        c.brings:SetPoint("LEFT", c.line2, "RIGHT", 10, 0)

        c.pips = {}
        for i = 1, MAX_PIPS do
            local p = W.Tex(c, "ARTWORK")
            p:SetSize(12, 12)
            if i == 1 then p:SetPoint("TOPLEFT", c.line2, "BOTTOMLEFT", 0, -8)
            else p:SetPoint("LEFT", c.pips[i - 1], "RIGHT", 4, 0) end
            c.pips[i] = p
        end
        c.prog = W.Text(c, "small")
        c.specs = W.Text(c, "small")   -- raids, Spec view
        c.specs:SetPoint("TOPLEFT", c.pips[1], "BOTTOMLEFT", 0, -10)
        -- Dungeons (5 players): the members as in Mythic+, role glyphs in
        -- class color, open spots dashed, spec names under them (Spec view).
        if not cfg.isRaid then
            c.slots, c.slotSpecs = {}, {}
            for i = 1, 5 do
                local rb = W.RoleBadge(c, 24)
                if i == 1 then rb:SetPoint("TOPLEFT", c.line2, "BOTTOMLEFT", 0, -6) end   -- the others: FillCard
                c.slots[i] = rb
                local sp = W.Text(c, "tiny")
                sp:SetPoint("TOP", rb, "BOTTOM", 0, -2)
                sp:SetWidth(24 + SPEC_GAP - 2)
                sp:SetJustifyH("CENTER")
                c.slotSpecs[i] = sp
            end
        end
        c.lust = W.Glyph(c, "lust", 22, C.lust)
        c.brez = W.Glyph(c, "brez", 22, C.brez)
        c.style = W.Pill(c, "")
        c.style:SetHeight(20)

        c.btn = W.Button(c, "Sign up", "ghost", 100)
        c.btn:SetPoint("RIGHT", -14, 0)
        c.btn:SetScript("OnClick", OnApplyClick)
        local div = W.Tex(c, "BORDER", C.line)
        div:SetPoint("TOPRIGHT", c, "TOPRIGHT", -128, -1); div:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -128, 1)
        PixelUtil.SetWidth(div, 1, 1)
        c.size = W.Text(c, "num"); c.size:SetPoint("TOPRIGHT", div, "TOPLEFT", -16, -12)
        c.roles = W.Text(c, "small", C.text2); c.roles:SetPoint("TOPRIGHT", c.size, "BOTTOMRIGHT", 0, -5)
        c.age = W.Text(c, "tiny"); c.age:SetPoint("TOPRIGHT", c.roles, "BOTTOMRIGHT", 0, -4)

        c.onEnter = Tooltip
        c.onLeave = function() GameTooltip:Hide() end
        return c
    end

    local ROLE_ICON = {}
    for role, g in pairs({ TANK = "tank", HEALER = "healer", DAMAGER = "dps" }) do
        ROLE_ICON[role] = "|T" .. T.TEX .. "glyph-" .. g .. ":13:13|t"
    end

    local RaidRow3   -- below

    local function FillCard(c, r)
        c.r = r
        local raid = Raid(r.gid)
        if raid.art then
            c.strip:SetTexture(raid.art)
            c.strip:SetTexCoord(0.048, 0.636, 0, 0.742)   -- journal button: 175 x 95 of 256 x 128
        else
            c.strip:SetTexture(raid.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            c.strip:SetTexCoord(0.08, 0.92, 0.2, 0.8)
        end
        c.short:SetText(raid.short)
        local d = DIFF[r.diff]
        c.diff:SetText(d.key)
        c.diff:SetTextColor(unpack(d.color))
        c.name:SetText(raid.name)
        pcall(c.title.SetText, c.title, r.title)
        c.title:SetWidth(max(40, c:GetWidth() - STRIP_W - 14 - c.name:GetStringWidth() - 10 - 290))

        local line = T.ColorCode(T.ClassColor(r.leaderClass)) .. (r.leader or "?") .. "|r"
        if r.leaderSpec then line = line .. "  |cffc3cbd6" .. r.leaderSpec .. "|r" end
        line = line .. "  |cff8d98a8·  " .. (r.ilvl > 0 and ("item level " .. r.ilvl .. "+") or "any item level") .. "|r"
        local lockout
        if r.kills == 0 then
            lockout = "|cff96e3adFresh|r"
        elseif #raid.bosses > 0 then
            lockout = ("%d/%d killed"):format(r.kills, #raid.bosses)
        else
            lockout = r.kills .. " killed"
        end
        -- Dungeons: the lockout joins line 2, row 3 holds the members.
        if c.slots then line = line .. "  |cff8d98a8·|r  " .. lockout end
        c.line2:SetText(line)
        local _, myClass = UnitClass("player")
        c.brings:SetShown(BREZ[myClass] and not r.brez or false)

        local spec = W.SpecView()
        c:SetHeight(CardH(cfg.isRaid))
        if c.slots then
            for _, p in ipairs(c.pips) do p:Hide() end
            c.prog:Hide()
            c.specs:Hide()
            local slots = {}
            for _, role in ipairs(D.ROLE_KEYS) do
                for _, m in ipairs(r.members) do
                    if m.role == role then slots[#slots + 1] = { role, m.class or true, m.spec } end
                end
            end
            -- Open spots from the role counts: they hold every member, even
            -- one whose details weren't readable.
            r.left = r.left or { TANK = max(0, 1 - r.T), HEALER = max(0, 1 - r.H), DAMAGER = max(0, 3 - r.D) }
            local open = D.OpenSpots(r)
            for _, role in ipairs(D.ROLE_KEYS) do
                for _ = 1, open[role] or 0 do slots[#slots + 1] = { role } end
            end
            for i, rb in ipairs(c.slots) do
                local s = slots[i]
                if i > 1 then
                    rb:ClearAllPoints()
                    rb:SetPoint("LEFT", c.slots[i - 1], "RIGHT", spec and SPEC_GAP or 4, 0)
                end
                if s then rb:Set(s[1], s[2]); rb:Show() else rb:Hide() end
                local sp = c.slotSpecs[i]
                sp:SetShown(spec and s and s[3] ~= nil or false)
                if s and s[3] then
                    sp:SetText(W.SpecShort(s[3]))
                    sp:SetTextColor(unpack(type(s[2]) == "string" and T.ClassColor(s[2]) or C.muted))
                end
            end
            local x = c.slots[min(5, max(1, #slots))]
            c.lust:ClearAllPoints(); c.brez:ClearAllPoints(); c.style:ClearAllPoints()
            c.lust:SetShown(r.lust or false)
            if r.lust then c.lust:SetPoint("LEFT", x, "RIGHT", 6, 0); x = c.lust end
            c.brez:SetShown(r.brez or false)
            if r.brez then c.brez:SetPoint("LEFT", x, "RIGHT", r.lust and 0 or 6, 0); x = c.brez end
            local ps = D.PlaystyleLabel(r.playstyle)
            c.style:SetShown(ps ~= nil)
            if ps then c.style:SetText(ps); c.style:SetPoint("LEFT", x, "RIGHT", 8, 0) end
        else
            RaidRow3(c, r, raid, lockout, spec)
        end

        c.size:SetText(("%d|cff8d98a8/%d|r"):format(r.size, r.max))
        c.roles:SetText(("%s %d  %s %d  %s %d"):format(ROLE_ICON.TANK, r.T, ROLE_ICON.HEALER, r.H, ROLE_ICON.DAMAGER, r.D))
        c.age:SetText(Clock(r))

        local sb = STATUS_BUTTON[r.status]
        c.btn:SetLabel(sb and sb[1] or "Sign up")
        c.btn:SetVariant(sb and sb[2] or "ghost")
        c.btn:SetEnabled(not (sb and sb[3]) and D.CanApply())
        c:SetAlpha(1)
    end

    -- Raids, row 3: the bosses, the lockout, lust / b-res, playstyle; in the
    -- Spec view a line of the members' specs under it.
    RaidRow3 = function(c, r, raid, lockout, spec)
        local n = #raid.bosses > 0 and min(MAX_PIPS, #raid.bosses) or min(MAX_PIPS, r.kills)
        for i, p in ipairs(c.pips) do
            local boss = raid.bosses[i]
            local dead = (boss and r.killed[boss]) or (not boss and i <= r.kills)
            p:SetShown(i <= n)
            p:SetVertexColor(unpack(dead and C.empty or { 0.82, 0.64, 0.30, 0.55 }))
        end
        local anchor = n > 0 and c.pips[n] or nil
        c.prog:ClearAllPoints()
        if anchor then c.prog:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
        else c.prog:SetPoint("TOPLEFT", c.line2, "BOTTOMLEFT", 0, -9) end
        c.prog:SetText(lockout)
        c.prog:Show()
        local x = c.prog
        c.lust:ClearAllPoints(); c.brez:ClearAllPoints(); c.style:ClearAllPoints()
        c.lust:SetShown(r.lust or false)
        if r.lust then c.lust:SetPoint("LEFT", x, "RIGHT", 10, 0); x = c.lust end
        c.brez:SetShown(r.brez or false)
        if r.brez then c.brez:SetPoint("LEFT", x, "RIGHT", r.lust and 0 or 10, 0); x = c.brez end
        local ps = D.PlaystyleLabel(r.playstyle)
        c.style:SetShown(ps ~= nil)
        if ps then c.style:SetText(ps); c.style:SetPoint("LEFT", x, "RIGHT", 8, 0) end

        -- The members: specs (Spec view) or role glyphs in class color; up to
        -- the size column, a long list is cut there.
        c.specs:SetWidth(max(60, c:GetWidth() - STRIP_W - 14 - 300))
        if #r.members == 0 then
            c.specs:SetText("|cff8d98a8Members not shared|r")
        else
            c.specs:SetText(spec and SpecLine(r.members) or RoleLine(r.members))
        end
        c.specs:Show()
    end

    local ORDER = {
        age   = function(a, b)
            local la, lb = a.readAt - a.age, b.readAt - b.age
            if la ~= lb then return la > lb end
            return a.id < b.id
        end,
        kills = function(a, b) if a.kills ~= b.kills then return a.kills < b.kills end return a.id < b.id end,
        size  = function(a, b) if a.size ~= b.size then return a.size > b.size end return a.id < b.id end,
    }

    Render = function(animate)
        if not (RB.child and RB.page and RB.page:IsVisible()) then return end
        local st = RB.st
        local list, hidden = {}, 0
        for _, r in ipairs(RB.results) do
            if Fits(r, st) then list[#list + 1] = r else hidden = hidden + 1 end
        end
        table.sort(list, ORDER[st.sort] or ORDER.age)
        for i, r in ipairs(list) do
            local c = RB.cards[i] or NewCard(RB.child)
            RB.cards[i] = c
            local y = -(i - 1) * (CardH(cfg.isRaid) + CARD_GAP)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", RB.child, "TOPLEFT", 0, y)
            c:SetPoint("TOPRIGHT", RB.child, "TOPRIGHT", 0, y)
            c:Show()
            FillCard(c, r)
            if animate and i <= 8 then A.Rise(c, (i - 1) * 0.04, 8, 0.35) end
        end
        for i = #list + 1, #RB.cards do RB.cards[i]:Hide() end
        RB.child:SetHeight(max(1, #list * (CardH(cfg.isRaid) + CARD_GAP)))
        local limit = max(0, RB.child:GetHeight() - RB.scroll:GetHeight())
        if RB.scroll:GetVerticalScroll() > limit then RB.scroll:SetVerticalScroll(limit) end

        local extra = hidden > 0 and ("  ·  %d hidden by your filters"):format(hidden) or ""
        if RB.total and RB.sent and RB.total > RB.sent then
            extra = extra .. ("  ·  |cffe0b868server sent %d of %d found|r"):format(RB.sent, RB.total)
        end
        if #list == 0 then
            RB.count:SetText(hidden > 0 and ("%d %s found, all hidden by your filters"):format(hidden,
                hidden == 1 and "group" or "groups") or "")
            RB.empty:SetText(RB.searched and cfg.noneText or cfg.pickText)
            RB.empty:Show()
        else
            RB.empty:Hide()
            RB.count:SetText(("|cfff5f7fa%d|r %s%s"):format(#list, #list == 1 and "group" or "groups", extra))
        end
    end

    -------------------------------------------------------------------------------
    --  Data in
    -------------------------------------------------------------------------------
    local function Load()
        -- Hidden (another section or tab): read the results when shown.
        if not (RB.page and RB.page:IsVisible()) then RB.stale = true; return end
        wipe(RB.results)
        -- Another section's results: nothing of ours left. (Raid takes a raid
        -- search from Blizzard's window; Mythic 0 shares Dungeons with
        -- Mythic+, which takes those.)
        if not D.OwnsResults(cfg.key, cfg.category, cfg.isRaid) then
            RB.searched, RB.total, RB.sent = false, nil, nil
            Render()
            return
        end
        local ids, total = D.ResultIDs()
        RB.sent, RB.total = #ids, total
        for _, id in ipairs(ids) do
            local r = Read(id)
            if r then RB.results[#RB.results + 1] = r end
        end
        RB.searched = RB.ownSearch or D.searchOwner == cfg.key
        if RB.ownSearch then RB.lastSearch = GetTime() end
        RB.ownSearch = false
        if RB.scroll then RB.scroll:SetVerticalScroll(0) end
        PaintSearch()
        Render(true)
    end

    local pending = {}
    local function Flush()
        RB.flushQueued = false
        local changed = false
        for id in pairs(pending) do
            for i, r in ipairs(RB.results) do
                if r.id == id then
                    local fresh = Read(id)
                    if fresh then RB.results[i] = fresh else table.remove(RB.results, i) end
                    changed = true
                    break
                end
            end
        end
        wipe(pending)
        if changed then Render() end
    end

    local events = CreateFrame("Frame")
    ns.Live(events, { "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED",
                      "LFG_LIST_APPLICATION_STATUS_UPDATED", "GROUP_ROSTER_UPDATE", "PLAYER_SPECIALIZATION_CHANGED",
                      "UPDATE_INSTANCE_INFO", "LFG_LIST_AVAILABILITY_UPDATE" })
    events:SetScript("OnEvent", function(_, event, arg1)
        if not RB.page then return end
        if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
            RB.searching = false
            C_Timer.After(0, Load)
        elseif event == "LFG_LIST_SEARCH_FAILED" then
            if RB.searching then ns.Print("search failed" .. (D.Str(arg1) and (" (" .. arg1 .. ")") or "") .. ".") end
            RB.searching = false
            PaintSearch()
        elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" or event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
            if D.Num(arg1) then
                pending[arg1] = true
                if not RB.flushQueued then RB.flushQueued = true; C_Timer.After(0.15, Flush) end
            end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
            if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 ~= "player" then return end
            D.ResetParty()
            PaintSpot()
            Render()
        elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
            -- Blizzard's activity list arrived: replace a stand-in list.
            if RB.standIn or #CURRENT == 0 then RB.ReloadGroups() end
        elseif event == "UPDATE_INSTANCE_INFO" then
            -- Lockouts arrived: the chips' "4/8 H".
            for _, c in ipairs(RB.chips) do if c.gid then SetLockout(c) end end
            RB.LayoutChips()
        end
    end)

    -------------------------------------------------------------------------------
    --  Build
    -------------------------------------------------------------------------------
    function RB.Build(page)
        RB.stale = true   -- the first show reads what the client holds
        RB.LoadGroups()
        RB.st = State()
        -- Picks of instances no longer offered would hide every result.
        for gid in pairs(RB.st.raids) do if not SEASON[gid] then RB.st.raids[gid] = nil end end
        if RequestRaidInfo then RequestRaidInfo() end

        RB.chipRow = CreateFrame("Frame", nil, page)
        RB.chipRow:SetPoint("TOPLEFT", S.pad, -14)
        RB.chipRow:SetPoint("TOPRIGHT", -S.pad, -14)
        RB.chipRow:SetHeight(S.chipH)
        BuildChips()
        local resizeQueued = false
        RB.chipRow:SetScript("OnSizeChanged", function()
            RB.LayoutChips()
            if resizeQueued then return end
            resizeQueued = true
            C_Timer.After(0.15, function() resizeQueued = false; Render() end)
        end)

        local bar = CreateFrame("Frame", nil, page)
        bar:SetPoint("TOPLEFT", RB.chipRow, "BOTTOMLEFT", 0, -12)
        bar:SetPoint("TOPRIGHT", RB.chipRow, "BOTTOMRIGHT", 0, -12)
        bar:SetHeight(106)
        local row2 = CreateFrame("Frame", nil, page)
        row2:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -10)
        row2:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -10)
        row2:SetHeight(30)
        BuildFilters(bar, row2)

        RB.count = W.Text(page, "small")
        RB.count:SetPoint("TOPLEFT", row2, "BOTTOMLEFT", 0, -10)

        local scroll = CreateFrame("ScrollFrame", nil, page)
        scroll:SetPoint("TOPLEFT", row2, "BOTTOMLEFT", 0, -32)
        scroll:SetPoint("BOTTOMRIGHT", -S.pad, 10)
        scroll:SetClipsChildren(true)
        RB.child = CreateFrame("Frame", nil, scroll)
        RB.child:SetSize(944, 1)
        scroll:SetScrollChild(RB.child)
        scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then RB.child:SetWidth(w) end end)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, d)
            local limit = max(0, RB.child:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(min(limit, max(0, self:GetVerticalScroll() - d * (CardH(cfg.isRaid) + CARD_GAP))))
        end)
        RB.scroll = scroll

        RB.empty = W.Text(page, "body", C.muted)
        RB.empty:SetPoint("TOP", scroll, "TOP", 0, -60)

        page:SetScript("OnShow", function()
            -- Built before the Group Finder knew its instances: try again.
            if #CURRENT == 0 or RB.standIn then RB.ReloadGroups() end
            D.ResetParty()
            PaintSpot()
            if RB.searching then RB.searching = false; PaintSearch() end
            -- Catch up when something came in while hidden or the window was
            -- closed (Window.lua sets stale); else keep the list and its scroll.
            if RB.stale then RB.stale = false; Load() else Render() end
            if RB.ticker then RB.ticker:Cancel() end
            RB.ticker = C_Timer.NewTicker(1, function()
                for _, c in ipairs(RB.cards) do if c:IsShown() and c.r then c.age:SetText(Clock(c.r)) end end
                if RB.lastSearch and UI.SetStatus then
                    UI.SetStatus("Last search " .. T.Clock(GetTime() - RB.lastSearch) .. " ago")
                elseif UI.SetStatus then
                    UI.SetStatus(cfg.noSearchText)
                end
            end)
        end)
        page:SetScript("OnHide", function()
            if RB.ticker then RB.ticker:Cancel(); RB.ticker = nil end
        end)
        RB.page = page
    end

    return RB
end   -- New

-------------------------------------------------------------------------------
--  The two pages
-------------------------------------------------------------------------------
local function Langs() return C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter() or {} end

-- Raid: this season's raids, Season 1's on request. The raid category
-- can't be narrowed on the server: all of it comes, the page filters.
UI.RaidBrowse = New({
    key = "raid", category = D.RAID_CATEGORY, isRaid = true, killsAny = 8, sizeMax = 25,
    diffs = {
        [14] = { key = "N", name = PLAYER_DIFFICULTY1 or "Normal", color = { 0.31, 0.84, 0.48, 1 } },
        [15] = { key = "H", name = PLAYER_DIFFICULTY2 or "Heroic", color = { 0.71, 0.49, 1, 1 } },
        [16] = { key = "M", name = PLAYER_DIFFICULTY6 or "Mythic", color = { 1, 0.54, 0.16, 1 } },
    },
    order = { 14, 15, 16 },
    defaultDiff = { [14] = true, [15] = true, [16] = false },
    -- The Venomous Abyss, The Unbinding of Kith'ix, The Tidebound Grotto;
    -- Season 1: The Voidspire, March on Quel'Danas, The Dreamrift, Sporefall.
    groups = function() return { 424, 427, 429 }, { 402, 403, 404, 422 } end,
    caps = function(r) return { TANK = 2, HEALER = r.diff == 16 and 4 or 6 } end,
    search = function() C_LFGList.Search(D.RAID_CATEGORY, 0, 0, Langs()) end,
    allLabel = "All raids",
    hint = "Fetches every raid group; your filters sort them out right here.",
    noneText = "No raid groups to show.", pickText = "Pick your raids and press Search.",
    noSearchText = "No raid search yet",
})

-- Mythic 0: this season's dungeons (the Mythic+ pool) at Mythic, no keystone.
-- Same category as Mythic+: the search asks for Mythic only.
local MYTHIC = 23
UI.DungeonBrowse = New({
    key = "dungeon", category = D.CATEGORY, isRaid = false, killsAny = 4, sizeMax = 4,
    diffs = { [MYTHIC] = { key = "M", name = PLAYER_DIFFICULTY6 or "Mythic", color = { 1, 0.54, 0.16, 1 } } },
    order = { MYTHIC },
    defaultDiff = { [MYTHIC] = true },
    -- The dungeons Blizzard's own Start a Group offers first (its
    -- "recommended" list: this expansion's and the season's, 12 in 12.1.5)
    -- that have a Mythic activity; the season's Mythic+ pool if that list
    -- isn't there yet.
    groups = function()
        local F = Enum and Enum.LFGListFilter or {}
        local ok, ids = pcall(C_LFGList.GetAvailableActivityGroups, D.CATEGORY, bit.bor(F.Recommended or 1, F.PvE or 4))
        local list = {}
        for _, gid in ipairs(ok and type(ids) == "table" and ids or {}) do list[#list + 1] = gid end
        if #list == 0 then
            for _, g in ipairs(ns.SeasonGroups and ns.SeasonGroups() or {}) do list[#list + 1] = g.id end
        end
        local function HasMythic(gid)
            local ok2, acts = pcall(C_LFGList.GetAvailableActivities, D.CATEGORY, gid)
            for _, act in ipairs(ok2 and type(acts) == "table" and acts or {}) do
                local ai = C_LFGList.GetActivityInfoTable(act)
                if type(ai) == "table" and D.Num(ai.difficultyID) == MYTHIC then return true end
            end
        end
        local function Name(gid) return D.Str((C_LFGList.GetActivityGroupInfo(gid))) or "" end
        -- Some recommended ones are Normal only this season (Windrunner Spire,
        -- Magisters' Terrace, ...): no Mythic 0 for them.
        local out = {}
        for _, gid in ipairs(list) do
            if HasMythic(gid) then out[#out + 1] = gid end
        end
        if #out == 0 then out = list end
        table.sort(out, function(a, b) return Name(a) < Name(b) end)
        -- true: only a stand-in; load again once Blizzard's list arrives.
        return out, {}, not (ok and type(ids) == "table" and #ids > 0)
    end,
    caps = function() return { TANK = 1, HEALER = 1, DAMAGER = 3 } end,
    -- The advanced filter narrows the dungeon category to Mythic.
    search = function(st)
        local f = C_LFGList.GetAdvancedFilter()
        local acts = {}
        for gid, on in pairs(st.raids or {}) do if on then acts[#acts + 1] = gid end end
        f.activities = acts
        f.minimumRating = 0
        f.difficultyNormal, f.difficultyHeroic, f.difficultyMythicPlus = false, false, false
        f.difficultyMythic = true
        f.needsTank, f.needsHealer, f.needsDamage, f.needsMyClass, f.hasTank, f.hasHealer = false, false, false, false, false, false
        f.generalPlaystyle1, f.generalPlaystyle2, f.generalPlaystyle3, f.generalPlaystyle4 = true, true, true, true
        C_LFGList.Search(D.CATEGORY, 0, 0, Langs(), nil, f)
    end,
    allLabel = "All dungeons",
    hint = "Mythic 0 groups of this season's dungeons; your filters sort them out here.",
    noneText = "No dungeon groups to show.", pickText = "Pick your dungeons and press Search.",
    noSearchText = "No dungeon search yet",
})

UI.BuildRaidBrowse = UI.RaidBrowse.Build
UI.BuildDungeonBrowse = UI.DungeonBrowse.Build
