-------------------------------------------------------------------------------
--  UI/KeyRead.lua  --  a listing's key level, measured from its title
--
--  Titles are K-strings: addons may show them, never read them. WoW still
--  lays them out like any text and reports how wide they are. The measuring
--  font (media/fonts/GQEA-Measure.ttf, tools/MakeMeasureFont.ps1) makes
--  every character 0 px wide except "+" (PLUS) and the digits (BASE + STEP *
--  digit, with 128 px of ink), at size 64.
--  How WoW adds up a line (measured in 12.1.5 with /gotta keyprobe): every
--  glyph's advance plus 1 px, except the last glyph, which counts with its
--  ink width instead. From that:
--   - title .. "~": all advances. Less "+" (if any: both are tried, see
--     Measure), / BASE = how many digits, the rest / STEP = their sum (the
--     1 px per character stays below one STEP),
--   - title alone minus title .. "~": the last glyph's advance against its
--     ink. A title ending in its key ("+14") gives the last digit away,
--   - "+14 Relaxed" ends in a word: wrapped narrow, WoW breaks it into "+1"
--     and "4 Relaxed"; the first line is the widest, and its width gives
--     the first digit (FontString:GetWrappedWidth; tested on its own, KR.words).
--   - several "+" in front ("++19 push", "+++17"): two to four are tried
--     when one or none doesn't add up, the fewest that do win,
--   - a title ending in "+" ("20+", "+17++"): its last glyph's advance is
--     the "+"'s; up to four "+" are tried, the fewest that add up wins.
--   Both: KR.ends, tested on its own like KR.words.
--  More than two digits (custom titles) -> nil. It tests itself on known
--  titles first (KR.Works); when WoW stops giving real widths it turns off
--  and the window shows titles as before.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T = UI.Theme
local KR = {}
UI.KeyRead = KR

local issecret = issecretvalue or function() return false end
local floor, abs = math.floor, math.abs

local PATH = T.MEDIA .. "fonts\\GQEA-Measure.ttf"
local SIZE = 64
local PLUS, BASE, STEP = 1280, 2560, 128   -- advances at SIZE, in px: "+", digit = BASE + STEP * digit
-- Wrap width for the first line: holds "+" and any digit, never two digits.
local WRAP = PLUS + BASE + 14 * STEP
local TOL = 6                  -- slack when checking the font itself
local MAX_TRIES = 5

local font = CreateFont("GQEAMeasureFont")   -- created now: WoW loads the file in time
font:SetFont(PATH, SIZE, "")

KR.diag = {}   -- what the last self-test saw, for /gotta keyprobe

local host, full, lines
-- Measured at the self-test, in reported units: scale (per font px), the
-- width of "~", WoW's extra per glyph, a digit's ink, "+" with its extra,
-- the ink of "+".
local scale, tilde, extra, ink, plus, plusInk
local state, tries, nextTry = "new", 0, 0
local cache, cached = {}, 0

local function Num(v) return type(v) == "number" and not issecret(v) and v or nil end

local function Width(text)
    if not pcall(full.SetText, full, text) then return end
    local ok, w = pcall(full.GetStringWidth, full)
    return ok and Num(w)
end

-- Advances of text with WoW's extras, in font px.
local function Advance(text)
    local w = Width(text .. "~")
    return w and (w - tilde) / scale
end

-- A digit from a measured advance (font px, without the extra), or nil.
local function Digit(adv)
    local d = floor((adv - BASE) / STEP + 0.5)
    if d >= 0 and d <= 9 and abs(adv - (BASE + STEP * d)) <= TOL then return d end
end

-- The title's last glyph: a digit (its value), "+", or nil (a letter).
local function LastGlyph(title)
    local w1, w2 = Width(title), Width(title .. "~")
    if not (w1 and w2) then return end
    local rest = w2 - w1 - tilde - extra   -- the last glyph's advance less its ink
    local d = Digit((rest + ink) / scale)
    if d then return d end
    if plusInk and abs((rest + plusInk) / scale - PLUS) <= TOL then return "+" end
end

-- The title's last glyph, when it is a digit.
local function LastDigit(title)
    local g = LastGlyph(title)
    return type(g) == "number" and g or nil
end

