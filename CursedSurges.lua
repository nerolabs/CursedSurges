-- CursedSurges: countdown + waypoint + zone announce for Cursed Surge events
-- on the Coiled Isle (Midnight 12.1).
--
-- Data source: C_EventScheduler (the world map's Events tab). RequestEvents()
-- must be called first; data arrives with EVENT_SCHEDULER_UPDATE.
-- GetScheduledEvents() lists days of entries with epoch startTime/endTime and
-- keeps the currently running one; GetOngoingEvents() entries carry no times.
--
-- The Coiled Isle surge rotation is five 45-minute events cycling back-to-back
-- (observed build 69299): areaPoiIDs 8936-8940 / eventIDs 42-46. Zone lookup
-- (GetEventUiMapID) and poi info (name/position) only resolve while an event
-- is ACTIVE, so we learn each surge's name and fixed location when it runs and
-- cache them in SavedVariables — after one full lap the addon knows all five.

local ADDON_NAME = ...
local VERSION = "0.3.0"
local COILED_ISLE = 2512

-- The five surges and their fixed Coiled Isle locations (coords from Andrew).
-- 8939 = Mlurkkr Massacre is confirmed from live data; the other four
-- name<->poiID pairings are inferred from the rotation order (42,44,46,43,45
-- = 8936,8939,8937,8940,8938) and self-correct from live poi data the first
-- time each surge runs (learned name/location beats this table).
local SURGES = {
  [8939] = { name = "Mlurkkr Massacre",              x = 0.705, y = 0.327 },
  [8937] = { name = "Siege at the Whispering Marsch", x = 0.671, y = 0.775 },
  [8940] = { name = "The Malformed Leviathan",       x = 0.467, y = 0.628 },
  [8938] = { name = "The Broodmother's Nest",        x = 0.457, y = 0.296 },
  [8936] = { name = "The Looming Mutagenior",        x = 0.264, y = 0.649 },
}

local CS = CreateFrame("Frame")
local ui
local ticker
local state = {
  active = nil,   -- { areaPoiID, start, endT (may be nil), eventID }
  nextEv = nil,
}

local function chat(msg)
  print("|cff9966ffCursedSurges:|r " .. msg)
end

-- 12.1 secret strings can throw on any string op; route every format of
-- game-provided text through this
local function safefmt(fmt, ...)
  local ok, s = pcall(string.format, fmt, ...)
  if ok then return s end
end

local function fmtDuration(secs)
  secs = math.max(0, math.floor(tonumber(secs) or 0))
  local h = math.floor(secs / 3600)
  local m = math.floor((secs % 3600) / 60)
  local s = secs % 60
  if h > 0 then
    return ("%dh %02dm"):format(h, m)
  elseif m >= 10 then
    return ("%dm"):format(m)
  else
    return ("%dm %02ds"):format(m, s)
  end
end

-- ---------------------------------------------------------------- poi lookup + learning

-- GetAreaPOIInfo needs the right map, which we only reliably know while the
-- event is active; try the scheduler's answer, the Coiled Isle, then wherever
-- the player is standing
local function poiInfoFor(poiID)
  local maps = {}
  local ok, m = pcall(C_EventScheduler.GetEventUiMapID, poiID)
  if ok and type(m) == "number" then maps[#maps + 1] = m end
  maps[#maps + 1] = COILED_ISLE
  local pm = C_Map.GetBestMapForUnit("player")
  if pm then maps[#maps + 1] = pm end
  for _, mapID in ipairs(maps) do
    local ok2, pi = pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapID, poiID)
    if ok2 and type(pi) == "table" then return pi, mapID end
  end
end

local function learn(poiID)
  if not (CursedSurgesDB and CursedSurgesDB.names) then return end
  local pi, mapID = poiInfoFor(poiID)
  if not pi then return end
  local ok, name = pcall(function() return pi.name .. "" end)
  if ok and name and name ~= "" then
    CursedSurgesDB.names[poiID] = name
  end
  local pos = pi.position
  if type(pos) == "table" then
    local x, y = tonumber(pos.x), tonumber(pos.y)
    if x and y then
      CursedSurgesDB.locs[poiID] = { mapID = mapID, x = x, y = y }
    end
  end
end

local function eventName(ev)
  if not ev then return "Cursed Surge" end
  local names = CursedSurgesDB and CursedSurgesDB.names
  local learned = names and names[ev.areaPoiID]
  if learned then return learned end
  local s = SURGES[ev.areaPoiID]
  return (s and s.name) or "Cursed Surge"
end

local function eventPosition(ev)
  if not ev then return end
  -- live info first (also refreshes the cache), then learned, then the built-in table
  learn(ev.areaPoiID)
  local loc = CursedSurgesDB and CursedSurgesDB.locs and CursedSurgesDB.locs[ev.areaPoiID]
  if loc then return loc.mapID, loc.x, loc.y end
  local s = SURGES[ev.areaPoiID]
  if s then return COILED_ISLE, s.x, s.y end
end

-- ---------------------------------------------------------------- event data

local function collectEvents()
  local now = GetServerTime()
  local active, nextEv

  -- scheduled list carries times and keeps the running event while active
  local ok, list = pcall(C_EventScheduler.GetScheduledEvents)
  if ok and type(list) == "table" then
    for _, raw in ipairs(list) do
      if type(raw) == "table" and SURGES[raw.areaPoiID] then
        local start, endT = tonumber(raw.startTime), tonumber(raw.endTime)
        if start and endT then
          local ev = { areaPoiID = raw.areaPoiID, start = start, endT = endT, eventID = raw.eventID }
          if start <= now and now < endT then
            if not active or ev.start > active.start then active = ev end
          elseif start > now then
            if not nextEv or ev.start < nextEv.start then nextEv = ev end
          end
        end
      end
    end
  end

  -- fallback: ongoing list (no times; end estimated from the POI timer if possible)
  if not active then
    local ok2, ong = pcall(C_EventScheduler.GetOngoingEvents)
    if ok2 and type(ong) == "table" then
      for _, raw in ipairs(ong) do
        if type(raw) == "table" and SURGES[raw.areaPoiID] then
          local okS, secs = pcall(C_AreaPoiInfo.GetAreaPOISecondsLeft, raw.areaPoiID)
          active = {
            areaPoiID = raw.areaPoiID,
            start = now,
            endT = (okS and tonumber(secs)) and (now + secs) or nil,
          }
        end
      end
    end
  end

  state.active, state.nextEv = active, nextEv
  if active then learn(active.areaPoiID) end
end

local function requestEvents()
  if C_EventScheduler and C_EventScheduler.RequestEvents then
    pcall(C_EventScheduler.RequestEvents)
  end
end

-- ---------------------------------------------------------------- actions

-- The event the buttons act on: the active surge if one is running, else the next one
local function targetEvent()
  return state.active or state.nextEv
end

local function setWaypoint()
  local ev = targetEvent()
  if not ev then chat("no surge to point at") return end
  local mapID, x, y = eventPosition(ev)
  if not mapID then
    chat("this surge's location isn't known yet — it's learned the first time each surge runs")
    return
  end
  local name = eventName(ev)
  local pinned = false
  if C_Map.CanSetUserWaypointOnMap(mapID) then
    local point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
    C_Map.SetUserWaypoint(point)
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    pinned = true
  end
  local tomtom = false
  if TomTom and TomTom.AddWaypoint then
    local ok = pcall(TomTom.AddWaypoint, TomTom, mapID, x, y, { title = name, from = "CursedSurges" })
    tomtom = ok
  end
  if pinned or tomtom then
    chat(safefmt("waypoint set: %s (%.1f, %.1f)%s", name, x * 100, y * 100,
      tomtom and " + TomTom" or "") or "waypoint set")
  else
    chat("couldn't set a waypoint on this map")
  end
end

local function zoneChannelIndex()
  local list = { GetChannelList() }
  for i = 1, #list, 3 do
    local id, name = list[i], list[i + 1]
    local ok, hit = pcall(function() return name:find("General", 1, true) ~= nil end)
    if ok and hit then return id end
  end
end

local function buildAnnounce()
  local ev = targetEvent()
  if not ev then return end
  local name = eventName(ev)
  local now = GetServerTime()
  local mapID, x, y = eventPosition(ev)
  local where = ""
  if x and y then
    where = safefmt(" at %.1f, %.1f", x * 100, y * 100) or ""
  end
  if state.active == ev then
    if ev.endT then
      return safefmt("%s is active on the Coiled Isle%s — ends in %s!", name, where, fmtDuration(ev.endT - now))
    end
    return safefmt("%s is active on the Coiled Isle%s!", name, where)
  else
    return safefmt("%s starts in %s on the Coiled Isle%s", name, fmtDuration(ev.start - now), where)
  end
end

-- ---------------------------------------------------------------- UI

local function ensureUI()
  if ui then return ui end
  ui = CreateFrame("Frame", "CursedSurgesWindow", UIParent, "BackdropTemplate")
  ui:SetSize(240, 108)
  ui:SetPoint("CENTER", 0, 200)
  ui:SetMovable(true)
  ui:EnableMouse(true)
  ui:RegisterForDrag("LeftButton")
  ui:SetScript("OnDragStart", function(self)
    if not CursedSurgesDB.locked then self:StartMoving() end
  end)
  ui:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    CursedSurgesDB.pos = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  ui:SetClampedToScreen(true)
  ui:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  ui:SetBackdropColor(0.05, 0.02, 0.10, 0.88)

  ui.title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ui.title:SetPoint("TOPLEFT", 10, -8)
  ui.title:SetText("|cff9966ffCursed Surges|r")

  local close = CreateFrame("Button", nil, ui, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    ui.userHidden = true -- session-only; a /reload brings it back
    ui:Hide()
  end)

  ui.name = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ui.name:SetPoint("TOPLEFT", 10, -24)
  ui.name:SetPoint("TOPRIGHT", -10, -24)
  ui.name:SetJustifyH("LEFT")
  ui.name:SetWordWrap(false)

  ui.timer = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ui.timer:SetPoint("TOPLEFT", 10, -40)
  ui.timer:SetPoint("TOPRIGHT", -10, -40)
  ui.timer:SetJustifyH("LEFT")

  ui.nextLine = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ui.nextLine:SetPoint("TOPLEFT", 10, -60)
  ui.nextLine:SetPoint("TOPRIGHT", -10, -60)
  ui.nextLine:SetJustifyH("LEFT")
  ui.nextLine:SetTextColor(0.7, 0.7, 0.7)

  ui.waypointBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
  ui.waypointBtn:SetSize(100, 22)
  ui.waypointBtn:SetPoint("BOTTOMLEFT", 10, 9)
  ui.waypointBtn:SetText("Waypoint")
  ui.waypointBtn:SetScript("OnClick", setWaypoint)

  ui.announceBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
  ui.announceBtn:SetSize(100, 22)
  ui.announceBtn:SetPoint("BOTTOMRIGHT", -10, 9)
  ui.announceBtn:SetText("Announce")
  -- SendChatMessage to a public channel needs a hardware event: it must run
  -- directly inside this OnClick, not via any timer/callback indirection
  ui.announceBtn:SetScript("OnClick", function()
    local msg = buildAnnounce()
    if not msg then chat("nothing to announce") return end
    local idx = zoneChannelIndex()
    if not idx then
      chat("couldn't find the zone General channel — announcing in /say instead")
      SendChatMessage(msg, "SAY")
      return
    end
    SendChatMessage(msg, "CHANNEL", nil, idx)
  end)

  if CursedSurgesDB.pos then
    local p = CursedSurgesDB.pos
    ui:ClearAllPoints()
    ui:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
  end
  return ui
end

local function refreshUI()
  local ev = state.active or state.nextEv
  if not ev then
    if ui then ui:Hide() end
    return
  end
  ensureUI()
  if ui.userHidden then return end

  local now = GetServerTime()
  if state.active then
    ui.name:SetText(eventName(state.active))
    if state.active.endT then
      ui.timer:SetText("|cff33ff66Active|r — ends in " .. fmtDuration(state.active.endT - now))
    else
      ui.timer:SetText("|cff33ff66Active now|r")
    end
    if state.nextEv then
      ui.nextLine:SetText("Next: " .. eventName(state.nextEv) .. " in " .. fmtDuration(state.nextEv.start - now))
    else
      ui.nextLine:SetText("")
    end
  else
    ui.name:SetText(eventName(state.nextEv))
    ui.timer:SetText("Starts in |cffffcc00" .. fmtDuration(state.nextEv.start - now) .. "|r")
    ui.nextLine:SetText("")
  end
  ui:Show()
end

-- ---------------------------------------------------------------- update loop

local lastRebuild = 0

local function rebuild()
  lastRebuild = GetTime()
  collectEvents()
  refreshUI()
end

local function onTick()
  local now = GetServerTime()
  -- roll over when the displayed event starts or ends
  if (state.active and state.active.endT and now >= state.active.endT)
    or (state.nextEv and now >= state.nextEv.start) then
    rebuild()
    return
  end
  -- periodic re-request keeps the schedule fresh
  if GetTime() - lastRebuild > 300 then
    requestEvents()
    rebuild()
    return
  end
  refreshUI()
end

-- ---------------------------------------------------------------- debug window

local dbgWin
local function ensureDebugWindow()
  if dbgWin then return dbgWin end
  dbgWin = CreateFrame("Frame", "CursedSurgesDebugWindow", UIParent, "BackdropTemplate")
  dbgWin:SetSize(680, 460)
  dbgWin:SetPoint("CENTER")
  dbgWin:SetMovable(true)
  dbgWin:EnableMouse(true)
  dbgWin:RegisterForDrag("LeftButton")
  dbgWin:SetScript("OnDragStart", dbgWin.StartMoving)
  dbgWin:SetScript("OnDragStop", dbgWin.StopMovingOrSizing)
  dbgWin:SetFrameStrata("DIALOG")
  dbgWin:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })

  local title = dbgWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText("CursedSurges debug — Select All, then Cmd/Ctrl+C")

  local scroll = CreateFrame("ScrollFrame", "CursedSurgesDebugScroll", dbgWin, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -38)
  scroll:SetPoint("BOTTOMRIGHT", -36, 46)

  local eb = CreateFrame("EditBox", nil, scroll)
  eb:SetMultiLine(true)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(620)
  eb:SetAutoFocus(false)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(self) self:SetWidth(620) end)
  scroll:SetScrollChild(eb)
  dbgWin.editBox = eb

  local selectBtn = CreateFrame("Button", nil, dbgWin, "UIPanelButtonTemplate")
  selectBtn:SetSize(110, 24)
  selectBtn:SetPoint("BOTTOMLEFT", 16, 14)
  selectBtn:SetText("Select All")
  selectBtn:SetScript("OnClick", function()
    eb:SetFocus()
    eb:HighlightText()
  end)

  local closeBtn = CreateFrame("Button", nil, dbgWin, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -6, -6)

  return dbgWin
