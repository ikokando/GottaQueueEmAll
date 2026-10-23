-------------------------------------------------------------------------------
--  UI/Region.lua  --  Where a group's leader plays from: a flag and a country
--
--  A leader reads as "Name-Realm" (no realm: yours). The realm's language and
--  time zone tell the country (UI/Realms.lua, made by tools/MakeRealms.ps1
--  from Blizzard's realm list). English EU realms are just "Europe".
--  Flags: media/flags, from flag-icons (MIT, media/flags/LICENSE).
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local R = {}
UI.Region = R

local FLAGS = "Interface\\AddOns\\GottaQueueEmAll\\media\\flags\\"
local REGION = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW" }
local NAMES = {
    DE = "Germany", FR = "France", ES = "Spain", IT = "Italy", RU = "Russia", PT = "Portugal",
    EU = "Europe (English)",
    US = "North America", MX = "Latin America", BR = "Brazil", AU = "Oceania",
    KR = "Korea", TW = "Taiwan",
}
R.NAMES = NAMES

-- Lower case for A-Z and Cyrillic (Lua's lower stops at A-Z): Russian
-- realms come as "Пиратская Бухта" and "Пиратская бухта".
local function Lower(s)
    s = s:lower():gsub("\208([\144-\175])", function(c)
        local b = c:byte()   -- А-П: D0 90-9F -> D0 B0-BF; Р-Я: D0 A0-AF -> D1 80-8F
        return b < 160 and ("\208" .. string.char(b + 32)) or ("\209" .. string.char(b - 32))
    end)
    return (s:gsub("\208\129", "\209\145"))   -- Ё -> ё
end

-- A realm's key: without spaces, hyphens, apostrophes, dots and brackets.
local function Key(realm) return Lower((realm:gsub("[%s%-'%.%(%)]", ""))) end
R.RealmKey = Key   -- player ratings key players by it too (UI/Ratings.lua)

-- This region's realms by key (nil on a region without data, e.g. China or a PTR).
local realms
local function Realms()
    if realms == nil then
        local reg = GetCurrentRegion and REGION[GetCurrentRegion()]
        local src = reg and ns.Realms and ns.Realms[reg]
        realms = false
        if src then
            realms = {}
            for k, v in pairs(src) do realms[Key(k)] = realms[Key(k)] or v end
        end
    end
    return realms or nil
end

-- Country code and realm name of a leader ("Name-Realm" or "Name"), or nil.
function R.Of(fullName)
    if type(fullName) ~= "string" or issecretvalue and issecretvalue(fullName) then return end
    local t = Realms()
    if not t then return end
    local realm = fullName:match("^[^%-]+%-(.+)$") or GetNormalizedRealmName()
    local hit = realm and t[Key(realm)]
    if hit then return hit[1], hit[2] end
end

local function On()
    local db = ns.DB and ns.DB()
    return not (db and db.leaderRegion == false)
end

-- An inline flag (4:3 in a 64 x 64 texture).
function R.FlagMarkup(code, h)
    h = h or 12
    return ("|T%s%s:%d:%d:0:0:64:64:0:64:0:48|t"):format(FLAGS, code:lower(), h, math.floor(h * 4 / 3 + 0.5))
end

-- The flag to put before a leader's name ("" when off or unknown).
function R.Markup(fullName)
    if not On() then return "" end
    local code = R.Of(fullName)
    return code and (R.FlagMarkup(code) .. " ") or ""
end

-- "Germany · Blackmoore" under a tooltip, when known.
function R.AddTooltipLine(tt, fullName)
    if not On() then return end
    local code, realm = R.Of(fullName)
    if not code then return end
    tt:AddLine(R.FlagMarkup(code) .. "  " .. NAMES[code] .. "  |cff8d98a8·  " .. realm .. "|r", 0.85, 0.85, 0.85)
end
