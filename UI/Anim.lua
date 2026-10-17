-------------------------------------------------------------------------------
--  UI/Anim.lua  --  the window's effects, all Blizzard AnimationGroups
--
--  Nothing here runs an OnUpdate: animations play on show, on hover or on a
--  state change and stop on their own. Looping ones (pulse, shine, live dot)
--  run only while their frame is visible; WoW pauses hidden animations.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local A = {}
UI.Anim = A

-- Rise: slide in from below and fade in. delay staggers lists.
function A.Rise(region, delay, dy, dur)
    local g = region.gqRise
    if not g then
        g = region:CreateAnimationGroup()
        g:SetToFinalAlpha(true)
        local fade = g:CreateAnimation("Alpha")
        fade:SetFromAlpha(0)
        fade:SetToAlpha(1)
        local jump = g:CreateAnimation("Translation")   -- to the start position, instantly
        jump:SetOrder(1)
        jump:SetDuration(0)
        local move = g:CreateAnimation("Translation")
        move:SetOrder(1)
        move:SetSmoothing("OUT")
        g.fade, g.jump, g.move = fade, jump, move
        region.gqRise = g
    end
    dy, dur, delay = dy or 8, dur or 0.4, delay or 0
    g.fade:SetDuration(dur); g.fade:SetStartDelay(delay)
    g.jump:SetOffset(0, -dy)
    g.move:SetOffset(0, dy); g.move:SetDuration(dur); g.move:SetStartDelay(delay)
    g:Stop()
    region:SetAlpha(0)   -- hidden while a stagger delay runs; the fade ends at 1
    g:Play()
end

function A.FadeIn(region, dur, delay)
    local g = region.gqFade
    if not g then
        g = region:CreateAnimationGroup()
        g:SetToFinalAlpha(true)
        local a = g:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        g.a = a
        region.gqFade = g
    end
    g.a:SetDuration(dur or 0.25)
    g.a:SetStartDelay(delay or 0)
    g:Stop()
    g:Play()
end

-- Pulse: a looping alpha breath (new applicant dot, "search again").
function A.Pulse(region, low, period)
    local g = region:CreateAnimationGroup()
    g:SetLooping("BOUNCE")
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(low or 0.35)
    a:SetDuration((period or 1.6) / 2)
    a:SetSmoothing("IN_OUT")
    g:Play()
    return g
end

-- Ping (breathe): a soft halo around a dot (live / new marker) that grows
-- while fading and eases back, without ever restarting: BOUNCE plays the
-- same motion forwards and backwards, so the loop has no seam.
function A.Ping(parent, dot, color, size)
    -- A disc texture (a mask would not scale with the ring).
    local ring = parent:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(UI.Theme.TEX .. "circle")
    ring:SetVertexColor(unpack(color))
    ring:SetSize(size, size)
    ring:SetPoint("CENTER", dot)
    local g = ring:CreateAnimationGroup()
    g:SetLooping("BOUNCE")
    local s = g:CreateAnimation("Scale")
    s:SetScaleFrom(1.1, 1.1)
    s:SetScaleTo(2.3, 2.3)
    s:SetDuration(1.5)
    s:SetSmoothing("IN_OUT")
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(0.45)
    a:SetToAlpha(0.06)
    a:SetDuration(1.5)
    a:SetSmoothing("IN_OUT")
    g:Play()
    return ring
end

-- Grow: an underline that scales out from its center (active tab).
function A.Grow(region, dur)
    local g = region.gqGrow
    if not g then
        g = region:CreateAnimationGroup()
        local s = g:CreateAnimation("Scale")
        s:SetScaleFrom(0.01, 1)
        s:SetScaleTo(1, 1)
        s:SetOrigin("CENTER", 0, 0)
        s:SetSmoothing("OUT")
        g.s = s
        region.gqGrow = g
    end
    g.s:SetDuration(dur or 0.35)
    g:Stop()
    g:Play()
end

-- Shine: a soft light band that sweeps across a frame every few seconds
-- (gold buttons). The frame clips it.
function A.Shine(frame, period)
    frame:SetClipsChildren(true)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints()
    holder:SetFrameLevel(frame:GetFrameLevel() + 2)
    -- The band starts fully left of the frame (clipped away) between sweeps.
    local w = 46
    local right = holder:CreateTexture(nil, "OVERLAY")
    right:SetTexture(UI.Theme.WHITE)
    right:SetSize(w / 2, 400)
    right:SetPoint("RIGHT", holder, "LEFT", -8, 0)
    local left = holder:CreateTexture(nil, "OVERLAY")
    left:SetTexture(UI.Theme.WHITE)
    left:SetSize(w / 2, 400)
    left:SetPoint("RIGHT", right, "LEFT", 0, 0)
    left:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.42))
    right:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0.42), CreateColor(1, 1, 1, 0))
    left:SetRotation(math.rad(-18)); right:SetRotation(math.rad(-18))

    local groups = {}
    for i, tex in ipairs({ left, right }) do
        local g = tex:CreateAnimationGroup()
        g:SetLooping("REPEAT")
        local t = g:CreateAnimation("Translation")
        t:SetDuration(0.9)
        t:SetStartDelay((period or 3.4) - 0.9)
        t:SetSmoothing("IN_OUT")
        g.t = t
        groups[i] = g
    end
    -- The sweep distance follows the frame's width.
    local function Build()
        for _, g in ipairs(groups) do
            g:Stop()
            g.t:SetOffset(frame:GetWidth() + w + 16, 0)
            g:Play()
        end
    end
    holder:SetScript("OnSizeChanged", Build)
    Build()
    return holder
end
