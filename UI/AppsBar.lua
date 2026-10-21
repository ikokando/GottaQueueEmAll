-------------------------------------------------------------------------------
--  UI/AppsBar.lua  --  "Your applications": the groups you wait on
--
--  A bar above a results list (Mythic+, Raid, Mythic 0) while you have
--  sign-ups open: one chip per group with its art, key, leader and how
--  long you've waited, an x to cancel, invites in gold with a shine, and
--  the free slots. It reads your sign-ups, not the results, so a new search
--  (in any section) keeps it; Blizzard's limit is shared by all sections.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A, D = UI.Theme, UI.W, UI.Anim, UI.Data
local C = T.C
local floor = math.floor

local AB = {}
UI.AppsBar = AB

local BAR_H, CHIP_H, GAP = 92, 42, 8

local function Status(a)
    if a.status == "invited" then return "|cffe6c27aINVITED|r" end
    return "waiting" .. (a.since and (" " .. T.Clock(GetTime() - a.since)) or "")
end

-- A sign-up: dungeon art, "+14 Leader" over "waiting 2:13", a cancel x.
local function NewChip(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(CHIP_H)
    c.bg = W.Round(c, "BACKGROUND", C.raised)
    c.bg:SetAllPoints()
    W.Border(c, C.line, "OVERLAY")
    c.art = c:CreateTexture(nil, "ARTWORK")
    c.art:SetSize(36, 32)
    c.art:SetPoint("LEFT", 5, 0)
    c.short = W.Text(c, "tiny", C.textHi, "OVERLAY")
    c.short:SetPoint("CENTER", c.art)
    c.short:SetShadowOffset(0, -1); c.short:SetShadowColor(0, 0, 0, 0.9)
    c.x = W.Button(c, "×", "mark", 22, 22, "button")
    c.x:SetPoint("RIGHT", -6, 0)
    c.x:SetScript("OnClick", function(self)
        local a = self:GetParent().a
        if not a then return end
        local ok, err = pcall(D.Cancel, a.id)
        if not ok then ns.Print("could not cancel (" .. tostring(err) .. ")") end
    end)
    c.x:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Cancel this application", 1, 1, 1)
        GameTooltip:Show()
    end)
    c.x:HookScript("OnLeave", function() GameTooltip:Hide() end)
    c.line1 = W.Text(c, "bodySm", C.textHi)
    c.line1:SetPoint("TOPLEFT", c.art, "TOPRIGHT", 8, 1)
    c.line1:SetPoint("RIGHT", c.x, "LEFT", -4, 0)
    c.line2 = W.Text(c, "tiny")
    c.line2:SetPoint("BOTTOMLEFT", c.art, "BOTTOMRIGHT", 8, -1)
    c.line2:SetPoint("RIGHT", c.x, "LEFT", -4, 0)
    -- An invite shines like the gold buttons.
    c.shine = A.Shine(c)
    return c
end

local function FillChip(c, a)
    c.a = a
    local art = T.DungeonArt(a.cid)
    if art.button then
        c.art:SetTexture(art.button)
        c.art:SetTexCoord(0.10, 0.58, 0.05, 0.70)
        c.art:SetVertexColor(0.8, 0.8, 0.8)
    elseif art.icon then
        c.art:SetTexture(art.icon)
        c.art:SetTexCoord(0.08, 0.92, 0.12, 0.88)
        c.art:SetVertexColor(0.8, 0.8, 0.8)
    else   -- no dungeon art (a raid): a navy square with the short name
        c.art:SetTexture(T.WHITE)
        c.art:SetTexCoord(0, 1, 0, 1)
        c.art:SetVertexColor(unpack(C.navy))
    end
    c.short:SetText(T.Short(a.dungeon))
    c.line1:SetText((a.key and ("+" .. a.key .. "  ") or "") .. T.ColorCode(T.ClassColor(a.leaderClass)) .. (a.leader or "?") .. "|r")
    c.line2:SetText(Status(a))
    local invited = a.status == "invited"
    c.x:SetShown(not invited)   -- an invite is answered in Blizzard's popup
    c.shine:SetShown(invited)
    c.bg:SetVertexColor(unpack(invited and { 0.82, 0.64, 0.30, 0.12 } or C.raised))
    W.SetBorder(c, invited and { 0.82, 0.64, 0.30, 0.7 } or C.line)
end

