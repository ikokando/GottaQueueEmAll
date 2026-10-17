-------------------------------------------------------------------------------
--  UI/Theme.lua  --  design tokens of the window
--
--  Deep navy surfaces, metallic gold as the only accent (gold and navy are
--  complementary), Blizzard's own semantic colors for everything that means
--  something in game: rating and key level rarity, class colors, roles.
--
--  Font: Barlow Semi Condensed (SIL Open Font License), media/fonts.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI or {}
ns.UI = UI

local T = {}
UI.Theme = T

local floor = math.floor

local function Hex(h, a)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, a or 1 }
end

-- Colors: { r, g, b, a }. Unpack with unpack(T.C.x).
T.C = {
    bg         = Hex("0A0E15"),
    bgTop      = Hex("0F1520"),
    panel      = Hex("0F141D"),
    raised     = Hex("131A25"),
    badge      = Hex("182131"),
    empty      = Hex("11161F"),
    navy       = Hex("101B2E"),
    line       = { 0.63, 0.71, 0.84, 0.10 },
    lineStrong = { 0.63, 0.71, 0.84, 0.18 },
    track      = Hex("1E2633"),

    text       = Hex("EAEEF4"),
    textHi     = Hex("F5F7FA"),
    text2      = Hex("C3CBD6"),
    label      = Hex("A9B3C1"),
    muted      = Hex("8D98A8"),
    faint      = Hex("4E5A6B"),

    -- A deep gold: the game renders gold brighter than it looks elsewhere.
    gold       = Hex("D2A24C"),
    goldLight  = Hex("E6C27A"),
    goldDark   = Hex("A9792E"),
    goldText   = Hex("E0B868"),
    onGold     = Hex("1A1407"),

    good       = Hex("3EB060"),
    goodText   = Hex("96E3AD"),
    badText    = Hex("FF9F96"),
    lust       = Hex("FF9A4D"),
    brez       = Hex("86E0A2"),
}

-- Spacing (UI units).
T.S = {
    pad    = 18,
    header = 56,
    tabs   = 44,
    footer = 32,
    btnH   = 32,
    chipH  = 32,
}

T.WHITE = "Interface\\Buttons\\WHITE8X8"
T.MEDIA = "Interface\\AddOns\\GottaQueueEmAll\\media\\"
-- White, tintable textures (media/ui, made by tools/MakeUITextures.ps1):
-- round-fill / round-border (radius 6, sliced), corner-cap, circle, ring,
-- ring-dashed, glyph-tank / -healer / -dps / -lust / -brez.
T.TEX = T.MEDIA .. "ui\\"

-------------------------------------------------------------------------------
--  Fonts
-------------------------------------------------------------------------------
local FONT_DIR = T.MEDIA .. "fonts\\"
T.FONT = {
    regular  = FONT_DIR .. "BarlowSemiCondensed-Regular.ttf",
    medium   = FONT_DIR .. "BarlowSemiCondensed-Medium.ttf",
    semibold = FONT_DIR .. "BarlowSemiCondensed-SemiBold.ttf",
    bold     = FONT_DIR .. "BarlowSemiCondensed-Bold.ttf",
}

-- Named font objects: { weight, size, color[, flags] }.
local STYLES = {
    title   = { "bold", 19, "textHi" },
    display = { "bold", 32, "textHi" },
    h2      = { "bold", 17, "textHi" },
    body    = { "medium", 15, "text" },
    bodySm  = { "medium", 14, "text2" },
    small   = { "regular", 13, "muted" },
    tiny    = { "semibold", 12, "muted" },
    label   = { "semibold", 13, "label" },
    button  = { "semibold", 14, "text" },
    tab     = { "semibold", 16, "muted" },
    num     = { "bold", 24, "textHi" },
    numSm   = { "bold", 19, "textHi" },
    key     = { "bold", 54, "textHi" },
    keyArt  = { "bold", 30, "textHi", "OUTLINE" },   -- key on dungeon art: black outline for any background
}

T.Font = {}
for name, s in pairs(STYLES) do
    local f = CreateFont("GQEAFont_" .. name)
    f:SetFont(T.FONT[s[1]], s[2], s[4] or "")
    f:SetTextColor(unpack(T.C[s[3]]))
    f:SetShadowOffset(0, 0)
    T.Font[name] = f
end

