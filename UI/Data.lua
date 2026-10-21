-------------------------------------------------------------------------------
--  UI/Data.lua  --  Group Finder data for the window
--
--  Reads search results into plain tables, builds the search filter, judges
--  the client-side fit filters, and searches / applies / cancels.
--  What it relies on (tested in patch 12.1.5):
--   - search results, members, leader and applicant data are readable;
--     the group title and comment are K-strings: shown, not read (the key
--     level is measured from the title instead, UI/KeyRead.lua).
--   - C_LFGList.Search, ApplyToGroup and CancelApplication work directly
--     from a button click (a hardware event), with Blizzard's window closed.
--  Every value is still checked with issecretvalue before it is compared.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local D = {}
UI.Data = D

local max = math.max
local issecret = issecretvalue or function() return false end
local canaccess = canaccesstable or function() return true end
local function Num(v) return type(v) == "number" and not issecret(v) and v or nil end
local function Str(v) return type(v) == "string" and not issecret(v) and v or nil end
local function Tab(v) return type(v) == "table" and not issecret(v) and canaccess(v) and v or nil end
-- A flag that is true: comparing a secret value errors, so a secret one is not.
local function True(v) return not issecret(v) and v == true end
D.Num, D.Str, D.Tab, D.True = Num, Str, Tab, True

D.CATEGORY = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
D.RAID_CATEGORY = GROUP_FINDER_CATEGORY_ID_RAIDS or 3
D.CUSTOM_CATEGORY = GROUP_FINDER_CATEGORY_ID_CUSTOM or 6

