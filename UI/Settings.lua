-------------------------------------------------------------------------------
--  UI/Settings.lua  --  the settings page in the window
--
--  The gear, the minimap button's right-click and /gotta settings open it.
--  It covers the tabs and pages (the header and footer stay); Back closes
--  it. Saved per account in GottaQueueEmAllDB, like everything else.
--  Blizzard's Options > AddOns page keeps a short entry that links here.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A = UI.Theme, UI.W, UI.Anim
local C, S = T.C, T.S

local SE = {}
UI.Settings = SE

local ROW_H, WIDE_H, HEAD_H = 54, 86, 36

local function DB() return ns.DB and ns.DB() end

-------------------------------------------------------------------------------
--  Panels and rows
-------------------------------------------------------------------------------
-- A panel with a heading; rows are stacked with panel:Row(...).
local function Panel(parent, title)
    local p = W.Panel(parent)
    local h = W.Label(p, title)
    h:SetPoint("TOPLEFT", 16, -14)
    p.y = -HEAD_H
    -- title, description; the control is placed by the caller on row.c
    -- (anchored to the row's RIGHT). wide: the control goes below the text;
    -- reserve: room kept for the control (px from the right edge).
    function p:Row(titleText, desc, wide, reserve)
        local r = CreateFrame("Frame", nil, self)
        r:SetPoint("TOPLEFT", 0, self.y)
        r:SetPoint("TOPRIGHT", 0, self.y)
        r:SetHeight(wide and WIDE_H or ROW_H)
        if self.y < -HEAD_H then   -- a line between rows
            local l = W.Tex(r, "BORDER", C.line)
            l:SetPoint("TOPLEFT", 16, 0); l:SetPoint("TOPRIGHT", -16, 0); PixelUtil.SetHeight(l, 1, 1)
        end
        r.title = W.Text(r, "button", C.text)
        r.title:SetPoint("TOPLEFT", 16, -10)
        r.title:SetText(titleText)
        r.desc = W.Text(r, "small")
        r.desc:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
        r.desc:SetText(desc or "")
        if not wide then r.desc:SetPoint("RIGHT", r, "RIGHT", -(reserve or 150), 0) end
        self.y = self.y - r:GetHeight()
        self:SetHeight(-self.y + 4)
        return r
    end
    return p
end

-- A switch for a boolean saved setting; onChange(value) after the save.
local switches = {}
local function SwitchRow(panel, key, titleText, desc, onChange, reserve)
    local r = panel:Row(titleText, desc, false, reserve)
    local s = W.Switch(r)
    s:SetPoint("RIGHT", -16, 0)
    s.onChange = function(on)
        local db = DB()
        if db then db[key] = on end
        if onChange then onChange(on) end
        SE.Paint()
    end
    switches[key] = s
    return r, s
end

-------------------------------------------------------------------------------
--  Build
-------------------------------------------------------------------------------
local frame, screen, soundBtn

-- win: the window.
function SE.Build(win)
    local f = CreateFrame("Frame", nil, win)
    f:SetPoint("TOPLEFT", 0, -S.header)
    f:SetPoint("BOTTOMRIGHT", 0, S.footer)
    -- Above the pages, their secure overlays and the welcome screen; it takes their clicks.
    f:SetFrameLevel(win:GetFrameLevel() + 250)
    f:EnableMouse(true)
    f:Hide()
    local bg = W.Tex(f, "BACKGROUND", C.bg)
    bg:SetAllPoints()

    -- Bar: Back, title, note
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT")
    bar:SetHeight(S.tabs)
    local bl = W.Tex(bar, "BORDER", C.line)
    bl:SetPoint("BOTTOMLEFT"); bl:SetPoint("BOTTOMRIGHT"); PixelUtil.SetHeight(bl, 1, 1)
    local back = W.Button(bar, "‹  Back", "mark", 76, 28)
    back:SetPoint("LEFT", S.pad, 0)
    back:SetScript("OnClick", function() SE.Hide() end)
    local title = W.Text(bar, "h2")
    title:SetPoint("LEFT", back, "RIGHT", 12, 0)
    title:SetText("Settings")
    local note = W.Text(bar, "small")
    note:SetPoint("RIGHT", -S.pad, 0)
    note:SetText("Saved for your account")

    -- Two columns
    local left = CreateFrame("Frame", nil, f)
    left:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", S.pad, -16)
    left:SetPoint("TOPRIGHT", f, "TOP", 24, -S.tabs - 16)
    left:SetHeight(1)
    local right = CreateFrame("Frame", nil, f)
    right:SetPoint("TOPLEFT", f, "TOP", 38, -S.tabs - 16)
    right:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -S.pad, -16)
    right:SetHeight(1)

    -- Alerts
    local alerts = Panel(f, "Alerts")
    alerts:SetPoint("TOPLEFT", left); alerts:SetPoint("TOPRIGHT", left)
    SwitchRow(alerts, "alertInvite", "When you're invited", "You signed up and a leader invites you.", function()
        if UI.Invite then UI.Invite.SettingChanged() end
    end)
    SwitchRow(alerts, "inviteCard", "Answer invites in our card", "Accept or decline right in it; off: Blizzard's invite window.",
        function() if UI.Invite then UI.Invite.SettingChanged() end end)
    SwitchRow(alerts, "alertApply", "When someone applies", "You lead a listed group and a new player signs up.")
    local scr = alerts:Row("On screen", "A soft gold edge that fades out, a short message at the top, or both.", true)
    screen = W.Segmented(scr, { { "both", "Edge + message" }, { "glow", "Edge" }, { "toast", "Message" }, { "off", "Nothing" } }, 28)
    screen:SetPoint("TOPLEFT", scr.desc, "BOTTOMLEFT", 0, -10)
    screen.onChange = function(v)
        local db = DB()
        if db then db.alertScreen = v end
    end
    local snd, sw = SwitchRow(alerts, "alertSound", "Sound", "On the Master channel: heard with sound effects off.", nil, 200)
    soundBtn = W.Button(snd, "", "mark", 110, 26, "tiny")
    soundBtn:SetPoint("RIGHT", sw, "LEFT", -10, 0)
    soundBtn:SetScript("OnClick", function(self)
        local list = UI.Alert and UI.Alert.SOUNDS or {}
        local db = DB()
        local function Pick(key)
            if db then db.alertSoundKit = key end
            if UI.Alert then UI.Alert.PlaySound(key) end
            SE.Paint()
        end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, s in ipairs(list) do
                    root:CreateRadio(s.name, function() return db and db.alertSoundKit == s.key end, function() Pick(s.key) end)
                end
            end)
        else   -- no menu API: the next sound
            local cur = 1
            for i, s in ipairs(list) do if db and s.key == db.alertSoundKit then cur = i end end
            local nxt = list[cur % #list + 1]
            if nxt then Pick(nxt.key) end
        end
    end)
    SwitchRow(alerts, "alertFlash", "Flash the taskbar icon", "New applicants, WoW in the background. Invites: Blizzard does it.")
    local try = alerts:Row("Try it", "Shows the invite alert with these settings.")
    local preview = W.Button(try, "Preview", "ghost", 92, 28)
    preview:SetPoint("RIGHT", -16, 0)
    preview:SetScript("OnClick", function() if UI.Alert then UI.Alert.Preview() end end)

    -- Group list
    local list = Panel(f, "Group list")
    list:SetPoint("TOPLEFT", right); list:SetPoint("TOPRIGHT", right)
    SwitchRow(list, "markStale", "Mark groups listed a while", "From 20 minutes with 2 players or fewer.", function()
        if UI.Browse and UI.Browse.Reread then UI.Browse.Reread() end
    end)

    -- Footer
    local foot = Panel(f, "Footer")
    foot:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -14); foot:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -14)
    SwitchRow(foot, "footerVault", "Great Vault and affixes", "Runs this week, vault slots, the affixes.", function()
        if UI.Vault then UI.Vault.Refresh() end
    end)

    -- Window
    local wnd = Panel(f, "Window")
    wnd:SetPoint("TOPLEFT", foot, "BOTTOMLEFT", 0, -14); wnd:SetPoint("TOPRIGHT", foot, "BOTTOMRIGHT", 0, -14)
    SwitchRow(wnd, "showMinimap", "Minimap button", "Right-click it for these settings.", function(on)
        -- Through Blizzard's setting too, so its page shows the same.
        if Settings and Settings.SetValue then pcall(Settings.SetValue, "GottaQueueEmAll_showMinimap", on) end
        UI.Launcher.Update()
    end)
    local hk = wnd:Row("Hotkey", "Click, then press a key. Right-click removes it.", false, 170)
    local hotkey = UI.Launcher.HotkeyButton(hk)
    hotkey:SetPoint("RIGHT", -16, 0)
    local sz = wnd:Row("Size and position", "Default size, in the middle of the screen.")
    local reset = W.Button(sz, "Reset", "ghost", 76, 28)
    reset:SetPoint("RIGHT", -16, 0)
    reset:SetScript("OnClick", function() if UI.ResetGeometry then UI.ResetGeometry() end end)

    -- Bottom line: Blizzard's page, the slash command, the version
    local more = CreateFrame("Button", nil, f)
    more:SetPoint("BOTTOMLEFT", S.pad, 14)
    more.text = W.Text(more, "small")
    more.text:SetPoint("LEFT")
    more.text:SetText("Also in Options › AddOns ›  |cffe0b868Gotta Queue 'Em All|r")
    more:SetSize(more.text:GetStringWidth() + 4, 18)
    more:SetScript("OnClick", function() if ns.OpenBlizzardSettings then ns.OpenBlizzardSettings() end end)
    more:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(C.text)) end)
    more:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(C.muted)) end)
    local slash = W.Text(f, "small")
    slash:SetPoint("LEFT", more, "RIGHT", 18, 0)
    slash:SetText("/gotta settings opens this page")
    local ver = W.Text(f, "small", C.faint)
    ver:SetPoint("BOTTOMRIGHT", -S.pad, 14)
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    ver:SetText(getMeta and getMeta("GottaQueueEmAll", "Version") or "")

    local panels = { alerts, list, foot, wnd }
    f:SetScript("OnShow", function()
        SE.Paint()
        for i, p in ipairs(panels) do A.Rise(p, (i - 1) * 0.04, 6, 0.3) end
    end)
    frame = f
    return f
