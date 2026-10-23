-------------------------------------------------------------------------------
--  UI/Invite.lua  --  invites answered in a card of our own
--
--  A leader invites you: a card at the top of the screen with the dungeon's
--  art, the key, the leader (flag, country and realm: UI/Region.lua), the
--  group as a lineup of spec portraits (Mythic+: class, spec and role of
--  each member; only the leader's name is known before you join), chips for
--  Lust, B-Res, open spots, friends, guild mates, playstyle and voice, the
--  leader's and your best run in the dungeon, the role you join as; Accept and
--  Decline answer right there (C_LFGList.AcceptInvite / DeclineInvite, what
--  Blizzard's own buttons call). More invites at once stack below the card
--  as small rows; a click brings one into the card.
--
--  Blizzard's invite window still opens, unseen and unclickable: its own
--  events close it once the invite is answered, and should WoW ever block
--  our buttons, it is shown again as it was (ADDON_ACTION_BLOCKED). Its
--  "you have joined a group" notice with an OK to click is closed at once;
--  a short message at the top says it and fades by itself.
--  Setting "inviteCard" (default on); off = Blizzard's window as before.
-------------------------------------------------------------------------------
local ADDON, ns = ...
local UI = ns.UI
local T, W, A, D = UI.Theme, UI.W, UI.Anim, UI.Data
local C = T.C
local floor = math.floor

local IV = {}
UI.Invite = IV

local CARD_W, ART_H, INSET = 360, 76, 4
local ROW_H, ROW_GAP = 44, 6

local invites = {}     -- result IDs invited, oldest first
local invitedAt = {}   -- result ID -> GetTime() of the invite
local selected         -- the one in the card
local blocked = false  -- WoW blocked our buttons this session: Blizzard's window answers

local function DB() return ns.DB and ns.DB() end

-- Only who may answer sees invites (Blizzard: LFGListUtil_IsAppEmpowered).
local function Empowered() return not IsInGroup() or UnitIsGroupLeader("player") end

function IV.Active()
    local db = DB()
    return db ~= nil and db.inviteCard ~= false and db.alertInvite ~= false and not blocked
end

-------------------------------------------------------------------------------
--  One invite as a plain table
-------------------------------------------------------------------------------
-- Mythic+: D.Read. Raid, Mythic 0, anything else: the activity's name, the
-- leader and the group's size by role.
local function Read(id)
    local r = D.Read(id)
    if r then r.mplus = true end
    if not r then
        local info = D.Tab(C_LFGList.GetSearchResultInfo(id))
        if not info then return end
        local ids = D.Tab(info.activityIDs)
        local ai = ids and D.Num(ids[1]) and D.Tab(C_LFGList.GetActivityInfoTable(ids[1]))
        r = { id = id, dungeon = ai and D.Str(ai.fullName) or "A group", title = info.name,
              leader = D.Str(info.leaderName), members = {} }
        if r.leader then r.leader = Ambiguate(r.leader, "short") end
        local li = D.Tab(C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(id))
        if li then r.leaderClass, r.leaderSpec = D.Str(li.classFilename), D.Str(li.specName) end
        local mc = D.Tab(C_LFGList.GetSearchResultMemberCounts(id))
        if mc then
            r.counts = { TANK = D.Num(mc.TANK) or 0, HEALER = D.Num(mc.HEALER) or 0, DAMAGER = D.Num(mc.DAMAGER) or 0 }
        end
        r.size = D.Num(info.numMembers) or 0
    end
    -- For the card only: friends and guild mates in the group, voice, playstyle.
    local info = D.Tab(C_LFGList.GetSearchResultInfo(id))
    if info then
        r.leaderFull = r.leaderFull or D.Str(info.leaderName)
        r.guild = D.Num(info.numGuildMates) or 0
        r.friends = (D.Num(info.numBNetFriends) or 0) + (D.Num(info.numCharFriends) or 0)
        local voice = D.Str(info.voiceChat)
        r.voice = voice and voice ~= "" and voice or nil
        r.playstyle = r.playstyle or D.Num(info.generalPlaystyle)
    end
    local role = select(5, C_LFGList.GetApplicationInfo(id))
    r.myRole = D.Str(role) or D.PlayerRole()
    if r.myRole ~= "TANK" and r.myRole ~= "HEALER" then r.myRole = "DAMAGER" end
    return r
end

-------------------------------------------------------------------------------
--  The card
-------------------------------------------------------------------------------
local card, rows = nil, {}
local ROLE_NAME = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
local ROLE_GLYPH = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local BODY_W = CARD_W - INSET - 8 - 12
local SLOT_W, PORTRAIT = floor(BODY_W / 5), 40
local GAP = 10

-- A spec's icon from its class and (localized) name; nil = not found.
local specIcons
local function SpecIcon(classFile, specName)
    if not (classFile and specName) then return end
    if not specIcons then
        specIcons = {}
        local info = GetSpecializationInfoForClassID
        local count = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
        if info and count and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
            for classID = 1, 20 do   -- class IDs run 1 .. 13 today
                local ci = C_CreatureInfo.GetClassInfo(classID)
                if ci and ci.classFile then
                    local t = {}
                    for j = 1, count(classID) or 0 do
                        local _, name, _, icon = info(classID, j)
                        if name and icon then t[name] = icon end
                    end
                    specIcons[ci.classFile] = t
                end
            end
        end
    end
    return specIcons[classFile] and specIcons[classFile][specName]
end

-- Cover-style crop: keep the picture's aspect, cut top and bottom evenly.
local function Cover(tex, w, h, srcAspect, box)
    local l, r, t, b = unpack(box or { 0, 1, 0, 1 })
    local v = math.min(1, srcAspect / (w / h))
    local mid, half = (t + b) / 2, (b - t) * v / 2
    tex:SetTexCoord(l, r, mid - half, mid + half)
end

local function SetArt(r)
    local art = r.cid and T.DungeonArt(r.cid) or {}
    local w, h = CARD_W - 2 * INSET, ART_H
    if art.bg then
        card.art:SetTexture(art.bg); Cover(card.art, w, h, 2)
    elseif art.button then
        card.art:SetTexture(art.button); Cover(card.art, w, h, 175 / 95, { 0.048, 0.636, 0, 0.742 })
    elseif art.lore or art.framed then
        card.art:SetTexture(art.lore or art.framed); Cover(card.art, w, h, 2.13, { 0.06, 0.70, 0.10, 0.70 })
    else
        card.art:SetTexture(T.WHITE); card.art:SetTexCoord(0, 1, 0, 1)
        card.art:SetVertexColor(unpack(C.badge))
        return
    end
    card.art:SetVertexColor(1, 1, 1, 1)
end

local function Clock()
    if not card or not card:IsShown() then return end
    local at = card.preview and card.previewAt or (selected and invitedAt[selected])
    card.clock:SetText(at and T.Clock(GetTime() - at) or "")
end

-------------------------------------------------------------------------------
--  The lineup: one portrait per spot, members first, then the open spots
-------------------------------------------------------------------------------
-- A round spec icon in a ring of the class color, the role at its foot.
-- The leader's ring turns slowly; your open spot breathes in gold.
local function Slot(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(SLOT_W, PORTRAIT + 34)
    local p = CreateFrame("Frame", nil, s)
    p:SetSize(PORTRAIT, PORTRAIT)
    p:SetPoint("TOP", 0, -2)
    s.disc = W.Circle(p, "BACKGROUND", C.badge, PORTRAIT)
    s.disc:SetPoint("CENTER")
    s.icon = p:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(PORTRAIT - 6, PORTRAIT - 6)
    s.icon:SetPoint("CENTER")
    local mask = p:CreateMaskTexture()
    mask:SetTexture(T.TEX .. "circle", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(s.icon)
    s.icon:AddMaskTexture(mask)
    s.ring = p:CreateTexture(nil, "OVERLAY")
    s.ring:SetAllPoints()
    s.lead = p:CreateTexture(nil, "OVERLAY", nil, 1)
    s.lead:SetTexture(T.TEX .. "ring-dashed")
    s.lead:SetSize(PORTRAIT + 10, PORTRAIT + 10)
    s.lead:SetPoint("CENTER")
    s.lead:SetVertexColor(unpack(C.goldLight))
    local spin = s.lead:CreateAnimationGroup()
    spin:SetLooping("REPEAT")
    local rot = spin:CreateAnimation("Rotation")
    rot:SetDegrees(-360)
    rot:SetDuration(10)
    spin:Play()
    s.mid = W.Glyph(p, "dps", 20, C.faint, "OVERLAY")   -- an open spot's role, in the middle
    s.mid:SetPoint("CENTER")
    local badge = CreateFrame("Frame", nil, p)
    badge:SetSize(17, 17)
    badge:SetPoint("BOTTOMRIGHT", 4, -3)
    badge:SetFrameLevel(p:GetFrameLevel() + 2)
    local bd = W.Circle(badge, "BACKGROUND", C.navy, 17)
    bd:SetPoint("CENTER")
    local br = badge:CreateTexture(nil, "BORDER")
    br:SetTexture(T.TEX .. "ring")
    br:SetAllPoints()
    br:SetVertexColor(unpack(C.lineStrong))
    s.role = W.Glyph(badge, "dps", 11, C.goldLight)
    s.role:SetPoint("CENTER")
    s.badge = badge
    -- Your spot breathes: a soft gold ring of a fixed size whose alpha goes
    -- up and down (no growing: a scaled halo spread over the whole screen).
    s.halo = p:CreateTexture(nil, "BACKGROUND", nil, -1)
    s.halo:SetTexture(T.TEX .. "circle")
    s.halo:SetSize(PORTRAIT + 14, PORTRAIT + 14)
    s.halo:SetPoint("CENTER")
    s.halo:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.35)
    A.Pulse(s.halo, 0.2, 2.4)
    s.name = W.Text(s, "tiny", C.text2)
    s.name:SetPoint("TOP", p, "BOTTOM", 0, -6)
    s.name:SetWidth(SLOT_W - 2)
    s.name:SetJustifyH("CENTER")
    s.sub = W.Text(s, "tiny", C.muted)
    s.sub:SetPoint("TOP", s.name, "BOTTOM", 0, -2)
    s.sub:SetWidth(SLOT_W - 2)
    s.sub:SetJustifyH("CENTER")

    -- m: { role, class, spec, leader, name } or nil for an open spot;
    -- mine: the open spot you would take.
    function s:Set(role, m, mine)
        self.role:SetTexture(T.TEX .. "glyph-" .. ROLE_GLYPH[role])
        self.mid:SetTexture(T.TEX .. "glyph-" .. ROLE_GLYPH[role])
        self.lead:SetShown(m ~= nil and m.leader or false)
        self.halo:SetShown(mine or false)
        if m then
            local col = T.ClassColor(m.class)
            local icon = SpecIcon(m.class, m.spec)
            if icon then
                self.icon:SetTexture(icon); self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif m.class then
                self.icon:SetAtlas("classicon-" .. m.class:lower())
            else
                self.icon:SetTexture(T.TEX .. "glyph-" .. ROLE_GLYPH[role]); self.icon:SetTexCoord(0, 1, 0, 1)
            end
            self.icon:Show(); self.mid:Hide(); self.badge:Show()
            self.disc:SetVertexColor(unpack(C.badge))
            self.ring:SetTexture(T.TEX .. "ring")
            self.ring:SetVertexColor(unpack(col))
            self.name:SetText(m.name or (m.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class]) or ROLE_NAME[role])
            self.name:SetTextColor(unpack(col))
            self.sub:SetText(m.spec or "")
        else
            self.icon:Hide(); self.mid:Show(); self.badge:Hide()
            self.disc:SetVertexColor(unpack(C.empty))
            self.ring:SetTexture(T.TEX .. "ring-dashed")
            self.ring:SetVertexColor(unpack(mine and C.gold or { 0.23, 0.27, 0.34, 1 }))
            self.mid:SetVertexColor(unpack(mine and C.goldLight or C.faint))
            self.name:SetText(mine and "You" or "Open")
            self.name:SetTextColor(unpack(mine and C.goldText or C.faint))
            self.sub:SetText(ROLE_NAME[role])
        end
    end
    return s
end

-- The five spots: the leader, the other members by role, the open spots
-- (yours in gold).
local function FillLineup(r)
    local list = {}
    for _, m in ipairs(r.members) do if m.leader then list[#list + 1] = { m.role, m } end end
    for _, role in ipairs(D.ROLE_KEYS) do
        for _, m in ipairs(r.members) do
            if not m.leader and m.role == role then list[#list + 1] = { role, m } end
        end
    end
    local open = D.OpenSpots(r)
    local mineShown = false
    for _, role in ipairs(D.ROLE_KEYS) do
        for _ = 1, open[role] or 0 do
            local mine = not mineShown and role == r.myRole
            if mine then mineShown = true end
            list[#list + 1] = { role, nil, mine }
        end
    end
    for i, s in ipairs(card.slots) do
        local e = list[i]
        s:SetShown(e ~= nil)
        if e then
            local m = e[2]
            if m and m.leader then m = { role = m.role, class = m.class or r.leaderClass, spec = m.spec or r.leaderSpec,
                                         leader = true, name = r.leader } end
            s:Set(e[1], m, e[3])
        end
    end
end

-------------------------------------------------------------------------------
--  Chips: Lust, B-Res, open spots, friends, playstyle, voice
-------------------------------------------------------------------------------
local function Chips(r)
    local out = {}
    local function Add(text, color) out[#out + 1] = { text, color } end
    if r.mplus then
        if r.lust then Add("Bloodlust", C.lust) end
        if r.brez then Add("Battle res", C.brez) end
        local open, need = D.OpenSpots(r), {}
        for _, role in ipairs(D.ROLE_KEYS) do
            if (open[role] or 0) > 0 then need[#need + 1] = ROLE_NAME[role]:lower() end
        end
        Add(#r.members .. " of 5" .. (#need > 0 and ("  ·  needs " .. table.concat(need, ", ")) or ""), C.text2)
    end
    if (r.guild or 0) > 0 then Add(r.guild == 1 and "1 guild mate" or (r.guild .. " guild mates"), C.goodText) end
    if (r.friends or 0) > 0 then Add(r.friends == 1 and "1 friend" or (r.friends .. " friends"), C.goodText) end
    local style = r.playstyle and D.PlaystyleLabel(r.playstyle)
    if style then Add(style, C.text2) end
    if r.voice then
        local v = r.voice
        if #v > 18 then v = v:sub(1, 17) .. "…" end
        Add("Voice: " .. v, C.text2)
    end
    return out
end

-- Wraps the chips into rows; returns their height.
local function FlowChips()
    local x, y, h = 0, 0, 0
    for _, p in ipairs(card.chips) do
        if p:IsShown() then
            local w = p:GetWidth()
            if x > 0 and x + w > BODY_W then x, y = 0, y + 30 end
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", card.chipRow, "TOPLEFT", x, -y)
            x = x + w + 6
            h = y + 24
        end
    end
    return h
end

-- Puts the body's parts below each other and sizes the card.
local function Stack()
    local body, y = card.body, 0
    local function Put(region, height, gap)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        region:SetPoint("RIGHT", body, "RIGHT")
        y = y + height + (gap or GAP)
    end
    Put(card.title, 16, 6)
    Put(card.leaderRow, 18, card.where:IsShown() and 2 or GAP)
    if card.where:IsShown() then Put(card.where, 14, GAP) end
    if card.lineup:IsShown() then Put(card.lineup, card.lineup:GetHeight()) end
    if card.size:IsShown() then Put(card.size, 16) end
    local ch = FlowChips()
    card.chipRow:SetHeight(math.max(1, ch))
    if ch > 0 then Put(card.chipRow, ch) end
    if card.bests:IsShown() then Put(card.bests, 42) end
    Put(card.you, 34, 12)
    Put(card.buttons, 34, 0)
    card:SetHeight(INSET + ART_H + 12 + y + 12)
end

local function Best(box, level, timed, none)
    if level then
        box.value:SetText(T.ColorCode(T.KeyColor(level, timed)) .. "+" .. level .. "|r  |cff8d98a8"
            .. (timed and "timed" or "over time") .. "|r")
    else
        box.value:SetText("|cff4e5a6b" .. none .. "|r")
    end
end

local function Fill(r)
    card.r = r
    SetArt(r)
    card.eyebrow:SetText(card.busy and "JOINING…" or (card.preview and "INVITED  ·  PREVIEW" or "INVITED"))
    card.key:SetShown(r.key ~= nil)
    card.name:ClearAllPoints()
    if r.key then
        card.key:SetText("+" .. r.key)
        card.key:SetTextColor(unpack(T.KeyColor(r.key)))
        card.name:SetPoint("BOTTOMLEFT", card.key, "BOTTOMRIGHT", 10, 3)
    else
        card.name:SetPoint("BOTTOMLEFT", card.art, "BOTTOMLEFT", 12, 12)
    end
    card.name:SetPoint("RIGHT", card.art, "RIGHT", -12, 0)
    card.name:SetText(r.dungeon)
    if not pcall(card.title.SetText, card.title, r.title or "") then card.title:SetText("") end   -- K-string: shown, not read

    -- The leader: their realm's flag, name, spec; below it the country and realm.
    local flag = UI.Region and UI.Region.Markup(r.leaderFull or r.leader) or ""
    local leader = r.leader and (T.ColorCode(T.ClassColor(r.leaderClass)) .. r.leader .. "|r") or "|cff8d98a8?|r"
    if r.leaderSpec then leader = leader .. "  |cff8d98a8" .. r.leaderSpec .. "|r" end
    if r.mplus and UI.Ratings then leader = leader .. UI.Ratings.Inline(r.leaderFull or r.leader) end   -- GOOD / BAD
    card.leader:SetText(flag .. leader)
    local code, realm
    if flag ~= "" then code, realm = UI.Region.Of(r.leaderFull or r.leader) end
    card.where:SetShown(code ~= nil)
    if code then card.where:SetText("|cffc3cbd6" .. (UI.Region.NAMES[code] or code) .. "|r  ·  " .. realm) end
    card.rating:SetText(r.mplus and (T.ColorCode(T.RatingColor(r.rating)) .. floor(r.rating) .. "|r") or "")

    -- The group: the lineup (Mythic+), else its size by role.
    if r.mplus then
        FillLineup(r)
        card.lineup:Show()
        card.size:Hide()
    else
        card.lineup:Hide()
        local c = r.counts
        card.size:SetText(c and ("%d players  |cff8d98a8·|r  %d tank  |cff8d98a8·|r  %d healer  |cff8d98a8·|r  %d damage")
            :format(r.size or 0, c.TANK, c.HEALER, c.DAMAGER) or "")
        card.size:Show()
    end

    local chips = Chips(r)
    for i = 1, math.max(#chips, #card.chips) do
        local p = card.chips[i]
        if chips[i] then
            if not p then p = W.Pill(card.chipRow); card.chips[i] = p end
            p:SetText(chips[i][1])
            p.text:SetTextColor(unpack(chips[i][2]))
            p:Show()
        elseif p then
            p:Hide()
        end
    end

    -- Best runs in this dungeon this season: the leader's and yours.
    card.bests:SetShown(r.mplus or false)
    if r.mplus then
        Best(card.leaderBest, r.best, r.timed, "no run yet")
        local level, timed = ns.BestKey(r.cid)
        Best(card.myBest, level, timed, "no run yet")
    end

    card.roleGlyph:SetTexture(T.TEX .. "glyph-" .. ROLE_GLYPH[r.myRole])
    card.roleText:SetText("You join as  |cffe6c27a" .. ROLE_NAME[r.myRole] .. "|r")
    local more = card.preview and 0 or (#invites - 1)
    card.more:SetText(more > 0 and (more == 1 and "1 more invite below" or (more .. " more invites below")) or "")

    card.accept:SetEnabled(not card.busy)
    card.decline:SetEnabled(not card.busy)
    Stack()
    C_Timer.After(0, function() if card.r == r then Stack() end end)   -- the chips' widths, once their font is in
    Clock()
end
local function Answer(accept)
    local r = card.r
    if not r then return end
    if card.preview then IV.Hide(); return end
    local fn = accept and C_LFGList.AcceptInvite or C_LFGList.DeclineInvite
    local ok, err = pcall(fn, r.id)
    if not ok then
        ns.Print("could not answer the invite (" .. tostring(err) .. "): Blizzard's invite window takes over.")
        IV.Block()
        return
    end
    if accept then
        card.busy = true   -- until the group is joined (GROUP_JOINED) or the status moves on
        Fill(r)
    else
        IV.Remove(r.id)
    end
end

local function BuildRow(i)
    local row = CreateFrame("Button", nil, card)
    row:SetSize(CARD_W, ROW_H)
    row.bg = W.Round(row, "BACKGROUND", { C.navy[1], C.navy[2], C.navy[3], 0.96 })
    row.bg:SetAllPoints()
    W.Border(row, C.lineStrong)
    row.key = W.Text(row, "numSm")
    row.key:SetPoint("LEFT", 14, 0)
    row.name = W.Text(row, "body", C.textHi)
    row.name:SetPoint("TOPLEFT", 64, -7)
    row.name:SetPoint("RIGHT", -60, 0)
    row.sub = W.Text(row, "tiny")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.hint = W.Text(row, "tiny", C.muted)
    row.hint:SetPoint("RIGHT", -14, 0)
    row.hint:SetText("Show")
    row:SetScript("OnEnter", function(self)
        W.SetBorder(self, { 0.82, 0.64, 0.30, 0.6 }); self.hint:SetTextColor(unpack(C.goldLight))
    end)
    row:SetScript("OnLeave", function(self)
        W.SetBorder(self, C.lineStrong); self.hint:SetTextColor(unpack(C.muted))
    end)
    row:SetScript("OnClick", function(self)
        if card.busy then return end
        selected = self.id
        IV.Refresh()
    end)
    rows[i] = row
    return row
end

local function Build()
    card = CreateFrame("Frame", "GottaQueueEmAllInviteCard", UIParent)
    card:SetSize(CARD_W, 268)
    card:SetPoint("TOP", UIParent, "TOP", 0, -110)
    card:SetFrameStrata("DIALOG")
    card:SetToplevel(true)
    card:SetClampedToScreen(true)
    card:EnableMouse(true)
    card:Hide()
    card.bg = W.Round(card, "BACKGROUND", { C.navy[1], C.navy[2], C.navy[3], 0.97 })
    card.bg:SetAllPoints()
    W.Border(card, { 0.82, 0.64, 0.30, 0.8 }, "OVERLAY", 2)

    -- Head: the dungeon's art, darker on the left for the text.
    card.art = card:CreateTexture(nil, "ARTWORK")
    card.art:SetPoint("TOPLEFT", INSET, -INSET); card.art:SetPoint("TOPRIGHT", -INSET, -INSET)
    card.art:SetHeight(ART_H)
    local shade = W.Tex(card, "ARTWORK", nil, 1)
    shade:SetAllPoints(card.art)
    W.Gradient(shade, "HORIZONTAL", { 0, 0, 0, 0.78 }, { 0, 0, 0, 0.12 })
    W.CornerCaps(card, card.art, C.navy, { TL = true, TR = true, BL = true, BR = true })
    card.eyebrow = W.Text(card, "tiny", C.goldText)
    card.eyebrow:SetPoint("TOPLEFT", card.art, "TOPLEFT", 12, -10)
    card.eyebrow:SetShadowOffset(0, -1); card.eyebrow:SetShadowColor(0, 0, 0, 0.9)
    card.clock = W.Text(card, "tiny", C.text2)
    card.clock:SetPoint("TOPRIGHT", card.art, "TOPRIGHT", -12, -10)
    card.clock:SetShadowOffset(0, -1); card.clock:SetShadowColor(0, 0, 0, 0.9)
    card.key = W.Text(card, "keyArt")
    card.key:SetPoint("BOTTOMLEFT", card.art, "BOTTOMLEFT", 12, 8)
    card.key:SetShadowOffset(1, -2); card.key:SetShadowColor(0, 0, 0, 0.9)
    card.name = W.Text(card, "title")
    card.name:SetPoint("RIGHT", card.art, "RIGHT", -12, 0)
    card.name:SetShadowOffset(1, -1); card.name:SetShadowColor(0, 0, 0, 0.9)

    -- Body: its parts are placed by Stack() from what an invite has.
    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", card.art, "BOTTOMLEFT", 8, -12)
    body:SetPoint("BOTTOMRIGHT", -12, 12)
    card.body = body
    card.title = W.Text(body, "bodySm", C.text2)
    card.leaderRow = CreateFrame("Frame", nil, body)
    card.leaderRow:SetHeight(18)
    card.leader = W.Text(card.leaderRow, "bodySm")
    card.leader:SetPoint("LEFT")
    card.rating = W.Text(card.leaderRow, "bodySm")
    card.rating:SetPoint("RIGHT")
    card.where = W.Text(body, "small")
    card.size = W.Text(body, "bodySm", C.text2)

    -- The lineup, on a panel lit gold from the top.
    local lineup = W.Panel(body, C.panel, C.line)
    lineup:SetHeight(PORTRAIT + 34 + 18)
    local glow = W.Tex(lineup, "BACKGROUND", nil, 1)
    glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("TOPRIGHT", -1, -1); glow:SetHeight(40)
    W.Gradient(glow, "VERTICAL", { C.gold[1], C.gold[2], C.gold[3], 0 }, { C.gold[1], C.gold[2], C.gold[3], 0.08 })
    card.lineup = lineup
    card.slots = {}
    for i = 1, 5 do
        local s = Slot(lineup)
        s:SetPoint("TOPLEFT", lineup, "TOPLEFT", (i - 1) * SLOT_W + floor((BODY_W - 5 * SLOT_W) / 2), -10)
        card.slots[i] = s
    end

    card.chipRow = CreateFrame("Frame", nil, body)
    card.chips = {}

    -- Best runs: the leader's and yours, side by side.
    local bests = CreateFrame("Frame", nil, body)
    bests:SetHeight(42)
    local function Box(label)
        local b = W.Panel(bests, C.panel, C.line)
        b:SetSize(floor((BODY_W - 6) / 2), 42)
        local l = W.Text(b, "tiny", C.muted)
        l:SetPoint("TOPLEFT", 10, -7)
        l:SetText(label:upper())
        b.value = W.Text(b, "button")
        b.value:SetPoint("BOTTOMLEFT", 10, 7)
        return b
    end
    card.leaderBest = Box("Leader's best here")
    card.leaderBest:SetPoint("LEFT")
    card.myBest = Box("Your best here")
    card.myBest:SetPoint("RIGHT")
    card.bests = bests

    local you = W.Panel(body, C.raised, C.lineStrong)
    you:SetHeight(34)
    card.you = you
    card.roleGlyph = W.Glyph(you, "tank", 20, C.goldLight)
    card.roleGlyph:SetPoint("LEFT", 9, 0)
    card.roleText = W.Text(you, "bodySm")
    card.roleText:SetPoint("LEFT", card.roleGlyph, "RIGHT", 8, 0)
    card.more = W.Text(you, "tiny")
    card.more:SetPoint("RIGHT", -10, 0)

    local buttons = CreateFrame("Frame", nil, body)
    buttons:SetHeight(34)
    card.buttons = buttons
    local bw = floor((BODY_W - 8) / 2)
    card.accept = W.Button(buttons, "Accept", "gold", bw, 34, "h2")
    card.accept:SetPoint("LEFT")
    card.accept:SetScript("OnClick", function() Answer(true) end)
    card.decline = W.Button(buttons, "Decline", "quiet", bw, 34, "h2")
    card.decline:SetPoint("RIGHT")
    card.decline:SetScript("OnClick", function() Answer(false) end)

    -- The shine clips on a layer of its own: a card that clips its children
    -- drew see-through and flickered while the screen edge glowed.
    local sheen = CreateFrame("Frame", nil, card)
    sheen:SetAllPoints()
    sheen:EnableMouse(false)
    card.shine = A.Shine(sheen, nil, 0.18, true)
    -- The clock ticks only while the card is up.
    card:SetScript("OnShow", function(self) self.ticker = self.ticker or C_Timer.NewTicker(1, Clock) end)
    card:SetScript("OnHide", function(self)
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
        if UI.Alert and UI.Alert.Dismiss then UI.Alert.Dismiss() end   -- answered: the edge stops
    end)
end

-------------------------------------------------------------------------------
--  Showing
-------------------------------------------------------------------------------
local function HideRows(from)
    for i = from, #rows do rows[i]:Hide() end
end

-- Rises in, then paints once more: colors set before the first frame drew
-- could come out without their alpha (as in the keystone window).
local function Appear()
    A.Rise(card, 0, -12, 0.35)
    C_Timer.After(0.35, function()
        if not card:IsShown() then return end
        card:SetAlpha(1)
        if card.r then Fill(card.r) end
        card.shine.Sweep()
    end)
end

function IV.Refresh()
    if card and card.preview then
        if #invites == 0 then return end   -- the preview stays until answered
        card.preview = false               -- a real invite takes its place
    end
    if not (IV.Active() and Empowered() and #invites > 0) then
        if card and card:IsShown() then card:Hide() end
        return
    end
    if not card then Build() end
    local found = false
    for _, id in ipairs(invites) do if id == selected then found = true end end
    if not found then selected = invites[1] end
    local r = Read(selected)
    if not r then IV.Remove(selected); return end
    card.preview = false
    Fill(r)
    local n = 0
    for _, id in ipairs(invites) do
        if id ~= selected then
            local o = Read(id)
            if o then
                n = n + 1
                local row = rows[n] or BuildRow(n)
                row.id = id
                row:ClearAllPoints()
                row:SetPoint("TOP", n == 1 and card or rows[n - 1], "BOTTOM", 0, n == 1 and -8 or -ROW_GAP)
                row.key:SetText(o.key and ("+" .. o.key) or "")
                row.key:SetTextColor(unpack(o.key and T.KeyColor(o.key) or C.text))
                row.name:SetText(o.dungeon)
                local sub = ROLE_NAME[o.myRole]
                if o.mplus then sub = sub .. "  ·  " .. T.ColorCode(T.RatingColor(o.rating)) .. floor(o.rating) .. "|r" end
                if o.leader then sub = sub .. "  ·  " .. T.ColorCode(T.ClassColor(o.leaderClass)) .. o.leader .. "|r" end
                row.sub:SetText(sub)
                row:Show()
            end
        end
    end
    HideRows(n + 1)
    if not card:IsShown() then
        card:Show()
        Appear()
    end
end

function IV.Hide()
    if not card then return end
    card.preview, card.busy = false, false
    card:Hide()
    HideRows(1)
end

function IV.Remove(id)
    for i = #invites, 1, -1 do if invites[i] == id then table.remove(invites, i) end end
    invitedAt[id] = nil
    if selected == id then selected = nil end
    IV.Refresh()
end

-- Invites as the server sees them now (after a reload, or a status change).
local function Scan()
    local now = {}
    local ok, apps = pcall(C_LFGList.GetApplications)
    for _, id in ipairs(ok and D.Tab(apps) or {}) do
        local _, status, pending = C_LFGList.GetApplicationInfo(id)
        if D.Str(status) == "invited" and not D.Str(pending) then now[id] = true end
    end
    for i = #invites, 1, -1 do
        if not now[invites[i]] then invitedAt[invites[i]] = nil; table.remove(invites, i) end
    end
    for id in pairs(now) do
        if not invitedAt[id] then invitedAt[id] = GetTime(); invites[#invites + 1] = id end
    end
end

-------------------------------------------------------------------------------
--  Blizzard's invite window: open but unseen while our card answers
-------------------------------------------------------------------------------
local dialog = LFGListInviteDialog

local function SetSeen(seen)
    if not dialog then return end
    dialog:SetAlpha(seen and 1 or 0)
    dialog:EnableMouse(seen)
    for _, key in ipairs({ "AcceptButton", "DeclineButton", "AcknowledgeButton" }) do
        if dialog[key] then dialog[key]:EnableMouse(seen) end
    end
end

-- "You have joined a group" with an OK to click: closed at once, a short
-- message at the top says it instead (it fades by itself).
local function Joined(resultID)
    dialog:Hide()   -- the frame only: Blizzard's code and its variables stay untouched
    if not (UI.Alert and UI.Alert.Notice) then return end
    local r = D.Num(resultID) and Read(resultID)
    if not r then   -- delisted already: just the news
        UI.Alert.Notice({ eyebrow = "JOINED", big = "You're in the group" })
        return
    end
    local _, _, _, _, role = C_LFGList.GetApplicationInfo(resultID)
    role = D.Str(role)
    UI.Alert.Notice({
        eyebrow = "JOINED",
        big = r.dungeon .. (r.key and (" +" .. r.key) or ""),
        bigColor = r.key and T.KeyColor(r.key) or nil,
        small = (role and ROLE_NAME[role] and ("You're the " .. ROLE_NAME[role]:lower() .. "  ·  ") or "")
            .. (r.leader and ("Leader " .. T.ColorCode(T.ClassColor(r.leaderClass)) .. r.leader .. "|r") or ""),
    })
end

if dialog and LFGListInviteDialog_Show then
    hooksecurefunc("LFGListInviteDialog_Show", function(self, resultID)
        if self.informational then
            if IV.Active() then Joined(resultID) end
            return
        end
        local ours = IV.Active() and Empowered()
        SetSeen(not ours)
        -- Our card should be up by now; if it isn't (the group couldn't be
        -- read), Blizzard's window shows after all: no invite goes unseen.
        if ours then
            C_Timer.After(1, function()
                if dialog:IsShown() and not (card and card:IsShown()) then SetSeen(true) end
            end)
        end
    end)
    dialog:HookScript("OnHide", function() SetSeen(true) end)
end

-- WoW blocked our buttons: Blizzard's window answers from now on.
function IV.Block()
    blocked = true
    IV.Hide()
    if dialog and dialog:IsShown() then SetSeen(true) end
end

-- The setting changed: the card or Blizzard's window.
function IV.SettingChanged()
    if dialog and dialog:IsShown() and not dialog.informational then SetSeen(not IV.Active()) end
    IV.Refresh()
end

-------------------------------------------------------------------------------
--  Preview (Settings): your keystone's dungeon, a made-up group (its
--  leader on a real Russian realm, so the flag shows)
-------------------------------------------------------------------------------
function IV.Preview()
    if not card then Build() end
    local key = D.OwnKey and D.OwnKey()
    local role = D.PlayerRole()
    if role ~= "TANK" and role ~= "HEALER" then role = "DAMAGER" end
    local members = { { role = "DAMAGER", class = "WARRIOR", spec = "Arms", leader = true },
                      { role = "DAMAGER", class = "MAGE", spec = "Frost" } }
    if role ~= "HEALER" then members[#members + 1] = { role = "HEALER", class = "PRIEST", spec = "Discipline" } end
    if role ~= "TANK" then members[#members + 1] = { role = "TANK", class = "DEATHKNIGHT", spec = "Blood" } end
    local r = { mplus = true, cid = key and key.cid, dungeon = key and key.dungeon or "Your next dungeon",
                key = key and key.level or 12, title = "", leader = "Thorgrim", leaderFull = "Thorgrim-Гордунни", leaderClass = "WARRIOR",
                leaderSpec = "Arms", rating = 2650, best = 14, timed = true, lust = true, brez = role ~= "TANK",
                guild = 1, playstyle = 2, voice = "Discord",
                members = members, myRole = role }
    card.preview, card.busy, card.previewAt = true, false, GetTime()
    HideRows(1)
    Fill(r)
    card:Show()
    Appear()
end

-------------------------------------------------------------------------------
--  Events (always registered: invites come while the window is closed)
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
events:RegisterEvent("GROUP_JOINED")
events:RegisterEvent("PARTY_LEADER_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg1 == ADDON and type(arg2) == "string" and arg2:find("Invite") and card and card:IsShown() then
            ns.Print("WoW didn't let the card answer the invite: Blizzard's invite window takes over.")
            IV.Block()
        end
        return
    end
    if event == "GROUP_JOINED" then   -- in a group: the other invites are gone
        wipe(invites); wipe(invitedAt); selected = nil
        if card and not card.preview then IV.Hide() end
        return
    end
    if card and card.busy then card.busy = false end
    Scan()
    IV.Refresh()
end)
