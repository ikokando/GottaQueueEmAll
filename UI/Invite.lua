-------------------------------------------------------------------------------
--  UI/Invite.lua  --  invites answered in a card of our own
--
--  A leader invites you: a card at the top of the screen with the dungeon's
--  art, the key, the leader, the group and the role you join as; Accept and
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

    local leader = r.leader and (T.ColorCode(T.ClassColor(r.leaderClass)) .. r.leader .. "|r") or "|cff8d98a8?|r"
    if r.leaderSpec then leader = leader .. "  |cff8d98a8" .. r.leaderSpec .. "|r" end
    card.leader:SetText(leader)
    if r.mplus then
        local s = T.ColorCode(T.RatingColor(r.rating)) .. floor(r.rating) .. "|r"
        if r.best then s = s .. "  |cff8d98a8best|r " .. T.ColorCode(T.KeyColor(r.best, r.timed)) .. "+" .. r.best .. "|r" end
        card.rating:SetText(s)
    else
        card.rating:SetText("")
    end

    -- The group: members by role, your spot in gold, the rest open (Mythic+);
    -- else its size by role.
    if r.mplus then
        local slots = {}
        for _, role in ipairs(D.ROLE_KEYS) do
            for _, m in ipairs(r.members) do if m.role == role then slots[#slots + 1] = { role, m.class or true } end end
        end
        local open = D.OpenSpots(r)
        local mineShown = false
        for _, role in ipairs(D.ROLE_KEYS) do
            for _ = 1, open[role] or 0 do
                local mine = not mineShown and role == r.myRole
                if mine then mineShown = true end
                slots[#slots + 1] = { role, nil, mine }
            end
        end
        for i, rb in ipairs(card.slots) do
            local s = slots[i]
            rb:SetShown(s ~= nil)
            if s then
                rb:Set(s[1], s[2])
                if s[3] then
                    rb.ring:SetVertexColor(unpack(C.goldLight))
                    rb.glyph:SetVertexColor(unpack(C.goldLight))
                end
            end
        end
        card.size:Hide()
        card.lust:SetShown(r.lust or false)
        card.brez:SetShown(r.brez or false)
        card.lust:ClearAllPoints()
        card.lust:SetPoint("RIGHT", r.brez and card.brez or card.badgeRow, r.brez and "LEFT" or "RIGHT", 0, 0)
    else
        for _, rb in ipairs(card.slots) do rb:Hide() end
        card.lust:Hide(); card.brez:Hide()
        local c = r.counts
        card.size:SetText(c and ("%d players  |cff8d98a8·|r  %d tank  |cff8d98a8·|r  %d healer  |cff8d98a8·|r  %d damage")
            :format(r.size or 0, c.TANK, c.HEALER, c.DAMAGER) or "")
        card.size:Show()
    end

    card.roleGlyph:SetTexture(T.TEX .. "glyph-" .. ROLE_GLYPH[r.myRole])
    card.roleText:SetText("You join as  |cffe6c27a" .. ROLE_NAME[r.myRole] .. "|r")
    local more = card.preview and 0 or (#invites - 1)
    card.more:SetText(more > 0 and (more == 1 and "1 more invite below" or (more .. " more invites below")) or "")

    card.accept:SetEnabled(not card.busy)
    card.decline:SetEnabled(not card.busy)
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

    -- Body
    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", card.art, "BOTTOMLEFT", 8, -12)
    body:SetPoint("BOTTOMRIGHT", -12, 12)
    card.body = body
    card.title = W.Text(body, "bodySm", C.text2)
    card.title:SetPoint("TOPLEFT"); card.title:SetPoint("TOPRIGHT")
    card.leader = W.Text(body, "bodySm")
    card.leader:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -8)
    card.rating = W.Text(body, "bodySm")
    card.rating:SetPoint("TOPRIGHT", card.title, "BOTTOMRIGHT", 0, -8)
    -- The group's row: members on the left, Lust / B-Res on the right.
    local badgeRow = CreateFrame("Frame", nil, body)
    badgeRow:SetPoint("TOPLEFT", card.leader, "BOTTOMLEFT", 0, -10)
    badgeRow:SetPoint("RIGHT", body, "RIGHT")
    badgeRow:SetHeight(24)
    card.badgeRow = badgeRow
    card.slots = {}
    for i = 1, 5 do
        local rb = W.RoleBadge(badgeRow, 24)
        if i == 1 then rb:SetPoint("LEFT") else rb:SetPoint("LEFT", card.slots[i - 1], "RIGHT", 5, 0) end
        card.slots[i] = rb
    end
    card.size = W.Text(badgeRow, "bodySm", C.text2)
    card.size:SetPoint("LEFT")
    card.lust = W.Glyph(badgeRow, "lust", 24, C.lust)
    card.brez = W.Glyph(badgeRow, "brez", 24, C.brez)
    card.brez:SetPoint("RIGHT")

    local you = W.Panel(body, C.raised, C.lineStrong)
    you:SetPoint("TOPLEFT", badgeRow, "BOTTOMLEFT", 0, -12)
    you:SetPoint("RIGHT", body, "RIGHT")
    you:SetHeight(34)
    card.roleGlyph = W.Glyph(you, "tank", 20, C.goldLight)
    card.roleGlyph:SetPoint("LEFT", 9, 0)
    card.roleText = W.Text(you, "bodySm")
    card.roleText:SetPoint("LEFT", card.roleGlyph, "RIGHT", 8, 0)
    card.more = W.Text(you, "tiny")
    card.more:SetPoint("RIGHT", -10, 0)

    local bw = floor((CARD_W - INSET - 8 - 12 - 8) / 2)
    card.accept = W.Button(body, "Accept", "gold", bw, 34, "h2")
    card.accept:SetPoint("TOPLEFT", you, "BOTTOMLEFT", 0, -12)
    card.accept:SetScript("OnClick", function() Answer(true) end)
    card.decline = W.Button(body, "Decline", "quiet", bw, 34, "h2")
    card.decline:SetPoint("TOPRIGHT", you, "BOTTOMRIGHT", 0, -12)
    card.decline:SetScript("OnClick", function() Answer(false) end)

    card.shine = A.Shine(card, nil, 0.18, true)
    -- The clock ticks only while the card is up.
    card:SetScript("OnShow", function(self) self.ticker = self.ticker or C_Timer.NewTicker(1, Clock) end)
    card:SetScript("OnHide", function(self)
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    end)
end

-------------------------------------------------------------------------------
--  Showing
-------------------------------------------------------------------------------
local function HideRows(from)
    for i = from, #rows do rows[i]:Hide() end
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
        A.Rise(card, 0, -12, 0.35)
        C_Timer.After(0.35, function() if card:IsShown() then card.shine.Sweep() end end)
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
--  Preview (Settings): your keystone's dungeon, a made-up group
-------------------------------------------------------------------------------
function IV.Preview()
    if not card then Build() end
    local key = D.OwnKey and D.OwnKey()
    local role = D.PlayerRole()
    if role ~= "TANK" and role ~= "HEALER" then role = "DAMAGER" end
    local members = { { role = "DAMAGER", class = "WARRIOR" }, { role = "DAMAGER", class = "MAGE" } }
    if role ~= "HEALER" then members[#members + 1] = { role = "HEALER", class = "PRIEST" } end
    if role ~= "TANK" then members[#members + 1] = { role = "TANK", class = "DEATHKNIGHT" } end
    local r = { mplus = true, cid = key and key.cid, dungeon = key and key.dungeon or "Your next dungeon",
                key = key and key.level or 12, title = "", leader = "Thorgrim", leaderClass = "WARRIOR",
                leaderSpec = "Arms", rating = 2650, best = 14, timed = true, lust = true,
                members = members, myRole = role }
    card.preview, card.busy, card.previewAt = true, false, GetTime()
    HideRows(1)
    Fill(r)
    card:Show()
    A.Rise(card, 0, -12, 0.35)
    C_Timer.After(0.35, function() if card:IsShown() then card.shine.Sweep() end end)
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
