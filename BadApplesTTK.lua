-- Bad Apples TTK
-- - Shows a boss timer based on saved/average guild kill times
-- - Blends that timer with TimeToKill's live TTK estimate (if installed)
-- - Shift-drag to move (unless locked)
-- - Commands mirror TimeToKill style, but via /battk

BadApplesTTKDB = BadApplesTTKDB or {}
BadApplesTTK = BadApplesTTK or {}

local ADDON_NAME = "BadApplesTTK"
local SETTINGS_VERSION = 1

-- ============================================================================
-- Internal boss defaults (seed estimates)
-- ============================================================================
local BossDefaults = {
  ["Anub'Rekhan"] = 42, -- 00:42
  ["Grand Widow Faerlina"] = 51, -- 00:51
  ["Maexxna"] = 37, -- 00:37
  ["Noth the Plaguebringer"] = 42, -- 00:42
  ["Heigan the Unclean"] = 54, -- 00:56
  ["Loatheb"] = 125, -- 02:05
  ["Instructor Razuvious"] = 50, -- 00:50
  ["Patchwerk"] = 97, -- 01:37
  ["Grobbulus"] = 56, -- 00:56
  ["Gluth"] = 51, -- 00:51
  ["Thaddius"] = 138, -- 02:10
  ["Sapphiron"] = 124, -- 02:04
  ["Kel'Thuzad"] = 266, -- 04:22
  ["The Four Horsemen"] = 210, -- 03:30
  ["Heroic Training Dummy"] = 300, -- 05:00 (test)
}

-- Encounters where the target name is NOT the encounter name.
-- Map unit names -> encounter name.
local EncounterAlias = {
  ["Lady Blaumeux"]     = "The Four Horsemen",
  ["Thane Korth'azz"]   = "The Four Horsemen",
  ["Sir Zeliek"]        = "The Four Horsemen",
  ["Highlord Mograine"] = "The Four Horsemen",
}

-- ============================================================================
-- Settings / SavedVariables
-- ============================================================================
local defaultPosition = {
  point = "BOTTOMLEFT",
  relativeTo = "UIParent",
  relativePoint = "BOTTOMLEFT",
  x = math.floor(GetScreenWidth() * 0.465),
  y = math.floor(GetScreenHeight() * 0.16),
}

local function EnsureDB()
  if type(BadApplesTTKDB) ~= "table" then BadApplesTTKDB = {} end
  BadApplesTTKDB.Settings = BadApplesTTKDB.Settings or {}
  BadApplesTTKDB.Position = BadApplesTTKDB.Position or {}
  BadApplesTTKDB.BossStats = BadApplesTTKDB.BossStats or {}

  local S = BadApplesTTKDB.Settings
  if S.version == nil then
    S.version = SETTINGS_VERSION
  end

  if S.isLocked == nil then S.isLocked = false end
  if S.combatHide == nil then S.combatHide = false end
  if S.isHidden == nil then S.isHidden = false end
  if S.showBossName == nil then S.showBossName = true end
  if S.showLastKill == nil then S.showLastKill = true end
  if S.showInternal == nil then S.showInternal = true end
  if S.showBlend == nil then S.showBlend = true end
  if S.blendSmoothing == nil then S.blendSmoothing = 0.15 end
end

local function GetStats(bossName)
  BadApplesTTKDB.BossStats[bossName] = BadApplesTTKDB.BossStats[bossName] or {}
  local st = BadApplesTTKDB.BossStats[bossName]

  if st.kills == nil then st.kills = 0 end
  if st.lastKill == nil then st.lastKill = nil end

  -- Seed avgKill from defaults if missing
  if st.avgKill == nil then
    st.avgKill = BossDefaults[bossName] or 0
  end

  return st
end

-- ============================================================================
-- Utilities
-- ============================================================================
local function Clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function SmoothValue(current, target, factor)
  if current == nil then return target end
  if target == nil then return current end
  return current + (target - current) * factor
end

local function FormatTime(sec)
  if not sec or sec < 0 then return "--:--" end
  sec = math.floor(sec + 0.5)
  local h = math.floor(sec / 3600)
  local m = math.floor((math.mod(sec, 3600)) / 60)
  local s = math.mod(sec, 60)

  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%02d:%02d", m, s)
end

local function IsBossTarget()
  if not UnitExists("target") then return false, nil end
  local name = UnitName("target")
  if not name then return false, nil end

  local encounter = EncounterAlias[name] or name
  if BossDefaults[encounter] then
    return true, encounter
  end
  return false, nil
