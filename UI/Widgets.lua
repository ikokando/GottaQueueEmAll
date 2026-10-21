-------------------------------------------------------------------------------
--  UI/Widgets.lua  --  building blocks of the window
--
--  Plain frames and textures, styled from UI/Theme.lua; no Blizzard
--  templates, so the window looks the same with or without a UI skin.
--  None of these are secure: they never touch protected frames.
--
--  Rounded corners come from one white texture each (media/ui/round-fill,
--  round-border, radius 6), stretched as 9-slice and tinted.
--
--  Panel, Text, Label, Button (gold / ghost / quiet / mark / done), Chip,
--  Toggle, Switch, Segmented, Tabs, Slider, RangeSlider, Histogram, Meter, Pill, DeserterTag, Glyph,
--  RoleBadge, Banner, Card.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, A = UI.Theme, UI.Anim
local C = T.C
local W = {}
UI.W = W

local floor, max, min = math.floor, math.max, math.min
local TEX = T.TEX

-------------------------------------------------------------------------------
--  Primitives
-------------------------------------------------------------------------------
function W.Tex(parent, layer, color, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(T.WHITE)
    if color then t:SetVertexColor(unpack(color)) end
    return t
end

-- from = left / bottom, to = right / top (Blizzard's min / max color).
function W.Gradient(t, orient, from, to)
    t:SetGradient(orient, CreateColor(unpack(from)), CreateColor(unpack(to)))
end

local function Slice(t, margin)
    if t.SetTextureSliceMargins then
        t:SetTextureSliceMargins(margin, margin, margin, margin)
        if t.SetTextureSliceMode and Enum.UITextureSliceMode then
            t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
    end
end

-- Rounded fill (radius 6) of any size.
function W.Round(parent, layer, color, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(TEX .. "round-fill")
    Slice(t, 8)
    if color then t:SetVertexColor(unpack(color)) end
    return t
end

-- Anti-aliased disc (thumbs, dots).
function W.Circle(parent, layer, color, size, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(TEX .. "circle")
    t:SetSize(size, size)
    if color then t:SetVertexColor(unpack(color)) end
    return t
end

-- Rounded 1px border; W.SetBorder recolors it. Frames with art inside draw
-- it on top ("OVERLAY", sub 2), above the art and its corner caps.
function W.Border(f, color, layer, sub)
    local t = f:CreateTexture(nil, layer or "BORDER", nil, sub or 0)
    t:SetTexture(TEX .. "round-border")
    Slice(t, 8)
    t:SetAllPoints()
    f.gqBorder = { t }
    W.SetBorder(f, color or C.line)
end

-- Square 1px border from four lines (small boxes, icons).
function W.Lines(f, color, layer)
    local b = {}
    for i = 1, 4 do b[i] = W.Tex(f, layer or "BORDER") end
    -- minPixels 1: stays visible when the window is scaled down to fit.
    b[1]:SetPoint("TOPLEFT");    b[1]:SetPoint("TOPRIGHT");    PixelUtil.SetHeight(b[1], 1, 1)
    b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); PixelUtil.SetHeight(b[2], 1, 1)
    b[3]:SetPoint("TOPLEFT");    b[3]:SetPoint("BOTTOMLEFT");  PixelUtil.SetWidth(b[3], 1, 1)
    b[4]:SetPoint("TOPRIGHT");   b[4]:SetPoint("BOTTOMRIGHT"); PixelUtil.SetWidth(b[4], 1, 1)
    f.gqBorder = b
    W.SetBorder(f, color or C.line)
end

function W.SetBorder(f, color)
    for _, t in ipairs(f.gqBorder) do t:SetVertexColor(unpack(color)) end
end

-- Covers square art corners inside a rounded frame. corners: "TL", "TR",
-- "BL", "BR" keys set to true; color = what lies behind the frame.
local CAP_COORDS = { TL = { 0, 1, 0, 1 }, TR = { 1, 0, 0, 1 }, BL = { 0, 1, 1, 0 }, BR = { 1, 0, 1, 0 } }
local CAP_POINT = { TL = "TOPLEFT", TR = "TOPRIGHT", BL = "BOTTOMLEFT", BR = "BOTTOMRIGHT" }
function W.CornerCaps(parent, region, color, corners)
    for key in pairs(corners) do
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexture(TEX .. "corner-cap")
        t:SetSize(8, 8)
        t:SetTexCoord(unpack(CAP_COORDS[key]))
        t:SetPoint(CAP_POINT[key], region, CAP_POINT[key])
        t:SetVertexColor(unpack(color))
    end
end

function W.Panel(parent, bg, border)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = W.Round(f, "BACKGROUND", bg or C.panel)
    f.bg:SetAllPoints()
    if border ~= false then W.Border(f, border or C.line) end
    return f
end

function W.Text(parent, style, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(T.Font[style or "body"])
    if color then fs:SetTextColor(unpack(color)) end
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Section label: uppercase.
function W.Label(parent, text)
    local fs = W.Text(parent, "label")
    fs:SetText(text:upper())
    return fs
end

-- A tintable white glyph from media/ui: tank, healer, dps, lust, brez.
-- The glyph sits centered in its square, with a little padding.
function W.Glyph(parent, name, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(TEX .. "glyph-" .. name)
    t:SetSize(size, size)
    if color then t:SetVertexColor(unpack(color)) end
    return t
end

-------------------------------------------------------------------------------
--  Button
-------------------------------------------------------------------------------
local VARIANT = {
    gold  = { gradient = true, shine = true, border = { 0.78, 0.60, 0.29, 1 }, hoverBorder = C.goldLight,
              text = C.onGold, hoverText = C.onGold },
    ghost = { bg = { 0.04, 0.055, 0.08, 0.4 }, hoverBg = { 0.82, 0.64, 0.30, 0.10 },
              border = { 0.82, 0.64, 0.30, 0.5 }, hoverBorder = C.gold, text = C.goldText, hoverText = C.goldLight },
    -- Nearly opaque: it also sits on bright dungeon art (Your Group's Delist).
    quiet = { bg = { 0.04, 0.055, 0.08, 0.85 }, hoverBg = { 0.20, 0.08, 0.08, 0.9 },
              border = { 0.63, 0.71, 0.84, 0.28 }, hoverBorder = { 0.84, 0.33, 0.29, 0.6 }, text = C.text, hoverText = C.badText },
    mark  = { bg = { 0, 0, 0, 0 }, hoverBg = { 0.82, 0.64, 0.30, 0.08 },
              border = { 0.63, 0.71, 0.84, 0.14 }, hoverBorder = { 0.82, 0.64, 0.30, 0.6 }, text = C.label, hoverText = C.textHi },
    done  = { bg = { 0.24, 0.69, 0.38, 0.12 }, hoverBg = { 0.24, 0.69, 0.38, 0.2 },
              border = { 0.24, 0.69, 0.38, 0.45 }, hoverBorder = { 0.24, 0.69, 0.38, 0.7 }, text = C.goodText, hoverText = C.goodText },
}

local function PaintButton(b)
    local v = VARIANT[b.variant] or VARIANT.ghost
    local hot = b.hot and b:IsEnabled()
    if v.gradient then
        b.bg:SetVertexColor(1, 1, 1, 1)
        W.Gradient(b.bg, "VERTICAL", C.goldDark, C.goldLight)
        b.hi:Show()
        b.glow:SetVertexColor(1, 1, 1, hot and 0.10 or 0)
    else
        local c = hot and v.hoverBg or v.bg
        W.Gradient(b.bg, "VERTICAL", c, c)
        b.hi:Hide()
        b.glow:SetVertexColor(1, 1, 1, 0)
    end
    W.SetBorder(b, hot and v.hoverBorder or v.border)
    b.label:SetTextColor(unpack(hot and v.hoverText or v.text))
    if v.shine and not b.shine then b.shine = A.Shine(b) end
    if b.shine then b.shine:SetShown(v.shine and true or false) end
    b:SetAlpha(b:IsEnabled() and 1 or 0.45)
end

-- variant: gold (primary, metallic, shine), ghost (secondary), quiet (cancel /
-- destructive on hover), mark (slider quick values), done (confirmed state).
function W.Button(parent, text, variant, width, height, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height or T.S.btnH)
    b.bg = W.Round(b, "BACKGROUND")
    b.bg:SetAllPoints()
    b.hi = W.Tex(b, "ARTWORK", { 1, 1, 1, 0.35 })
    b.hi:SetPoint("TOPLEFT", 6, -1); b.hi:SetPoint("TOPRIGHT", -6, -1); PixelUtil.SetHeight(b.hi, 1, 1)
    b.glow = W.Round(b, "ARTWORK", { 1, 1, 1, 0 })
    b.glow:SetAllPoints()
    W.Border(b)
    b.label = W.Text(b, style or "button")
    b.label:SetPoint("CENTER")
    b.label:SetText(text or "")

    b:SetScript("OnEnter", function(self) self.hot = true; PaintButton(self) end)
    b:SetScript("OnLeave", function(self) self.hot = false; PaintButton(self) end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("CENTER", 0, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnEnable", PaintButton)
    b:SetScript("OnDisable", PaintButton)

    function b:SetVariant(v) self.variant = v; PaintButton(self) end
    function b:SetLabel(t) self.label:SetText(t) end
    b:SetVariant(variant or "ghost")
    return b
end

-------------------------------------------------------------------------------
--  Chip (dungeon filter): optional icon, label, small colored extra text
-------------------------------------------------------------------------------
local function PaintChip(c)
    if c.on then
        W.Gradient(c.bg, "VERTICAL", { 0.82, 0.64, 0.30, 0.06 }, { 0.82, 0.64, 0.30, 0.16 })
        W.SetBorder(c, { 0.82, 0.64, 0.30, 0.75 })
        c.label:SetTextColor(unpack(C.textHi))
    else
        local bg = c.hot and C.raised or C.panel
        W.Gradient(c.bg, "VERTICAL", bg, bg)
        W.SetBorder(c, c.hot and { 0.63, 0.71, 0.84, 0.26 } or { 0.63, 0.71, 0.84, 0.11 })
        c.label:SetTextColor(unpack(c.hot and C.textHi or C.text2))
    end
end

function W.Chip(parent, text, icon, extra, extraColor)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(T.S.chipH)
    c.bg = W.Round(c, "BACKGROUND")
    c.bg:SetAllPoints()
    W.Border(c)
    local x = 12
    if icon then
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(20, 20)
        c.icon:SetPoint("LEFT", 6, 0)
        c.icon:SetTexture(icon)
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        x = 33
    end
    c.label = W.Text(c, "button")
    c.label:SetPoint("LEFT", x, 0)
    c.label:SetText(text)
    local w = x + c.label:GetStringWidth() + 12
    if extra then
        c.extra = W.Text(c, "tiny", extraColor)
        c.extra:SetPoint("LEFT", c.label, "RIGHT", 6, 0)
        c.extra:SetText(extra)
        w = w + 6 + c.extra:GetStringWidth()
    end
    c:SetWidth(math.ceil(w))
    c:SetScript("OnEnter", function(self) self.hot = true; PaintChip(self) end)
    c:SetScript("OnLeave", function(self) self.hot = false; PaintChip(self) end)
    c:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if self.onClick then self.onClick(self) end
    end)
    function c:SetOn(on) self.on = on and true or false; PaintChip(self) end
    c:SetOn(false)
    return c
end

-------------------------------------------------------------------------------
--  Toggle (checkbox look): box, optional glyph, label
-------------------------------------------------------------------------------
local function PaintToggle(t)
    if t.checked then
        W.SetBorder(t, { 0.82, 0.64, 0.30, 0.7 })
        t.bg:SetVertexColor(0.82, 0.64, 0.30, 0.09)
        t.boxFill:Show()
        W.SetBorder(t.box, C.gold)
        t.label:SetTextColor(unpack(C.textHi))
    else
        W.SetBorder(t, t.hot and { 0.63, 0.71, 0.84, 0.26 } or { 0.63, 0.71, 0.84, 0.11 })
        t.bg:SetVertexColor(unpack(C.panel))
        t.boxFill:Hide()
        W.SetBorder(t.box, C.faint)
        t.label:SetTextColor(unpack(t.hot and C.textHi or C.text2))
    end
end

-- glyph / glyphColor: e.g. "lust", C.lust.
function W.Toggle(parent, text, glyph, glyphColor, height)
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(height or 30)
    t.bg = W.Round(t, "BACKGROUND")
    t.bg:SetAllPoints()
    W.Border(t)
    t.box = CreateFrame("Frame", nil, t)
    t.box:SetSize(12, 12)
    t.box:SetPoint("LEFT", 10, 0)
    W.Lines(t.box)
    t.boxFill = W.Tex(t.box, "ARTWORK")
    t.boxFill:SetAllPoints()
    W.Gradient(t.boxFill, "VERTICAL", C.goldDark, C.goldLight)
    local x = 30
    if glyph then
        t.icon = W.Glyph(t, glyph, 22, glyphColor)
        t.icon:SetPoint("LEFT", x - 4, 0)
        x = x + 18
    end
    t.label = W.Text(t, "bodySm")
    t.label:SetPoint("LEFT", x, 0)
    t.label:SetText(text)
    t:SetWidth(math.ceil(x + t.label:GetStringWidth() + 12))
    t:SetScript("OnEnter", function(self) self.hot = true; PaintToggle(self) end)
    t:SetScript("OnLeave", function(self) self.hot = false; PaintToggle(self) end)
    t:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if self.onChange then self.onChange(self.checked) end
    end)
    function t:SetChecked(v) self.checked = v and true or false; PaintToggle(self) end
    t:SetChecked(false)
    return t
end

-------------------------------------------------------------------------------
--  Switch (settings): a small track with a knob, gold when on
-------------------------------------------------------------------------------
local function PaintSwitch(s)
    local on = s.checked
    s.bg:SetVertexColor(unpack(on and { 0.82, 0.64, 0.30, 0.25 } or C.track))
    W.SetBorder(s, on and { 0.82, 0.64, 0.30, 0.6 } or (s.hot and { 0.63, 0.71, 0.84, 0.3 } or C.lineStrong))
    s.knob:SetVertexColor(unpack(on and C.goldLight or C.muted))
    s.knob:ClearAllPoints()
    s.knob:SetPoint("CENTER", s, on and "RIGHT" or "LEFT", on and -11 or 11, 0)
end

function W.Switch(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(38, 22)
    s.bg = W.Round(s, "BACKGROUND")
    s.bg:SetAllPoints()
    W.Border(s)
    s.knob = W.Circle(s, "ARTWORK", nil, 14)
    s:SetScript("OnEnter", function(self) self.hot = true; PaintSwitch(self) end)
    s:SetScript("OnLeave", function(self) self.hot = false; PaintSwitch(self) end)
    s:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if self.onChange then self.onChange(self.checked) end
    end)
    function s:SetChecked(v) self.checked = v and true or false; PaintSwitch(self) end
    s:SetChecked(false)
    return s
end

-------------------------------------------------------------------------------
--  Segmented: one choice out of a few ({ { key, label }, ... }), anchored
--  by its LEFT edge. onChange(key) after a click.
-------------------------------------------------------------------------------
function W.Segmented(parent, items, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or 28)
    f.buttons = {}
    local x = 0
    for _, it in ipairs(items) do
        local b = W.Button(f, it[2], "mark", nil, height or 28, "tiny")
        b:SetWidth(math.ceil(b.label:GetStringWidth() + 20))
        b:SetPoint("LEFT", x, 0)
        x = x + b:GetWidth() + 4
        b:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            f:SetValue(it[1])
            if f.onChange then f.onChange(it[1]) end
        end)
        f.buttons[it[1]] = b
    end
    f:SetWidth(math.max(1, x - 4))
    function f:SetValue(key)
        self.value = key
        for k, b in pairs(self.buttons) do b:SetVariant(k == key and "ghost" or "mark") end
    end
    return f
end

-------------------------------------------------------------------------------
--  Tabs: labels with a gold underline that grows out of the active one
-------------------------------------------------------------------------------
function W.Tabs(parent, names, onSelect)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(T.S.tabs)
    local line = W.Tex(bar, "BACKGROUND", C.line)
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); PixelUtil.SetHeight(line, 1, 1)

    local ul = CreateFrame("Frame", nil, bar)
    ul:SetHeight(2)
    local l = W.Tex(ul, "OVERLAY"); l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMRIGHT", ul, "BOTTOM")
    W.Gradient(l, "HORIZONTAL", C.goldDark, C.goldLight)
    local r = W.Tex(ul, "OVERLAY"); r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMLEFT", ul, "BOTTOM")
    W.Gradient(r, "HORIZONTAL", C.goldLight, C.goldDark)
    local glow = W.Tex(ul, "ARTWORK", { 0.82, 0.64, 0.30, 0.18 })
    glow:SetPoint("TOPLEFT", -4, 4); glow:SetPoint("BOTTOMRIGHT", 4, 0)

    bar.tabs = {}
    local x = 0
    for i, name in ipairs(names) do
        local b = CreateFrame("Button", nil, bar)
        b.label = W.Text(b, "tab")
        b.label:SetPoint("LEFT")
        b.label:SetText(name)
        b.badge = CreateFrame("Frame", nil, b)
        b.badge:SetSize(20, 20)
        b.badge:SetPoint("LEFT", b.label, "RIGHT", 7, 0)
        b.badge.bg = W.Circle(b.badge, "BACKGROUND", nil, 20)
        b.badge.bg:SetPoint("CENTER")
        W.Gradient(b.badge.bg, "VERTICAL", C.goldDark, C.goldLight)
        b.badge.text = W.Text(b.badge, "tiny", C.onGold)
        b.badge.text:SetPoint("CENTER", 0, 0)
        b.badge:Hide()
        b:SetHeight(T.S.tabs)
        b:SetPoint("BOTTOMLEFT", x, 0)
        b:SetWidth(b.label:GetStringWidth() + 2)
        b:SetScript("OnEnter", function(self) if bar.active ~= self.index then self.label:SetTextColor(unpack(C.text)) end end)
        b:SetScript("OnLeave", function(self) if bar.active ~= self.index then self.label:SetTextColor(unpack(C.muted)) end end)
        b:SetScript("OnClick", function(self) bar:Select(self.index) end)
        b.index = i
        bar.tabs[i] = b
        x = x + b:GetWidth() + 26
    end

    function bar:SetBadge(i, n)
        local b = self.tabs[i]
        b.badge:SetShown(n and n > 0)
        b.badge.text:SetText(n or "")
        b:SetWidth(b.label:GetStringWidth() + 2 + ((n and n > 0) and 27 or 0))
        local xx = 0
        for _, t in ipairs(self.tabs) do t:SetPoint("BOTTOMLEFT", xx, 0); xx = xx + t:GetWidth() + 26 end
        if self.active then self:Select(self.active, true) end
    end

    function bar:Select(i, quiet)
        local changed = self.active ~= i
        self.active = i
        for j, t in ipairs(self.tabs) do t.label:SetTextColor(unpack(j == i and C.textHi or C.muted)) end
        local t = self.tabs[i]
        ul:ClearAllPoints()
        ul:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
        ul:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
        if changed and not quiet then
            A.Grow(ul)
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            if onSelect then onSelect(i) end
        end
    end
    return bar
end

-------------------------------------------------------------------------------
--  Slider and RangeSlider
--   A minimum: left of the thumb is dimmed (rating, over a gradient track),
--   or the gold fill runs from the thumb to the right end (item level).
--  Dragging runs an OnUpdate only while the mouse button is held.
-------------------------------------------------------------------------------
local function Thumb(parent)
    local th = CreateFrame("Frame", nil, parent)
    th:SetSize(16, 16)
    th.glow = W.Circle(th, "BACKGROUND", { 0.82, 0.64, 0.30, 0.16 }, 26)
    th.glow:SetPoint("CENTER")
    th.ring = W.Circle(th, "BORDER", C.gold, 16)
    th.ring:SetPoint("CENTER")
    th.core = W.Circle(th, "ARTWORK", nil, 12)
    th.core:SetPoint("CENTER")
    W.Gradient(th.core, "VERTICAL", { 0.89, 0.91, 0.94, 1 }, { 1, 1, 1, 1 })
    return th
end

local function SetHot(th, hot)
    th.glow:SetSize(hot and 32 or 26, hot and 32 or 26)
    th.glow:SetVertexColor(0.82, 0.64, 0.30, hot and 0.28 or 0.16)
end

local function Track(s, stops)
    s.track = W.Tex(s, "BACKGROUND", C.track)
    s.track:SetHeight(4)
    s.track:SetPoint("LEFT"); s.track:SetPoint("RIGHT")
    s.segs = {}
    if stops then
        for i = 1, #stops - 1 do
            local seg = W.Tex(s, "BACKGROUND", nil, 1)
            seg:SetHeight(4)
            W.Gradient(seg, "HORIZONTAL", stops[i][2], stops[i + 1][2])
            seg.from, seg.to = stops[i][1], stops[i + 1][1]
            s.segs[#s.segs + 1] = seg
        end
    end
end

local function Frac(s, v) return (v - s.lo) / (s.hi - s.lo) end

local function CursorValue(s)
    local x = GetCursorPosition() / s:GetEffectiveScale()
    local f = (x - s:GetLeft()) / max(1, s:GetWidth())
    f = min(1, max(0, f))
    return s.lo + floor((s.hi - s.lo) * f / s.step + 0.5) * s.step
end

local function Drag(s)
    if not IsMouseButtonDown("LeftButton") then
        s:SetScript("OnUpdate", nil)
        return
    end
    s:Pick(CursorValue(s))
end

local function Interactive(s)
    s:EnableMouse(true)
    s:SetScript("OnMouseDown", function(self)
        self:Grab(CursorValue(self))
        self:SetScript("OnUpdate", Drag)
    end)
    s:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    s:SetScript("OnEnter", function(self) self:Hot(true) end)
    s:SetScript("OnLeave", function(self) self:Hot(false) end)
end

-- opts: min, max, step, value, stops (gradient track), fill (gold fill to the
-- right instead of dimming the left; fill = "left": up to the thumb), marker
-- (a value, e.g. your own rating).
function W.Slider(parent, opts)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(22)
    s.lo, s.hi, s.step = opts.min or 0, opts.max or 100, opts.step or 1
    s.fillLeft = opts.fill == "left"
    Track(s, opts.stops)
    if opts.fill then
        s.fill = W.Tex(s, "BACKGROUND", nil, 2)
        s.fill:SetHeight(4)
        W.Gradient(s.fill, "HORIZONTAL", C.goldDark, C.goldLight)
    else
        s.dim = W.Tex(s, "BACKGROUND", { 0.04, 0.055, 0.08, 0.8 }, 3)
        s.dim:SetHeight(4)
    end
    if opts.marker then
        s.marker = W.Tex(s, "ARTWORK", { 0.96, 0.97, 0.98, 0.55 })
        s.marker:SetSize(2, 16)
        s.markerValue = opts.marker
    end
    s.thumb = Thumb(s)

    function s:Layout()
        local w = self:GetWidth()
        if w <= 0 or not self.value then return end
        for _, seg in ipairs(self.segs) do
            seg:ClearAllPoints()
            seg:SetPoint("LEFT", self, "LEFT", seg.from * w, 0)
            seg:SetWidth(max(1, (seg.to - seg.from) * w))
        end
        local x = Frac(self, self.value) * w
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("CENTER", self, "LEFT", x, 0)
        if self.fill and self.fillLeft then
            self.fill:ClearAllPoints()
            self.fill:SetPoint("LEFT")
            self.fill:SetWidth(max(1, x))
        elseif self.fill then
            self.fill:ClearAllPoints()
            self.fill:SetPoint("LEFT", self, "LEFT", x, 0)
            self.fill:SetPoint("RIGHT")
        else
            self.dim:ClearAllPoints()
            self.dim:SetPoint("LEFT")
            self.dim:SetWidth(max(1, x))
            self.dim:SetShown(x > 0.5)
        end
        if self.marker then
            self.marker:ClearAllPoints()
            self.marker:SetPoint("CENTER", self, "LEFT", Frac(self, self.markerValue) * w, 0)
        end
    end

    function s:SetValue(v, fire)
        v = min(self.hi, max(self.lo, v))
        local changed = v ~= self.value
        self.value = v
        self:Layout()
        if fire and changed and self.onChange then self.onChange(v) end
    end
    function s:Grab(v) self:SetValue(v, true) end
    function s:Pick(v) self:SetValue(v, true) end
    function s:Hot(h) SetHot(self.thumb, h) end

    Interactive(s)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, d) self:SetValue(self.value + d * self.step, true) end)
    s:SetScript("OnSizeChanged", s.Layout)
    s:SetValue(opts.value or s.lo)
    return s
end

-- Two thumbs; the gold fill spans the range. onChange(lo, hi).
function W.RangeSlider(parent, opts)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(22)
    s.lo, s.hi, s.step = opts.min or 0, opts.max or 100, opts.step or 1
    Track(s)
    s.fill = W.Tex(s, "BACKGROUND", nil, 2)
    s.fill:SetHeight(4)
    W.Gradient(s.fill, "HORIZONTAL", C.goldDark, C.goldLight)
    s.a, s.b = Thumb(s), Thumb(s)

    function s:Layout()
        local w = self:GetWidth()
        if w <= 0 or not self.va then return end
        local xa, xb = Frac(self, self.va) * w, Frac(self, self.vb) * w
        self.a:ClearAllPoints(); self.a:SetPoint("CENTER", self, "LEFT", xa, 0)
        self.b:ClearAllPoints(); self.b:SetPoint("CENTER", self, "LEFT", xb, 0)
        self.fill:ClearAllPoints()
        self.fill:SetPoint("LEFT", self, "LEFT", xa, 0)
        self.fill:SetWidth(max(1, xb - xa))
    end

    function s:SetValues(va, vb, fire)
        va = min(self.hi, max(self.lo, va)); vb = min(self.hi, max(self.lo, vb))
        if va > vb then va, vb = vb, va end
        local changed = va ~= self.va or vb ~= self.vb
        self.va, self.vb = va, vb
        self:Layout()
        if fire and changed and self.onChange then self.onChange(va, vb) end
    end
    -- The thumb nearest to the click follows the mouse.
    function s:Grab(v)
        self.which = math.abs(v - self.va) <= math.abs(v - self.vb) and "a" or "b"
        if self.va == self.vb then self.which = v < self.va and "a" or "b" end
        self:Pick(v)
    end
    function s:Pick(v)
        if self.which == "a" then self:SetValues(min(v, self.vb), self.vb, true)
        else self:SetValues(self.va, max(v, self.va), true) end
    end
    function s:Hot(h) SetHot(self.a, h); SetHot(self.b, h) end

    Interactive(s)
    s:SetScript("OnSizeChanged", s.Layout)
    s:SetValues(opts.from or s.lo, opts.to or s.hi)
    return s
end

-------------------------------------------------------------------------------
--  Histogram: bars over a slider. SetData(counts, colorOf(i), dimmed(i))
-------------------------------------------------------------------------------
function W.Histogram(parent, bins)
    local h = CreateFrame("Frame", nil, parent)
    h.bars = {}
    for i = 1, bins do h.bars[i] = W.Tex(h, "ARTWORK") end
    function h:Layout()
        local w, ht = self:GetWidth(), self:GetHeight()
        if w <= 0 or not self.counts then return end
        local n, gap = #self.bars, 2
        local bw = (w - (n - 1) * gap) / n
        local peak = 1
        for _, c in ipairs(self.counts) do peak = max(peak, c) end
        for i, bar in ipairs(self.bars) do
            local c = self.counts[i] or 0
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", (i - 1) * (bw + gap), 0)
            bar:SetWidth(max(1, bw))
            bar:SetHeight(c > 0 and (6 + c / peak * (ht - 6)) or 2)
            local col = self.colorOf and self.colorOf(i) or C.gold
            bar:SetVertexColor(col[1], col[2], col[3], (self.dimmed and self.dimmed(i)) and 0.18 or 0.85)
        end
    end
    function h:SetData(counts, colorOf, dimmed)
        self.counts, self.colorOf, self.dimmed = counts, colorOf or self.colorOf, dimmed or self.dimmed
        self:Layout()
    end
    h:SetScript("OnSizeChanged", h.Layout)
    return h
end

-------------------------------------------------------------------------------
--  Meter: thin value bar (rating, item level)
-------------------------------------------------------------------------------
function W.Meter(parent, width)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(width or 72, 3)
    m.track = W.Tex(m, "BACKGROUND", C.track)
    m.track:SetAllPoints()
    m.fill = W.Tex(m, "ARTWORK")
    m.fill:SetPoint("TOPLEFT"); m.fill:SetPoint("BOTTOMLEFT")
    -- frac 0..1; color, or nil for the gold gradient.
    function m:SetValue(frac, color)
        self.fill:SetWidth(max(1, min(1, max(0, frac)) * self:GetWidth()))
        if color then
            self.fill:SetGradient("HORIZONTAL", CreateColor(unpack(color)), CreateColor(unpack(color)))
        else
            W.Gradient(self.fill, "HORIZONTAL", C.goldDark, C.goldLight)
        end
    end
    return m
end

-------------------------------------------------------------------------------
--  Pill: small rounded tag (playstyle, requirements). Value parts can be
--  colored inline: "Rating |cffb57cff2100+|r".
-------------------------------------------------------------------------------
function W.Pill(parent, text, border, bg)
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(24)
    p.bg = W.Round(p, "BACKGROUND", bg or { 0.04, 0.055, 0.08, 0.55 })
    p.bg:SetAllPoints()
    W.Border(p, border or C.lineStrong)
    p.text = W.Text(p, "button", C.text2)
    p.text:SetPoint("LEFT", 9, 0)
    -- Measured again a frame later: the first measure can come before the
    -- font file is loaded and be too narrow.
    local function Fit() p:SetWidth(math.ceil(p.text:GetStringWidth() + 18)) end
    function p:SetText(t)
        self.text:SetText(t)
        Fit()
        C_Timer.After(0, Fit)
    end
    p:SetScript("OnShow", Fit)
    p:SetText(text or "")
    return p
end

-- Deserter tag: a rose pill with a slow, soft shine (Keystone Deserters).
-- Noticeable without shouting: the band passes every few seconds, on all
-- tags at once and at the same speed (one clock, running only while a tag
-- is visible).
local deserterTags, deserterClock = {}, nil
local function SweepDeserters()
    local any = false
    for _, p in ipairs(deserterTags) do
        if p:IsVisible() then any = true; p.shine.Sweep() end
    end
    if not any then deserterClock:Cancel(); deserterClock = nil end
end

function W.DeserterTag(parent, text)
    local c = C.deserter
    local p = W.Pill(parent, nil, { c[1], c[2], c[3], 0.6 }, { c[1], c[2], c[3], 0.14 })
    p:SetHeight(18)
    p.text:SetFontObject(T.Font.tiny)
    p.text:SetTextColor(unpack(c))
    p:SetText(text or "DESERTER")
    p.shine = A.Shine(p, nil, 0.3, true)
    p:HookScript("OnShow", function()
        if not deserterClock then deserterClock = C_Timer.NewTicker(4.5, SweepDeserters) end
    end)
    deserterTags[#deserterTags + 1] = p
    return p
end

-------------------------------------------------------------------------------
--  RoleBadge: dark disc, the role glyph in the member's class color (as
--  Blizzard tints them); open spots grey with a dashed ring.
-------------------------------------------------------------------------------
local ROLE_GLYPH = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local GLYPH_TEX = {}
for role, g in pairs(ROLE_GLYPH) do GLYPH_TEX[role] = TEX .. "glyph-" .. g end

function W.RoleBadge(parent, size)
    size = size or 28
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.disc = W.Circle(f, "BACKGROUND", C.badge, size)
    f.disc:SetPoint("CENTER")
    f.ring = f:CreateTexture(nil, "BORDER")
    f.ring:SetAllPoints()
    f.glyph = f:CreateTexture(nil, "ARTWORK")
    f.glyph:SetAllPoints()
    -- role: TANK / HEALER / DAMAGER; classFile nil = open spot, true =
    -- filled but the class is unknown.
    function f:Set(role, classFile)
        self.glyph:SetTexture(GLYPH_TEX[role] or GLYPH_TEX.DAMAGER)
        if classFile then
            self.disc:SetVertexColor(unpack(C.badge))
            self.ring:SetTexture(TEX .. "ring")
            self.ring:SetVertexColor(unpack(C.lineStrong))
            self.glyph:SetVertexColor(unpack(type(classFile) == "string" and T.ClassColor(classFile) or C.text2))
        else
            self.disc:SetVertexColor(unpack(C.empty))
            self.ring:SetTexture(TEX .. "ring-dashed")
            self.ring:SetVertexColor(0.23, 0.27, 0.34, 1)
            self.glyph:SetVertexColor(unpack(C.faint))
        end
    end
    return f
end

-------------------------------------------------------------------------------
--  Members view: role glyphs only ("role", default) or with each member's
--  spec ("spec"). One account-wide setting (GottaQueueEmAllDB.ui.memberView),
--  one switch per Browse page; flipping one repaints them all.
-------------------------------------------------------------------------------
function W.SpecView()
    local db = ns.DB and ns.DB()
    return db and db.ui and db.ui.memberView == "spec" or false
end

-- Short spec names, as players write them; other names up to six letters
-- stay whole (Arcane, Unholy), longer ones (other client languages) are cut
-- to five.
local SPEC_SHORT = {
    ["Demonology"] = "Demo", ["Destruction"] = "Destro", ["Affliction"] = "Affli", ["Protection"] = "Prot",
    ["Retribution"] = "Ret", ["Restoration"] = "Resto", ["Discipline"] = "Disc", ["Assassination"] = "Assa",
    ["Subtlety"] = "Sub", ["Beast Mastery"] = "BM", ["Marksmanship"] = "MM", ["Survival"] = "Surv",
    ["Elemental"] = "Ele", ["Enhancement"] = "Enh", ["Brewmaster"] = "Brew", ["Mistweaver"] = "MW",
    ["Windwalker"] = "WW", ["Vengeance"] = "Veng", ["Devastation"] = "Dev", ["Preservation"] = "Pres",
    ["Augmentation"] = "Aug", ["Guardian"] = "Guard", ["Balance"] = "Boomy", ["Devourer"] = "Devo",
}
function W.SpecShort(spec)
    if not spec then return "" end
    if SPEC_SHORT[spec] then return SPEC_SHORT[spec] end
    local chars = {}
    for ch in spec:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end   -- by character, not byte
    if #chars <= 6 then return spec end
    return table.concat(chars, "", 1, 5)
end

local viewSwitches = {}

-- "View  [Role] [Spec]", anchored by its RIGHT edge (call :SetPoint on
-- the returned frame). onChange: the page's render.
function W.ViewSwitch(parent, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(1, 26)
    f.onChange = onChange
    f.buttons = {}
    local right
    for _, v in ipairs({ { "spec", "Spec" }, { "role", "Role" } }) do
        local b = W.Button(f, v[2], "mark", nil, 26, "tiny")
        b:SetWidth(b.label:GetStringWidth() + 18)
        if right then b:SetPoint("RIGHT", right, "LEFT", -4, 0) else b:SetPoint("RIGHT") end
        b:SetScript("OnClick", function()
            local db = ns.DB and ns.DB()
            if not db then return end
            db.ui = db.ui or {}
            db.ui.memberView = v[1]
            for _, s in ipairs(viewSwitches) do
                s:Paint()
                if s.onChange then s.onChange() end
            end
        end)
        f.buttons[v[1]] = b
        right = b
    end
    local l = W.Text(f, "small")
    l:SetPoint("RIGHT", right, "LEFT", -8, 0)
    l:SetText("View")   -- short: it shares row 2 with the toggles and Sort
    f.left = l   -- what a neighbor anchors to
    function f:Paint()
        local cur = W.SpecView() and "spec" or "role"
        for k, b in pairs(self.buttons) do b:SetVariant(k == cur and "ghost" or "mark") end
    end
    f:Paint()
    viewSwitches[#viewSwitches + 1] = f
    return f
end

-------------------------------------------------------------------------------
--  Banner: Blizzard's own dungeon art
-------------------------------------------------------------------------------
-- Art on the right, running out into navy on the left. behind = the color
-- around the banner (for its rounded corners over the art).
function W.Banner(parent, behind)
    local b = CreateFrame("Frame", nil, parent)
    b.base = W.Round(b, "BACKGROUND", C.navy)
    b.base:SetAllPoints()
    b.art = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.art:SetPoint("TOPRIGHT"); b.art:SetPoint("BOTTOMRIGHT")   -- flush; the border is drawn over it
    b.fade = W.Tex(b, "BACKGROUND", nil, 2)
    b.fade:SetPoint("TOPLEFT", b.art, "TOPLEFT"); b.fade:SetPoint("BOTTOMLEFT", b.art, "BOTTOMLEFT")
    W.Gradient(b.fade, "HORIZONTAL", C.navy, { C.navy[1], C.navy[2], C.navy[3], 0 })
    b.shade = W.Tex(b, "BACKGROUND", nil, 3)
    b.shade:SetPoint("BOTTOMLEFT", 1, 1); b.shade:SetPoint("BOTTOMRIGHT", -1, 1); b.shade:SetHeight(48)
    W.Gradient(b.shade, "VERTICAL", { 0, 0, 0, 0.45 }, { 0, 0, 0, 0 })
    W.CornerCaps(b, b.art, behind or C.bg, { TR = true, BR = true })
    W.Border(b, C.lineStrong, "OVERLAY", 2)
    -- Cover-style crop: keep the art's aspect, cut top and bottom evenly.
    -- box = { l, r, t, b }: the part of the file that holds the picture.
    function b:Layout()
        local w, h = self:GetWidth(), self:GetHeight()
        if w <= 0 or h <= 0 then return end
        local aw = w * 0.68
        self.art:SetWidth(aw)
        self.fade:SetWidth(aw * 0.55)
        local l, r, t, bt = unpack(self.box or { 0, 1, 0, 1 })
        local v = min(1, (self.srcAspect or 2) / (aw / h))   -- visible share of the picture's height
        local mid, half = (t + bt) / 2, (bt - t) * v / 2
        self.art:SetTexCoord(l, r, mid - half, mid + half)
    end
    b:SetScript("OnSizeChanged", b.Layout)
    -- texture: file ID; srcAspect: the picture's width / height; box: see Layout.
    function b:SetArt(texture, srcAspect, box)
        self.art:SetTexture(texture)
        self.srcAspect, self.box = srcAspect or 2, box
        self.art:SetShown(texture ~= nil)
        self:Layout()
    end
    return b
end

-------------------------------------------------------------------------------
--  Card: a list row that lifts on hover
-------------------------------------------------------------------------------
function W.Card(parent)
    local c = CreateFrame("Button", nil, parent)
    c.bg = W.Round(c, "BACKGROUND", C.panel)
    c.bg:SetAllPoints()
    W.Border(c, nil, "OVERLAY", 2)   -- above card art and its corner caps
    c:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(unpack(C.raised))
        W.SetBorder(self, { 0.82, 0.64, 0.30, 0.4 })
        if self.onEnter then self.onEnter(self) end
    end)
    c:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(unpack(C.panel))
        W.SetBorder(self, C.line)
        if self.onLeave then self.onLeave(self) end
    end)
    return c
end
