-------------------------------------------------------------------------------
--  UI/Ratings.lua  --  your own ratings of Mythic+ players
--
--  After a key (in time, over time, or ended early: abandoned, or you left)
--  a window lists the group: Good or Bad for whoever you want, a note if
--  you like. One rating per player; a new one replaces it. Rated players are
--  marked where the addon knows their name: the leader of a Mythic+ group
--  (the other members of a listed group come without names), applicants to
--  your Mythic+ group, the invite card. Groups of leaders rated Bad can be
--  hidden from the Mythic+ search.
--
--  Only on this PC (GottaQueueEmAllDB.ratings), never sent anywhere.
--  Ratings expire after a set time (or never); the list on the settings
--  page flips and deletes them.
--
--  The group is read when the key starts and again whenever it changes
--  during the run, so players who leave early are still in the window.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W, A, D = UI.Theme, UI.W, UI.Anim, UI.Data
local C, S = T.C, T.S

local RT = {}
UI.Ratings = RT

local floor, max = math.floor, math.max
local MONTH = 30 * 86400
local BAD = { 0.88, 0.34, 0.29, 1 }

local function DB() return ns.DB and ns.DB() end

-- The saved ratings: { ["Name-realmkey"] = { v = "good" | "bad", t = time,
-- name = "Name-Realm", class, dungeon, level, note } }.
local function Saved()
    local db = DB()
    if not db then return nil end
    if type(db.ratings) ~= "table" then db.ratings = {} end
    return db.ratings
end

-------------------------------------------------------------------------------
--  Lookup
-------------------------------------------------------------------------------
-- A player's key: "Name-realmkey" (no realm: yours). Realms are written
-- differently by different APIs ("Twisting Nether", "TwistingNether"):
-- the key drops spaces and the like (UI/Region.lua).
function RT.Key(fullName)
    local s = D.Str(fullName)
    if not s or s == "" then return end
    local name, realm = s:match("^([^%-]+)%-(.+)$")
    if not name then name, realm = s, GetNormalizedRealmName() end
    if not realm or realm == "" then return end
    return name .. "-" .. UI.Region.RealmKey(realm)
end

local function Months()
    local db = DB()
    return db and tonumber(db.rateExpire) or 0
end

-- When a rating runs out (nil: never). Expired ones count as gone at once
-- and are deleted at the next login, so a shorter setting can be undone
-- until then.
local function ExpiresAt(e)
    local m = Months()
    return m > 0 and (e.t or 0) + m * MONTH or nil
end
local function Expired(e)
    local at = ExpiresAt(e)
    return at ~= nil and at <= time()
end

function RT.Purge()
    local list = Saved()
    if not list then return end
    for k, e in pairs(list) do
        if type(e) ~= "table" or (e.v ~= "good" and e.v ~= "bad") or Expired(e) then list[k] = nil end
    end
end

-- The rating of a player ("Name-Realm" or "Name"), and its key; nil: none.
function RT.Get(fullName)
    local list = Saved()
    local key = list and RT.Key(fullName)
    local e = key and list[key]
    if e and not Expired(e) then return e, key end
end

-- A group to leave out of the Mythic+ search: its leader is rated Bad.
function RT.Hides(fullName)
    local db = DB()
    if not db or db.rateHideBad == false then return false end
    local e = RT.Get(fullName)
    return e ~= nil and e.v == "bad"
end

-- Ratings changed: the groups, applicants and the list show it at once.
function RT.Changed()
    if UI.Browse and UI.Browse.Reread then UI.Browse.Reread() end
    if UI.Group and UI.Group.Refresh then UI.Group.Refresh() end
    if RT.PaintList then RT.PaintList() end
end

-------------------------------------------------------------------------------
--  Marks: a tag, an inline word, tooltip lines
-------------------------------------------------------------------------------
local STYLE = {
    good = { "GOOD", C.good, C.goodText, "Good" },
    bad  = { "BAD", BAD, C.badText, "Bad" },
}

