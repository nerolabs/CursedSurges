-- SurgeProbe: in-game API probe for Cursed Surge events on the Coiled Isle (12.1).
-- Goal: find which API backs the world map's Events tab (next-surge time + location).
-- Candidates: C_AreaPoiInfo, C_EventScheduler, C_VignetteInfo, task quests, UI widgets.
-- All output accumulates in a copyable window: /csp show, click "Select All", Cmd+C.

local ADDON_NAME = ...
local VERSION = "0.1.0"
local MAX_LINES = 6000

local SP = CreateFrame("Frame")
local lines = {}

local function chat(msg)
  print("|cffff66ccSurgeProbe:|r " .. msg)
end

local function out(msg, ...)
  if select("#", ...) > 0 then
    local ok, formatted = pcall(string.format, msg, ...)
    msg = ok and formatted or (tostring(msg) .. " <format error>")
  end
  lines[#lines + 1] = tostring(msg)
  if #lines > MAX_LINES then
    table.remove(lines, 1)
  end
end

-- ---------------------------------------------------------------- safe access

local function safeget(t, k)
  local ok, v = pcall(function() return t[k] end)
  if ok then return v end
end

local function safepairs(t)
  local ok, iter, state, ctrl = pcall(pairs, t)
  if ok then return iter, state, ctrl end
  return function() end
end

local function shortval(v)
  local tv = type(v)
  if tv == "string" then
    if #v > 160 then v = v:sub(1, 157) .. "..." end
    v = v:gsub("|", "||") -- keep UI escape codes visible/copyable
    return string.format("%q", v)
  elseif tv == "table" then
    local ok, s = pcall(tostring, v)
    return "<table " .. (ok and s or "?") .. ">"
  elseif tv == "function" then
    return "<function>"
  end
  return tostring(v)
end

local function dumpTable(t, depth, prefix, seen)
  seen = seen or {}
  if seen[t] then out(prefix .. "<cycle>") return end
  seen[t] = true
  local keys = {}
  for k in safepairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local shown = 0
  for _, k in ipairs(keys) do
    if shown >= 250 then
      out(prefix .. ("... (%d more keys)"):format(#keys - shown))
      break
    end
    shown = shown + 1
    local v = safeget(t, k)
    if type(v) == "table" and depth > 1 then
      out(prefix .. tostring(k) .. " = {")
      dumpTable(v, depth - 1, prefix .. "    ", seen)
      out(prefix .. "}")
    else
      out(prefix .. tostring(k) .. " = " .. shortval(v))
    end
  end
  if shown == 0 then out(prefix .. "(empty or unreadable)") end
end

-- 12.1 "secret" strings throw on any string op; forcing a concat inside pcall filters them out
local function frameNameSafe(f)
  local ok, n = pcall(function()
    local name = f:GetDebugName()
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name) ~= "string" then return nil end
    return name .. ""
  end)
  if ok then return n end
end

-- ---------------------------------------------------------------- output window

local win
local function ensureWindow()
  if win then return win end
  win = CreateFrame("Frame", "SurgeProbeWindow", UIParent, "BackdropTemplate")
  win:SetSize(780, 540)
  win:SetPoint("CENTER")
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetFrameStrata("DIALOG")
  win:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })

  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText("SurgeProbe — Select All, then Cmd/Ctrl+C to copy")

  local scroll = CreateFrame("ScrollFrame", "SurgeProbeScroll", win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -38)
  scroll:SetPoint("BOTTOMRIGHT", -36, 46)

  local eb = CreateFrame("EditBox", nil, scroll)
  eb:SetMultiLine(true)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(720)
  eb:SetAutoFocus(false)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(self) self:SetWidth(720) end)
  scroll:SetScrollChild(eb)
  win.editBox = eb

  local selectBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  selectBtn:SetSize(110, 24)
  selectBtn:SetPoint("BOTTOMLEFT", 16, 14)
  selectBtn:SetText("Select All")
  selectBtn:SetScript("OnClick", function()
    eb:SetFocus()
    eb:HighlightText()
  end)

  local clearBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  clearBtn:SetSize(110, 24)
  clearBtn:SetPoint("LEFT", selectBtn, "RIGHT", 8, 0)
  clearBtn:SetText("Clear Log")
  clearBtn:SetScript("OnClick", function()
    wipe(lines)
    eb:SetText("")
  end)

  local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -6, -6)

  return win
