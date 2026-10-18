-------------------------------------------------------------------------------
--  Core.lua  --  "Gotta Queue 'Em All": saved settings, season data, slash
--  command and the settings page. The window itself lives in UI/.
--
--  /gotta, /gqea          open / close the window
--  /gotta settings        the settings page (Options > AddOns)
--  /gotta help            these commands
--  /gotta welcome         the welcome screen again
--  /gotta keyprobe        whether key levels can be read from titles (for bug reports)
-------------------------------------------------------------------------------
local _, ns = ...

local TITLE = "Gotta Queue 'Em All"

local issecretvalue = issecretvalue or function() return false end
local db

function ns.Print(msg)
    print("|cffd2a24c" .. TITLE .. "|r " .. msg)
end

function ns.DB() return db end

-- Events the window only needs while it is open: listed here, registered
-- when it opens (ns.SetLive(true)) and dropped when it closes. Closed, the
-- addon does no work.
local live = {}
function ns.Live(frame, events) live[#live + 1] = { frame, events } end
function ns.SetLive(on)
    for _, l in ipairs(live) do
        local frame = l[1]
        for _, e in ipairs(l[2]) do
            pcall(on and frame.RegisterEvent or frame.UnregisterEvent, frame, e)   -- unknown events are skipped
        end
    end
end

-- Classes that bring Bloodlust / Heroism and a battle res.
ns.LUST_CLASS = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
ns.BREZ_CLASS = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }

-------------------------------------------------------------------------------
--  Saved settings
-------------------------------------------------------------------------------
local DEFAULTS = { showMinimap = true }

-- Settings of the 0.x sidebar addon, and logs of pre-release test builds;
-- nothing uses them any more.
local LEGACY = { "enabled", "width", "height", "dimPercent", "dimAlpha", "showLeaderScore", "showDungeonIcon",
                 "showBadges", "fitParty", "fitLust", "fitBrez", "fitNotDeclined", "presets", "createPresets",
                 "createLookTitle", "keyMin", "keyMax", "keyprobe", "raidprobe", "raidcreate", "raidlist", "uidebug",
                 "createTitlePlaystyle",
                 "createLust", "createBrez", "moreOpen" }

local function LoadDB()
    if type(GottaQueueEmAllDB) ~= "table" then GottaQueueEmAllDB = {} end
    db = GottaQueueEmAllDB
    for _, k in ipairs(LEGACY) do db[k] = nil end
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
end

-------------------------------------------------------------------------------
--  Season dungeons and your best keys
-------------------------------------------------------------------------------
local DUNGEON_CATEGORY = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
local challengeByInstance, challengeByName = {}, {}

local function BuildChallengeLookup()
    wipe(challengeByInstance); wipe(challengeByName)
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return end
    for _, cid in ipairs(C_ChallengeMode.GetMapTable() or {}) do
        local name, _, _, _, _, instanceMapID = C_ChallengeMode.GetMapUIInfo(cid)
        if name then challengeByName[name] = cid end
        if instanceMapID then challengeByInstance[instanceMapID] = cid end
    end
end

local function ChallengeMapForGroup(groupID, groupName)
    for _, act in ipairs(C_LFGList.GetAvailableActivities(DUNGEON_CATEGORY, groupID) or {}) do
        local ai = C_LFGList.GetActivityInfoTable(act)
        local cid = ai and ai.mapID and challengeByInstance[ai.mapID]
        if cid then return cid end
    end
    return challengeByName[groupName]
end

-- This season's Mythic+ dungeons: { id = activity group, name, cid = challenge map }.
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

-- Your season best in a dungeon: level, inTime, score.
function ns.BestKey(cid)
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

-------------------------------------------------------------------------------
--  Settings page (Options > AddOns > Gotta Queue 'Em All)
-------------------------------------------------------------------------------
local category

function ns.OpenSettings()
    if InCombatLockdown() then ns.Print("settings open after combat."); return end
    if category and Settings and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
end

local function RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local cat, layout = Settings.RegisterVerticalLayoutCategory(TITLE)
    local function Header(text)
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end
    local function Button(name, text, onClick, tip)
        if layout and CreateSettingsButtonInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tip, true))
        end
    end

    Header("Window")
    Button("Window", "Open", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if ns.UI and ns.UI.Toggle then ns.UI.Toggle() end
    end, "Opens the Gotta Queue 'Em All window. Also: /gotta, the minimap button, or your hotkey.")
    Button("Size and position", "Reset", function()
        if ns.UI and ns.UI.ResetGeometry then ns.UI.ResetGeometry() end
    end, "Puts the window back to its default size in the middle of the screen.")

    Header("Opening the window")
    local var = "GottaQueueEmAll_showMinimap"
    local setting = Settings.RegisterAddOnSetting(cat, var, "showMinimap", db, "boolean", "Minimap button", DEFAULTS.showMinimap)
    Settings.SetOnValueChangedCallback(var, function()
        if ns.UI and ns.UI.Launcher then ns.UI.Launcher.Update() end
    end)
    Settings.CreateCheckbox(cat, setting,
        "A minimap button that opens the window. Drag it to move it around the minimap; right-click opens these settings.")
    Button("Hotkey", "Key Bindings", function()
        pcall(function()   -- Blizzard's key bindings page, where it can be found
            local kb = SettingsPanel:GetCategory(Settings.KEYBINDINGS_CATEGORY_ID)
            if kb then SettingsPanel:SelectCategory(kb) end
        end)
    end, "Set it in the window: the Hotkey button at the top (click, then press a key). Or in Key Bindings > AddOns > Gotta Queue 'Em All.")

    Settings.RegisterAddOnCategory(cat)
    category = cat
end

-------------------------------------------------------------------------------
--  Boot and slash command
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    LoadDB()
    local ok, err = pcall(RegisterSettings)
    if not ok then ns.Print("settings page unavailable (" .. tostring(err) .. ")") end
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
    -- The Group Finder's activities: Blizzard builds its category buttons
    -- (which + Create clicks) and its dungeon list from them.
    if C_LFGList.RequestAvailableActivities then C_LFGList.RequestAvailableActivities() end
end)

SLASH_GOTTAQUEUEEMALL1 = "/gotta"
SLASH_GOTTAQUEUEEMALL2 = "/gqea"
local function Help()
    ns.Print("commands:")
    print("  /gotta  -  open / close the window (also /gqea)")
    print("  /gotta settings  -  the settings page")
    print("  /gotta welcome  -  the welcome screen again")
    print("  /gotta keyprobe  -  check whether key levels can be read (for bug reports)")
end

SlashCmdList.GOTTAQUEUEEMALL = function(msg)
    if not db then return end
    msg = strtrim((msg or ""):lower())
    if msg == "" then
        if ns.UI and ns.UI.Toggle then ns.UI.Toggle() end
    elseif msg == "settings" or msg == "options" or msg == "config" then
        ns.OpenSettings()
    elseif msg == "welcome" and ns.UI and ns.UI.ShowWelcome then
        ns.UI.ShowWelcome()
    elseif msg == "keyprobe" and ns.UI and ns.UI.KeyProbe then
        ns.UI.KeyProbe.Run()
    else
        Help()
    end
end
