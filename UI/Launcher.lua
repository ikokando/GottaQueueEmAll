-------------------------------------------------------------------------------
--  UI/Launcher.lua  --  ways to open the window
--
--  - a key binding (Bindings.xml; set in Blizzard's Key Bindings or with the
--    window's Hotkey button, L.HotkeyButton),
--  - a minimap button: click toggles, right-click opens the settings, drag
--    moves it around the minimap (round or square). Hidden by the setting
--    "Minimap button" (GottaQueueEmAllDB.showMinimap),
--  - the retail addon compartment (TOC: AddonCompartmentFunc).
--  No libraries: the minimap button follows LibDBIcon's look and layout.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W = UI.Theme, UI.W

local L = {}
UI.Launcher = L

local BINDING = "GOTTAQUEUEEMALL_TOGGLE"
BINDING_HEADER_GOTTAQUEUEEMALL = "Gotta Queue 'Em All"
_G["BINDING_NAME_" .. BINDING] = "Open / close the window"

function GottaQueueEmAll_Toggle()
    if UI.Toggle then UI.Toggle() end
end
function GottaQueueEmAll_OnAddonCompartmentClick()
    GottaQueueEmAll_Toggle()
end

local function OpenSettings()
    if ns.OpenSettings then ns.OpenSettings() end
end

function L.HotkeyText()
    local key = GetBindingKey(BINDING)
    return key and (GetBindingText and GetBindingText(key, "KEY_") or key) or nil
end

-------------------------------------------------------------------------------
--  Minimap button
-------------------------------------------------------------------------------
local button

local function Store()
    local db = ns.DB and ns.DB()
    if not db then return {} end
    db.ui = db.ui or {}
    if type(db.ui.minimap) ~= "table" then db.ui.minimap = { angle = 200 } end
    return db.ui.minimap
end

-- On the minimap's edge at the stored angle; square minimaps put it on the
-- square's edge.
local function Place()
    local a = math.rad(Store().angle or 200)
    local x, y = math.cos(a), math.sin(a)
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local m = math.max(math.abs(x), math.abs(y))
        x, y = x / m, y / m
    end
    local rx, ry = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * rx, y * ry)
end

local function Drag(self)
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    Store().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    Place()
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Gotta Queue 'Em All", 1, 1, 1)
    GameTooltip:AddLine("Click: open / close", 0.85, 0.85, 0.85)
    GameTooltip:AddLine("Right-click: settings", 0.85, 0.85, 0.85)
    GameTooltip:AddLine("Drag: move", 0.85, 0.85, 0.85)
    local key = L.HotkeyText()
    GameTooltip:AddLine(key and ("Hotkey: " .. key) or "No hotkey yet (set it in the window)", 0.6, 0.65, 0.72)
    GameTooltip:Show()
end

local function Create()
    button = CreateFrame("Button", "GottaQueueEmAllMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER", 0, 1)
    bg:SetVertexColor(0.06, 0.09, 0.15, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(T.MEDIA .. "logo-qlens-mark")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then OpenSettings() else GottaQueueEmAll_Toggle() end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", Drag)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, 0) end)
    button:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", 0, 1) end)
    Place()
end

-- Shown or hidden by the setting.
function L.Update()
    local db = ns.DB and ns.DB()
    local show = not db or db.showMinimap ~= false
    if show and not button then Create() end
    if button then button:SetShown(show) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(0, L.Update)   -- after the main file has loaded the saved settings
end)

-------------------------------------------------------------------------------
--  Hotkey button (window header): click, then press a key
-------------------------------------------------------------------------------
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
                    LMETA = true, RMETA = true, UNKNOWN = true }

function L.HotkeyButton(parent)
    local b = W.Button(parent, "", "mark", 120, 26, "tiny")
    local function Paint()
        local key = L.HotkeyText()
        b:SetLabel(b.listening and "Press a key…  (Esc cancels)" or (key and ("Hotkey: " .. key) or "Set hotkey"))
        b:SetWidth(b.label:GetStringWidth() + 20)
        b:SetVariant(b.listening and "ghost" or "mark")
    end
    local function Stop()
        b.listening = false
        b:EnableKeyboard(false)
        b:SetScript("OnKeyDown", nil)
        Paint()
    end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, mouse)
        if InCombatLockdown() then return end
        if mouse == "RightButton" then   -- clear
            local old = GetBindingKey(BINDING)
            if old then SetBinding(old); SaveBindings(GetCurrentBindingSet()) end
            Stop()
            return
        end
        b.listening = true
        b:EnableKeyboard(true)
        b:SetPropagateKeyboardInput(false)
        b:SetScript("OnKeyDown", function(_, key)
            if MODIFIERS[key] then return end
            if key == "ESCAPE" then Stop(); return end
            local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
                .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
            local old = GetBindingKey(BINDING)
            if old then SetBinding(old) end
            local replaced = GetBindingAction(combo)
            SetBinding(combo, BINDING)
            SaveBindings(GetCurrentBindingSet())
            if replaced and replaced ~= "" and replaced ~= BINDING then
                ns.Print(("%s was bound to %s before."):format(combo, _G["BINDING_NAME_" .. replaced] or replaced))
            end
            Stop()
        end)
        Paint()
    end)
    b:SetScript("OnHide", function() if b.listening then Stop() end end)
    b.tipText = "Click, then press a key (with Shift / Ctrl / Alt if you like).\nRight-click: remove the hotkey."
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Hotkey for this window", 1, 1, 1)
        GameTooltip:AddLine(self.tipText, 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    Paint()
    return b
end
