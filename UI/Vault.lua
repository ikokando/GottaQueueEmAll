-------------------------------------------------------------------------------
--  UI/Vault.lua  --  Great Vault and this week's affixes, in the footer
--
--  "VAULT ▮▯▯▮▯▯▯▮ 6/8 | [icons]": eight marks for this week's Mythic+
--  runs, the tall ones are the vault slots (1, 4, 8 runs) and glow once
--  unlocked; the tooltip has each slot's key level and item level, a click
--  opens the Great Vault. Then this week's affixes as icons, each with its
--  own tooltip (name and text).
--  Setting "footerVault" hides it. Updated while the window is open.
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, W = UI.Theme, UI.W
local C = T.C

local V = {}
UI.Vault = V

local PIPS, PIP_W, PIP_GAP = 8, 5, 3
local f

local function DB() return ns.DB and ns.DB() end
local function Num(v) return UI.Data.Num(v) end

-- This week's Mythic+ vault rows, by threshold: { threshold, progress, level, id }.
local function Slots()
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then return {} end
    local kind = Enum and Enum.WeeklyRewardChestThresholdType
    local ok, acts = pcall(C_WeeklyRewards.GetActivities, kind and kind.Activities or 1)
    local out = {}
    for _, a in ipairs(ok and type(acts) == "table" and acts or {}) do
        if type(a) == "table" and Num(a.threshold) then
            out[#out + 1] = { threshold = a.threshold, progress = Num(a.progress) or 0, level = Num(a.level) or 0,
                              id = a.id, tier = Num(a.activityTierID) }
        end
    end
    table.sort(out, function(a, b) return a.threshold < b.threshold end)
    return out
end

-- This week's affixes: { { name, desc, icon }, ... }.
local function Affixes()
    local out = {}
    local ok, list = pcall(C_MythicPlus.GetCurrentAffixes)
    for _, a in ipairs(ok and type(list) == "table" and list or {}) do
        local id = type(a) == "table" and Num(a.id)
        local name, desc, icon
        if id and C_ChallengeMode.GetAffixInfo then name, desc, icon = C_ChallengeMode.GetAffixInfo(id) end
        if UI.Data.Str(name) then out[#out + 1] = { name = name, desc = UI.Data.Str(desc), icon = Num(icon) } end
    end
    return out
end

-- One affix icon: Blizzard's art, cropped, in a thin frame; its own tooltip.
local ICON = 18
local function AffixIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(ICON, ICON)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1); b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    W.Lines(b, C.lineStrong, "OVERLAY")
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        W.SetBorder(self, C.gold)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.name or "", 1, 1, 1)
        if self.desc then GameTooltip:AddLine(self.desc, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        W.SetBorder(self, C.lineStrong)
        GameTooltip:Hide()
    end)
    return b
end

-- The reward's item level for an unlocked slot (nil until the item is cached).
local function RewardLevel(id)
    if not (id and C_WeeklyRewards.GetExampleRewardItemHyperlinks) then return end
    local ok, link = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, id)
    if not (ok and type(link) == "string") then return end
    local get = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    return get and Num(get(link))
end

-- A slot earned with Heroic dungeons (no key level), as Blizzard's vault tells it.
local function Heroic(s)
    if not (s.tier and C_WeeklyRewards.GetDifficultyIDForActivityTier) then return s.level == 0 end
    local ok, diff = pcall(C_WeeklyRewards.GetDifficultyIDForActivityTier, s.tier)
    local heroic = DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonHeroic or 2
    return ok and diff == heroic
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Great Vault  ·  Dungeons", 1, 1, 1)
    for i, s in ipairs(Slots()) do
        local left = ("Slot %d  ·  %d %s"):format(i, s.threshold, s.threshold == 1 and "run" or "runs")
        if s.progress >= s.threshold then
            local il = RewardLevel(s.id)
            local col = Heroic(s) and C.text2 or T.KeyColor(s.level)
            GameTooltip:AddDoubleLine(left, (Heroic(s) and "Heroic" or ("+" .. s.level)) .. (il and ("  ·  item level " .. il) or ""),
                0.85, 0.85, 0.85, col[1], col[2], col[3])
        else
            local togo = s.threshold - s.progress
            GameTooltip:AddDoubleLine(left, ("%d %s to go"):format(togo, togo == 1 and "run" or "runs"),
                0.85, 0.85, 0.85, 0.55, 0.6, 0.68)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: open the Great Vault", 0.55, 0.6, 0.68)
    GameTooltip:Show()