-- Who searched last: the client keeps one result list, and each section
-- reads only its own. A page calls D.SearchAs(key) right before its search;
-- a search without it (Blizzard's window) belongs to nobody here but the
-- section that owns its category by default (Mythic+ for Dungeons, Raid
-- for Raids).
local pendingOwner
function D.SearchAs(key) pendingOwner = key end
hooksecurefunc(C_LFGList, "Search", function(category)
    D.searchCategory = Num(category)
    D.searchOwner = pendingOwner
    pendingOwner = nil
end)

-- The last search's results are this section's (key; category; true when
-- it takes searches of its category made outside this window).
function D.OwnsResults(key, category, takesForeign)
    if D.searchOwner then return D.searchOwner == key end
    if not D.searchCategory then return true end   -- no search seen yet: whatever the client holds
    return takesForeign and D.searchCategory == category or false
end

local LUST, BREZ = ns.LUST_CLASS, ns.BREZ_CLASS
local DECLINED = { declined = true, declined_delisted = true, declined_full = true }
local ROLE_KEYS = { "TANK", "HEALER", "DAMAGER" }
D.ROLE_KEYS = ROLE_KEYS

local PLAYSTYLE = {
    [1] = GROUP_FINDER_GENERAL_PLAYSTYLE1 or "Learning",
    [2] = GROUP_FINDER_GENERAL_PLAYSTYLE2 or "Relaxed",
    [3] = GROUP_FINDER_GENERAL_PLAYSTYLE3 or "Competitive",
    [4] = GROUP_FINDER_GENERAL_PLAYSTYLE4 or "Carry offered",
}
function D.PlaystyleLabel(v) return PLAYSTYLE[v] end

-------------------------------------------------------------------------------
--  Season dungeons: activity map -> challenge map
-------------------------------------------------------------------------------
local cidByInstance
local function ChallengeFor(instanceMap)
    if not instanceMap then return end
    if not cidByInstance then
        cidByInstance = {}
        for _, cid in ipairs(C_ChallengeMode.GetMapTable() or {}) do
            local _, _, _, _, _, inst = C_ChallengeMode.GetMapUIInfo(cid)
            if inst then cidByInstance[inst] = cid end
        end
    end
    return cidByInstance[instanceMap]
end
function D.ResetMaps() cidByInstance = nil end

-------------------------------------------------------------------------------
--  The player and the player's group
-------------------------------------------------------------------------------
function D.PlayerRole()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local spec = getSpec and getSpec()
    local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
    if role == "TANK" or role == "HEALER" then return role end
    return "DAMAGER"
end

local party
function D.ResetParty() party = nil end

-- Roles the group needs and what it already brings; cached until the roster changes.
function D.Party()
    if party then return party end
    local p = { roles = { TANK = 0, HEALER = 0, DAMAGER = 0 }, lust = false, brez = false }
    local function Add(unit, role)
        if not Str(role) or (role ~= "TANK" and role ~= "HEALER") then role = "DAMAGER" end
        p.roles[role] = p.roles[role] + 1
        local _, class = UnitClass(unit)
        if Str(class) then
            if LUST[class] then p.lust = true end
            if BREZ[class] then p.brez = true end
        end
    end
    local n = GetNumGroupMembers()
    if n == 0 then
        Add("player", D.PlayerRole())
    elseif not IsInRaid() then
        Add("player", UnitGroupRolesAssigned("player"))
        for i = 1, n - 1 do Add("party" .. i, UnitGroupRolesAssigned("party" .. i)) end
    else
        for i = 1, n do Add("raid" .. i, UnitGroupRolesAssigned("raid" .. i)) end
    end
    party = p
    return p
end

-- Are you a Keystone Deserter (Blizzard's mark for repeatedly leaving
-- Mythic+ runs; it shows on your applications and listings)?
function D.PlayerLeaver()
    if ns.deserterPreview then return true end
    local api = C_InstanceLeaver and C_InstanceLeaver.IsPlayerLeaver
    if not api then return false end
    local ok, leaver = pcall(api)
    return ok and True(leaver)
end

-- Only the leader (or someone alone) may sign up.
function D.CanApply()
    return not IsInGroup() or UnitIsGroupLeader("player")
end

-------------------------------------------------------------------------------
--  Search results
-------------------------------------------------------------------------------
-- The result IDs the server sent, and how many it found in all (more than
-- it sends when the search hits its limit).
function D.ResultIDs()
    local ok, total, ids = pcall(C_LFGList.GetSearchResults)
    ids = ok and Tab(ids) or {}
    return ids, max(Num(total) or 0, #ids)
end

-- One Mythic+ listing as a plain table, or nil (delisted, unreadable, not M+).
function D.Read(id)
    if not Num(id) then return end
    local info = Tab(C_LFGList.GetSearchResultInfo(id))
    if not info or True(info.isDelisted) then return end
    local ids = Tab(info.activityIDs)
    local act = ids and Num(ids[1])
    local ai = act and Tab(C_LFGList.GetActivityInfoTable(act))
    if not (ai and True(ai.isMythicPlusActivity)) then return end

    local cid = ChallengeFor(Num(ai.mapID))
    local r = {
        id = id, cid = cid,
        dungeon = (cid and C_ChallengeMode.GetMapUIInfo(cid)) or Str(ai.fullName) or "?",
        title = info.name,                         -- K-string: SetText shows it, nobody reads it
        key = UI.KeyRead and UI.KeyRead.Level(info.name),   -- measured from its width (UI/KeyRead.lua)
        leader = Str(info.leaderName),
        rating = Num(info.leaderOverallDungeonScore) or 0,
        playstyle = Num(info.generalPlaystyle),
        age = Num(info.age) or 0,
        readAt = GetTime(),
        members = {},
        partyGUID = Str(info.partyGUID),
    }
    r.leaderFull = r.leader   -- "Name-Realm", for Raider.IO
    if r.leader then r.leader = Ambiguate(r.leader, "short") end

    -- Leader's best run in the listed dungeon this season.
    local scores = Tab(info.leaderDungeonScoreInfo)
    local best = scores and Tab(scores[1])
    if best then
        r.best = Num(best.bestRunLevel)
        if r.best == 0 then r.best = nil end
        r.timed = True(best.finishedSuccess)
    end

    local li = Tab(C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(id))
    if li then
        r.leaderClass, r.leaderSpec = Str(li.classFilename), Str(li.specName)
        r.leaderLeaver = True(li.isLeaver)
    end

    -- Keystone Deserters in the group (Blizzard's isLeaver, patch 11.2).
    r.leavers = 0
    for i = 1, Num(info.numMembers) or 0 do
        local pi = Tab(C_LFGList.GetSearchResultPlayerInfo(id, i))
        if pi then
            local m = { role = Str(pi.assignedRole) or "DAMAGER", class = Str(pi.classFilename),
                        spec = Str(pi.specName), leader = True(pi.isLeader), leaver = True(pi.isLeaver) }
            if m.role ~= "TANK" and m.role ~= "HEALER" then m.role = "DAMAGER" end
            if m.leaver then
                r.leavers = r.leavers + 1
                if m.leader then r.leaderLeaver = true end
            end
            r.members[#r.members + 1] = m
            if m.class and LUST[m.class] then r.lust = true end
            if m.class and BREZ[m.class] then r.brez = true end
        end
    end

    -- /gotta deserter: made-up deserters to see how they look (every third
    -- leader, a member of the next group).
    if ns.deserterPreview then
        local wantLeader = id % 3 == 0
        if wantLeader or id % 3 == 1 then
            for _, m in ipairs(r.members) do
                if m.leader == wantLeader then
                    if not m.leaver then m.leaver = true; r.leavers = r.leavers + 1 end
                    if wantLeader then r.leaderLeaver = true end
                    break
                end
            end
        end
    end
    if r.leaderLeaver and r.leavers == 0 then r.leavers = 1 end

    local mc = Tab(C_LFGList.GetSearchResultMemberCounts(id))
    if mc then
        r.left = { TANK = Num(mc.TANK_REMAINING), HEALER = Num(mc.HEALER_REMAINING), DAMAGER = Num(mc.DAMAGER_REMAINING) }
    end

    D.UpdateStatus(r)
    return r
end

-- Application status ("applied", "invited", "declined", ...) and Blizzard's
-- own decline memory.
function D.UpdateStatus(r)
    local _, status, pending = C_LFGList.GetApplicationInfo(r.id)
    r.status = Str(status) or "none"
    if Str(pending) then r.status = pending end
    r.declined = DECLINED[r.status] or false
    if not r.declined and r.partyGUID and LFGListFrame and type(LFGListFrame.declines) == "table"
       and LFGListFrame.declines[r.partyGUID] then
        r.declined = true
    end
end

-- Open spots per role: Blizzard's counts, else what a 1 / 1 / 3 group lacks.
function D.OpenSpots(r)
    local have = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for _, m in ipairs(r.members) do have[m.role] = have[m.role] + 1 end
    local want = { TANK = 1, HEALER = 1, DAMAGER = 3 }
    local open = {}
    for _, role in ipairs(ROLE_KEYS) do
        open[role] = (r.left and r.left[role]) or max(0, want[role] - have[role])
    end
    return open
end

-------------------------------------------------------------------------------
--  Client-side fit (groups that don't fit are hidden)
-------------------------------------------------------------------------------
local function SlotAfterJoin(r, role, p)
    local open = D.OpenSpots(r)[role]
    return open - p.roles[role] > 0
end

-- st: keyMin, keyMax, expMin, expMax, fitLust, fitBrez, notDeclined.
function D.Fits(r, st)
    local p = D.Party()
    -- Minimum leader rating: the server filters by it too, but only on the
    -- next search; here it applies to the groups already found at once.
    if (st.minRating or 0) > 0 and (r.rating or 0) < st.minRating then return false end
    -- Key level, when the title could be measured; the top end is open at
    -- +20 too. Titles that couldn't be measured (custom text) stay.
    if r.key and (st.keyMin > 2 or st.keyMax < 20) then
        if r.key < st.keyMin or (st.keyMax < 20 and r.key > st.keyMax) then return false end
    end
    -- The top end is open at +20: "+10 – +20" includes +21 and up. Leaders
    -- without a run in that dungeon stay: the card says "no run here".
    if r.best and (st.expMin > 2 or st.expMax < 20) then
        if r.best < st.expMin or (st.expMax < 20 and r.best > st.expMax) then return false end
    end
    if st.fitLust then
        if p.lust then
            if r.lust then return false end
        elseif not (r.lust or SlotAfterJoin(r, "HEALER", p) or SlotAfterJoin(r, "DAMAGER", p)) then
            return false
        end
    end
    if st.fitBrez then
        if p.brez then
            if r.brez then return false end
        elseif not (r.brez or SlotAfterJoin(r, "TANK", p) or SlotAfterJoin(r, "HEALER", p)
                    or SlotAfterJoin(r, "DAMAGER", p)) then
            return false
        end
    end
    if st.notDeclined and r.declined then return false end
    return true
end

-------------------------------------------------------------------------------
--  Actions (button clicks only: they need a hardware event)
-------------------------------------------------------------------------------
-- Server-side filter: Mythic+ only, chosen dungeons, minimum leader rating,
-- a free spot for the player's role. Saved as Blizzard's advanced filter too,
-- so Blizzard's window shows the same.
function D.Filter(st)
    local f = C_LFGList.GetAdvancedFilter()
    local acts = {}
    for gid, on in pairs(st.dungeons or {}) do if on then acts[#acts + 1] = gid end end
    table.sort(acts)
    f.activities = acts
    f.minimumRating = st.minRating or 0
    f.difficultyNormal, f.difficultyHeroic, f.difficultyMythic, f.difficultyMythicPlus = false, false, false, true
    local role = D.PlayerRole()
    f.needsTank = st.spot and role == "TANK" or false
    f.needsHealer = st.spot and role == "HEALER" or false
    f.needsDamage = st.spot and role == "DAMAGER" or false
    f.needsMyClass, f.hasTank, f.hasHealer = false, false, false
    f.generalPlaystyle1, f.generalPlaystyle2, f.generalPlaystyle3, f.generalPlaystyle4 = true, true, true, true
    return f
end

function D.Search(st)
    local f = D.Filter(st)
    C_LFGList.SaveAdvancedFilter(f)
    local langs = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter() or {}
    D.SearchAs("mplus")
    C_LFGList.Search(D.CATEGORY, 0, 0, langs, nil, f)
end

function D.Apply(id)
    local role = D.PlayerRole()
    C_LFGList.ApplyToGroup(id, role == "TANK", role == "HEALER", role == "DAMAGER")
end

function D.Cancel(id)
    C_LFGList.CancelApplication(id)
end

-- How many groups you may wait on at once (Blizzard's limit).
D.MAX_APPLICATIONS = MAX_LFG_LIST_APPLICATIONS or 5

-- Your sign-ups that are still open (any section: the limit is shared):
-- { id, status = "applied" | "invited", dungeon, cid, key, leader,
-- leaderClass, since = GetTime() of the sign-up or nil }; invites first.
D.appliedAt = D.appliedAt or {}   -- filled by UI/Alert.lua's status event
function D.Applications()
    local out = {}
    local ok, ids = pcall(C_LFGList.GetApplications)
    for _, id in ipairs(ok and Tab(ids) or {}) do
        local _, status, pending = C_LFGList.GetApplicationInfo(id)
        status = Str(pending) or Str(status)
        if status == "applied" or status == "invited" then
            local a = { id = id, status = status, since = D.appliedAt[id] }
            local r = D.Read(id)   -- Mythic+
            if r then
                a.dungeon, a.cid, a.key, a.leader, a.leaderClass = r.dungeon, r.cid, r.key, r.leader, r.leaderClass
            else                   -- Raid, Mythic 0, ...: the activity's name
                local info = Tab(C_LFGList.GetSearchResultInfo(id))
                local acts = info and Tab(info.activityIDs)
                local ai = acts and Num(acts[1]) and Tab(C_LFGList.GetActivityInfoTable(acts[1]))
                a.dungeon = ai and Str(ai.fullName) or "?"
                a.leader = info and Str(info.leaderName) and Ambiguate(info.leaderName, "short")
                local li = Tab(C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(id))
                a.leaderClass = li and Str(li.classFilename)
            end
            out[#out + 1] = a
        end
    end
    table.sort(out, function(a, b)
        if (a.status == "invited") ~= (b.status == "invited") then return a.status == "invited" end
        if (a.since or 0) ~= (b.since or 0) then return (a.since or 0) < (b.since or 0) end
        return a.id < b.id
    end)
    return out
end

-------------------------------------------------------------------------------
--  Your listing
-------------------------------------------------------------------------------
-- Challenge map and dungeon name of an activity.
function D.ActivityDungeon(act)
    local ai = act and Tab(C_LFGList.GetActivityInfoTable(act))
    if not ai then return end
    local cid = ChallengeFor(Num(ai.mapID))
    local name = (cid and C_ChallengeMode.GetMapUIInfo(cid)) or Str(ai.fullName) or "?"
    return cid, name, ai
end

-- The active listing as a plain table, or nil.
function D.Entry()
    if not C_LFGList.HasActiveEntryInfo() then return end
    local e = Tab(C_LFGList.GetActiveEntryInfo())
    if not e then return end
    local ids = Tab(e.activityIDs)
    local act = ids and Num(ids[1])
    local cid, dungeon, ai = D.ActivityDungeon(act)
    local r = {
        act = act, cid = cid, dungeon = dungeon or "?", mplus = ai and True(ai.isMythicPlusActivity),
        title = e.name,
        rating = Num(e.requiredDungeonScore) or 0, ilvl = Num(e.requiredItemLevel) or 0,
        playstyle = Num(e.generalPlaystyle), private = True(e.privateGroup),
        autoAccept = True(e.autoAccept), crossFaction = True(e.isCrossFactionListing),
        newPlayerFriendly = True(e.newPlayerFriendly), questID = Num(e.questID),
    }
    -- A raid, or a dungeon without a keystone: its activity group (the
    -- instance), difficulty and size.
    if ai and (Num(ai.categoryID) == D.RAID_CATEGORY or (Num(ai.categoryID) == D.CATEGORY and not r.mplus)) then
        r.raid = Num(ai.categoryID) == D.RAID_CATEGORY
        r.isDungeon = not r.raid
        r.gid, r.diff, r.max = Num(ai.groupFinderActivityGroupID), Num(ai.difficultyID), Num(ai.maxNumPlayers)
    end
    -- The keystone in your bags, when it is the listed one.
    local kAct, _, kLevel = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
    if Num(kAct) and kAct == act then r.keyLevel = Num(kLevel) end
    return r
end

-- New requirements for the active listing. The title stays: it lives in the
-- client's creation fields, where Blizzard's form put it (addon code writing
-- it gets the listing blocked).
function D.UpdateListing(e, rating, ilvl)
    C_LFGList.UpdateListing({
        activityIDs = { e.act },
        generalPlaystyle = e.playstyle,
        requiredDungeonScore = e.mplus and (rating or e.rating) or 0,
        requiredItemLevel = ilvl or e.ilvl,
        isPrivateGroup = e.private,
        isCrossFactionListing = e.crossFaction,
        isAutoAccept = e.autoAccept,
        newPlayerFriendly = e.newPlayerFriendly,
        questID = e.questID,
    })
end

function D.Delist() C_LFGList.RemoveListing() end

-------------------------------------------------------------------------------
--  Creating a listing: Blizzard's own Start a Group, clicked
--  securely, opens its form and writes activity and title; a later click
--  sends CreateListing with our values. Both in one click is blocked.
-------------------------------------------------------------------------------
-- The keystone in your bags: { act, level, cid, dungeon } or nil.
function D.OwnKey()
    local act, _, level = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
    act, level = Num(act), Num(level)
    if not act then return end
    local cid, dungeon = D.ActivityDungeon(act)
    return { act = act, level = level, cid = cid, dungeon = dungeon or "?" }
end

-- Is Blizzard's form prepared for this activity (open, your key's activity
-- chosen, so its title written)? Blizzard's own List Group may still be off:
-- after a login its form has no playstyle, which our listing sends itself.
function D.FormReady(act)
    local ec = LFGListFrame and LFGListFrame.EntryCreation
    if not (ec and ec:IsShown()) then return false end
    return Num(ec.selectedActivity) == act
end

-- Blizzard's button for a category (Dungeons by default) on its category
-- page. Blizzard builds these at login (LFG_LIST_AVAILABILITY_UPDATE),
-- before its window opens. Raids has two: current (filters 1) and older.
function D.CategoryButton(category)
    category = category or D.CATEGORY
    local cs = LFGListFrame and LFGListFrame.CategorySelection
    local first, plain
    for _, b in ipairs(cs and cs.CategoryButtons or {}) do
        if b.categoryID == category then
            first = first or b
            if (b.filters or 0) == 0 then plain = plain or b end
        end
    end
    if category == D.CATEGORY then return plain or first end
    return first
end

-- Can Start a Group run? It needs the category selected on Blizzard's
-- category page; the + Create click selects it first when the button exists.
function D.CanStart(category)
    category = category or D.CATEGORY
    local cs = LFGListFrame and LFGListFrame.CategorySelection
    if not (cs and cs.StartGroupButton) then return false end
    return cs.selectedCategory == category or D.CategoryButton(category) ~= nil
end

-- Blizzard's Start a Group form, when it is open on that category (raids by
-- default): the title typed there ("" when none yet), else nil.
function D.FormTitle(category)
    local ec = LFGListFrame and LFGListFrame.EntryCreation
    if not (ec and ec:IsShown() and Num(ec.selectedCategory) == (category or D.RAID_CATEGORY)) then return end
    local ok, text = pcall(function() return ec.Name and ec.Name:GetText() end)
    text = ok and Str(text) or ""
    -- On Dungeons Blizzard writes your keystone's title in ("+14 Relaxed", a
    -- K-string): that's no title of yours, a Mythic 0 group needs its own.
    if text:find("|K", 1, true) then return "" end
    return strtrim(text)
end

-- A raid listing: any raid activity (tested in 12.1.5: it need not be the
-- form's); the title stays what was typed into Blizzard's form.
-- st: playstyle, ilvl, private, ownFaction.
function D.CreateRaidListing(act, st)
    C_LFGList.CreateListing({
        activityIDs = { act },
        generalPlaystyle = st.playstyle,
        requiredItemLevel = st.ilvl or 0,
        isPrivateGroup = st.private and true or false,
        isCrossFactionListing = not st.ownFaction,
        isAutoAccept = false,
        newPlayerFriendly = false,
    })
end

-- st: playstyle, rating, ilvl, private, ownFaction.
function D.CreateListing(key, st)
    C_LFGList.CreateListing({
        activityIDs = { key.act },
        generalPlaystyle = st.playstyle,
        requiredDungeonScore = st.rating or 0,
        requiredItemLevel = st.ilvl or 0,
        isPrivateGroup = st.private and true or false,
        isCrossFactionListing = not st.ownFaction,
        isAutoAccept = false,
        newPlayerFriendly = false,
    })
end

-------------------------------------------------------------------------------
--  Applicants
-------------------------------------------------------------------------------
local GONE = { declined = true, declined_full = true, declined_delisted = true, cancelled = true,
               timedout = true, invitedeclined = true, failed = true }

-- Waiting and invited applicants: { id, status, isNew, comment, members }.
function D.Applicants(act)
    local out = {}
    local ok, ids = pcall(C_LFGList.GetApplicants)
    for _, id in ipairs(ok and Tab(ids) or {}) do
        local info = Num(id) and Tab(C_LFGList.GetApplicantInfo(id))
        local status = info and (Str(info.pendingApplicationStatus) or Str(info.applicationStatus))
        if info and status and not GONE[status] then
            local a = { id = id, status = status, isNew = True(info.isNew), comment = info.comment, members = {} }
            for i = 1, Num(info.numMembers) or 1 do
                local name, class, _, _, ilvl, _, tank, healer, _, role, _, score, _, _, _, specID, leaver =
                    C_LFGList.GetApplicantMemberInfo(id, i)
                local m = {
                    name = Str(name) and Ambiguate(name, "short") or "?", fullName = Str(name), class = Str(class),
                    ilvl = Num(ilvl) or 0, rating = Num(score) or 0,
                    -- Keystone Deserter (patch 11.2); /gotta deserter marks every other applicant.
                    leaver = True(leaver) or (ns.deserterPreview and id % 2 == 0 and i == 1) or false,
                    role = Str(role) or (True(tank) and "TANK") or (True(healer) and "HEALER") or "DAMAGER",
                }
                if m.role ~= "TANK" and m.role ~= "HEALER" then m.role = "DAMAGER" end
                local sid = Num(specID)
                if sid and GetSpecializationInfoByID then m.spec = select(2, GetSpecializationInfoByID(sid)) end
                if act and C_LFGList.GetApplicantDungeonScoreForListing then
                    local best = Tab(C_LFGList.GetApplicantDungeonScoreForListing(id, i, act))
                    if best and Num(best.bestRunLevel) and best.bestRunLevel > 0 then
                        m.best, m.timed = best.bestRunLevel, True(best.finishedSuccess)
                    end
                end
                m.lust = m.class and LUST[m.class] and true or false
                m.brez = m.class and BREZ[m.class] and true or false
                a.members[#a.members + 1] = m
            end
            out[#out + 1] = a
        end
    end
    return out
end

-- Raider.IO's own profile block on a tooltip, when Raider.IO is installed
-- (its public API; extra information only, nothing searches or filters by it).
function D.RaiderIOTooltip(tooltip, fullName)
    local rio = _G.RaiderIO
    if not (rio and fullName and rio.ShowProfile) then return false end
    local ok, shown = pcall(rio.ShowProfile, tooltip, fullName)
    return ok and shown and true or false
end

-- The Raider.IO main's score when this character is an alt whose main is
-- clearly stronger (at least 100 more than its own rating), else nil.
function D.RaiderIOMain(fullName, ownRating)
    local rio = _G.RaiderIO
    if not (rio and fullName and rio.GetProfile) then return end
    local ok, profile = pcall(rio.GetProfile, fullName)
    local mk = ok and type(profile) == "table" and profile.mythicKeystoneProfile
    if type(mk) ~= "table" or mk.blocked then return end
    local main = type(mk.mplusMainCurrent) == "table" and Num(mk.mplusMainCurrent.score) or Num(mk.mainCurrentScore)
    if main and main >= (ownRating or 0) + 100 then return main end
end

-- "  MAIN 3100" for a line of text, or "".
function D.MainTag(fullName, ownRating)
    local main = D.RaiderIOMain(fullName, ownRating)
    if not main then return "" end
    local T = UI.Theme
    return "  |cffe0b868MAIN|r " .. T.ColorCode(T.RatingColor(main)) .. math.floor(main) .. "|r"
end

function D.Invite(id) C_LFGList.InviteApplicant(id) end
function D.Decline(id) C_LFGList.DeclineApplicant(id) end

-- Applicants can be handled by the leader or an assistant.
function D.CanManage()
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-------------------------------------------------------------------------------
--  Your group
-------------------------------------------------------------------------------
local function UnitRating(unit)
    local s = C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
              and Tab(C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit))
    return s and Num(s.currentSeasonScore) or nil
end

-- { name, class, role, spec, rating } for you and your party.
function D.GroupMembers()
    local out = {}
    local function Add(unit)
        if not UnitExists(unit) then return end
        local _, class = UnitClass(unit)
        local role = Str(UnitGroupRolesAssigned(unit))
        if unit == "player" and (not role or role == "NONE") then role = D.PlayerRole() end
        if role ~= "TANK" and role ~= "HEALER" then role = "DAMAGER" end
        local m = { name = Str(UnitName(unit)) or "?", class = Str(class), role = role,
                    rating = UnitRating(unit) }
        if unit == "player" then
            local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
            local spec = getSpec and getSpec()
            local info = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
            m.spec = spec and info and Str((select(2, info(spec)))) or nil
            local _, ilvl = GetAverageItemLevel()
            m.ilvl = Num(ilvl) and math.floor(ilvl) or nil
        end
        out[#out + 1] = m
    end
    Add("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if not UnitIsUnit(unit, "player") then Add(unit) end
        end
    else
        for i = 1, 4 do Add("party" .. i) end
    end
    return out
end
