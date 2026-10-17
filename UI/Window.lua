-------------------------------------------------------------------------------
--  UI/Window.lua  --  the window: frame, header, tabs, footer
--
--  /gotta, the minimap button or the hotkey opens it: Browse, Your Group,
--  + Create.
--  The + Create tab holds a secure button, which makes the window
--  protected: it closes when combat starts and opens only out of combat.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A = UI.Theme, UI.W, UI.Anim
local C, S = T.C, T.S

local WIN_W, WIN_H = 980, 780
local win

-- Header icon buttons: "close" (an X from two rotated bars, no Blizzard
-- close button look) or the gear.
local function IconButton(parent, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(32, 32)
    b.bg = W.Tex(b, "BACKGROUND", { 0.63, 0.71, 0.84, 0 })
    b.bg:SetAllPoints()
    local parts = {}
    if kind == "close" then
        for i, rot in ipairs({ 45, -45 }) do
            local t = W.Tex(b, "ARTWORK", C.muted)
            t:SetSize(14, 1.6)
            t:SetPoint("CENTER")
            t:SetRotation(math.rad(rot))
            parts[i] = t
        end
    else
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetSize(17, 17)
        t:SetPoint("CENTER")
        if C_Texture.GetAtlasInfo("GM-icon-settings") then t:SetAtlas("GM-icon-settings")
        else t:SetTexture("Interface\\Icons\\INV_Misc_Gear_01") end
        t:SetDesaturated(true)
        t:SetVertexColor(unpack(C.muted))
        parts[1] = t
    end
    b:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(0.63, 0.71, 0.84, 0.07)
        for _, t in ipairs(parts) do t:SetVertexColor(unpack(C.textHi)) end
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(0.63, 0.71, 0.84, 0)
        for _, t in ipairs(parts) do t:SetVertexColor(unpack(C.muted)) end
    end)
    return b
end

local MIN_W, MIN_H, MAX_W, MAX_H = 940, 700, 1800, 1300

-- Largest scale (max 1) at which the window fits the screen.
local function FitScale()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    win:SetScale(math.min(1, (sw - 40) / win:GetWidth(), (sh - 40) / win:GetHeight()))
end

-- Size and position, per account (GottaQueueEmAllDB.ui.window).
local function Saved()
    local db = ns.DB and ns.DB()
    if not db then return {} end
    db.ui = db.ui or {}
    if type(db.ui.window) ~= "table" then db.ui.window = {} end
    return db.ui.window
end

local function SaveGeometry()
    local s = Saved()
    s.w, s.h = math.floor(win:GetWidth() + 0.5), math.floor(win:GetHeight() + 0.5)
    local point, _, relPoint, x, y = win:GetPoint(1)
    s.point, s.relPoint, s.x, s.y = point, relPoint, x, y
end

-- Drag handle in the bottom right corner (Blizzard's chat size grabber art).
local function SizeGrip()
    local g = CreateFrame("Button", nil, win)
    g:SetSize(18, 18)
    g:SetPoint("BOTTOMRIGHT", -4, 4)
    g:SetFrameLevel(win:GetFrameLevel() + 20)
    g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    g:GetNormalTexture():SetVertexColor(unpack(C.muted))
    g:GetHighlightTexture():SetVertexColor(unpack(C.gold))
    g:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not InCombatLockdown() then win:StartSizing("BOTTOMRIGHT") end
    end)
    g:SetScript("OnMouseUp", function()
        win:StopMovingOrSizing()
        SaveGeometry()
    end)
end