end

-- Try to confirm it's a boss-y unit; fallback to name list only.
local function IsLikelyRaidBossUnit()
  if not UnitExists("target") then return false end
  local lvl = UnitLevel("target")
  if lvl and lvl == -1 then return true end
  if type(UnitClassification) == "function" then
    local c = UnitClassification("target")
    if c == "worldboss" then return true end
  end
  return false
end

local function GetTTKSeconds()
  if TimeToKill and type(TimeToKill.GetTTK) == "function" then
    local v = TimeToKill.GetTTK()
    if type(v) == "number" and v > 0 then
      return v
    end
  end
  return nil
end

-- ============================================================================
-- BigWigs-style engage scan (target + raid/party targets)
-- ============================================================================
local function GetBossFromUnit(unit)
  if not UnitExists(unit) then return nil end
  local name = UnitName(unit)
  if not name then return nil end
  local encounter = EncounterAlias[name] or name
  if BossDefaults[encounter] then
    return encounter
  end
  return nil
end

local function ScanForEngageBoss()
  -- 1) Player target
  local enc = GetBossFromUnit("target")
  if enc and UnitAffectingCombat("target") then
    return enc
  end

  -- 2) Raid targets
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  if n and n > 0 then
    local i
    for i = 1, n do
      local unit = "raid" .. i .. "target"
      local e = GetBossFromUnit(unit)
      if e and UnitAffectingCombat(unit) then
        return e
      end
    end
    return nil
  end

  -- 3) Party targets
  local p = GetNumPartyMembers and GetNumPartyMembers() or 0
  if p and p > 0 then
    local i
    for i = 1, p do
      local unit = "party" .. i .. "target"
      local e = GetBossFromUnit(unit)
      if e and UnitAffectingCombat(unit) then
        return e
      end
    end
  end

  return nil
end

-- ============================================================================
-- Frame / UI (TTK-style)
-- ============================================================================
local frame = CreateFrame("Frame", "BadApplesTTKFrame", UIParent)
BadApplesTTK.Frame = frame

frame:SetFrameStrata("HIGH")
frame:SetWidth(210)
frame:SetHeight(90)
frame:SetMovable(true)
frame:EnableMouse(true)

local textBoss = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
textBoss:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE, MONOCHROME")
textBoss:SetPoint("TOP", 0, -6)
textBoss:SetTextColor(1, 0.82, 0.25)

local textLast = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
textLast:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE, MONOCHROME")
textLast:SetPoint("TOP", 0, -24)
textLast:SetTextColor(0.8, 0.8, 0.8)

local textInternal = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
textInternal:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE, MONOCHROME")
textInternal:SetPoint("TOP", 0, -44)
textInternal:SetTextColor(1, 1, 1)

local textBlend = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
textBlend:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE, MONOCHROME")
textBlend:SetPoint("TOP", 0, -72)
textBlend:SetTextColor(0.7, 0.7, 1.0)

local isMoving = false

frame:SetScript("OnMouseDown", function()
  if BadApplesTTKDB.Settings.isLocked then return end
  if IsShiftKeyDown() and frame and frame.StartMoving then
    isMoving = true
    pcall(frame.StartMoving, frame)
  end
end)

frame:SetScript("OnMouseUp", function()
  if not isMoving then return end
  isMoving = false
  if frame and frame.StopMovingOrSizing then
    pcall(frame.StopMovingOrSizing, frame)
  end

  -- Save position
  local x = frame:GetLeft()
  local y = frame:GetBottom()
  if x and y then
    BadApplesTTKDB.Position.point = "BOTTOMLEFT"
    BadApplesTTKDB.Position.relativeTo = "UIParent"
    BadApplesTTKDB.Position.relativePoint = "BOTTOMLEFT"
    BadApplesTTKDB.Position.x = x
    BadApplesTTKDB.Position.y = y
  end
end)

local function ApplyFramePosition()
  local P = BadApplesTTKDB.Position
  local point = P.point or defaultPosition.point
  local relativeToName = P.relativeTo or defaultPosition.relativeTo
  local relativePoint = P.relativePoint or defaultPosition.relativePoint
  local x = P.x or defaultPosition.x
  local y = P.y or defaultPosition.y

  local rel = getglobal(relativeToName) or UIParent
  frame:ClearAllPoints()
  frame:SetPoint(point, rel, relativePoint, x, y)
