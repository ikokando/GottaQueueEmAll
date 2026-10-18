-------------------------------------------------------------------------------
--  UI/TitleBox.lua  --  Blizzard's own title box, borrowed into the window
--
--  Group titles can only be typed by the player: addon code writing one gets
--  the listing blocked. So the + Create pages borrow the title box of
--  Blizzard's Start a Group form (LFGListFrame.EntryCreation.Name) into a
--  holder of theirs, styled like the window, while Blizzard's window stays
--  closed (tested in 12.1.5: the listing takes the typed title).
--  One owner at a time; the box goes home when its page hides or Blizzard's
--  window opens.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W = UI.Theme, UI.W
local C = T.C

local TB = {}
UI.TitleBox = TB

local saved   -- while borrowed: where the box came from, what was restyled
local owner   -- { holder, onEnter, onFocus }

function TB.Box()
    local ec = LFGListFrame and LFGListFrame.EntryCreation
    return ec and ec.Name
end

-- Blizzard's box in our look: its own frame art hidden, our font and colors
-- (each call guarded: the box is restricted, some calls may be refused).
local function Restyle(box)
    saved.hidden = {}
    for _, r in ipairs({ box:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r:IsShown() then
            if pcall(r.Hide, r) then saved.hidden[#saved.hidden + 1] = r end
        end
    end
    -- Child frames (a border or clear button of the template) too.
    for _, f in ipairs({ box:GetChildren() }) do
        if f:IsShown() and pcall(f.Hide, f) then saved.hidden[#saved.hidden + 1] = f end
    end
    saved.insets = { box:GetTextInsets() }
    pcall(box.SetTextInsets, box, 10, 10, 0, 0)
    -- Font by file, size and flags, never by font object: the box's own font
    -- object set back onto it loops the client (a crash, 12.1.5).
    saved.font = { box:GetFont() }
    saved.color = { box:GetTextColor() }
    pcall(box.SetFont, box, T.FONT.medium, 15, "")
    pcall(box.SetTextColor, box, unpack(C.textHi))
    local hint = box.Instructions
    if hint then
        saved.hintFont = { hint:GetFont() }
        saved.hintColor = { hint:GetTextColor() }
        pcall(hint.SetFont, hint, T.FONT.medium, 14, "")
        pcall(hint.SetTextColor, hint, unpack(C.faint))
        saved.hintPoints = {}
        for i = 1, hint:GetNumPoints() do saved.hintPoints[i] = { hint:GetPoint(i) } end
        pcall(function()
            hint:ClearAllPoints()
            hint:SetPoint("LEFT", box, "LEFT", 12, 0)
            hint:SetPoint("RIGHT", box, "RIGHT", -10, 0)
        end)
    end
end

local function Unstyle(box)
    for _, r in ipairs(saved.hidden or {}) do pcall(r.Show, r) end
    if saved.font and saved.font[1] then pcall(box.SetFont, box, unpack(saved.font)) end
    if saved.color then pcall(box.SetTextColor, box, unpack(saved.color)) end
    local hint = box.Instructions
    if hint and saved.hintFont and saved.hintFont[1] then pcall(hint.SetFont, hint, unpack(saved.hintFont)) end
    if hint and saved.hintColor then pcall(hint.SetTextColor, hint, unpack(saved.hintColor)) end
    if hint and saved.hintPoints then
        pcall(function()
            hint:ClearAllPoints()
            for _, p in ipairs(saved.hintPoints) do hint:SetPoint(unpack(p)) end
        end)
    end
    if saved.insets and saved.insets[1] then pcall(box.SetTextInsets, box, unpack(saved.insets)) end
end

-- The box goes home (its page hid, or Blizzard's window opened); its page's
-- holder shows its prompt again.
function TB.Return()
    local box = TB.Box()
    if not (saved and box) then return end
    box:ClearFocus()
    Unstyle(box)
    box:SetParent(saved.parent)
    box:ClearAllPoints()
    for _, p in ipairs(saved.points) do box:SetPoint(unpack(p)) end
    box:SetFrameStrata(saved.strata)
    box:SetFrameLevel(saved.level)
    local holder = owner and owner.holder
    saved, owner = nil, nil
    if holder and holder.Paint then holder:Paint(false) end
end

-- Is the box in this holder (or anywhere, without one)?
function TB.IsBorrowed(holder)
    return saved ~= nil and (holder == nil or (owner and owner.holder == holder))
end

-- holder: our frame; opts.onEnter (Enter pressed), opts.onFocus (focus changed).
function TB.Borrow(holder, opts)
    local box = TB.Box()
    if not (box and holder) or InCombatLockdown() then return end
    if saved then
        if owner and owner.holder == holder then return end
        TB.Return()
    end
    -- Blizzard's window opening wants its box back.
    if PVEFrame and not TB.hooked then
        TB.hooked = true
        PVEFrame:HookScript("OnShow", function() TB.Return() end)
    end
    saved = { parent = box:GetParent(), points = {}, strata = box:GetFrameStrata(), level = box:GetFrameLevel() }
    for i = 1, box:GetNumPoints() do saved.points[i] = { box:GetPoint(i) } end
    owner = { holder = holder, onEnter = opts and opts.onEnter, onFocus = opts and opts.onFocus }
    box:SetParent(holder)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", 2, 0); box:SetPoint("BOTTOMRIGHT", -2, 0)
    box:SetFrameStrata(holder:GetFrameStrata())
    box:SetFrameLevel(holder:GetFrameLevel() + 5)
    box:Show()
    Restyle(box)
    if not TB.boxHooked then
        TB.boxHooked = true
        local function Focus() if owner and owner.onFocus then owner.onFocus() end end
        pcall(box.HookScript, box, "OnEditFocusGained", Focus)
        pcall(box.HookScript, box, "OnEditFocusLost", Focus)
        pcall(box.HookScript, box, "OnEnterPressed", function() if owner and owner.onEnter then owner.onEnter() end end)
    end
end

function TB.Focus()
    local box = TB.Box()
    if saved and box then box:SetFocus() end
end

function TB.HasFocus()
    local box = TB.Box()
    return saved ~= nil and box ~= nil and box:HasFocus()
end

-- The typed text, "" when empty, nil when the box can't be read.
function TB.Text()
    local box = TB.Box()
    if not box then return end
    local ok, text = pcall(box.GetText, box)
    text = ok and UI.Data.Str(text)
    return text and strtrim(text) or (ok and "" or nil)
end

-- After a + Create secure click opened Blizzard's form: its window closes
-- again (the form stays prepared) and the box moves into holder.
function TB.TakeOver(holder, opts)
    if InCombatLockdown() then return end
    if PVEFrame and PVEFrame:IsShown() then HideUIPanel(PVEFrame) end
    TB.Borrow(holder, opts)
end

-- A holder in the window's look: dark field, gold border while typing, a
-- click anywhere focuses the box; :Flash() for a missing title.
function TB.Holder(parent)
    local h = W.Panel(parent, C.bg, C.lineStrong)
    h:SetHeight(42)
    h:EnableMouse(true)
    h:SetScript("OnMouseDown", function(self) if TB.IsBorrowed(self) then TB.Focus() end end)
    -- Not prepared yet (or the box went home): a prompt in its place whose
    -- click prepares the listing (a secure overlay, UI/Window.lua).
    h.prompt = W.Button(h, "Click here to write a title", "mark", nil, 42, "button")
    h.prompt:SetAllPoints()
    UI.createTargets = UI.createTargets or {}
    table.insert(UI.createTargets, h.prompt)
    local pulse = UI.Anim.Pulse(h, 0.45, 0.35)
    pulse:Stop()
    function h:Flash()
        pulse:Play()
        h.flashN = (h.flashN or 0) + 1
        local n = h.flashN
        C_Timer.After(1.05, function() if h.flashN == n then pulse:Stop(); h:SetAlpha(1) end end)
    end
    -- missing: red border (a List click found no title).
    function h:Paint(missing)
        if not InCombatLockdown() then self.prompt:SetShown(not TB.IsBorrowed(self)) end
        W.SetBorder(self, missing and { 0.84, 0.33, 0.29, 0.8 }
            or (TB.IsBorrowed(self) and TB.HasFocus()) and C.gold or C.lineStrong)
    end
    return h
end
