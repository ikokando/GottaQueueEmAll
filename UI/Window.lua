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
    b:SetSize(36, 36)
    b:SetHitRectInsets(-4, -4, -6, -6)   -- clicks a little beyond the drawn square count too
    b.bg = W.Round(b, "BACKGROUND", { 0.63, 0.71, 0.84, 0 })
    b.bg:SetAllPoints()
    local parts = {}
    if kind == "close" then
        for i, rot in ipairs({ 45, -45 }) do
            local t = W.Tex(b, "ARTWORK", C.muted)
            t:SetSize(18, 2)
            t:SetPoint("CENTER")
            t:SetRotation(math.rad(rot))
            parts[i] = t
        end
    else
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetSize(30, 30)   -- the atlas has a wide margin: drawn, the cog is about 20
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
    local function Rest(self)
        self.bg:SetVertexColor(0.82, 0.64, 0.30, self.active and 0.14 or 0)
        for _, t in ipairs(parts) do t:SetVertexColor(unpack(self.active and C.goldLight or C.muted)) end
    end
    b:SetScript("OnLeave", Rest)
    -- Active (the gear while the settings page shows): gold.
    function b:SetActive(on) self.active = on and true or false; Rest(self) end
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
    win.subtitle = subtitle

    -- Section switch: Mythic+ / Raid / Mythic 0, then PvP (announced).
    win.sectionButtons = {}
    local prev
    for _, sec in ipairs({ { "mplus", "Mythic+" }, { "raid", "Raid" }, { "dungeon", "Mythic 0" } }) do
        local b = W.Button(head, sec[2], "mark", nil, 30, "button")
        b:SetWidth(b.label:GetStringWidth() + 28)
        -- Follows the title's width (it grows once the font file is loaded).
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else b:SetPoint("LEFT", title, "RIGHT", 28, -8) end
        b:SetScript("OnClick", function() UI.SetSection(sec[1]) end)
        win.sectionButtons[sec[1]] = b
        prev = b
    end
    -- PvP: announced, not there yet.
    local pvp = W.Button(head, "PvP  |cff8d98a8SOON|r", "mark", nil, 30, "button")
    pvp:SetWidth(pvp.label:GetStringWidth() + 28)
    pvp:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    pvp:Disable()   -- greyed out, no hover; the tooltip still shows
    pvp:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("PvP: coming soon", 1, 1, 1)
        GameTooltip:AddLine("Arena and rated battleground groups, in this window.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    pvp:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local close = IconButton(head, "close")
    close:SetPoint("RIGHT", -12, 0)
    close:SetScript("OnClick", function() win:Hide() end)
    local gear = IconButton(head, "gear")
    gear:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local hotkey = UI.Launcher.HotkeyButton(head)
    hotkey:SetPoint("RIGHT", gear, "LEFT", -10, 0)
    gear:SetScript("OnClick", function() UI.Settings.Toggle() end)
    UI.Settings.onToggle = function(on) gear:SetActive(on) end
    gear:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Settings", 1, 1, 1)
        GameTooltip:Show()
    end)
    gear:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Pages
    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", 0, -(S.header + S.tabs))
    content:SetPoint("BOTTOMRIGHT", 0, S.footer)
    win.pages = {}
    local names = { "Browse", "Your Group", "+ Create" }
    for i in ipairs(names) do
        local p = CreateFrame("Frame", nil, content)
        p:SetAllPoints()
        p:Hide()
        win.pages[i] = p
    end
    -- Browse and + Create hold one page per section (Mythic+, Raid, Mythic 0); Your
    -- Group shows whichever listing you have.
    win.sections, win.createSections = {}, {}
    for _, key in ipairs({ "mplus", "dungeon", "raid" }) do
        for _, pair in ipairs({ { win.sections, 1 }, { win.createSections, 3 } }) do
            local f = CreateFrame("Frame", nil, win.pages[pair[2]])
            f:SetAllPoints()
            f:Hide()
            pair[1][key] = f
        end
    end
    UI.BuildBrowse(win.sections.mplus)
    UI.BuildDungeonBrowse(win.sections.dungeon)
    UI.BuildRaidBrowse(win.sections.raid)
    UI.BuildGroup(win.pages[2])
    UI.BuildCreate(win.createSections.mplus)
    UI.BuildDungeonCreate(win.createSections.dungeon)
    UI.BuildRaidCreate(win.createSections.raid)

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
    -- Towards the section's category: Dungeons (Mythic+ and the Dungeons
    -- section) or Raids.
    local function WireStart()
        if InCombatLockdown() then return end
        local D = UI.Data
        -- Mythic 0 prepares Custom's form: on Dungeons Blizzard would pick
        -- your keystone and title the group "+14".
        local cat = ({ raid = D.RAID_CATEGORY, dungeon = D.CUSTOM_CATEGORY })[Saved().section] or D.CATEGORY
        local cs = LFGListFrame and LFGListFrame.CategorySelection
        local button = D.CategoryButton(cat)
        -- No category buttons yet (Blizzard builds them from the activity
        -- list): ask for it; the next click finds them.
        if not button and C_LFGList.RequestAvailableActivities then C_LFGList.RequestAvailableActivities() end
        category:SetAttribute("clickbutton", button)
        -- Only towards that category: else Blizzard would prepare another one.
        local ok = cs and cs.StartGroupButton and (button or cs.selectedCategory == cat)
        helper:SetAttribute("clickbutton", ok and cs.StartGroupButton or nil)
    end
    win.WireStart = WireStart
    WireStart()
    -- A secure overlay that runs the + Create preparation, on the tab and on
    -- every "prepare" button of the pages (UI.createTargets: Your Group's
    -- "Create a group", the title box prompts).
    local function ActsOn(down) return (down and true or false) == GetCVarBool("ActionButtonUseKeyDown") end
    -- floating: the target's layout hangs off text (a label), and a protected
    -- frame may not be anchored to text, not even through other frames. Such
    -- an overlay is a child of the window, placed over its target by numbers
    -- whenever the target shows, moves or resizes (out of combat).
    local floats = {}
    local function Trigger(target, name, floating)
        local over = CreateFrame("Button", name, floating and win or target, "SecureActionButtonTemplate")
        if floating then
            local function Place()
                if InCombatLockdown() then return end
                local l, b, wl, wb = target:GetLeft(), target:GetBottom(), win:GetLeft(), win:GetBottom()
                if not (target:IsVisible() and l and wl) then over:Hide(); return end
                over:ClearAllPoints()
                over:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", l - wl, b - wb)
                over:SetSize(target:GetWidth(), target:GetHeight())
                over:SetFrameLevel(target:GetFrameLevel() + 10)
                over:Show()
            end
            local function Later() C_Timer.After(0, Place) end
            target:HookScript("OnShow", Later)
            target:HookScript("OnSizeChanged", Later)
            target:HookScript("OnHide", function() if not InCombatLockdown() then over:Hide() end end)
            floats[#floats + 1] = Later
            over:Hide()
        else
            over:SetAllPoints(target)
            over:SetFrameLevel(target:GetFrameLevel() + 10)
        end
        over:RegisterForClicks("AnyUp", "AnyDown")
        over:SetAttribute("type1", "macro")
        over:SetAttribute("macrotext1", "/click GQEACreateCategory\n/click GQEACreateStart")
        -- The secure action fires on down or up (ActionButtonUseKeyDown): act on that one.
        over:SetScript("PreClick", function(_, _, down)
            if not ActsOn(down) then return end
            WireStart()
            -- After a delist Blizzard can leave Start a Group disabled while its
            -- window is closed (it refreshes the button only on its own events),
            -- and a disabled button ignores the click. Nothing stands against it
            -- here: enable it, so the macro's click goes through.
            local cs = LFGListFrame and LFGListFrame.CategorySelection
            local start = cs and cs.StartGroupButton
            if start and not start:IsEnabled() and not InCombatLockdown() and not C_LFGList.HasActiveEntryInfo()
               and UI.Data.CanApply() then
                start:Enable()
            end
            win.tabs:Select(3)
        end)
        over:SetScript("PostClick", function(_, _, down)
            if not ActsOn(down) then return end
            -- Blizzard's window closes again and its title box moves in.
            local page = ({ raid = UI.RaidCreate, dungeon = UI.DungeonCreate })[Saved().section] or UI.Create
            if page then C_Timer.After(0.1, page.AfterStart or page.Refresh) end
        end)
        over:SetScript("OnEnter", function() local f = target:GetScript("OnEnter"); if f then f(target) end end)
        over:SetScript("OnLeave", function() local f = target:GetScript("OnLeave"); if f then f(target) end end)
        return over
    end
    Trigger(win.tabs.tabs[3], "GQEACreateTab")
    for _, target in ipairs(UI.createTargets or {}) do Trigger(target, nil, true) end
    -- The window resized or moved: the floating overlays follow.
    local function PlaceAll() for _, f in ipairs(floats) do f() end end
    win:HookScript("OnSizeChanged", PlaceAll)
    win.PlaceFloats = PlaceAll   -- and when it opens (its OnShow, below)

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
    -- You as a Keystone Deserter: a shining tag at the far right, with a
    -- tooltip on what it means.
    local tag = W.DeserterTag(foot)
    tag:SetPoint("RIGHT", -S.pad - 18, 0)   -- room for the size grip
    tag:Hide()
    tag:EnableMouse(true)
    tag:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Keystone Deserter", unpack(C.deserter))
        GameTooltip:AddLine("Blizzard marks you for leaving Mythic+ runs early. Group leaders see the mark on your applications, and players see it on your listing.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Finish Mythic+ runs (timed or not) to lose it. A run ended by an abandon vote doesn't count against you.", 0.6, 0.65, 0.72, true)
        GameTooltip:Show()
    end)
    tag:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- You: name, rating, item level, deserter mark (fresh each time the window opens).
    local function PaintMe()
        local _, class = UnitClass("player")
        local score = UI.Data.Num(C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore()) or 0
        local _, ilvl = GetAverageItemLevel()
        me:SetText(("%s%s|r  ·  %s%d|r  ·  ilvl %d"):format(T.ColorCode(T.ClassColor(class)), UnitName("player"),
            T.ColorCode(T.RatingColor(score)), score, math.floor(UI.Data.Num(ilvl) or 0)))
        local leaver = UI.Data.PlayerLeaver()
        tag:SetShown(leaver)
        me:ClearAllPoints()
        if leaver then
            me:SetPoint("RIGHT", tag, "LEFT", -10, 0)
        else
            me:SetPoint("RIGHT", -S.pad - 18, 0)   -- room for the size grip
            if GameTooltip:IsOwned(tag) then GameTooltip:Hide() end
        end
    end
    win.PaintMe = PaintMe
    -- The mark can come or go while the window is open.
    local meEvents = CreateFrame("Frame")
    ns.Live(meEvents, { "INSTANCE_LEAVER_STATUS_CHANGED" })
    meEvents:SetScript("OnEvent", PaintMe)
    -- Great Vault and affixes, left of your line (UI/Vault.lua).
    UI.Vault.Build(foot, me)

    -- First start: the welcome screen over the pages.
    UI.Welcome.Build(win, function(key)
        UI.Welcome.Done()
        UI.SetSection(key)
    end)

    UI.Settings.Build(win)

    SizeGrip()
    -- Events and the combat watch only while the window is open.
    win:SetScript("OnShow", function()
        ns.SetLive(true)
        PaintMe()
        UI.Vault.Request()
        if win.PlaceFloats then win.PlaceFloats() end
        FitScale()
        A.FadeIn(win, 0.18)
        if UI.Group and UI.Group.Refresh then UI.Group.Refresh() end
    end)
    win:SetScript("OnHide", function()
        ns.SetLive(false)
        UI.Settings.Hide()   -- next time the window opens on its pages
        -- No events while closed: each results page catches up on its next show.
        for _, p in ipairs({ UI.Browse, UI.RaidBrowse, UI.DungeonBrowse }) do p.stale = true end
    end)
    win.tabs:Select(1, true)
    for j, p in ipairs(win.pages) do p:SetShown(j == 1) end
    local section = Saved().section
    UI.SetSection(win.sections[section] and section or "mplus", true)
    if UI.Welcome.Due() then UI.Welcome.Show() end
