-------------------------------------------------------------------------------
--  UI/Welcome.lua  --  the first-start screen
--
--  Covers the window below the header the first time it opens: what the
--  three sections are (each with Open), the three steps, hotkey and minimap
--  button, Start. Shown once (GottaQueueEmAllDB.welcomed); /gotta welcome
--  brings it back. Picking a section anywhere dismisses it.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A = UI.Theme, UI.W, UI.Anim
local C, S = T.C, T.S

local WL = {}
UI.Welcome = WL

local BOX_W = 860
local GAP = 10

local SECTIONS = {
    { "mplus",   "Mythic+",  "The key level read from every title. Filter and sort by it." },
    { "raid",    "Raid",     "Current raids and Season 1, with your lockouts." },
    { "dungeon", "Mythic 0", "This season's dungeons on Mythic, no keystone." },
}
local STEPS = {
    { "1 · Browse",     "Pick dungeons, search, sign up." },
    { "2 · + Create",   "Type a title, list your group." },
    { "3 · Your Group", "Invite or decline applicants." },
}

local function DB() return ns.DB and ns.DB() end

-- Wrapped body text between two edges of its parent.
local function Body(parent, text, top)
    local fs = W.Text(parent, "bodySm")
    fs:SetWordWrap(true)
    fs:SetJustifyV("TOP")
    fs:SetPoint("TOPLEFT", 12, top)
    fs:SetPoint("TOPRIGHT", -12, top)
    fs:SetText(text)
    return fs
end