-- Wrapped narrower than "+" and two digits, WoW breaks "+14 Relaxed" into
-- "+1" and "4 Relaxed" (between the digits). "+" is wider than any line
-- holding one digit and a few letters, so the widest line is "+1": its
-- width minus "+" is the first digit's advance.
local function FirstDigit(title)
    if not (lines and lines.GetWrappedWidth) then return end
    if not pcall(lines.SetText, lines, title) then return end
    lines:SetWidth(WRAP * scale)
    local ok, w = pcall(lines.GetWrappedWidth, lines)
    w = ok and Num(w)
    if not w then return end
    return Digit((w - plus) / scale)
end

-- The first digit of a title starting with own "+" ("++19 push": 2): ours
-- go in front up to five, and wrapped as wide as five "+" and one digit,
-- the first line holds them and the first digit only. With five in front
-- it is also the widest line, even when a later one ends in "+" ("7++").
-- A wrong own leaves too many or too few "+" on it: no digit.
local LEAD = 5
local function FirstDigitLead(title, own)
    if not (lines and lines.GetWrappedWidth) or own > LEAD then return end
    if not pcall(lines.SetText, lines, ("+"):rep(LEAD - own) .. title) then return end
    lines:SetWidth((LEAD * PLUS + BASE + 14 * STEP) * scale)
    local ok, w = pcall(lines.GetWrappedWidth, lines)
    w = ok and Num(w)
    return w and Digit((w - LEAD * plus) / scale)
end

-- The level a title's digits make, given its advance without the "+" it is
-- assumed to have (hasPlus), or nil when the digits don't add up. A title
-- ending in "+" (endsPlus) gives no last digit. lead: the title is taken
-- to start with that many "+"; the first digit then comes from
-- FirstDigitLead, which also checks a one-digit reading.
local function Read(title, a, hasPlus, endsPlus, lead)
    local count = floor(a / BASE)
    if count < 1 or count > 2 then return end
    local sum = floor((a - count * BASE) / STEP)
    if sum > 9 * count then return end
    local last = not endsPlus and LastDigit(title) or nil
    local first
    if lead then
        if not last then first = FirstDigitLead(title, lead) end
    elseif not last and KR.words then first = FirstDigit(hasPlus and title or ("+" .. title)) end   -- our own "+" in front
    if count == 1 then
        if last and last ~= sum then return end
        if (endsPlus or lead) and first and first ~= sum then return end
        return sum
    end
    if last then first = sum - last end
    if not first or first < 1 or first > 9 or sum - first < 0 or sum - first > 9 then return end
    return first * 10 + (sum - first)
end

-- Level of a title, or nil. "+14" and "14" both count: "+" is 10 digit
-- steps (and 1 px) wide, so the wrong guess about it leaves digits that
-- can't be (a first digit of 10 and more, a sum above 9 per digit).
local function Measure(title)
    local a = Advance(title)
    if not a then return end
    -- "20+", "+17++", "++17+": one to four "+" (some of them in front),
    -- the fewest that give a level.
    if KR.ends and LastGlyph(title) == "+" then
        for n = 1, 4 do
            for own = 0, n - 1 do
                local level = Read(title, a - n * plus / scale, true, true, own)
                if level then return level >= 2 and level <= 40 and level or nil end
            end
        end
        return
    end
    local with, without = Read(title, a - plus / scale, true), Read(title, a, false)
    local level
    if with and not without then level = with elseif without and not with then level = without end
    -- "++19 push", "+++17": several "+" in front, the fewest that give a level.
    if not with and not without and KR.ends then
        for n = 2, 4 do
            level = Read(title, a - n * plus / scale, true, false, n)
            if level then break end
        end
    end
    -- Custom titles can line digits up into nonsense ("+9 ... 3k" -> 93).
    if level and level >= 2 and level <= 40 then return level end
end

local KNOWN = { ["+2"] = 2, ["+9"] = 9, ["+20"] = 20, ["+13"] = 13, ["+31"] = 31, ["+19"] = 19,
                ["+9 Relaxed"] = 9, ["14"] = 14, ["9"] = 9, ["20"] = 20, ["10"] = 10 }
local ENDS = { ["++19 push"] = 19, ["+++17"] = 17, ["++8"] = 8, ["+++21 Relaxed"] = 21, ["++17+"] = 17, ["20+"] = 20, ["+17++"] = 17, ["15+"] = 15, ["+15+"] = 15, ["+9+"] = 9, ["12++"] = 12 }
local WORDS = { ["+12 Relaxed"] = 12, ["+21 Competitive"] = 21, ["+19 Carry Offered"] = 19, ["+30 Learning"] = 30,
                ["14 Relaxed"] = 14, ["21 push"] = 21 }

