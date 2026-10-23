-------------------------------------------------------------------------------
--  UI/Alert.lua  --  when you're invited, when someone applies to the group
--  you lead (members of someone else's group get no applicant alerts; an
--  answered invite or a joined group takes the message away)
--
--  On screen (setting "alertScreen"): a gold edge ("glow"; it breathes
--  until an invite is answered, twice for an applicant) or nothing ("off";
--  older "toast" counts as off, "both" as glow). Invites show no message at
--  the top (the card or Blizzard's window says it all); applicants and "you
--  joined" do. Plus a sound on the Master channel and the taskbar
--  icon flashing while WoW is in the background (FlashClientIcon only
--  flashes then).
--  Invites and applicants come while the window is closed, so these two
--  Group Finder events stay registered (the only ones that do); both are
--  rare and do nothing unless they're about you.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A = UI.Theme, UI.W, UI.Anim
local C = T.C

local AL = {}
UI.Alert = AL

local function DB() return ns.DB and ns.DB() end

-- Sounds to pick from (Settings); only the ones this client has.
AL.SOUNDS = {}
local function AddSound(key, name, kit)
    if kit then AL.SOUNDS[#AL.SOUNDS + 1] = { key = key, name = name, kit = kit } end
end
AddSound("chime", "Soft chime", SOUNDKIT.UI_GROUP_FINDER_RECEIVE_APPLICATION or SOUNDKIT.IG_PLAYER_INVITE)
AddSound("ready", "Ready check", SOUNDKIT.READY_CHECK)
AddSound("whisper", "Whisper", SOUNDKIT.TELL_MESSAGE)
AddSound("warning", "Raid warning", SOUNDKIT.RAID_WARNING)

function AL.PlaySound(key)
    for _, s in ipairs(AL.SOUNDS) do
        if s.key == key then pcall(PlaySound, s.kit, "Master"); return end
    end
    if AL.SOUNDS[1] then pcall(PlaySound, AL.SOUNDS[1].kit, "Master") end
end

-------------------------------------------------------------------------------
--  The gold edge
-------------------------------------------------------------------------------
local glow
local EDGE, LINE = 110, 22

local function BuildGlow()
    glow = CreateFrame("Frame", nil, UIParent)
    glow:SetAllPoints(UIParent)
    -- Under every window (the invite card sits in the top edge): the edge
    -- lights the game world, never the card or other windows.
    glow:SetFrameStrata("BACKGROUND")
    glow:SetFrameLevel(0)
    glow:EnableMouse(false)
    glow:Hide()
    local soft, clear = { 0.82, 0.64, 0.30, 0.55 }, { 0.82, 0.64, 0.30, 0 }
    local bright, clear2 = { 0.90, 0.76, 0.48, 0.35 }, { 0.90, 0.76, 0.48, 0 }
    -- side, size, its two anchors, gradient orientation, outer edge first?
    -- The gradients are set again each time the edge shows (PaintGlow): set
    -- before the frame ever drew, their alpha got lost and the edges came
    -- out solid gold, deep into the screen.
    glow.sides = {}
    local function Edge(size, inner, outer)
        -- Each band is pinned by two opposite corners (no SetHeight or
        -- SetWidth to lose): it can never grow past "size" into the screen.
        -- a, b: the band's corners on the screen's (b moved in by size).
        local function Side(a, b, bTo, x, y, orient, outerFirst)
            local t = W.Tex(glow, "BACKGROUND")
            t:SetPoint(a, glow, a)
            t:SetPoint(b, glow, bTo, x, y)
            local from, to = inner, outer
            if outerFirst then from, to = outer, inner end
            glow.sides[#glow.sides + 1] = { t, orient, from, to }
        end
        Side("TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", 0, -size, "VERTICAL", false)       -- top: bottom clear, top gold
        Side("BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", 0, size, "VERTICAL", true)      -- bottom: bottom gold
        Side("TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", size, 0, "HORIZONTAL", true)     -- left: left gold
        Side("TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", -size, 0, "HORIZONTAL", false)  -- right: right gold
    end
    Edge(EDGE, clear, soft)
    Edge(LINE, clear2, bright)

    local g = glow:CreateAnimationGroup()
    g:SetToFinalAlpha(true)
    for i, step in ipairs({ { 0, 0.9, 0.5 }, { 0.9, 0.35, 0.65 }, { 0.35, 0.8, 0.65 }, { 0.8, 0, 1.8 } }) do
        local a = g:CreateAnimation("Alpha")
        a:SetOrder(i)
        a:SetFromAlpha(step[1]); a:SetToAlpha(step[2]); a:SetDuration(step[3])
        a:SetSmoothing("IN_OUT")
    end
    g:SetScript("OnFinished", function() glow:Hide() end)
    glow.anim = g
end

local function PaintGlow()
    for _, s in ipairs(glow.sides) do W.Gradient(s[1], s[2], s[3], s[4]) end
end

-- hold: the edge keeps breathing until AL.Dismiss (an invite waiting for
-- its answer); otherwise it breathes twice and fades.
local function PlayGlow(hold)
    if not glow then BuildGlow() end
    glow.anim:Stop()
    glow.anim:SetLooping(hold and "REPEAT" or "NONE")
    glow:SetAlpha(0)
    glow:Show()
    PaintGlow()
    C_Timer.After(0, PaintGlow)   -- once more after the first frame drew
    glow.anim:Play()
end

-------------------------------------------------------------------------------
--  The message at the top
-------------------------------------------------------------------------------
local toast
local TOAST_W, TOAST_H, HOLD = 400, 70, 6

local function BuildToast()
    toast = CreateFrame("Button", nil, UIParent)
    toast:SetSize(TOAST_W, TOAST_H)
    toast:SetPoint("TOP", UIParent, "TOP", 0, -140)
    toast:SetFrameStrata("FULLSCREEN_DIALOG")
    toast:SetClampedToScreen(true)
    toast:Hide()
    toast.bg = W.Round(toast, "BACKGROUND", { 0.04, 0.055, 0.08, 0.95 })
    toast.bg:SetAllPoints()
    W.Border(toast, { 0.82, 0.64, 0.30, 0.75 }, "OVERLAY")
    local logo = toast:CreateTexture(nil, "ARTWORK")
    logo:SetSize(40, 40)
    logo:SetPoint("LEFT", 14, 0)
    logo:SetTexture(T.MEDIA .. "logo-qlens-mark")
    toast.eyebrow = W.Text(toast, "tiny", C.goldText)
    toast.eyebrow:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, 4)
    toast.big = W.Text(toast, "h2")
    toast.big:SetPoint("TOPLEFT", toast.eyebrow, "BOTTOMLEFT", 0, -3)
    toast.big:SetPoint("RIGHT", -14, 0)
    toast.small = W.Text(toast, "small")
    toast.small:SetPoint("TOPLEFT", toast.big, "BOTTOMLEFT", 0, -3)
    toast.small:SetPoint("RIGHT", -14, 0)
    toast.shine = A.Shine(toast, nil, 0.22, true)

    local out = toast:CreateAnimationGroup()
    out:SetToFinalAlpha(true)
    local a = out:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0); a:SetDuration(0.6)
    out:SetScript("OnFinished", function() toast:Hide() end)
    toast.out = out

    toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    toast:SetScript("OnClick", function(self)
        self:Hide()
        if self.onClick then self.onClick() end
    end)
end

-- text: { eyebrow, big, small, bigColor, onClick }
local toastToken = 0
local function PlayToast(text)
    if not toast then BuildToast() end
    toast.out:Stop()
    toast.eyebrow:SetText(text.eyebrow or "")
    pcall(toast.big.SetText, toast.big, text.big or "")   -- a group title can be a K-string: shown, not read
    toast.big:SetTextColor(unpack(text.bigColor or C.textHi))
    toast.small:SetText(text.small or "")
    toast.onClick = text.onClick
    toast.notice = nil
    toast:Show()
    A.Rise(toast, 0, -12, 0.35)
    C_Timer.After(0.35, function() if toast:IsShown() then toast.shine.Sweep() end end)
    toastToken = toastToken + 1
    local mine = toastToken
    C_Timer.After(HOLD, function()
        if mine == toastToken and toast:IsShown() then toast.out:Play() end
    end)
end

-------------------------------------------------------------------------------
--  One alert, by the settings
-------------------------------------------------------------------------------
-- invite: Blizzard's invite window plays the Ready Check sound and flashes
-- the taskbar icon itself (LFGListInviteDialog_Show, also while our card
-- answers and its window stays unseen): no second flash, and no second
-- Ready Check sound. hold: the edge breathes until the invite is
-- answered. Invites (and their preview, text.invite) get no message at
-- the top: the card or Blizzard's window says it all.
local function Fire(text, invite, hold)
    local db = DB() or {}
    local screen = db.alertScreen or "glow"
    if screen ~= "off" and screen ~= "toast" then PlayGlow(hold) end
    if not (invite or text.invite) then PlayToast(text) end   -- invites: the card or Blizzard's window
    if db.alertSound ~= false and not (invite and db.alertSoundKit == "ready") then AL.PlaySound(db.alertSoundKit) end
    if db.alertFlash ~= false and not invite and FlashClientIcon then FlashClientIcon() end
end

local D = UI.Data
local function Num(v) return D.Num(v) end
local function Str(v) return D.Str(v) end

-- An invite: the group as a toast text.
local function InviteText(id)
    local text = { eyebrow = "INVITED", small = "Accept in Blizzard's invite window" }
    local r = D.Read(id)   -- Mythic+: dungeon, key, leader
    if r then
        text.big = r.dungeon .. (r.key and (" +" .. r.key) or "")
        local who = r.leader and (T.ColorCode(T.ClassColor(r.leaderClass)) .. r.leader .. "|r") or nil
        if who then
            text.small = who .. (r.leaderSpec and ("  " .. r.leaderSpec) or "") .. "  ·  "
                .. T.ColorCode(T.RatingColor(r.rating)) .. math.floor(r.rating) .. "|r  ·  " .. text.small
        end
        return text
    end
    -- Raid, Mythic 0, anything else: the activity's name and the leader.
    local info = D.Tab(C_LFGList.GetSearchResultInfo(id))
    local ids = info and D.Tab(info.activityIDs)
    local ai = ids and Num(ids[1]) and D.Tab(C_LFGList.GetActivityInfoTable(ids[1]))
    text.big = ai and Str(ai.fullName) or (info and info.name) or "A group"
    local leader = info and Str(info.leaderName)
    if leader then text.small = Ambiguate(leader, "short") .. "  ·  " .. text.small end
    return text
end

-- The window on Your Group (a click on the applicant message).
local function OpenGroup()
    if UI.OpenTab then UI.OpenTab(2) end
end

-- Applicants are the leader's business (Blizzard: LFGListUtil_IsAppEmpowered).
-- In someone else's group you get no applicant alerts.
local function Leading() return not IsInGroup() or UnitIsGroupLeader("player") end

-- New applicants: alerted once each, while your listing is up.
local seen = {}

-- Everyone waiting now counts as seen: you joined a listed group or became
-- its leader; only applicants after that alert.
local function SeeAll()
    local ok, ids = pcall(C_LFGList.GetApplicants)
    for _, id in ipairs(ok and D.Tab(ids) or {}) do seen[id] = true end
end

local function NewApplicants()
    local db = DB()
    if not (db and db.alertApply ~= false) or not C_LFGList.HasActiveEntryInfo() then return end
    if not Leading() then SeeAll(); return end
    local fresh = {}
    local ok, ids = pcall(C_LFGList.GetApplicants)
    for _, id in ipairs(ok and D.Tab(ids) or {}) do
        local info = Num(id) and D.Tab(C_LFGList.GetApplicantInfo(id))
        local status = info and (Str(info.pendingApplicationStatus) or Str(info.applicationStatus))
        if info and status == "applied" and D.True(info.isNew) and not seen[id] then
            local name, class, _, _, ilvl, _, _, _, _, _, _, score, _, _, _, specID = C_LFGList.GetApplicantMemberInfo(id, 1)
            if Str(name) then   -- its data is in: alert it now, never again
                seen[id] = true
                local spec = Num(specID) and GetSpecializationInfoByID and select(2, GetSpecializationInfoByID(specID))
                fresh[#fresh + 1] = { name = Ambiguate(name, "short"), class = Str(class), spec = spec,
                                      rating = Num(score) or 0, ilvl = Num(ilvl) or 0,
                                      size = Num(info.numMembers) or 1 }
            end
        end
    end
    if #fresh == 0 then return end
    local m = fresh[1]
    local parts = {}
    if m.spec then parts[#parts + 1] = m.spec end
    parts[#parts + 1] = T.ColorCode(T.RatingColor(m.rating)) .. math.floor(m.rating) .. "|r"
    parts[#parts + 1] = "ilvl " .. math.floor(m.ilvl)
    if m.size > 1 then parts[#parts + 1] = "group of " .. m.size end
    Fire({
        eyebrow = #fresh > 1 and (#fresh .. " NEW APPLICANTS") or "NEW APPLICANT",
        big = m.name .. (#fresh > 1 and ("  |cff8d98a8+" .. (#fresh - 1) .. "|r") or ""),
        bigColor = T.ClassColor(m.class),
        small = table.concat(parts, "  ·  ") .. "  ·  click: Your Group",
        onClick = OpenGroup,
    })
end

-------------------------------------------------------------------------------
--  Events (registered always: see the top)
-------------------------------------------------------------------------------
D.appliedAt = D.appliedAt or {}   -- search result ID -> GetTime() of the sign-up (Browse's bar)

local waiting = {}   -- invites without an answer yet: the edge breathes for them

local events = CreateFrame("Frame")
events:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
events:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
events:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
events:RegisterEvent("GROUP_JOINED")
events:RegisterEvent("PARTY_LEADER_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        local id, status = Num(arg1), Str(arg2)
        if not id then return end
        if status == "applied" then
            D.appliedAt[id] = D.appliedAt[id] or GetTime()
        elseif status ~= "invited" then
            D.appliedAt[id] = nil
        end
        local db = DB()
        if status == "invited" and db and db.alertInvite ~= false then
            waiting[id] = true
            Fire(InviteText(id), true, true)
        elseif waiting[id] then   -- answered, timed out or withdrawn
            waiting[id] = nil
            if not next(waiting) then AL.Dismiss() end
        end
    elseif event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
        NewApplicants()
    elseif event == "GROUP_JOINED" then
        AL.Dismiss()   -- in a group now: the invite message has done its job
        SeeAll()
    elseif event == "PARTY_LEADER_CHANGED" then
        SeeAll()
    elseif not C_LFGList.HasActiveEntryInfo() then   -- delisted: a new listing starts fresh
        wipe(seen)
    elseif arg1 ~= true then   -- a listing you didn't just create (a group you joined)
        SeeAll()
    end
end)

-- The edge and the message go away (an invite answered, a group joined);
-- a notice (AL.Notice) runs its course.
function AL.Dismiss()
    wipe(waiting)
    if glow and glow:IsShown() then glow.anim:Stop(); glow:Hide() end
    if toast and toast:IsShown() and not toast.notice then toast.out:Play() end
end

-- A message at the top and nothing else (no edge, no sound): "you joined
-- a group" (UI/Invite.lua).
function AL.Notice(text)
    PlayToast(text)
    toast.notice = true
end

-- Settings' "Preview": the invite alert with your keystone's dungeon (or a
-- plain line), whatever the "when" switches say; with the invite card on,
-- the card instead of the message.
function AL.Preview()
    local card = UI.Invite and UI.Invite.Active()
    if card then UI.Invite.Preview() end
    local key = D.OwnKey and D.OwnKey()
    Fire({
        eyebrow = "INVITED  ·  PREVIEW",
        big = key and (key.dungeon .. (key.level and (" +" .. key.level) or "")) or "Your next group",
        small = "Accept in Blizzard's invite window",
        invite = true,
    }, false, card)   -- with the card: the edge breathes until it's answered
end