local function When(t) return date("%d %b %Y", t or 0) end
local function RunText(e) return (e.dungeon or "?") .. (e.level and (" +" .. e.level) or "") end

-- A small pill like the DESERTER tag: green GOOD, red BAD. Hidden at first.
function RT.Tag(parent)
    local p = W.Pill(parent, nil)
    p:SetHeight(18)
    p.text:SetFontObject(T.Font.tiny)
    function p:SetRating(v)
        local s = STYLE[v] or STYLE.good
        local c = s[2]
        W.Fill(self.bg, { c[1], c[2], c[3], 0.14 })
        W.SetBorder(self, { c[1], c[2], c[3], 0.6 })
        self.text:SetTextColor(unpack(s[3]))
        self:SetText(s[1])
    end
    p:SetRating("good")
    p:Hide()
    return p
end

-- Shows a tag for the player's rating; true when there is one.
function RT.PaintTag(tag, fullName)
    local e = RT.Get(fullName)
    if e then tag:SetRating(e.v); tag:Show() else tag:Hide() end
    return e ~= nil
end

-- "  GOOD" / "  BAD" in color, for a line of text ("" when not rated).
function RT.Inline(fullName)
    local e = RT.Get(fullName)
    if not e then return "" end
    local s = STYLE[e.v] or STYLE.good
    return "  " .. T.ColorCode(s[3]) .. s[1] .. "|r"
end

-- Your rating and note under a tooltip; who: the name to put first (groups).
function RT.AddTooltip(tt, fullName, who)
    local e = RT.Get(fullName)
    if not e then return end
    local s = STYLE[e.v] or STYLE.good
    tt:AddLine(" ")
    tt:AddLine((who and (who .. ": ") or "") .. "You rated " .. s[4] .. "  |cff8d98a8" .. When(e.t) .. "  ·  "
        .. RunText(e) .. "|r", s[3][1], s[3][2], s[3][3])
    if e.note then tt:AddLine("\"" .. e.note .. "\"", C.text2[1], C.text2[2], C.text2[3], true) end
end

-------------------------------------------------------------------------------
--  The run: who played, read at the start and when the group changes
-------------------------------------------------------------------------------
local UNITS = { "party1", "party2", "party3", "party4" }
-- { cid, dungeon, level, instance, started, result, players = { [key] = p }, order = { key } };
-- saved (GottaQueueEmAllDB.rateRun) so a /reload in the dungeon keeps it.
local run
local lastParty = {}   -- the group as read outside, in case names can't be read inside
local waiting          -- a run to rate once combat ends

local function InstanceID() return D.Num((select(8, GetInstanceInfo()))) end

local function ReadUnit(unit)
    local name, realm = UnitName(unit)
    name, realm = D.Str(name), D.Str(realm)
    if not name or name == "" or name == (UNKNOWNOBJECT or "Unknown") then return end
    if not realm or realm == "" then realm = GetNormalizedRealmName() end
    if not realm then return end
    local _, class = UnitClass(unit)
    local role = D.Str(UnitGroupRolesAssigned(unit))
    if role ~= "TANK" and role ~= "HEALER" then role = "DAMAGER" end
    return { name = name, realm = realm, full = name .. "-" .. realm, class = D.Str(class), role = role }
end