local function Build()
    local s = Saved()
    win = CreateFrame("Frame", "GQEAWindow", UIParent)
    win:SetSize(math.max(MIN_W, math.min(MAX_W, s.w or WIN_W)), math.max(MIN_H, math.min(MAX_H, s.h or WIN_H)))
    if s.point then win:SetPoint(s.point, UIParent, s.relPoint or s.point, s.x or 0, s.y or 0) else win:SetPoint("CENTER") end
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetResizable(true)
    if win.SetResizeBounds then win:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif win.SetMinResize then win:SetMinResize(MIN_W, MIN_H); win:SetMaxResize(MAX_W, MAX_H) end
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()
    tinsert(UISpecialFrames, "GQEAWindow")   -- Escape closes it

    win.bg = W.Round(win, "BACKGROUND", C.bg)
    win.bg:SetAllPoints()
    W.Border(win, C.lineStrong, "OVERLAY")
    local hi = W.Tex(win, "BORDER", { 1, 1, 1, 0.04 })
    hi:SetPoint("TOPLEFT", 7, -1); hi:SetPoint("TOPRIGHT", -7, -1); PixelUtil.SetHeight(hi, 1, 1)

    -- Header (drag handle)
    local head = CreateFrame("Frame", nil, win)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT")
    head:SetHeight(S.header)
    head.bg = W.Round(head, "BACKGROUND", nil, 1)
    head.bg:SetAllPoints()
    W.Gradient(head.bg, "VERTICAL", C.bg, C.bgTop)
    local hl = W.Tex(head, "BORDER", C.line)
    hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT"); PixelUtil.SetHeight(hl, 1, 1)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() win:StartMoving() end)
    head:SetScript("OnDragStop", function() win:StopMovingOrSizing(); SaveGeometry() end)

    local logo = head:CreateTexture(nil, "ARTWORK")
    logo:SetSize(34, 34)
    logo:SetPoint("LEFT", 16, 0)
    logo:SetTexture(T.MEDIA .. "logo-qlens-mark")   -- the mark alone; the tiled version is the CurseForge icon
    local title = W.Text(head, "title")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, 1)
    title:SetText("Gotta Queue 'Em All")
    local subtitle = W.Text(head, "small")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("Mythic+")

    local close = IconButton(head, "close")
    close:SetPoint("RIGHT", -12, 0)
    close:SetScript("OnClick", function() win:Hide() end)
    local gear = IconButton(head, "gear")
    gear:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local hotkey = UI.Launcher.HotkeyButton(head)
    hotkey:SetPoint("RIGHT", gear, "LEFT", -10, 0)
    gear:SetScript("OnClick", function() if ns.OpenSettings then ns.OpenSettings() end end)

    -- Pages
    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", 0, -(S.header + S.tabs))
    content:SetPoint("BOTTOMRIGHT", 0, S.footer)
    win.pages = {}
    local names = { "Browse", "Your Group", "+ Create" }
    for i, name in ipairs(names) do
        local p = CreateFrame("Frame", nil, content)
        p:SetAllPoints()
        p:Hide()
        win.pages[i] = p
    end
    UI.BuildBrowse(win.pages[1])
    UI.BuildGroup(win.pages[2])
    UI.BuildCreate(win.pages[3])

    win.tabs = W.Tabs(win, names, function(i)
        for j, p in ipairs(win.pages) do p:SetShown(j == i) end
        A.FadeIn(win.pages[i], 0.2)
    end)
    win.tabs:SetPoint("TOPLEFT", S.pad, -S.header)
    win.tabs:SetPoint("TOPRIGHT", -S.pad, -S.header)

    -- "+ Create" is a secure click on Blizzard's Start a Group:
    -- Blizzard's code picks your keystone and writes the title, the Create
    -- tab's "List group" lists later. A macro /clicks a named helper, which
    -- clicks Blizzard's (nameless) button; no addon code runs in between.
    -- This makes the window protected: it closes when combat starts.
    -- Two helpers, clicked in order by the macro: Blizzard's Dungeons
    -- category button (Start a Group needs it selected; after a login
    -- nothing is), then Start a Group.
    local function Helper(name)
        local h = CreateFrame("Button", name, win, "SecureActionButtonTemplate")
        h:SetSize(1, 1)
        h:SetPoint("BOTTOMLEFT")
        h:SetAlpha(0)
        h:EnableMouse(false)
        h:SetAttribute("type", "click")
        h:SetAttribute("useOnKeyDown", false)
        return h
    end
    local category = Helper("GQEACreateCategory")
    local helper = Helper("GQEACreateStart")
    local function WireStart()
        if InCombatLockdown() then return end
        local cs = LFGListFrame and LFGListFrame.CategorySelection
        local dungeons = UI.Data.DungeonCategoryButton()
        category:SetAttribute("clickbutton", dungeons)
        -- Only towards Dungeons: else Blizzard would prepare another category.
        local ok = cs and cs.StartGroupButton and (dungeons or cs.selectedCategory == UI.Data.CATEGORY)
        helper:SetAttribute("clickbutton", ok and cs.StartGroupButton or nil)
    end
    WireStart()
    local tab = win.tabs.tabs[3]
    local over = CreateFrame("Button", "GQEACreateTab", tab, "SecureActionButtonTemplate")
    over:SetAllPoints(tab)
    over:RegisterForClicks("AnyUp", "AnyDown")
    over:SetAttribute("type1", "macro")
    over:SetAttribute("macrotext1", "/click GQEACreateCategory\n/click GQEACreateStart")
    -- The secure action fires on down or up (ActionButtonUseKeyDown): act on that one.
    local function ActsOn(down) return (down and true or false) == GetCVarBool("ActionButtonUseKeyDown") end
    over:SetScript("PreClick", function(_, _, down)
        if not ActsOn(down) then return end
        WireStart()
        win.tabs:Select(3)
    end)
    over:SetScript("PostClick", function(_, _, down)
        if ActsOn(down) and UI.Create then C_Timer.After(0.1, UI.Create.Refresh) end
    end)
    over:SetScript("OnEnter", function() local f = tab:GetScript("OnEnter"); if f then f(tab) end end)
    over:SetScript("OnLeave", function() local f = tab:GetScript("OnLeave"); if f then f(tab) end end)

    -- Footer
    local foot = CreateFrame("Frame", nil, win)
    foot:SetPoint("BOTTOMLEFT"); foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(S.footer)
    local fl = W.Tex(foot, "BORDER", C.line)
    fl:SetPoint("TOPLEFT"); fl:SetPoint("TOPRIGHT"); PixelUtil.SetHeight(fl, 1, 1)
    local dot = W.Circle(foot, "ARTWORK", C.good, 7)
    dot:SetPoint("LEFT", S.pad, 0)
    A.Ping(foot, dot, C.good, 7)
    win.status = W.Text(foot, "small")
    win.status:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    win.status:SetText("No search yet")
    local me = W.Text(foot, "small")
    me:SetPoint("RIGHT", -S.pad - 18, 0)   -- room for the size grip
    -- You: name, rating, item level (fresh each time the window opens).
    local function PaintMe()
        local _, class = UnitClass("player")
        local score = UI.Data.Num(C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore()) or 0
        local _, ilvl = GetAverageItemLevel()
        me:SetText(("%s%s|r  ·  %s%d|r  ·  ilvl %d"):format(T.ColorCode(T.ClassColor(class)), UnitName("player"),
            T.ColorCode(T.RatingColor(score)), score, math.floor(UI.Data.Num(ilvl) or 0)))
    end

    SizeGrip()
    -- Events and the combat watch only while the window is open.
    win:SetScript("OnShow", function()
        ns.SetLive(true)
        PaintMe()
        FitScale()
        A.FadeIn(win, 0.18)
        if UI.Group and UI.Group.Refresh then UI.Group.Refresh() end
    end)
    win:SetScript("OnHide", function()
        ns.SetLive(false)
        if UI.Browse then UI.Browse.stale = true end   -- its results catch up on the next show
    end)
    win.tabs:Select(1, true)
    for j, p in ipairs(win.pages) do p:SetShown(j == 1) end