end

local function refreshWindow()
  local w = ensureWindow()
  w.editBox:SetText(table.concat(lines, "\n"))
  w:Show()
end

-- ---------------------------------------------------------------- generic probes

local function matchesAny(name, patterns)
  local l = name:lower()
  for _, p in ipairs(patterns) do
    if l:find(p, 1, true) then return true end
  end
  return false
end

local function probeGlobals(patterns, dumpNamespaces)
  out("== _G SCAN: %s ==", table.concat(patterns, "/"))
  local hits = {}
  for k in safepairs(_G) do
    if type(k) == "string" and matchesAny(k, patterns) then
      hits[#hits + 1] = k
    end
  end
  table.sort(hits)
  for _, k in ipairs(hits) do
    local v = safeget(_G, k)
    out("%s  [%s]", k, type(v))
    if dumpNamespaces and type(v) == "table" and k:sub(1, 2) == "C_" then
      dumpTable(v, 1, "    ")
    end
  end
  out("(%d global matches)", #hits)
end

local function probeStringValues(pattern)
  out("== GLOBAL STRING *VALUE* SCAN: '%s' ==", pattern)
  local pat = pattern:lower()
  local found = 0
  for k, v in safepairs(_G) do
    if type(k) == "string" and type(v) == "string" and #v < 400 and v:lower():find(pat, 1, true) then
      found = found + 1
      if found <= 120 then
        out("  %s = %s", k, (v:gsub("|", "||")))
      end
    end
  end
  out("(%d string-value matches%s)", found, found > 120 and ", first 120 shown" or "")
end

local function loadDocs()
  if APIDocumentation then return true end
  pcall(C_AddOns.LoadAddOn, "Blizzard_APIDocumentation")
  pcall(C_AddOns.LoadAddOn, "Blizzard_APIDocumentationGenerated")
  return APIDocumentation ~= nil
end

local function docFuncName(f)
  local ok, s = pcall(function() return f:GetSingleOutputLine() end)
  if ok and s then return s end
  ok, s = pcall(function() return f:GetFullName(false, false) end)
  if ok and s then return s end
  return tostring(safeget(f, "Name"))
end

local function probeDocs(pattern)
  out("== API DOC SCAN: '%s' ==", pattern)
  if not loadDocs() then
    out("APIDocumentation not available (Blizzard_APIDocumentation failed to load)")
    return
  end
  local pat = pattern:lower()
  local found = 0
  for _, system in ipairs(APIDocumentation.systems or {}) do
    local sysName = tostring(safeget(system, "Namespace") or safeget(system, "Name") or "?")
    local sysMatch = sysName:lower():find(pat, 1, true) ~= nil
    local buf = {}
    for _, f in ipairs(safeget(system, "Functions") or {}) do
      local name = docFuncName(f)
      if sysMatch or name:lower():find(pat, 1, true) then
        buf[#buf + 1] = "  fn:    " .. name
      end
    end
    for _, e in ipairs(safeget(system, "Events") or {}) do
      local name = tostring(safeget(e, "LiteralName") or safeget(e, "Name"))
      if sysMatch or name:lower():find(pat, 1, true) then
        buf[#buf + 1] = "  event: " .. name
      end
    end
    for _, t in ipairs(safeget(system, "Tables") or {}) do
      local name = tostring(safeget(t, "Name"))
      if sysMatch or name:lower():find(pat, 1, true) then
        buf[#buf + 1] = "  table: " .. name
      end
    end
    if #buf > 0 then
      found = found + #buf
      out("system %s:", sysName)
      for _, line in ipairs(buf) do out(line) end
    end
  end
  out("(%d doc matches)", found)
end

local function probeEnums(pattern)
  out("== Enum SCAN: '%s' ==", pattern)
  local pat = pattern:lower()
  local found = 0
  for k, v in safepairs(Enum) do
    if type(k) == "string" and k:lower():find(pat, 1, true) then
      found = found + 1
      out("Enum.%s:", k)
      if type(v) == "table" then dumpTable(v, 1, "    ") end
    end
  end
  out("(%d enum matches)", found)
end

local function dumpGlobal(name, depth)
  depth = depth or 2
  local v = _G
  for part in name:gmatch("[^%.]+") do
    if type(v) ~= "table" then v = nil break end
    v = safeget(v, part)
  end
  out("== DUMP %s [%s] depth=%d ==", name, type(v), depth)
  if type(v) == "table" then
    dumpTable(v, depth, "  ")
  else
    out("  " .. shortval(v))
  end
end

-- Generic invoker: /csp call C_EventScheduler.GetOngoingEvents 2352
-- Lets us iterate on discovered functions without shipping a new probe build.
local function callFn(rest)
  local path, argstr = rest:match("^(%S+)%s*(.-)$")
  if not path then chat("usage: /csp call <ns.fn> [args...]") return end
  local fn = _G
  for part in path:gmatch("[^%.]+") do
    if type(fn) ~= "table" then fn = nil break end
    fn = safeget(fn, part)
  end
  if type(fn) ~= "function" then
    out("== CALL %s: not a function (%s) ==", path, type(fn))
    return
  end
  local args = {}
  for word in argstr:gmatch("%S+") do
    if word == "true" then args[#args + 1] = true
    elseif word == "false" then args[#args + 1] = false
    elseif word == "nil" then args[#args + 1] = nil
    elseif tonumber(word) then args[#args + 1] = tonumber(word)
    else args[#args + 1] = word end
  end
  out("== CALL %s(%s) ==", path, argstr)
  local results = { pcall(fn, unpack(args)) }
  if not results[1] then
    out("  ERROR: %s", tostring(results[2]))
    return
  end
  for i = 2, #results do
    local v = results[i]
    if type(v) == "table" then
      out("  ret[%d] = {", i - 1)
      dumpTable(v, 3, "    ")
      out("  }")
    else
      out("  ret[%d] = %s", i - 1, shortval(v))
    end
  end
  if #results == 1 then out("  (no return values)") end
end

-- ---------------------------------------------------------------- zone / map

local function probeZone()
  out("== ZONE ==")
  out("  GetZoneText=%s GetSubZoneText=%s", tostring(GetZoneText()), tostring(GetSubZoneText()))
  local mapID = C_Map.GetBestMapForUnit("player")
  out("  best mapID=%s", tostring(mapID))
  if mapID then
    local info = C_Map.GetMapInfo(mapID)
    while info do
      out("    mapID=%s name=%s mapType=%s", tostring(info.mapID), tostring(info.name), tostring(info.mapType))
      info = info.parentMapID and info.parentMapID > 0 and C_Map.GetMapInfo(info.parentMapID) or nil
    end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then out("  player pos: %.4f, %.4f", pos.x, pos.y) end
  end
end

local function probeMaps(pattern)
  pattern = (pattern and pattern ~= "") and pattern:lower() or "coiled"
  out("== MAP ID SCAN 1..3500: name contains '%s' ==", pattern)
  local found = 0
  for id = 1, 3500 do
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if ok and info and info.name and info.name:lower():find(pattern, 1, true) then
      found = found + 1
      out("  mapID=%d name=%s mapType=%s parent=%s", id, info.name, tostring(info.mapType), tostring(info.parentMapID))
    end
  end
  out("(%d maps matched)", found)
end

-- ---------------------------------------------------------------- targeted probes

local function poiTimers(poiID)
  local bits = {}
  if C_AreaPoiInfo.GetAreaPOISecondsLeft then
    local ok, s = pcall(C_AreaPoiInfo.GetAreaPOISecondsLeft, poiID)
    bits[#bits + 1] = "secondsLeft=" .. (ok and tostring(s) or "<err>")
  end
  if C_AreaPoiInfo.GetAreaPOITimeLeftMinutes then
    local ok, m = pcall(C_AreaPoiInfo.GetAreaPOITimeLeftMinutes, poiID)
    bits[#bits + 1] = "minutesLeft=" .. (ok and tostring(m) or "<err>")
  end
  if C_AreaPoiInfo.IsAreaPOITimed then
    local ok, timed, hideTimer = pcall(C_AreaPoiInfo.IsAreaPOITimed, poiID)
    bits[#bits + 1] = "timed=" .. (ok and tostring(timed) or "<err>") .. " hideTimer=" .. (ok and tostring(hideTimer) or "?")
  end
  return table.concat(bits, "  ")
end

local function probePOIs(mapID)
  mapID = mapID or C_Map.GetBestMapForUnit("player")
  if not mapID then out("== AREA POIs: no mapID ==") return end
  local info = C_Map.GetMapInfo(mapID)
  out("== AREA POIs for map %d (%s) @ %.1f ==", mapID, info and info.name or "?", GetTime())
  local ok, pois = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
  if not ok or type(pois) ~= "table" then
    out("  GetAreaPOIForMap failed: %s", tostring(pois))
    return
  end
  out("  %d POIs", #pois)
  for _, poiID in ipairs(pois) do
    out("  -- poiID %s --", tostring(poiID))
    local ok2, pi = pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapID, poiID)
    if ok2 and type(pi) == "table" then
      dumpTable(pi, 2, "    ")
    else
      out("    <GetAreaPOIInfo failed: %s>", tostring(pi))
    end
    out("    " .. poiTimers(poiID))
  end
  -- some event POIs only show on the parent/continent map — caller should also
  -- probe parent mapIDs (the run battery does)
end

local SCHED_CANDIDATES = {
  "GetOngoingEvents", "GetScheduledEvents", "GetEvents", "GetActiveEvents",
  "GetEventInfo", "GetPlayerEntries", "GetEntries", "GetEventsForMap",
  "GetAvailableEvents", "GetUpcomingEvents",
}

local function probeScheduler(mapID)
  out("== C_EventScheduler PROBE ==")
  if not C_EventScheduler then
    out("  C_EventScheduler is nil — trying to load Blizzard addons")
    for _, name in ipairs({ "Blizzard_EventScheduler", "Blizzard_WorldMap" }) do
      local ok, res = pcall(C_AddOns.LoadAddOn, name)
      out("  LoadAddOn(%s): ok=%s result=%s", name, tostring(ok), tostring(res))
    end
  end
  if not C_EventScheduler then
    out("  still nil — namespace does not exist in this build")
    return
  end
  out("  namespace functions:")
  dumpTable(C_EventScheduler, 1, "    ")
  mapID = mapID or C_Map.GetBestMapForUnit("player")
  for _, fname in ipairs(SCHED_CANDIDATES) do
    local fn = safeget(C_EventScheduler, fname)
    if type(fn) == "function" then
      for _, arg in ipairs({ false, mapID }) do  -- false sentinel = no args
        local label = arg and (" (" .. tostring(arg) .. ")") or "()"
        local results = arg and { pcall(fn, arg) } or { pcall(fn) }
        if results[1] and results[2] ~= nil then
          out("  %s%s:", fname, label)
          for i = 2, #results do
            local v = results[i]
            if type(v) == "table" then
              dumpTable(v, 3, "    ")
            else
              out("    ret = %s", shortval(v))
            end
          end
        else
          out("  %s%s -> %s", fname, label, results[1] and "nil" or ("ERR " .. tostring(results[2])))
        end
      end
    end
  end
end

local function probeVignettes()
  out("== VIGNETTES @ %.1f ==", GetTime())
  local ok, vigs = pcall(C_VignetteInfo.GetVignettes)
  if not ok or type(vigs) ~= "table" then
    out("  GetVignettes failed: %s", tostring(vigs))
    return
  end
  out("  %d vignettes", #vigs)
  local mapID = C_Map.GetBestMapForUnit("player")
  for _, guid in ipairs(vigs) do
    local ok2, vi = pcall(C_VignetteInfo.GetVignetteInfo, guid)
    if ok2 and type(vi) == "table" then
      out("  -- %s --", tostring(safeget(vi, "name")))
      dumpTable(vi, 2, "    ")
      if mapID then
        local ok3, pos = pcall(C_VignetteInfo.GetVignettePosition, guid, mapID)
        if ok3 and pos then out("    pos on map %d: %.4f, %.4f", mapID, pos.x, pos.y) end
      end
    end
  end
end

local function probeTaskQuests(mapID)
  mapID = mapID or C_Map.GetBestMapForUnit("player")
  if not mapID then out("== TASK QUESTS: no mapID ==") return end
  out("== TASK QUESTS (world quests/events) for map %d ==", mapID)
  local ok, quests = pcall(C_TaskQuest.GetQuestsOnMap, mapID)
  if not ok then
    -- older API name
    ok, quests = pcall(C_TaskQuest.GetQuestsForPlayerByMapID, mapID)
  end
  if not ok or type(quests) ~= "table" then
    out("  no task quest data: %s", tostring(quests))
    return
  end
  out("  %d task quests", #quests)
  for _, q in ipairs(quests) do
    if type(q) == "table" then
      dumpTable(q, 2, "  ")
      out("  --")
    end
  end
end

local function probeWidgets()
  out("== UI WIDGETS (event timers often live here) ==")
  local sets = {}
  if C_UIWidgetManager.GetTopCenterWidgetSetID then
    sets[#sets + 1] = { "topCenter", C_UIWidgetManager.GetTopCenterWidgetSetID() }
  end
  if C_UIWidgetManager.GetBelowMinimapWidgetSetID then
    sets[#sets + 1] = { "belowMinimap", C_UIWidgetManager.GetBelowMinimapWidgetSetID() }
  end
  local mapID = C_Map.GetBestMapForUnit("player")
  if mapID and C_Map.GetMapDisplayInfo then
    local ok, di = pcall(C_Map.GetMapDisplayInfo, mapID)
    if ok and type(di) == "table" and di.mapWidgetSetID then
      sets[#sets + 1] = { "map", di.mapWidgetSetID }
    end
  end
  for _, entry in ipairs(sets) do
    local label, setID = entry[1], entry[2]
    out("  set %s (id=%s):", label, tostring(setID))
    if setID then
      local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
      if ok and type(widgets) == "table" then
        for _, w in ipairs(widgets) do
          out("    widgetID=%s type=%s", tostring(safeget(w, "widgetID")), tostring(safeget(w, "widgetType")))
        end
        if #widgets == 0 then out("    (none)") end
      end
    end
  end
  out("  (dump a specific widget: /csp call C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo <widgetID>)")
end

local CANDIDATE_ADDONS = {
  "Blizzard_EventScheduler", "Blizzard_WorldMap", "Blizzard_SharedMapDataProviders",
  "Blizzard_MapCanvas", "Blizzard_EventScheduler_Shared", "Blizzard_UIWidgets",
}

local function probeAddons(pattern)
  local pats = (pattern and pattern ~= "") and { pattern:lower() } or { "event", "map", "poi", "sched" }
  out("== ADDON LIST matching %s ==", table.concat(pats, "/"))
  local n = C_AddOns.GetNumAddOns()
  local found = 0
  for i = 1, n do
    local ok, name, title, _, loadable, reason = pcall(C_AddOns.GetAddOnInfo, i)
    if ok and name then
      local hay = (tostring(name) .. " " .. tostring(title)):lower()
      for _, p in ipairs(pats) do
        if hay:find(p, 1, true) then
          found = found + 1
          out("  %s | loaded=%s loadable=%s reason=%s | %s", tostring(name),
            tostring(C_AddOns.IsAddOnLoaded(name)), tostring(loadable), tostring(reason), tostring(title))
          break
        end
      end
    end
  end
  out("(%d of %d listed addons matched)", found, n)
  out("candidate Blizzard load-on-demand addons:")
  for _, name in ipairs(CANDIDATE_ADDONS) do
    local exists = C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(name)
    out("  %s: exists=%s loaded=%s", name, tostring(exists), tostring(C_AddOns.IsAddOnLoaded(name)))
  end
end

-- ---------------------------------------------------------------- frames / mouseover

local function probeFrames(pattern)
  out("== FRAME SCAN: '%s' ==", pattern)
  local pat = pattern:lower()
  local f = EnumerateFrames()
  local found = 0
  while f do
    local name = frameNameSafe(f)
    if name and name:lower():find(pat, 1, true) then
      found = found + 1
      if found <= 200 then
        local ok2, objType, shown = pcall(function() return f:GetObjectType(), f:IsShown() end)
        out("  %s [%s] shown=%s", name, ok2 and tostring(objType) or "?", ok2 and tostring(shown) or "?")
      end
    end
    f = EnumerateFrames(f)
  end
  out("(%d frames matched%s)", found, found > 200 and ", first 200 shown" or "")
end

local function probeMouse()
  out("== MOUSE FOCUS PROBE ==")
  local foci
  if GetMouseFoci then
    foci = GetMouseFoci()
  elseif GetMouseFocus then
    foci = { GetMouseFocus() }
  end
  if not foci or #foci == 0 then
    out("  nothing under the mouse")
    return
  end
  for i, f in ipairs(foci) do
    out("focus[%d]: %s", i, tostring(frameNameSafe(f)))
    local okED, ed = pcall(function() return f:GetElementData() end)
    if okED and type(ed) == "table" then
      out("  elementData:")
      dumpTable(ed, 3, "    ")
    end
    out("  keys:")
    pcall(dumpTable, f, 2, "    ")
    local p = f
    for depth = 1, 4 do
      local okP, parent = pcall(function() return p:GetParent() end)
      if not okP or not parent then break end
      out("  parent^%d: %s", depth, tostring(frameNameSafe(parent)))
      p = parent
    end
  end
end

-- ---------------------------------------------------------------- watch mode
-- Leave running across a surge spawning: logs every POI/vignette update on the
-- watched map with timestamps, so we can see what data appears BEFORE a surge
-- starts vs. when it goes active.

local watcher = CreateFrame("Frame")
local watchMapID, watchPending

local function watchSnapshot(reason)
  out("---- WATCH SNAPSHOT (%s) @ %.1f | server time %s ----", tostring(reason), GetTime(), date("%H:%M:%S"))
  local ok, pois = pcall(C_AreaPoiInfo.GetAreaPOIForMap, watchMapID)
  if ok and type(pois) == "table" then
    for _, poiID in ipairs(pois) do
      local ok2, pi = pcall(C_AreaPoiInfo.GetAreaPOIInfo, watchMapID, poiID)
      local name = ok2 and pi and tostring(safeget(pi, "name")) or "?"
      local pos = ok2 and pi and safeget(pi, "position")
      local x, y = 0, 0
      if type(pos) == "table" then
        x = tonumber(safeget(pos, "x")) or 0
        y = tonumber(safeget(pos, "y")) or 0
      end
      out("  poi %s | %s | %.4f,%.4f | %s | desc=%s", tostring(poiID), name, x, y,
        poiTimers(poiID), tostring(ok2 and pi and safeget(pi, "description") or ""))
    end
  end
  local okV, vigs = pcall(C_VignetteInfo.GetVignettes)
  if okV and type(vigs) == "table" and #vigs > 0 then
    for _, guid in ipairs(vigs) do
      local ok2, vi = pcall(C_VignetteInfo.GetVignetteInfo, guid)
      if ok2 and vi then
        out("  vignette %s | id=%s atlas=%s", tostring(safeget(vi, "name")),
          tostring(safeget(vi, "vignetteID")), tostring(safeget(vi, "atlasName")))
      end
    end
  end
end

watcher:SetScript("OnEvent", function(_, event)
  if watchPending then return end
  watchPending = true
  C_Timer.After(0.5, function()
    watchPending = false
    watchSnapshot(event)
  end)
end)

local WATCH_EVENTS = { "AREA_POIS_UPDATED", "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED" }

local function watchCmd(arg)
  if arg == "on" then
    watchMapID = C_Map.GetBestMapForUnit("player")
    if not watchMapID then chat("can't determine current map — try again outdoors") return end
    for _, e in ipairs(WATCH_EVENTS) do pcall(watcher.RegisterEvent, watcher, e) end
    local info = C_Map.GetMapInfo(watchMapID)
    out("== WATCH ON for map %d (%s) ==", watchMapID, info and info.name or "?")
    watchSnapshot("baseline")
    chat(("watching map %d — leave this running across a surge spawn, then /csp watch off"):format(watchMapID))
  elseif arg == "off" then
    watcher:UnregisterAllEvents()
    out("== WATCH OFF ==")
    refreshWindow()
    chat("watch OFF — results in window")
  else
    chat("usage: /csp watch on | off")
  end
end

-- ---------------------------------------------------------------- event logger

local logger = CreateFrame("Frame")
local counts, mode = {}, nil
local INTERESTING = { "POI", "VIGNETTE", "SCHEDULER", "SURGE", "TASK_QUEST", "WORLD_QUEST" }
local NOISY = {
  COMBAT_LOG_EVENT_UNFILTERED = true, UNIT_AURA = true, UNIT_POWER_UPDATE = true,
  UNIT_POWER_FREQUENT = true, UNIT_HEALTH = true, UNIT_TARGET = true,
  SPELL_UPDATE_COOLDOWN = true, SPELL_UPDATE_USABLE = true, SPELL_UPDATE_CHARGES = true,
  ACTIONBAR_UPDATE_COOLDOWN = true, CURSOR_CHANGED = true, UPDATE_UI_WIDGET = true,
  PLAYER_STARTED_MOVING = true, PLAYER_STOPPED_MOVING = true,
}

logger:SetScript("OnEvent", function(_, event, ...)
  counts[event] = (counts[event] or 0) + 1
  local interesting = false
  for _, p in ipairs(INTERESTING) do
    if event:find(p, 1, true) then interesting = true break end
  end
  if interesting or (mode == "all" and not NOISY[event] and counts[event] <= 5) then
    local n = select("#", ...)
    local args = {}
    for i = 1, math.min(n, 12) do
      args[i] = shortval((select(i, ...)))
    end
    out("%9.2f  %s(%s)", GetTime(), event, table.concat(args, ", "))
  end
end)

local function eventsCmd(arg)
  if arg == "on" or arg == "all" then
    wipe(counts)
    mode = arg
    logger:RegisterAllEvents()
    out("== EVENT LOG START (%s mode) @ %.2f ==", arg, GetTime())
    chat("event logging ON (" .. arg .. " mode) — open the world map / Events tab, wait for a surge, then /csp events off")
  elseif arg == "off" then
    logger:UnregisterAllEvents()
    mode = nil
    out("== EVENT LOG END — event counts ==")
    local arr = {}
    for e, c in pairs(counts) do arr[#arr + 1] = { e, c } end
    table.sort(arr, function(a, b) return a[2] > b[2] end)
    for _, ec in ipairs(arr) do out("  %5d  %s", ec[2], ec[1]) end
    refreshWindow()
    chat("event logging OFF — results in window")
  else
    chat("usage: /csp events on | all | off")
  end
end

-- ---------------------------------------------------------------- run battery

local function runAll()
  local v, build, bdate, toc = GetBuildInfo()
  out("==================================================================")
  out("SurgeProbe v%s | WoW %s (build %s, %s) toc=%s | %s", VERSION, v, build, bdate, toc, date())
  out("==================================================================")
  probeZone()
  probeMaps("coiled")
  probeGlobals({ "surge", "cursed" }, true)
  probeGlobals({ "areapoi", "eventscheduler", "vignette" }, true)
  probeDocs("poi")
  probeDocs("scheduler")
  probeDocs("vignette")
  probeDocs("surge")
  probeEnums("poi")
  probeEnums("scheduler")
  probeEnums("vignette")
  probeStringValues("surge")
  -- POIs on current map + every parent up the chain (events often live on the
  -- zone map AND the continent map with different data)
  local mapID = C_Map.GetBestMapForUnit("player")
  local seen = {}
  while mapID and not seen[mapID] do
    seen[mapID] = true
    probePOIs(mapID)
    local info = C_Map.GetMapInfo(mapID)
    mapID = info and info.parentMapID and info.parentMapID > 0 and info.parentMapID or nil
  end
  probeScheduler()
  probeVignettes()
  probeTaskQuests()
  probeWidgets()
  probeAddons()
  out("== DONE — copy everything above ==")
  refreshWindow()
  chat("probe battery complete — window opened, Select All + Cmd/Ctrl+C")
end

-- ---------------------------------------------------------------- slash commands

local HELP = [[
/csp run             - full probe battery (start here, ideally ON the Coiled Isle)
/csp show            - open/refresh output window
/csp clear           - clear log
/csp watch on|off    - live-log POI/vignette changes across a surge spawn (key experiment!)
/csp events on|all|off - log POI/vignette/scheduler events (open map + Events tab while on)
/csp mouseover       - dump UI element under mouse (hover Events tab entry, press Enter)
/csp poi [mapID]     - dump area POIs for a map (default: current)
/csp sched [mapID]   - probe C_EventScheduler
/csp vig             - dump vignettes
/csp tq [mapID]      - dump task quests (world quests/events) on a map
/csp widgets         - list active UI widget sets (event timers)
/csp maps [pattern]  - find mapIDs by name (default: coiled)
/csp call <ns.fn> [args] - call any API fn and dump results, e.g. /csp call C_AreaPoiInfo.GetAreaPOISecondsLeft 7813
/csp find <text>     - search _G + API docs + Enums for <text>
/csp dumpg <name> [depth] - dump a global table
/csp strings <text>  - find globals whose string VALUE contains <text>
/csp frames <pat>    - scan live frames by name (run with map open)
/csp addons [pat]    - list addons incl. Blizzard load-on-demand candidates
/csp load <name>     - force-load a Blizzard addon
/csp zone            - current zone/map IDs + player position
]]

SLASH_SURGEPROBE1 = "/csp"
SLASH_SURGEPROBE2 = "/surgeprobe"
SlashCmdList.SURGEPROBE = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()

  if cmd == "" or cmd == "help" then
    chat("commands:")
    print(HELP)
  elseif cmd == "run" then
    runAll()
  elseif cmd == "show" then
    refreshWindow()
  elseif cmd == "clear" then
    wipe(lines)
    if win then win.editBox:SetText("") end
    chat("log cleared")
  elseif cmd == "watch" then
    watchCmd(rest:lower())
  elseif cmd == "events" then
    eventsCmd(rest:lower())
  elseif cmd == "mouseover" or cmd == "mo" then
    probeMouse()
    refreshWindow()
  elseif cmd == "poi" then
    probePOIs(tonumber(rest))
    refreshWindow()
  elseif cmd == "sched" then
    probeScheduler(tonumber(rest))
    refreshWindow()
  elseif cmd == "vig" then
    probeVignettes()
    refreshWindow()
  elseif cmd == "tq" then
    probeTaskQuests(tonumber(rest))
    refreshWindow()
  elseif cmd == "widgets" then
    probeWidgets()
    refreshWindow()
  elseif cmd == "maps" then
    probeMaps(rest)
    refreshWindow()
  elseif cmd == "call" then
    if rest == "" then chat("usage: /csp call <ns.fn> [args...]") return end
    callFn(rest)
    refreshWindow()
  elseif cmd == "find" then
    if rest == "" then chat("usage: /csp find <text>") return end
    probeGlobals({ rest:lower() }, true)
    probeDocs(rest)
    probeEnums(rest)
    refreshWindow()
  elseif cmd == "dumpg" then
    local name, depth = rest:match("^(%S+)%s*(%d*)$")
    if not name then chat("usage: /csp dumpg <globalName> [depth]") return end
    dumpGlobal(name, tonumber(depth) or 2)
    refreshWindow()
  elseif cmd == "strings" then
    if rest == "" then chat("usage: /csp strings <text>") return end
    probeStringValues(rest)
    refreshWindow()
  elseif cmd == "frames" then
    if rest == "" then chat("usage: /csp frames <pattern>") return end
    probeFrames(rest)
    refreshWindow()
  elseif cmd == "addons" then
    probeAddons(rest)
    refreshWindow()
  elseif cmd == "load" then
    if rest == "" then chat("usage: /csp load <addonName>") return end
    local ok, loadedOrErr = pcall(C_AddOns.LoadAddOn, rest)
    out("== LOAD ADDON %s: ok=%s result=%s ==", rest, tostring(ok), tostring(loadedOrErr))
    chat("load attempt done — now /csp find scheduler (etc.) to see what appeared")
    refreshWindow()
  elseif cmd == "zone" then
    probeZone()
    refreshWindow()
  else
    chat("unknown command '" .. cmd .. "' — /csp help")
  end
end

-- ---------------------------------------------------------------- init / persistence

SP:RegisterEvent("ADDON_LOADED")
SP:RegisterEvent("PLAYER_LOGOUT")
SP:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    SurgeProbeDB = SurgeProbeDB or {}
    chat("v" .. VERSION .. " loaded — /csp run to start, /csp help for commands")
  elseif event == "PLAYER_LOGOUT" then
    -- log also lands in WTF/.../SavedVariables/SurgeProbe.lua as a copyable fallback
    SurgeProbeDB.log = lines
    SurgeProbeDB.savedAt = date()
  end
end)
