-- CursedSurges: countdown + waypoint + zone announce for Cursed Surge events
-- on the Coiled Isle (Midnight 12.1).
--
-- Data source: C_EventScheduler (the world map's Events tab). Event entries
-- carry areaPoiID, startTime/endTime (epoch seconds); position comes from
-- C_AreaPoiInfo.GetAreaPOIInfo(mapID, areaPoiID). Data must be requested via
-- RequestEvents() and arrives with EVENT_SCHEDULER_UPDATE.

local ADDON_NAME = ...
local VERSION = "0.1.0"
local COILED_ISLE = 2512

local CS = CreateFrame("Frame")
local ui
local ticker
local state = {
  active = nil,   -- normalized event currently running
  nextEv = nil,   -- normalized next upcoming event
  requested = false,
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
  secs = math.max(0, math.floor(secs))
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

-- ---------------------------------------------------------------- event data

local function poiInfoFor(ev)
  local ok, pi = pcall(C_AreaPoiInfo.GetAreaPOIInfo, ev.mapID, ev.areaPoiID)
  if ok and type(pi) == "table" then return pi end
end

local function eventName(ev)
  local pi = poiInfoFor(ev)
  if pi then
    local ok, name = pcall(function() return pi.name .. "" end)
    if ok and name and name ~= "" then return name end
  end
  local di = ev.raw and ev.raw.displayInfo
  if type(di) == "table" then
    for _, key in ipairs({ "name", "eventName", "title" }) do
      local ok, name = pcall(function() return di[key] .. "" end)
      if ok and name and name ~= "" then return name end
    end
  end
  return "Cursed Surge"
end

local function eventPosition(ev)
  local pi = poiInfoFor(ev)
  local pos = pi and pi.position
  if type(pos) == "table" then
    local x = tonumber(pos.x)
    local y = tonumber(pos.y)
    if x and y then return ev.mapID, x, y end
  end
end

local function normalize(raw)
  if type(raw) ~= "table" or not raw.areaPoiID then return end
  local ok, mapID = pcall(C_EventScheduler.GetEventUiMapID, raw.areaPoiID)
  if not ok or mapID ~= COILED_ISLE then return end
  local start = tonumber(raw.startTime)
  local endT = tonumber(raw.endTime)
  if not (start and endT) then return end
  return {
    raw = raw,
    areaPoiID = raw.areaPoiID,
    mapID = mapID,
    key = raw.eventKey or (tostring(raw.areaPoiID) .. "@" .. tostring(start)),
    start = start,
    endT = endT,
  }
end

local function collectEvents()
  local byKey = {}
  for _, getter in ipairs({ "GetOngoingEvents", "GetScheduledEvents" }) do
    local fn = C_EventScheduler[getter]
    if fn then
      local ok, list = pcall(fn)
      if ok and type(list) == "table" then
        for _, raw in ipairs(list) do
          local ev = normalize(raw)
          if ev then byKey[ev.key] = ev end
        end
      end
    end
  end
  local now = GetServerTime()
  local active, nextEv
  for _, ev in pairs(byKey) do
    if ev.start <= now and now < ev.endT then
      if not active or ev.start > active.start then active = ev end
    elseif ev.start > now then
      if not nextEv or ev.start < nextEv.start then nextEv = ev end
    end
  end
  state.active, state.nextEv = active, nextEv
end

local function requestEvents()
  if C_EventScheduler and C_EventScheduler.RequestEvents then
    pcall(C_EventScheduler.RequestEvents)
    state.requested = true
  end
end

-- ---------------------------------------------------------------- actions

-- The event the buttons act on: the active surge if one is running, else the next one
local function targetEvent()
  return state.active or state.nextEv
end

local function setWaypoint()
  local ev = targetEvent()
  if not ev then chat("no Coiled Isle event to point at") return end
  local mapID, x, y = eventPosition(ev)
  if not mapID then
    chat("the event's map position isn't available yet — try once it appears on the map")
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
    return safefmt("%s is active on the Coiled Isle%s — ends in %s!", name, where, fmtDuration(ev.endT - now))
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
    ui.timer:SetText("|cff33ff66Active|r — ends in " .. fmtDuration(state.active.endT - now))
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
  if (state.active and now >= state.active.endT)
    or (state.nextEv and now >= state.nextEv.start) then
    rebuild()
    return
  end
  -- periodic re-request keeps the day's schedule fresh
  if GetTime() - lastRebuild > 300 then
    requestEvents()
    rebuild()
    return
  end
  refreshUI()
end

-- ---------------------------------------------------------------- slash commands

local function debugDump()
  chat(("v%s | HasData=%s"):format(VERSION,
    tostring(C_EventScheduler and C_EventScheduler.HasData and select(2, pcall(C_EventScheduler.HasData)))))
  local now = GetServerTime()
  for _, getter in ipairs({ "GetOngoingEvents", "GetScheduledEvents" }) do
    local fn = C_EventScheduler and C_EventScheduler[getter]
    local ok, list
    if fn then ok, list = pcall(fn) end
    if not ok or type(list) ~= "table" then
      chat(("%s: no table (%s)"):format(getter, tostring(list)))
    else
      chat(("%s: %d entries"):format(getter, #list))
      if #list == 0 and next(list) ~= nil then
        -- not a plain array — show its shape so we can adapt
        for k, v in pairs(list) do
          chat(("  key %s = %s"):format(tostring(k), tostring(v)))
        end
      end
      for _, raw in ipairs(list) do
        if type(raw) == "table" then
          local okM, mapID = pcall(C_EventScheduler.GetEventUiMapID, raw.areaPoiID)
          local mi = okM and mapID and C_Map.GetMapInfo(mapID)
          local ev = normalize(raw)
          chat(safefmt("  poi=%s map=%s (%s) start %+ds end %+ds%s | %s",
            tostring(raw.areaPoiID), tostring(okM and mapID or "?"),
            mi and mi.name or "?", (tonumber(raw.startTime) or 0) - now,
            (tonumber(raw.endTime) or 0) - now,
            ev and " [COILED]" or "",
            ev and eventName(ev) or "") or "  <entry>")
        end
      end
    end
  end
end

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
        chat("no Coiled Isle events in the scheduler right now")
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