end

-- Settings page "Reset": default size, centered, saved geometry forgotten.
function UI.ResetGeometry()
    local db = ns.DB and ns.DB()
    if db and db.ui then db.ui.window = nil end
    if not win or InCombatLockdown() then return end
    win:ClearAllPoints()
    win:SetPoint("CENTER")
    win:SetSize(WIN_W, WIN_H)
end

-- Footer text (left).
function UI.SetStatus(text)
    if win and win.status then win.status:SetText(text) end
end

-- Count bubble on a tab (nil / 0 hides it). It re-anchors the tabs, one of
-- which holds a secure button: in combat it waits for the combat's end.
local pendingBadge = {}
local combat = CreateFrame("Frame")
function UI.SetTabBadge(i, n)
    if not (win and win.tabs) then return end
    if InCombatLockdown() then
        pendingBadge[i] = n or 0
        combat:RegisterEvent("PLAYER_REGEN_ENABLED")   -- once, for the waiting badge
        return
    end
    win.tabs:SetBadge(i, n)
end

-- The window holds a secure button, so it can't be shown or hidden in
-- combat: it closes as combat starts (still allowed in that event). Watched
-- only while the window is open (ns.Live).
ns.Live(combat, { "PLAYER_REGEN_DISABLED" })
combat:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if win and win:IsShown() then win:Hide() end
    else
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        for i, n in pairs(pendingBadge) do UI.SetTabBadge(i, n) end
        wipe(pendingBadge)
    end