-- win: the window; onPick(key) opens a section.
function WL.Build(win, onPick)
    local f = CreateFrame("Frame", nil, win)
    f:SetPoint("TOPLEFT", 0, -S.header)
    f:SetPoint("BOTTOMRIGHT")
    -- Above the pages and their secure overlays, and it takes their clicks.
    f:SetFrameLevel(win:GetFrameLevel() + 200)
    f:EnableMouse(true)
    f:Hide()
    f.bg = W.Round(f, "BACKGROUND", C.bg)
    f.bg:SetAllPoints()
    -- A soft gold light from the top.
    local glow = W.Tex(f, "BACKGROUND", nil, 1)
    glow:SetPoint("TOPLEFT", 1, 0); glow:SetPoint("TOPRIGHT", -1, 0)
    glow:SetHeight(180)
    W.Gradient(glow, "VERTICAL", { 0.82, 0.64, 0.30, 0 }, { 0.82, 0.64, 0.30, 0.08 })

    local box = CreateFrame("Frame", nil, f)
    box:SetSize(BOX_W, 456)   -- hero 176, sections 22 + 92, steps 10 + 66, row 22 + 40, note 12 + 16
    box:SetPoint("CENTER", 0, 4)
    local parts = {}

    -- Logo, title, line
    local hero = CreateFrame("Frame", nil, box)
    hero:SetPoint("TOPLEFT"); hero:SetPoint("TOPRIGHT")
    hero:SetHeight(176)
    local logo = hero:CreateTexture(nil, "ARTWORK")
    logo:SetSize(76, 76)
    logo:SetPoint("TOP")
    logo:SetTexture(T.MEDIA .. "logo-qlens-mark")
    local title = W.Text(hero, "display")
    title:SetPoint("TOP", logo, "BOTTOM", 0, -10)
    title:SetText("Welcome to Gotta Queue 'Em All")
    local sub = W.Text(hero, "body", C.muted)
    sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
    sub:SetText("Find groups and list your own. Blizzard's window stays closed.")
    for i, side in ipairs({ "RIGHT", "LEFT" }) do   -- the tabs' gold line, fading out both ways
        local l = W.Tex(hero, "ARTWORK")
        l:SetSize(80, 2)
        l:SetPoint(side, hero, "BOTTOM", 0, 0)
        if i == 1 then W.Gradient(l, "HORIZONTAL", { 0.82, 0.64, 0.30, 0 }, C.goldLight)
        else W.Gradient(l, "HORIZONTAL", C.goldLight, { 0.82, 0.64, 0.30, 0 }) end
    end
    parts[#parts + 1] = hero

    -- The three sections
    local pw = (BOX_W - 2 * GAP) / 3
    for i, s in ipairs(SECTIONS) do
        local p = W.Panel(box)
        p:SetSize(pw, 92)
        p:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", (i - 1) * (pw + GAP), -22)
        local open = W.Button(p, "Open", "ghost", 76, 28)
        open:SetPoint("TOPRIGHT", -10, -8)
        open:SetScript("OnClick", function() onPick(s[1]) end)
        local lbl = W.Label(p, s[2])
        lbl:SetPoint("LEFT", p, "TOPLEFT", 12, -22)   -- centered on the button's height
        Body(p, s[3], -44)
        parts[#parts + 1] = p
    end

    -- The three steps
    local steps = W.Panel(box)
    steps:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -22 - 92 - GAP)
    steps:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -22 - 92 - GAP)
    steps:SetHeight(66)
    local sw = BOX_W / 3
    for i, s in ipairs(STEPS) do
        local col = CreateFrame("Frame", nil, steps)
        col:SetPoint("TOPLEFT", (i - 1) * sw, 0)
        col:SetSize(sw, 66)
        local lbl = W.Label(col, s[1])
        lbl:SetTextColor(unpack(C.goldText))
        lbl:SetPoint("TOPLEFT", 12, -12)
        Body(col, s[2], -32)
        if i > 1 then
            local sep = W.Tex(steps, "ARTWORK", C.line)
            sep:SetPoint("TOPLEFT", (i - 1) * sw, -12)
            sep:SetPoint("BOTTOMLEFT", (i - 1) * sw, 12)
            PixelUtil.SetWidth(sep, 1, 1)
        end
    end
    parts[#parts + 1] = steps

    -- Hotkey, minimap button, Start
    local row = CreateFrame("Frame", nil, box)
    row:SetPoint("TOPLEFT", steps, "BOTTOMLEFT", 0, -22)
    row:SetPoint("TOPRIGHT", steps, "BOTTOMRIGHT", 0, -22)
    row:SetHeight(40)
    local hk = W.Label(row, "Hotkey")
    hk:SetPoint("LEFT")
    local hotkey = UI.Launcher.HotkeyButton(row)
    hotkey:SetPoint("LEFT", hk, "RIGHT", 10, 0)
    local mm = W.Toggle(row, "Minimap button")
    mm:SetPoint("LEFT", hotkey, "RIGHT", 18, 0)
    mm.onChange = function(on)
        local db = DB()
        if not db then return end
        -- Through the settings page's setting too, so it shows the same.
        if Settings and Settings.SetValue then pcall(Settings.SetValue, "GottaQueueEmAll_showMinimap", on) end
        db.showMinimap = on
        UI.Launcher.Update()
    end
    f.minimap = mm
    local start = W.Button(row, "Start", "gold", 150, 40, "h2")
    start:SetPoint("RIGHT")
    start:SetScript("OnClick", function() onPick("mplus") end)
    parts[#parts + 1] = row

    local note = W.Text(box, "small")
    note:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, -12)
    note:SetText("Shown once  ·  /gotta welcome brings it back")
    parts[#parts + 1] = note

    f:SetScript("OnShow", function()
        local db = DB()
        mm:SetChecked(not db or db.showMinimap ~= false)
        for i, r in ipairs(parts) do A.Rise(r, (i - 1) * 0.06) end
    end)
    WL.frame = f
    return f
end

-- Not seen yet on this account.
function WL.Due()
    local db = DB()
    return db and not db.welcomed
end

function WL.Show()
    if WL.frame then WL.frame:Show() end
end

-- Dismissed: not shown again by itself.
function WL.Done()
    local db = DB()
    if db then db.welcomed = true end
    if WL.frame and WL.frame:IsShown() then WL.frame:Hide() end
end