-------------------------------------------------------------------------------
--  Semantic colors from the game (fallbacks match Blizzard's scale)
-------------------------------------------------------------------------------
local RATING = { { 3000, Hex("FF6FAE") }, { 2500, Hex("FF8A2A") }, { 2000, Hex("B57CFF") },
                 { 1500, Hex("4D9BFF") }, { 1000, Hex("4FD67A") }, { 0, Hex("C2C6CC") } }
local KEY    = { { 17, Hex("FF6FAE") }, { 14, Hex("FF8A2A") }, { 11, Hex("B57CFF") },
                 { 8, Hex("4D9BFF") }, { 5, Hex("4FD67A") }, { 0, Hex("C2C6CC") } }

local function FromScale(scale, v)
    for _, s in ipairs(scale) do if v >= s[1] then return s[2] end end
    return scale[#scale][2]
end

local function Unpack(col)
    if col and col.GetRGB then local r, g, b = col:GetRGB(); return { r, g, b, 1 } end
end

function T.RatingColor(score)
    score = score or 0
    local c = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
              and Unpack(C_ChallengeMode.GetDungeonScoreRarityColor(score))
    return c or FromScale(RATING, score)
end

function T.KeyColor(level, timed)
    if timed == false then return T.C.muted end
    local c = C_ChallengeMode and C_ChallengeMode.GetKeystoneLevelRarityColor
              and Unpack(C_ChallengeMode.GetKeystoneLevelRarityColor(level or 0))
    return c or FromScale(KEY, level or 0)
end

-- Gradient stops of the rating track (0 .. max rating), for the slider.
T.RATING_STOPS = { { 0, Hex("C2C6CC") }, { 0.30, Hex("4FD67A") }, { 0.45, Hex("4D9BFF") },
                   { 0.60, Hex("B57CFF") }, { 0.75, Hex("FF8A2A") }, { 1, Hex("FF6FAE") } }

function T.ClassColor(classFile)
    local c = classFile and C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile)
    if c then return { c.r, c.g, c.b, 1 } end
    c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return { c.r, c.g, c.b, 1 } end
    return T.C.text
end

function T.ColorCode(c)
    return ("|cff%02x%02x%02x"):format(floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

-------------------------------------------------------------------------------
--  Dungeon art from the Encounter Journal (the Mythic+ tab tiles from
--  GetMapUIInfo carry a painted frame). Cached per challenge map.
-------------------------------------------------------------------------------
local artCache = {}

local function JournalInstance(name, instanceMap)
    if instanceMap and C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap then
        local id = C_EncounterJournal.GetInstanceForGameMap(instanceMap)
        if id then return id end
    end
    -- By name through every tier; the journal's own tier is restored after.
    if not (name and EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return end
    local current = EJ_GetCurrentTier and EJ_GetCurrentTier()
    local found
    for tier = EJ_GetNumTiers(), 1, -1 do
        EJ_SelectTier(tier)
        local i = 1
        while not found do
            local id, n = EJ_GetInstanceByIndex(i, false)
            if not id then break end
            if n == name then found = id end
            i = i + 1
        end
        if found then break end
    end
    if current then EJ_SelectTier(current) end
    return found
end

-- Returns { bg, lore, button, framed, icon } (file IDs, any may be nil):
-- bg = the journal's large background, lore = its small framed lore art,
-- button = its 175 x 95 instance button art, framed = Mythic+ tab tile.
function T.DungeonArt(challengeMapID)
    if not challengeMapID then return {} end
    local c = artCache[challengeMapID]
    if not c then
        local name, _, _, icon, background, instanceMap = C_ChallengeMode.GetMapUIInfo(challengeMapID)
        c = { icon = icon, framed = background }
        local jid = name and JournalInstance(name, instanceMap)
        if jid and EJ_GetInstanceInfo then
            local _, _, bgImage, buttonImage, loreImage = EJ_GetInstanceInfo(jid)
            c.bg, c.button, c.lore = bgImage, buttonImage, loreImage
        end
        artCache[challengeMapID] = c
    end
    return c
end

-- "Altar of Fangs" -> "AoF", for chips and art strips.
function T.Short(name)
    local out = ""
    for word in (name or "?"):gmatch("[%w']+") do
        local low = word:lower()
        out = out .. ((low == "of" or low == "the") and word:sub(1, 1):lower() or word:sub(1, 1):upper())
    end
    return out
end

-- m:ss for ages and timers.
function T.Clock(sec)
    sec = floor(sec or 0)
    return ("%d:%02d"):format(floor(sec / 60), sec % 60)
end