end

local function dbgval(v)
  local tv = type(v)
  if tv == "string" then
    local ok, s = pcall(function() return (v:gsub("|", "||")) end)
    return ok and ("%q"):format(s) or "<secret string>"
  end
  return tostring(v)
end

-- shallow-ish dump: scalars at both levels, functions skipped (vector mixins are noisy)
local function dbgdump(t, prefix, outLines, depth)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local v = t[k]
    if type(v) == "table" and depth > 1 then
      outLines[#outLines + 1] = prefix .. tostring(k) .. " = {"
      dbgdump(v, prefix .. "    ", outLines, depth - 1)
      outLines[#outLines + 1] = prefix .. "}"
    elseif type(v) ~= "function" then
      outLines[#outLines + 1] = prefix .. tostring(k) .. " = " .. dbgval(v)
    end
  end
end

local function debugDump()
  local outLines = {}
  local function out(fmt, ...)
    outLines[#outLines + 1] = safefmt(fmt, ...) or tostring(fmt)
  end

  local now = GetServerTime()
  out("CursedSurges v%s | server time %d (%s) | player map %s",
    VERSION, now, date("%H:%M:%S"), tostring(C_Map.GetBestMapForUnit("player")))
  for _, probe in ipairs({ "HasData", "CanShowEvents", "GetActiveContinentName" }) do
    local fn = C_EventScheduler and C_EventScheduler[probe]
    if fn then
      local ok, v = pcall(fn)
      out("%s = %s", probe, ok and tostring(v) or ("ERR " .. tostring(v)))
    end
  end

  out("state: active=%s next=%s", tostring(state.active and state.active.areaPoiID),
    tostring(state.nextEv and state.nextEv.areaPoiID))
  out("learned names/locations:")
  if CursedSurgesDB then
    for poiID in pairs(SURGES) do
      local loc = CursedSurgesDB.locs and CursedSurgesDB.locs[poiID]
      out("  %d: %s | %s", poiID,
        tostring(CursedSurgesDB.names and CursedSurgesDB.names[poiID]),
        loc and safefmt("map %d %.4f,%.4f", loc.mapID, loc.x, loc.y) or "no location yet")
    end
  end

  for _, getter in ipairs({ "GetOngoingEvents", "GetScheduledEvents" }) do
    local fn = C_EventScheduler and C_EventScheduler[getter]
    local ok, list
    if fn then ok, list = pcall(fn) end
    if not ok or type(list) ~= "table" then
      out("== %s: no table (%s) ==", getter, tostring(list))
    else
      out("== %s: %d entries ==", getter, #list)
      if #list == 0 and next(list) ~= nil then
        out("(not a plain array — raw shape below)")
        dbgdump(list, "  ", outLines, 3)
      end
      for i, raw in ipairs(list) do
        if type(raw) == "table" then
          local okM, mapID = pcall(C_EventScheduler.GetEventUiMapID, raw.areaPoiID)
          local mi = okM and mapID and C_Map.GetMapInfo(mapID)
          out("-- [%d]%s map=%s (%s) start %+ds end %+ds", i,
            SURGES[raw.areaPoiID] and " [SURGE]" or "", tostring(okM and mapID or "?"),
            mi and mi.name or "?", (tonumber(raw.startTime) or 0) - now,
            (tonumber(raw.endTime) or 0) - now)
          dbgdump(raw, "    ", outLines, 3)
          if raw.areaPoiID then
            local pi, piMap = poiInfoFor(raw.areaPoiID)
            if pi then
              out("    poiInfo (via map %s):", tostring(piMap))
              dbgdump(pi, "        ", outLines, 2)
            else
              out("    poiInfo: nil (position not resolvable yet)")
            end
          end
        else
          out("-- [%d] = %s", i, dbgval(raw))
        end
      end
    end
  end

  local w = ensureDebugWindow()
  w.editBox:SetText(table.concat(outLines, "\n"))
  w:Show()
  chat("debug dump in window — Select All + Cmd/Ctrl+C")
end

-- ---------------------------------------------------------------- slash commands

SLASH_CURSEDSURGES1 = "/cursedsurges"
SLASH_CURSEDSURGES2 = "/surge"
SlashCmdList.CURSEDSURGES = function(msg)
  local cmd = (msg or ""):lower():match("^(%S*)")
  if cmd == "" or cmd == "toggle" then
    if ui and ui:IsShown() then
      ui.userHidden = true
      ui:Hide()
    else
      if ui then ui.userHidden = false end
      requestEvents()
      rebuild()
      if not (state.active or state.nextEv) then
        chat("no surge events in the scheduler right now (data may still be loading — try /surge refresh)")
      end
    end
  elseif cmd == "lock" then
    CursedSurgesDB.locked = true
    chat("window locked")
  elseif cmd == "unlock" then
    CursedSurgesDB.locked = false
    chat("window unlocked")
  elseif cmd == "reset" then
    CursedSurgesDB.pos = nil
    if ui then
      ui:ClearAllPoints()
      ui:SetPoint("CENTER", 0, 200)
    end
    chat("position reset")
  elseif cmd == "refresh" then
    requestEvents()
    rebuild()
    chat("refreshed")
  elseif cmd == "debug" then
    debugDump()
  else
    chat("commands: /surge (toggle), lock, unlock, reset, refresh, debug")
  end
end

-- ---------------------------------------------------------------- init

CS:RegisterEvent("ADDON_LOADED")
CS:RegisterEvent("PLAYER_ENTERING_WORLD")
CS:RegisterEvent("EVENT_SCHEDULER_UPDATE")
CS:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    CursedSurgesDB = CursedSurgesDB or {}
    CursedSurgesDB.names = CursedSurgesDB.names or {}
    CursedSurgesDB.locs = CursedSurgesDB.locs or {}
  elseif event == "PLAYER_ENTERING_WORLD" then
    requestEvents()
    rebuild()
    if not ticker then
      ticker = C_Timer.NewTicker(1, onTick)
    end
  elseif event == "EVENT_SCHEDULER_UPDATE" then
    rebuild()
  end
end)