end

-- Blizzard's Great Vault window (its own opener loads it first).
local function OpenVault()
    if InCombatLockdown() then return end
    if WeeklyRewards_ShowUI then pcall(WeeklyRewards_ShowUI); return end
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "Blizzard_WeeklyRewards") end
    if WeeklyRewardsFrame then pcall(ShowUIPanel, WeeklyRewardsFrame, true) end
end

-- foot: the footer; anchorTo: what it sits left of (your name line).
function V.Build(foot, anchorTo)
    f = CreateFrame("Button", nil, foot)
    f:SetHeight(24)
    f:SetPoint("RIGHT", anchorTo, "LEFT", -22, 0)
    f.hover = W.Round(f, "BACKGROUND", { 1, 1, 1, 0 })
    f.hover:SetAllPoints()
    f.label = W.Text(f, "tiny", C.label)
    f.label:SetPoint("LEFT", 8, 0)
    f.label:SetText("VAULT")
    f.pips = {}
    for i = 1, PIPS do
        local p = W.Tex(f, "ARTWORK")
        p:SetWidth(PIP_W)
        p:SetPoint("BOTTOMLEFT", f.label, "BOTTOMRIGHT", 7 + (i - 1) * (PIP_W + PIP_GAP), 0)
        f.pips[i] = p
    end
    f.count = W.Text(f, "small", C.textHi)
    f.count:SetPoint("LEFT", f.label, "RIGHT", 7 + PIPS * (PIP_W + PIP_GAP) + 4, 0)
    -- A thin line, then this week's affixes as icons.
    f.sep = W.Tex(f, "ARTWORK", C.lineStrong)
    f.sep:SetSize(1, 14)
    f.sep:SetPoint("LEFT", f.count, "RIGHT", 10, 0)
    f.icons = {}
    f:SetScript("OnEnter", function(self) self.hover:SetVertexColor(1, 1, 1, 0.04); Tooltip(self) end)
    f:SetScript("OnLeave", function(self) self.hover:SetVertexColor(1, 1, 1, 0); GameTooltip:Hide() end)
    f:SetScript("OnClick", OpenVault)

    local events = CreateFrame("Frame")
    ns.Live(events, { "WEEKLY_REWARDS_UPDATE", "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "CHALLENGE_MODE_COMPLETED" })
    events:SetScript("OnEvent", function() V.Refresh() end)
    return f
end

function V.Refresh()
    if not f then return end
    local db = DB()
    local slots = Slots()
    if (db and db.footerVault == false) or #slots == 0 then f:Hide(); return end
    local runs, slotAt = 0, {}
    for _, s in ipairs(slots) do
        runs = math.max(runs, s.progress)
        slotAt[s.threshold] = true
    end
    local top = slots[#slots].threshold
    for i, p in ipairs(f.pips) do
        local done, slot = i <= runs, slotAt[i]
        p:SetHeight(slot and 13 or 8)
        if slot and done then p:SetVertexColor(unpack(C.goldLight))
        elseif done then p:SetVertexColor(unpack(C.goldDark))
        else p:SetVertexColor(unpack(C.track)) end
    end
    f.count:SetText(("%d/%d"):format(math.min(runs, top), top))
    local affixes = Affixes()
    f.sep:SetShown(#affixes > 0)
    for i, a in ipairs(affixes) do
        local b = f.icons[i] or AffixIcon(f)
        f.icons[i] = b
        b.name, b.desc = a.name, a.desc
        b.tex:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        b:ClearAllPoints()
        b:SetPoint("LEFT", i == 1 and f.sep or f.icons[i - 1], "RIGHT", i == 1 and 10 or 4, 0)
        b:Show()
    end
    for i = #affixes + 1, #f.icons do f.icons[i]:Hide() end
    local icons = #affixes > 0 and (10 + 1 + 10 + #affixes * ICON + (#affixes - 1) * 4) or 0
    f:SetWidth(math.ceil(8 + f.label:GetStringWidth() + 7 + PIPS * (PIP_W + PIP_GAP) + 4
        + f.count:GetStringWidth() + icons + 8))
    f:Show()
end

-- The window opened: ask the server for fresh data, show what's known.
function V.Request()
    if C_MythicPlus and C_MythicPlus.RequestCurrentAffixes then C_MythicPlus.RequestCurrentAffixes() end
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
    V.Refresh()
end