end

local function ApplyLockState()
  if BadApplesTTKDB.Settings.isLocked then
    frame:EnableMouse(false)
  else
    frame:EnableMouse(true)
  end
end

local function ApplyVisibilityState(inCombat)
  if BadApplesTTKDB.Settings.isHidden then
    frame:Hide()
    return
  end

  if BadApplesTTKDB.Settings.combatHide then
    if inCombat then frame:Show() else frame:Hide() end
  else
    frame:Show()
  end
end

local function ClearDisplay()
  textBoss:SetText("")
  textLast:SetText("")
  textInternal:SetText("--:--")
  textBlend:SetText("")
end

-- ============================================================================
-- Encounter state
-- ============================================================================
local inCombat = false
local activeBoss = nil
local encounterStart = nil
local lastTTKSeen = nil
local smoothBlend = nil

-- BigWigs-style engage scan state
local engageScanActive = false
local lastEngageScanAt = 0
local engageScanInterval = 0.5

local function StartEncounter(bossName)
  if activeBoss == bossName and encounterStart then return end

  activeBoss = bossName
  encounterStart = GetTime()
  lastTTKSeen = nil
  smoothBlend = nil
  engageScanActive = false

  local st = GetStats(bossName)

  -- Draw initial rows immediately
  if BadApplesTTKDB.Settings.showBossName then
    textBoss:SetText(bossName)
  else
    textBoss:SetText("")
  end

  if BadApplesTTKDB.Settings.showLastKill then
    if st.lastKill and st.lastKill > 0 then
      textLast:SetText("Last: " .. FormatTime(st.lastKill))
    else
      textLast:SetText("Last: --:--")
    end
  else
    textLast:SetText("")
  end
end

local function EndEncounter(recordKill)
  if not activeBoss or not encounterStart then
    activeBoss = nil
    encounterStart = nil
    lastTTKSeen = nil
    smoothBlend = nil
    return
  end

  if recordKill then
    local dur = GetTime() - encounterStart
    if dur > 0 and dur < 36000 then
      local st = GetStats(activeBoss)
      st.lastKill = dur

      -- Seeded running average:
      -- if kills==0, treat the default avg as one prior sample so first real kill becomes (default + kill)/2
      local priorN = st.kills or 0
      local seedN = (priorN == 0 and 1 or priorN)
      local seedAvg = st.avgKill or (BossDefaults[activeBoss] or dur)
      local newAvg = (seedAvg * seedN + dur) / (seedN + 1)

      st.avgKill = newAvg
      st.kills = priorN + 1
    end
  end

  -- Leave the last values on screen; stop updating until next pull
  activeBoss = nil
  encounterStart = nil
  lastTTKSeen = nil
  smoothBlend = nil
end

-- ============================================================================
-- Update loop
-- ============================================================================
local lastCheckTime = 0
local checkInterval = 0.1

local function UpdateDisplay()
  if not activeBoss or not encounterStart then
    return
  end

  local now = GetTime()
  local elapsed = now - encounterStart

  local st = GetStats(activeBoss)
  local avgKill = st.avgKill or (BossDefaults[activeBoss] or 0)

  -- Internal countdown based on guild avg
  local internalRemaining = nil
  if avgKill and avgKill > 0 then
    internalRemaining = avgKill - elapsed
    if internalRemaining < 0 then internalRemaining = 0 end
  end

  -- Pull TTK estimate when available
  local ttk = GetTTKSeconds()
  if ttk then
    lastTTKSeen = ttk
  end

  local blend = nil
  if internalRemaining and internalRemaining > 0 and lastTTKSeen and lastTTKSeen > 0 then
    blend = (internalRemaining + lastTTKSeen) / 2
  elseif internalRemaining and internalRemaining >= 0 then
    blend = internalRemaining
  elseif lastTTKSeen and lastTTKSeen > 0 then
    blend = lastTTKSeen
  end

  -- Row 1: boss
  if BadApplesTTKDB.Settings.showBossName then
    textBoss:SetText(activeBoss)
  else
    textBoss:SetText("")
  end

  -- Row 2: last
  if BadApplesTTKDB.Settings.showLastKill then
    if st.lastKill and st.lastKill > 0 then
      textLast:SetText("Last: " .. FormatTime(st.lastKill) .. "  (N=" .. tostring(st.kills or 0) .. ")")
    else
      textLast:SetText("Last: --:--")
    end
  else
    textLast:SetText("")
  end

  -- Row 3: internal
  if BadApplesTTKDB.Settings.showInternal then
    if internalRemaining ~= nil then
      textInternal:SetText(FormatTime(internalRemaining))
    else
      textInternal:SetText("--:--")
    end
  else
    textInternal:SetText("")
  end

  -- Row 4: blend
  if BadApplesTTKDB.Settings.showBlend then
    if blend ~= nil then
      smoothBlend = SmoothValue(smoothBlend, blend, Clamp(BadApplesTTKDB.Settings.blendSmoothing, 0.05, 0.5))
      local label = "Blend: " .. FormatTime(smoothBlend)
      textBlend:SetText(label)
    else
      textBlend:SetText("")
    end
  else
    textBlend:SetText("")
  end