end

-- Mythic+ or Raid: which Browse page shows (saved per account).
local SECTION_NAME = { mplus = "Mythic+", dungeon = "Mythic 0", raid = "Raid" }
function UI.SetSection(key, quiet)
    if not (win and win.sections and win.sections[key]) then return end
    Saved().section = key
    for k, f in pairs(win.sections) do f:SetShown(k == key) end
    for k, f in pairs(win.createSections) do f:SetShown(k == key) end
    if win.WireStart then win.WireStart() end
    for k, b in pairs(win.sectionButtons) do b:SetVariant(k == key and "ghost" or "mark") end
    win.subtitle:SetText(SECTION_NAME[key])
    if not quiet then
        UI.Welcome.Done()   -- a section picked in the header: the welcome screen has done its job
        win.tabs:Select(1)
        A.FadeIn(win.sections[key], 0.2)
    end
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

-- /gotta deserter switched: footer, groups and applicants show it at once.
function UI.RefreshDeserter()
    if not (win and win:IsShown()) then return end   -- OnShow paints all of it
    win.PaintMe()
    if UI.Browse and UI.Browse.Reread then UI.Browse.Reread() end
    if UI.Group and UI.Group.Refresh then UI.Group.Refresh() end
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

-- The tab showing (nil while the window is closed).
function UI.ActiveTab()
    return win and win:IsShown() and win.tabs and win.tabs.active or nil
end

function UI.Toggle()
    if InCombatLockdown() then ns.Print("the window opens after combat."); return end
    if not win then Build() end
    win:SetShown(not win:IsShown())
end

-- The window with its settings page (the gear, the minimap button's
-- right-click, /gotta settings).
function UI.ShowSettings()
    if InCombatLockdown() then ns.Print("the window opens after combat."); return end
    if not win then Build() end
    win:Show()
    UI.Settings.Show()
end

-- The window on a tab (an alert's message: Your Group).
function UI.OpenTab(i)
    if InCombatLockdown() then ns.Print("the window opens after combat."); return end
    if not win then Build() end
    win:Show()
    UI.Settings.Hide()
    UI.Welcome.Done()
    win.tabs:Select(i)
end

-- /gotta welcome: the window with its welcome screen.
function UI.ShowWelcome()
    if InCombatLockdown() then ns.Print("the window opens after combat."); return end
    if not win then Build() end
    win:Show()
    UI.Welcome.Show()
end