end

-- Controls from the saved settings.
function SE.Paint()
    local db = DB()
    if not (db and frame) then return end
    for key, s in pairs(switches) do s:SetChecked(db[key] ~= false) end
    screen:SetValue(db.alertScreen or "both")
    local name = "Sound"
    for _, s in ipairs(UI.Alert and UI.Alert.SOUNDS or {}) do if s.key == db.alertSoundKit then name = s.name end end
    soundBtn:SetLabel(name)
    soundBtn:SetWidth(math.ceil(soundBtn.label:GetStringWidth() + 22))
    soundBtn:SetEnabled(db.alertSound ~= false)
    -- Everything below the two "when" switches waits for one of them.
    local any = db.alertInvite ~= false or db.alertApply ~= false
    for _, b in pairs(screen.buttons) do b:SetEnabled(any) end
end

function SE.IsShown() return frame and frame:IsShown() or false end

function SE.Show()
    if not frame then return end
    frame:Show()
    A.FadeIn(frame, 0.15)
    if SE.onToggle then SE.onToggle(true) end
end

function SE.Hide()
    if not (frame and frame:IsShown()) then return end
    frame:Hide()
    if SE.onToggle then SE.onToggle(false) end
end

function SE.Toggle()
    if SE.IsShown() then SE.Hide() else SE.Show() end
end