end

frame:SetScript("OnUpdate", function()
  if isMoving then return end
  if not inCombat then return end

  local t = GetTime()

  -- BigWigs-style engage scan: while in combat but no active boss yet,
  -- scan target + raid/party targets every 0.5s until a boss is found.
  if engageScanActive and (not activeBoss) then
    if (t - lastEngageScanAt) >= engageScanInterval then
      lastEngageScanAt = t
      local boss = ScanForEngageBoss()
      if boss then
        StartEncounter(boss)
      end
    end
  end

  if (t - lastCheckTime) >= checkInterval then
    lastCheckTime = t
    UpdateDisplay()
  end
end)

-- ============================================================================
-- Event handling
-- ============================================================================
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")

frame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then return end
    EnsureDB()
    ApplyFramePosition()
    ApplyLockState()
    ApplyVisibilityState(UnitAffectingCombat("player"))
    ClearDisplay()

  elseif event == "PLAYER_LOGIN" then
    EnsureDB()
    ApplyFramePosition()
    ApplyLockState()
    inCombat = UnitAffectingCombat("player") and true or false
    ApplyVisibilityState(inCombat)

  elseif event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    ApplyVisibilityState(true)

    -- Start engage scan (BigWigs-style)
    engageScanActive = true
    lastEngageScanAt = 0

    -- Immediate attempt (in case boss is already targeted)
    local boss = ScanForEngageBoss()
    if boss then
      StartEncounter(boss)
    end

  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    engageScanActive = false
    ApplyVisibilityState(false)
    -- Wipe / disengage: do NOT record
    EndEncounter(false)

  elseif event == "PLAYER_DEAD" then
    inCombat = false
    engageScanActive = false
    ApplyVisibilityState(false)
    EndEncounter(false)

  elseif event == "PLAYER_TARGET_CHANGED" then
    if not inCombat then return end
    if activeBoss then return end

    -- If you (or the raid) has engaged a boss, starting when you acquire it as a target
    local ok, boss = IsBossTarget()
    if ok and UnitExists("target") and UnitAffectingCombat("target") then
      StartEncounter(boss)
    end

  elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
    -- Typical format: "Bossname dies."
    if not arg1 then return end
    local deadName = string.match(arg1, "^(.+) dies%.$")
    if not deadName then
      deadName = string.match(arg1, "^You have slain (.+)!$")
    end
    if not deadName then
      deadName = string.match(arg1, "^(.+) is slain%.$")
    end
    if not deadName then return end

    local encounter = EncounterAlias[deadName] or deadName

    -- Record kill if the active encounter matches, or if we were tracking an alias encounter.
    if activeBoss and encounter == activeBoss then
      EndEncounter(true)
    end
  end
end)