-- The party (not you); unread = someone's name could not be read.
local function ReadParty()
    local out, unread = {}, false
    for _, unit in ipairs(UNITS) do
        if UnitExists(unit) then
            local p = ReadUnit(unit)
            if p then out[#out + 1] = p else unread = true end
        end
    end
    return out, unread
end

local function Add(p)
    local key = RT.Key(p.full)
    if not key or run.players[key] then return end
    run.players[key] = p
    run.order[#run.order + 1] = key
end

local function Capture()
    if not run then return end
    local party, unread = ReadParty()
    for _, p in ipairs(party) do Add(p) end
    -- No name readable in the instance: the group from before it.
    if unread and #party == 0 then
        for _, p in ipairs(lastParty) do Add(p) end
    end
end

local function SaveRun()
    local db = DB()
    if db then db.rateRun = run end
end

local function Start()
    local cm = C_ChallengeMode
    local cid = cm and cm.GetActiveChallengeMapID and D.Num(cm.GetActiveChallengeMapID())
    local level = cm and cm.GetActiveKeystoneInfo and D.Num((cm.GetActiveKeystoneInfo()))
    local dungeon = cid and D.Str((cm.GetMapUIInfo(cid)))
    run = { cid = cid, dungeon = dungeon or "Mythic+", level = level, instance = InstanceID(), started = time(),
            players = {}, order = {} }
    Capture()
    SaveRun()
end

-- The run is over: the window (once out of combat), unless switched off.
local function Prompt()
    local r = run
    run = nil
    SaveRun()
    local db = DB()
    if not r or #r.order == 0 or (db and db.ratePrompt == false) then return end
    if InCombatLockdown() then waiting = r; return end
    RT.Show(r)
end

local function Completed()
    if not run then Start() end
    Capture()
    local cm = C_ChallengeMode
    local onTime, known
    if cm.GetChallengeCompletionInfo then
        local ok, info = pcall(cm.GetChallengeCompletionInfo)
        info = ok and D.Tab(info)
        if info then known, onTime = true, D.True(info.onTime) end
    end
    if not known and cm.GetCompletionInfo then
        local ok, _, _, _, timed = pcall(cm.GetCompletionInfo)
        if ok then known, onTime = true, D.True(timed) end
    end
    run.result = known and (onTime and "timed" or "over") or "done"
    SaveRun()
    C_Timer.After(4, Prompt)   -- after the chest and the first look at the score
end

-- Out of the run's instance: it ended early (abandoned, or you left), or
-- it ended in time and the window waited.
local function CheckLeft()
    if not run then return end
    if time() - (run.started or 0) > 4 * 3600 then run = nil; SaveRun(); return end   -- left over from long ago
    if InstanceID() == run.instance then return end
    run.result = run.result or "left"
    Prompt()
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
                     "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    pcall(events.RegisterEvent, events, e)   -- unknown events are skipped
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Next frame: Core.lua loads the saved settings on this event too.
        C_Timer.After(0, function()
            RT.Purge()
            local db = DB()
            if db and type(db.rateRun) == "table" and type(db.rateRun.players) == "table" then run = db.rateRun end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, CheckLeft)
    elseif event == "CHALLENGE_MODE_START" then
        Start()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        Completed()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if run and InstanceID() == run.instance then
            Capture(); SaveRun()
        elseif IsInGroup() and not IsInRaid() then
            local party = ReadParty()
            if #party > 0 then lastParty = party end
        end
    elseif event == "PLAYER_REGEN_ENABLED" and waiting then
        local r = waiting
        waiting = nil
        RT.Show(r)
    end
end)

-------------------------------------------------------------------------------
--  The rating window
-------------------------------------------------------------------------------
local WIN_W, ROW_H, NOTE_H, TOP, FOOT = 470, 46, 32, 84, 60
local RESULT = { timed = { "In time", C.goodText }, over = { "Over time", C.muted },
                 left = { "Ended early", C.badText }, done = { "Done", C.text2 } }
local win, rows = nil, {}

local function Layout()
    local y = 0
    for _, r in ipairs(rows) do
        if r:IsShown() then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", win.list, "TOPRIGHT", 0, -y)
            y = y + r:GetHeight() + 6
        end
    end
    win:SetHeight(TOP + max(0, y - 6) + FOOT)
end

local function PaintRow(r)
    r.good:SetVariant(r.choice == "good" and "done" or "mark")
    r.bad:SetVariant(r.choice == "bad" and "bad" or "mark")
    r.noteBox:SetShown(r.choice ~= nil)
    r:SetHeight(r.choice and (ROW_H + NOTE_H) or ROW_H)
    if not r.choice then r.edit:ClearFocus() end
end

local function Choose(r, v)
    r.choice = r.choice ~= v and v or nil   -- the same again: cleared
    PlaySound(r.choice and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    PaintRow(r)
    Layout()
end

local function NewRow()
    local r = CreateFrame("Frame", nil, win.list)
    r.bg = W.Round(r, "BACKGROUND", C.panel)
    r.bg:SetAllPoints()
    W.Border(r, C.line)
    r.badge = W.RoleBadge(r, 26)
    r.badge:SetPoint("TOPLEFT", 10, -10)
    r.name = W.Text(r, "button")
    r.name:SetPoint("TOPLEFT", 46, -8)
    r.sub = W.Text(r, "tiny")
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", r, "RIGHT", -150, 0)
    r.bad = W.Button(r, "Bad", "mark", 62, 28, "tiny")
    r.bad:SetPoint("TOPRIGHT", -9, -9)
    r.bad:SetScript("OnClick", function() Choose(r, "bad") end)
    r.good = W.Button(r, "Good", "mark", 62, 28, "tiny")
    r.good:SetPoint("RIGHT", r.bad, "LEFT", -6, 0)
    r.good:SetScript("OnClick", function() Choose(r, "good") end)

    r.noteBox = CreateFrame("Frame", nil, r)
    r.noteBox:SetPoint("TOPLEFT", 46, -(ROW_H - 2))
    r.noteBox:SetPoint("TOPRIGHT", -9, -(ROW_H - 2))
    r.noteBox:SetHeight(26)
    local bg = W.Round(r.noteBox, "BACKGROUND", C.bg)
    bg:SetAllPoints()
    W.Border(r.noteBox, C.lineStrong)
    local eb = CreateFrame("EditBox", nil, r.noteBox)
    eb:SetAllPoints()
    eb:SetFontObject(T.Font.bodySm)
    eb:SetTextColor(unpack(C.textHi))
    eb:SetTextInsets(10, 10, 0, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(120)
    local hint = W.Text(r.noteBox, "bodySm", C.faint)
    hint:SetPoint("LEFT", 10, 0)
    hint:SetText("Note (optional)")
    eb:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function() W.SetBorder(r.noteBox, C.gold) end)
    eb:SetScript("OnEditFocusLost", function() W.SetBorder(r.noteBox, C.lineStrong) end)
    r.edit = eb
    r.noteBox:Hide()
    return r
end

local function Save()
    local r0 = win.run
    local list = Saved()
    local n = 0
    if r0 and list and not r0.preview then
        for _, r in ipairs(rows) do
            if r:IsShown() and r.choice and r.key then
                local note = strtrim(r.edit:GetText() or "")
                list[r.key] = { v = r.choice, t = time(), name = r.p.full, class = r.p.class,
                                dungeon = r0.dungeon, level = r0.level, note = note ~= "" and note or nil }
                n = n + 1
            end
        end
    end
    win:Hide()
    if r0 and r0.preview then
        ns.Print("preview: nothing was saved.")
    elseif n > 0 then
        ns.Print(("%d %s saved (only on this PC)."):format(n, n == 1 and "rating" or "ratings"))
        RT.Changed()
    end
end

local function Build()
    win = CreateFrame("Frame", "GottaQueueEmAllRate", UIParent)
    win:SetSize(WIN_W, 300)
    win:SetPoint("TOP", UIParent, "TOP", 0, -150)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    win.bg = W.Round(win, "BACKGROUND", { C.navy[1], C.navy[2], C.navy[3], 0.97 })
    win.bg:SetAllPoints()
    W.Border(win, { 0.82, 0.64, 0.30, 0.8 }, "OVERLAY", 2)

    win.eyebrow = W.Text(win, "tiny", C.goldText)
    win.eyebrow:SetPoint("TOPLEFT", S.pad, -16)
    win.title = W.Text(win, "title")
    win.title:SetPoint("TOPLEFT", win.eyebrow, "BOTTOMLEFT", 0, -6)
    win.result = W.Text(win, "label")
    win.result:SetPoint("TOPRIGHT", -S.pad, -18)
    win.hint = W.Text(win, "small")
    win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -6)
    win.hint:SetText("Rate only who you want. Click again to clear.")

    win.list = CreateFrame("Frame", nil, win)
    win.list:SetPoint("TOPLEFT", 14, -TOP)
    win.list:SetPoint("TOPRIGHT", -14, -TOP)
    win.list:SetHeight(1)

    local line = W.Tex(win, "BORDER", C.line)
    line:SetPoint("BOTTOMLEFT", 14, FOOT - 6); line:SetPoint("BOTTOMRIGHT", -14, FOOT - 6)
    PixelUtil.SetHeight(line, 1, 1)
    local where = W.Text(win, "small")
    where:SetPoint("BOTTOMLEFT", S.pad, 22)
    where:SetText("Only on this PC, never shared.")
    win.save = W.Button(win, "Save", "gold", 92)
    win.save:SetPoint("BOTTOMRIGHT", -14, 14)
    win.save:SetScript("OnClick", Save)
    win.skip = W.Button(win, "Skip", "quiet", 80)
    win.skip:SetPoint("RIGHT", win.save, "LEFT", -8, 0)
    win.skip:SetScript("OnClick", function() win:Hide() end)
    tinsert(UISpecialFrames, "GottaQueueEmAllRate")   -- Escape closes it (nothing saved)
end

-- r: a run (see above).
function RT.Show(r)
    if not win then Build() end
    win.run = r
    win.eyebrow:SetText(r.preview and "RATE YOUR GROUP  ·  PREVIEW" or "RATE YOUR GROUP")
    win.title:SetText(r.dungeon .. (r.level and ("  " .. T.ColorCode(T.KeyColor(r.level)) .. "+" .. r.level .. "|r") or ""))
    local res = RESULT[r.result] or RESULT.done
    win.result:SetText(res[1]:upper())
    win.result:SetTextColor(unpack(res[2]))
    local list = Saved() or {}
    for i, key in ipairs(r.order) do
        local row = rows[i] or NewRow()
        rows[i] = row
        local p = r.players[key]
        row.key, row.p = key, p
        row.badge:Set(p.role, p.class or true)
        row.name:SetText(p.name)
        row.name:SetTextColor(unpack(T.ClassColor(p.class)))
        -- Rated before: that rating is chosen, its note is in the box.
        local e = list[key]
        if e and Expired(e) then e = nil end
        row.choice = e and e.v or nil
        row.edit:SetText(e and e.note or "")
        local sub = p.realm or ""
        if e then
            local s = STYLE[e.v] or STYLE.good
            sub = sub .. "  ·  " .. T.ColorCode(s[3]) .. "rated " .. s[4] .. "|r |cff8d98a8" .. When(e.t) .. "|r"
        end
        row.sub:SetText(sub)
        PaintRow(row)
        row:Show()
    end
    for i = #r.order + 1, #rows do rows[i]:Hide() end
    Layout()
    win:Show()
    A.FadeIn(win, 0.2)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
end

-- /gotta rate: the window with a made-up group (nothing is saved).
function RT.Preview()
    local realm = GetNormalizedRealmName() or "Blackrock"
    local r = { preview = true, dungeon = "Ara-Kara, City of Echoes", level = 12, result = "timed", players = {}, order = {} }
    for _, p in ipairs({ { "Brakthor", "WARRIOR", "TANK" }, { "Lunaria", "EVOKER", "HEALER" },
                         { "Shinyblade", "PALADIN", "DAMAGER" }, { "Pewpewlol", "HUNTER", "DAMAGER" } }) do
        local full = p[1] .. "-" .. realm
        local key = RT.Key(full)
        r.players[key] = { name = p[1], realm = realm, full = full, class = p[2], role = p[3] }
        r.order[#r.order + 1] = key
    end
    RT.Show(r)
end

-------------------------------------------------------------------------------
--  The list (Settings › Player ratings)
-------------------------------------------------------------------------------
local LROW_H, LGAP = 46, 4
local page, filter, offset, lrows = nil, "all", 0, {}

local function Flip(key)
    local list = Saved()
    local e = list and list[key]
    if not e then return end
    e.v = e.v == "bad" and "good" or "bad"
    e.t = time()   -- a new rating: its time (and expiry) starts again
    RT.Changed()
end

local function Delete(key)
    local list = Saved()
    if list then list[key] = nil end
    RT.Changed()
end

local function NewListRow()
    local r = CreateFrame("Frame", nil, page.list)
    r:SetHeight(LROW_H)
    r:EnableMouse(true)
    r.bg = W.Round(r, "BACKGROUND", C.raised)
    r.bg:SetAllPoints()
    W.Border(r, C.line)
    r.tag = RT.Tag(r)
    r.tag:SetPoint("LEFT", 10, 0)
    r.flip = CreateFrame("Button", nil, r)
    r.flip:SetAllPoints(r.tag)
    r.flip:SetScript("OnClick", function() if r.key then Flip(r.key) end end)
    r.flip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click: switch to " .. (r.e and r.e.v == "bad" and "Good" or "Bad"), 1, 1, 1)
        GameTooltip:Show()
    end)
    r.flip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.name = W.Text(r, "button")
    r.name:SetPoint("TOPLEFT", 64, -7)
    r.sub = W.Text(r, "tiny")
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.del = W.Button(r, "Delete", "quiet", 64, 26, "tiny")
    r.del:SetPoint("RIGHT", -10, 0)
    r.del:SetScript("OnClick", function() if r.key then Delete(r.key) end end)
    r.exp = W.Text(r, "tiny")
    r.exp:SetPoint("RIGHT", r.del, "LEFT", -12, 0)
    r.exp:SetJustifyH("RIGHT")
    r.sub:SetPoint("RIGHT", r.exp, "LEFT", -10, 0)
    -- The whole note in a tooltip (the line is cut).
    r:SetScript("OnEnter", function(self)
        local e = self.e
        if not (e and e.note) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.name or "?", unpack(T.ClassColor(e.class)))
        GameTooltip:AddLine("\"" .. e.note .. "\"", C.text2[1], C.text2[2], C.text2[3], true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function Rows()
    local h = page.list:GetHeight()
    return max(1, floor((h + LGAP) / (LROW_H + LGAP)))
end

function RT.PaintList()
    if not (page and page:IsShown()) then return end
    local list = Saved() or {}
    local q = strtrim(page.search:GetText() or ""):lower()
    local all, good, bad = {}, 0, 0
    for key, e in pairs(list) do
        if type(e) == "table" and not Expired(e) then
            if e.v == "bad" then bad = bad + 1 else good = good + 1 end
            local name = (e.name or key):lower()
            if (filter == "all" or e.v == filter) and (q == "" or name:find(q, 1, true)) then
                all[#all + 1] = { key = key, e = e }
            end
        end
    end
    table.sort(all, function(a, b)
        if (a.e.t or 0) ~= (b.e.t or 0) then return (a.e.t or 0) > (b.e.t or 0) end
        return a.key < b.key
    end)
    page.count:SetText(("%d rated  ·  |cff96e3ad%d Good|r  ·  |cffff9f96%d Bad|r"):format(good + bad, good, bad))
    local n = Rows()
    offset = math.min(offset, max(0, #all - n))
    for i = 1, max(n, #lrows) do
        local item = i <= n and all[offset + i]
        local r = lrows[i]
        if item then
            if not r then r = NewListRow(); lrows[i] = r end
            local e = item.e
            r.key, r.e = item.key, e
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", page.list, "TOPLEFT", 0, -(i - 1) * (LROW_H + LGAP))
            r:SetPoint("TOPRIGHT", page.list, "TOPRIGHT", 0, -(i - 1) * (LROW_H + LGAP))
            r.tag:SetRating(e.v)
            r.tag:Show()
            local name, realm = (e.name or item.key):match("^([^%-]+)%-?(.*)$")
            r.name:SetText(name or "?")
            r.name:SetTextColor(unpack(T.ClassColor(e.class)))
            r.sub:SetText((realm ~= "" and (realm .. "  ·  ") or "") .. When(e.t) .. "  ·  " .. RunText(e)
                .. (e.note and ("  ·  |cffc3cbd6\"" .. e.note .. "\"|r") or ""))
            local at = ExpiresAt(e)
            r.exp:SetText(at and ("expires " .. When(at)) or "kept")
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    page.empty:SetShown(#all == 0)
    page.empty:SetText((good + bad) == 0 and "No ratings yet. After your next key you can rate your group."
        or "No player matches.")
    page.more:SetText(#all > n and ("%d - %d of %d  ·  scroll for more"):format(offset + 1, math.min(#all, offset + n), #all) or "")
end

-- settings: the settings page's frame; SE: UI.Settings (its panels and switch rows).
function RT.BuildPage(settings, SE)
    local f = CreateFrame("Frame", nil, settings)
    f:SetAllPoints()
    f:SetFrameLevel(settings:GetFrameLevel() + 30)
    f:EnableMouse(true)
    f:Hide()
    local bg = W.Tex(f, "BACKGROUND", C.bg)
    bg:SetAllPoints()
    page = f
    settings:HookScript("OnHide", function() f:Hide() end)   -- the settings open on their own page next time

    -- Bar: Back to the settings, title, note
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT")
    bar:SetHeight(S.tabs)
    local bl = W.Tex(bar, "BORDER", C.line)
    bl:SetPoint("BOTTOMLEFT"); bl:SetPoint("BOTTOMRIGHT"); PixelUtil.SetHeight(bl, 1, 1)
    local back = W.Button(bar, "‹  Settings", "mark", 96, 28)
    back:SetPoint("LEFT", S.pad, 0)
    back:SetScript("OnClick", function() f:Hide() end)
    local title = W.Text(bar, "h2")
    title:SetPoint("LEFT", back, "RIGHT", 12, 0)
    title:SetText("Player ratings")
    local note = W.Text(bar, "small")
    note:SetPoint("RIGHT", -S.pad, 0)
    note:SetText("Only on this PC, never shared")

    -- Left: the options
    local opts = SE.Panel(f, "Mythic+ player ratings")
    opts:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", S.pad, -16)
    opts:SetPoint("TOPRIGHT", f, "TOP", -10, -S.tabs - 16)
    SE.SwitchRow(opts, "ratePrompt", "Rate your group after a key", "In time, over time or ended early. Rate only who you want.")
    SE.SwitchRow(opts, "rateHideBad", "Hide groups of leaders rated Bad", "In the Mythic+ search. Off: they show, marked BAD.",
        function() RT.Changed() end)
    local ex = opts:Row("Ratings expire", "Older ratings stop counting and are deleted at your next login.", true)
    local seg = W.Segmented(ex, { { 0, "Never" }, { 3, "3 months" }, { 6, "6 months" }, { 12, "12 months" } }, 28)
    seg:SetPoint("TOPLEFT", ex.desc, "BOTTOMLEFT", 0, -10)
    seg.onChange = function(v)
        local db = DB()
        if db then db.rateExpire = v end
        RT.Changed()
    end
    local da = opts:Row("Delete all ratings", "Every player in the list. Can't be undone.")
    local wipeBtn = W.Button(da, "Delete all", "quiet", 120, 28, "tiny")
    wipeBtn:SetPoint("RIGHT", -16, 0)
    local armed
    wipeBtn:SetScript("OnClick", function(self)
        if not armed then
            -- Our own confirm: the button asks once more for a few seconds.
            armed = true
            self:SetLabel("Click to confirm"); self:SetVariant("bad")
            C_Timer.After(4, function()
                if armed then armed = nil; self:SetLabel("Delete all"); self:SetVariant("quiet") end
            end)
            return
        end
        armed = nil
        self:SetLabel("Delete all"); self:SetVariant("quiet")
        local list = Saved()
        if list then wipe(list) end
        ns.Print("all player ratings deleted.")
        RT.Changed()
    end)
    local try = opts:Row("Try it", "The rating window with a made-up group; nothing is saved.")
    local preview = W.Button(try, "Preview", "ghost", 92, 28)
    preview:SetPoint("RIGHT", -16, 0)
    preview:SetScript("OnClick", RT.Preview)

    -- Right: the rated players
    local lp = W.Panel(f)
    lp:SetPoint("TOPLEFT", f, "TOP", 4, -S.tabs - 16)
    lp:SetPoint("BOTTOMRIGHT", -S.pad, 16)
    local lh = W.Label(lp, "Rated players")
    lh:SetPoint("TOPLEFT", 16, -14)
    page.count = W.Text(lp, "small")
    page.count:SetPoint("TOPRIGHT", -16, -14)

    local fseg = W.Segmented(lp, { { "all", "All" }, { "good", "Good" }, { "bad", "Bad" } }, 28)
    fseg:SetPoint("TOPRIGHT", -16, -38)
    fseg.onChange = function(v) filter = v; offset = 0; RT.PaintList() end
    fseg:SetValue("all")
    local box = CreateFrame("Frame", nil, lp)
    box:SetPoint("TOPLEFT", 16, -38)
    box:SetPoint("RIGHT", fseg, "LEFT", -10, 0)
    box:SetHeight(28)
    local bbg = W.Round(box, "BACKGROUND", C.bg); bbg:SetAllPoints()
    W.Border(box, C.lineStrong)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetAllPoints()
    eb:SetFontObject(T.Font.bodySm)
    eb:SetTextColor(unpack(C.textHi))
    eb:SetTextInsets(10, 10, 0, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(40)
    local hint = W.Text(box, "bodySm", C.faint)
    hint:SetPoint("LEFT", 10, 0)
    hint:SetText("Search a name…")
    eb:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
        offset = 0
        RT.PaintList()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function() W.SetBorder(box, C.gold) end)
    eb:SetScript("OnEditFocusLost", function() W.SetBorder(box, C.lineStrong) end)
    page.search = eb

    page.list = CreateFrame("Frame", nil, lp)
    page.list:SetPoint("TOPLEFT", 16, -78)
    page.list:SetPoint("BOTTOMRIGHT", -16, 34)
    page.list:EnableMouseWheel(true)
    page.list:SetScript("OnMouseWheel", function(_, delta)
        offset = max(0, offset - delta * 2)
        RT.PaintList()
    end)
    page.list:SetScript("OnSizeChanged", function() RT.PaintList() end)
    page.empty = W.Text(lp, "bodySm", C.muted)
    page.empty:SetPoint("TOP", page.list, "TOP", 0, -24)
    page.more = W.Text(lp, "small")
    page.more:SetPoint("BOTTOMLEFT", 16, 12)

    f:SetScript("OnShow", function()
        local db = DB()
        seg:SetValue(db and tonumber(db.rateExpire) or 0)
        SE.Paint()
        offset = 0
        RT.PaintList()
        A.Rise(opts, 0, 6, 0.3)
        A.Rise(lp, 0.04, 6, 0.3)
    end)
    return f
end

function RT.ShowPage()
    if page then page:Show(); A.FadeIn(page, 0.15) end
end