end)

function UI.SelectTab(i)
    if win and win.tabs then win.tabs:Select(i) end
end

-- /gotta uidebug: how far the + Create preparation gets, printed to chat
-- (for bug reports).
function UI.Debug()
    local D = UI.Data
    local cs = LFGListFrame and LFGListFrame.CategorySelection
    local ec = LFGListFrame and LFGListFrame.EntryCreation
    local key = D.OwnKey()
    local b = D.DungeonCategoryButton()
    local function S(v) return tostring(v) end
    local ids = {}
    for _, btn in ipairs(cs and cs.CategoryButtons or {}) do
        ids[#ids + 1] = S(btn.categoryID) .. "/" .. S(btn.filters) .. (btn:IsEnabled() and "" or " off")
    end
    local lines = {
        "time: " .. date("%H:%M:%S") .. ", window open: " .. S(win and win:IsShown()) .. ", tab: " .. S(win and win.tabs and win.tabs.active),
        "Blizzard_GroupFinder loaded: " .. S(LFGListFrame ~= nil) .. ", PVEFrame shown: " .. S(PVEFrame and PVEFrame:IsShown()),
        "category buttons (id/filters): " .. (#ids > 0 and table.concat(ids, ", ") or "none")
            .. ", dungeons button: " .. S(b ~= nil) .. ", selected category: " .. S(cs and cs.selectedCategory),
        "Start a Group button: " .. S(cs and cs.StartGroupButton ~= nil)
            .. ", enabled: " .. S(cs and cs.StartGroupButton and cs.StartGroupButton:IsEnabled()),
        "helpers: category -> " .. S(GQEACreateCategory and GQEACreateCategory:GetAttribute("clickbutton") ~= nil)
            .. ", start -> " .. S(GQEACreateStart and GQEACreateStart:GetAttribute("clickbutton") ~= nil),
        "active panel: " .. S(LFGListFrame and LFGListFrame.activePanel and LFGListFrame.activePanel:GetDebugName()),
        "form shown: " .. S(ec and ec:IsShown()) .. ", activity: " .. S(ec and ec.selectedActivity)
            .. ", playstyle: " .. S(ec and ec.generalPlaystyle)
            .. ", List Group enabled: " .. S(ec and ec.ListGroupButton and ec.ListGroupButton:IsEnabled()),
        "your key activity: " .. S(key and key.act) .. ", level: " .. S(key and key.level)
            .. ", form ready: " .. S(key and D.FormReady(key.act)) .. ", can start: " .. S(D.CanStart())
            .. ", listed: " .. S(C_LFGList.HasActiveEntryInfo()) .. ", leader/alone: " .. S(D.CanApply()),
    }
    ns.Print("+ Create check:")
    for _, l in ipairs(lines) do print("  " .. l) end
end

function UI.Toggle()
    if InCombatLockdown() then ns.Print("the window opens after combat."); return end
    if not win then Build() end
    win:SetShown(not win:IsShown())
end