-- ============================================================================
-- Slash commands: /battk (TimeToKill-style)
-- ============================================================================
SLASH_BADAPPLESTTK1 = "/battk"
SlashCmdList["BADAPPLESTTK"] = function(msg)
  EnsureDB()

  local args = {}
  local i = 1
  while true do
    local next_space = string.find(msg or "", " ", i)
    if not next_space then
      table.insert(args, string.sub(msg or "", i))
      break
    end
    table.insert(args, string.sub(msg, i, next_space - 1))
    i = next_space + 1
  end

  if not args[1] or args[1] == "" then
    print("Bad Apples TTK Usage:")
    print("|cFF33FF99/battk show|r - Show frame")
    print("|cFF33FF99/battk hide|r - Hide frame")
    print("|cFF33FF99/battk lock|r - Lock frame (click-through)")
    print("|cFF33FF99/battk unlock|r - Unlock frame (Shift-drag to move)")
    print("|cFF33FF99/battk combathide on|r - Hide frame when out of combat")
    print("|cFF33FF99/battk combathide off|r - Keep frame visible")
    print("|cFF33FF99/battk boss on|r - Show boss name")
    print("|cFF33FF99/battk boss off|r - Hide boss name")
    print("|cFF33FF99/battk last on|r - Show last kill row")
    print("|cFF33FF99/battk last off|r - Hide last kill row")
    print("|cFF33FF99/battk internal on|r - Show internal countdown row")
    print("|cFF33FF99/battk internal off|r - Hide internal countdown row")
    print("|cFF33FF99/battk blend on|r - Show blended ETA row")
    print("|cFF33FF99/battk blend off|r - Hide blended ETA row")
    print("|cFF33FF99/battk smooth <0.05-0.5>|r - Blend smoothing (default 0.15)")
    return
  end

  local cmd = string.lower(args[1])
  local opt = args[2] and string.lower(args[2]) or nil

  if cmd == "show" then
    BadApplesTTKDB.Settings.isHidden = false
    ApplyVisibilityState(inCombat)
    print("Bad Apples TTK: Shown")

  elseif cmd == "hide" then
    BadApplesTTKDB.Settings.isHidden = true
    ApplyVisibilityState(inCombat)
    print("Bad Apples TTK: Hidden")

  elseif cmd == "lock" then
    BadApplesTTKDB.Settings.isLocked = true
    ApplyLockState()
    print("Bad Apples TTK: Frame locked")

  elseif cmd == "unlock" then
    BadApplesTTKDB.Settings.isLocked = false
    ApplyLockState()
    print("Bad Apples TTK: Frame unlocked (Shift-drag)")

  elseif cmd == "combathide" then
    if opt == "on" then
      BadApplesTTKDB.Settings.combatHide = true
      ApplyVisibilityState(inCombat)
      print("Bad Apples TTK: Combat hide enabled")
    elseif opt == "off" then
      BadApplesTTKDB.Settings.combatHide = false
      ApplyVisibilityState(inCombat)
      print("Bad Apples TTK: Combat hide disabled")
    else
      print("Bad Apples TTK: Usage: /battk combathide [on|off]")
    end

  elseif cmd == "boss" then
    if opt == "on" then BadApplesTTKDB.Settings.showBossName = true
    elseif opt == "off" then BadApplesTTKDB.Settings.showBossName = false
    else print("Bad Apples TTK: Usage: /battk boss [on|off]") return end

  elseif cmd == "last" then
    if opt == "on" then BadApplesTTKDB.Settings.showLastKill = true
    elseif opt == "off" then BadApplesTTKDB.Settings.showLastKill = false
    else print("Bad Apples TTK: Usage: /battk last [on|off]") return end

  elseif cmd == "internal" then
    if opt == "on" then BadApplesTTKDB.Settings.showInternal = true
    elseif opt == "off" then BadApplesTTKDB.Settings.showInternal = false
    else print("Bad Apples TTK: Usage: /battk internal [on|off]") return end

  elseif cmd == "blend" then
    if opt == "on" then BadApplesTTKDB.Settings.showBlend = true
    elseif opt == "off" then BadApplesTTKDB.Settings.showBlend = false
    else print("Bad Apples TTK: Usage: /battk blend [on|off]") return end

  elseif cmd == "smooth" then
    local v = tonumber(opt or "")
    if v and v >= 0.05 and v <= 0.5 then
      BadApplesTTKDB.Settings.blendSmoothing = v
      print("Bad Apples TTK: Blend smoothing set to " .. tostring(v))
    else
      print("Bad Apples TTK: Usage: /battk smooth <0.05-0.5>")
    end

  else
    print("Bad Apples TTK: Unknown command. Type /battk for help.")
  end

  UpdateDisplay()
end

-- Optional: tiny API for other addons
BadApplesTTK.GetActiveBoss = function() return activeBoss end
BadApplesTTK.GetInternalRemaining = function()
  if not activeBoss or not encounterStart then return nil end
  local st = GetStats(activeBoss)
  local avgKill = st.avgKill or (BossDefaults[activeBoss] or 0)
  if not avgKill or avgKill <= 0 then return nil end
  local rem = avgKill - (GetTime() - encounterStart)
  if rem < 0 then rem = 0 end
  return rem
end
BadApplesTTK.GetBlendRemaining = function() return smoothBlend end