local function Check(list, d)
    for text, level in pairs(list) do
        local got = Measure(text)
        if got ~= level then
            d[#d + 1] = ("%s read as %s (advance %s, last digit %s, first line digit %s)"):format(text,
                tostring(got), tostring((Advance(text))), tostring((LastDigit(text))), tostring((FirstDigit(text))))
            return false, ("%s read as %s"):format(text, tostring(got))
        end
    end
    return true
end

-- Scale and WoW's extras from known glyphs, then the method on known titles.
local function Calibrate()
    if not host then
        host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(1, 1)
        host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20000, 20000)
        host:SetAlpha(0)
        full = host:CreateFontString(nil, "ARTWORK")
        full:SetWordWrap(false)
        lines = host:CreateFontString(nil, "ARTWORK")
        lines:SetPoint("TOPLEFT")
        lines:SetWordWrap(true)
        if lines.SetNonSpaceWrap then lines:SetNonSpaceWrap(false) end
    end
    host:Show()
    local set = font:SetFont(PATH, SIZE, "")
    full:SetFontObject(font)
    lines:SetFontObject(font)
    local d = {}
    KR.diag = d
    local t1, t2, z, n, i0, p0 = Width("~"), Width("~~"), Width("0~"), Width("9~"), Width("0"), Width("+0")
    d[1] = ("SetFont %s, font %s, widths ~=%s ~~=%s 0~=%s 9~=%s 0=%s +0=%s, GetWrappedWidth %s"):format(
        tostring(set), tostring((font:GetFont())), tostring(t1), tostring(t2), tostring(z), tostring(n),
        tostring(i0), tostring(p0), tostring(lines.GetWrappedWidth ~= nil))
    if not (t1 and t2 and z and n and i0 and p0) then return false, "no width" end
    tilde, extra, ink = t1, t2 - t1, i0
    scale = (z - t1 - extra) / BASE
    plus = p0 - i0   -- "+" with its extra
    plusInk = Width("+")
    if scale <= 0 then return false, "no width" end
    if abs((n - t1 - extra) / scale - (BASE + 9 * STEP)) > TOL or abs(plus / scale - PLUS) > TOL then
        return false, "digit widths (not the measuring font)"
    end
    local letters = Advance("Relaxed")
    if not letters or letters > STEP / 4 then return false, "letters not empty" end
    KR.words, KR.ends = false, false
    local ok, why = Check(KNOWN, d)
    if not ok then return false, why end
    -- Titles with a word after the key: a bonus, tested on its own.
    KR.words = true
    KR.words = Check(WORDS, d)
    d[#d + 1] = "titles with a word after the key: " .. (KR.words and "read" or "not read")
    -- Titles ending in "+" ("20+", "+17++"): they need the first line's digit.
    if KR.words then
        KR.ends = true
        KR.ends = Check(ENDS, d)
    end
    d[#d + 1] = "titles ending in \"+\": " .. (KR.ends and "read" or "not read")
    return true
end

-- True when titles can be measured (tests itself once, retries a few times
-- while the font may still be loading).
function KR.Works()
    if state == "ok" then return true end
    if state == "off" or GetTime() < nextTry then return false end
    local done, ok, why = pcall(Calibrate)   -- e.g. "Font not set" when the font file is missing
    if not done then ok, why = false, tostring(ok) end
    if ok then
        state, KR.why = "ok", nil
    else
        tries = tries + 1
        KR.why = why
        state = tries >= MAX_TRIES and "off" or "retry"
        nextTry = GetTime() + 2
    end
    return ok
end

-- Key level of a listing title (K-string), or nil.
function KR.Level(title)
    if title == nil or not KR.Works() then return end
    local hit = cache[title]
    if hit ~= nil then return hit or nil end
    if cached > 3000 then wipe(cache); cached = 0 end
    local level = Measure(title)
    cache[title] = level or false
    cached = cached + 1
    return level
end

-- A new search: titles may have been edited since (the K-string may stay).
function KR.Reset() wipe(cache); cached = 0 end

-- /gotta keyprobe: test again from scratch, and the state of the test.
function KR.Retest() state, tries, nextTry, KR.why = "new", 0, 0, nil; KR.Reset() end
function KR.State() return state, KR.why, scale, tries end