-- A bar for a results page. row2: the filter row it sits under; count and
-- scroll: the count line and the list, moved down while the bar shows.
-- bar:Paint(refetch) lays the bar out from your sign-ups (renders; set
-- bar.dirty first when they changed) or only ticks the waiting times;
-- bar.n is how many are open.
function AB.New(page, row2, count, scroll)
    local p = W.Panel(page, C.panel, C.lineStrong)
    p:SetHeight(BAR_H)
    p:Hide()
    local lbl = W.Label(p, "Your applications")
    lbl:SetPoint("TOPLEFT", 12, -11)
    local num = W.Text(p, "button", C.textHi)
    num:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    local dots = {}
    for i = 1, 8 do
        local d = W.Circle(p, "ARTWORK", C.track, 8)
        d:SetPoint("LEFT", num, "RIGHT", 10 + (i - 1) * 12, 0)
        dots[i] = d
    end
    local hint = W.Text(p, "small")
    hint:SetPoint("TOPRIGHT", -12, -11)
    hint:SetText("Stays while you search again")
    local free = CreateFrame("Frame", nil, p)
    free:SetHeight(CHIP_H)
    W.Border(free, C.line)
    free.text = W.Text(free, "small", C.faint)
    free.text:SetPoint("CENTER")

    local bar = { frame = p, chips = {}, list = {}, n = 0 }

    -- Count line and list below the filters, with the bar in between when shown.
    local function Layout()
        local y = -10
        if p:IsShown() then
            p:SetPoint("TOPLEFT", row2, "BOTTOMLEFT", 0, y)
            p:SetPoint("TOPRIGHT", row2, "BOTTOMRIGHT", 0, y)
            y = y - BAR_H - 10
        end
        count:ClearAllPoints()
        count:SetPoint("TOPLEFT", row2, "BOTTOMLEFT", 0, y)
        scroll:SetPoint("TOPLEFT", row2, "BOTTOMLEFT", 0, y - 22)
    end

    function bar:Paint(refetch)
        -- Renders come often (a slider drag): your sign-ups are read again
        -- when they changed (the page's status event sets dirty) or now and then.
        if refetch and (self.dirty or not self.readAt or GetTime() - self.readAt > 2) then
            self.list = D.Applications()
            self.dirty, self.readAt = false, GetTime()
        end
        local list = self.list
        self.n = #list
        local shown = #list > 0
        if shown ~= p:IsShown() then
            p:SetShown(shown)
            Layout()
        end
        if not shown then return end
        if not refetch then
            for _, c in ipairs(self.chips) do if c:IsShown() and c.a then c.line2:SetText(Status(c.a)) end end
            return
        end
        local maxN = D.MAX_APPLICATIONS
        num:SetText(("%d / %d"):format(#list, maxN))
        for i, dot in ipairs(dots) do
            dot:SetShown(i <= maxN)
            dot:SetVertexColor(unpack(i <= #list and C.goldText or C.track))
        end
        -- One slot per possible sign-up, all as wide (at most 220).
        local w = math.min(220, floor((p:GetWidth() - 24 - (maxN - 1) * GAP) / maxN))
        if w < 60 then   -- just shown, not laid out yet: once more next frame
            w = 160
            C_Timer.After(0, function() if p:IsShown() then bar:Paint(true) end end)
        end
        local prev
        for i, a in ipairs(list) do
            local c = self.chips[i] or NewChip(p)
            self.chips[i] = c
            FillChip(c, a)
            c:SetWidth(w)
            c:ClearAllPoints()
            if prev then c:SetPoint("LEFT", prev, "RIGHT", GAP, 0) else c:SetPoint("BOTTOMLEFT", 12, 12) end
            c:Show()
            prev = c
        end
        for i = #list + 1, #self.chips do self.chips[i]:Hide() end
        local nFree = maxN - #list
        free:SetShown(nFree > 0)
        if nFree > 0 then
            free.text:SetText(nFree == 1 and "1 free" or (nFree .. " free"))
            free:SetWidth(w)
            free:ClearAllPoints()
            free:SetPoint("LEFT", prev, "RIGHT", GAP, 0)
        end
    end

    -- A Sign up button's state when all sign-ups are used: label or nil.
    function bar:FullLabel()
        if self.n >= D.MAX_APPLICATIONS then return ("%d / %d applied"):format(self.n, D.MAX_APPLICATIONS) end
    end
    return bar
end
