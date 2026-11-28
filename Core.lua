local addonName, ns = ...

-- FDR, the Flight Data Recorder: times every flight-master flight from take
-- off to landing, remembers each route, and counts the next flight on that
-- route down to landing.
--
-- How a flight is caught: picking a destination on the flight map calls the
-- game's TakeTaxiNode(slot), which is hooked to note where from and where to.
-- The flight itself starts when UnitOnTaxi("player") turns true and ends
-- when it turns false again; a ticker watches for both. The flight in
-- progress is saved, so a /reload in the air carries on counting.

ns.addonName = addonName

-- chat: a line in chat on landing; alert: a sound and a note on screen
-- shortly before landing.
local DEFAULTS = { bar = true, mapPanel = true, chat = true, alert = true }
local BOARD_WAIT = 20       -- seconds to wait for take off after picking a destination
local MIN_FLIGHT = 5        -- shorter "flights" (a cancelled take off) are not recorded
local RESUME_LIMIT = 2 * 3600
local KEEP_TIMES = 5        -- recent flights kept per route; the usual time is their middle one
local ALERT_AHEAD = 10      -- seconds before landing for the alert
local ALERT_SOUND = SOUNDKIT and SOUNDKIT.MAP_PING or 3175
ns.ISSUES = "github.com/bizzal70/FlightDataRecorder/issues"

local pending          -- destination picked, not in the air yet
ns.flight = nil        -- the flight in the air: from, to, fromName, toName, started

function ns.Print(message)
    print("|cff66c2ffFDR|r: " .. message)
end

-- 1:05, 12:40, 1:02:03.
function ns.Clock(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

-- "Sentinel Hill, Westfall" -> "Sentinel Hill".
function ns.ShortName(name)
    if type(name) ~= "string" then return "?" end
    return name:match("^([^,]+)") or name
end

local function Usable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function RouteKey(from, to) return tostring(from) .. ">" .. tostring(to) end
ns.RouteKey = RouteKey

-- The usual time of a route: the middle of its last few flights (the
-- quicker middle one when there is an even number). A flight slowed by
-- lag or a loading screen doesn't replace a good time, and a route the
-- game has changed catches up after a few flights.
function ns.UsualTime(times)
    if type(times) ~= "table" or #times == 0 then return nil end
    local sorted = {}
    for i, seconds in ipairs(times) do sorted[i] = seconds end
    table.sort(sorted)
    return sorted[math.floor((#sorted + 1) / 2)]
end

-- What the flight map shows right now: the node the player stands at, and
-- every node by its slot on the map. Uses C_TaxiMap where there is one, the
-- older TaxiNode functions otherwise.
function ns.ReadTaxiMap()
    local here, bySlot = nil, {}
    local ok = pcall(function()
        if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
            local current = Enum and Enum.FlightPathState and Enum.FlightPathState.Current or 0
            for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID()) or {}) do
                if Usable(node.nodeID) and Usable(node.name) then
                    local entry = { id = node.nodeID, name = node.name }
                    if Usable(node.slotIndex) then bySlot[node.slotIndex] = entry end
                    if node.state == current then here = entry end
                end
            end
        end
    end)
    if (not ok or not next(bySlot)) and NumTaxiNodes and TaxiNodeName then
        for slot = 1, NumTaxiNodes() or 0 do
            local name = TaxiNodeName(slot)
            if Usable(name) and name ~= "" then
                -- No node IDs here: names stand in for them.
                local entry = { id = name, name = name }
                bySlot[slot] = entry
                if TaxiNodeGetType and TaxiNodeGetType(slot) == "CURRENT" then here = entry end
            end
        end
    end
    return here, bySlot
end

-- Every recorded route from a node, quickest first.
function ns.RoutesFrom(fromID)
    local list = {}
    for _, route in pairs(ns.db.routes) do
        if route.from == fromID then list[#list + 1] = route end
    end
    table.sort(list, function(a, b) return (a.time or 0) < (b.time or 0) end)
    return list
end

function ns.Route(fromID, toID)
    return ns.db.routes[RouteKey(fromID, toID)]
end

-- How long a flight takes: the recorded time, or, for a route only flown
-- the other way so far, that time as an estimate (flights take about as
-- long either way). Returns seconds and whether it is an estimate.
function ns.Estimate(fromID, toID)
    local route = ns.Route(fromID, toID)
    if route and route.time then return route.time, false end
    local back = ns.Route(toID, fromID)
    if back and back.time then return back.time, true end
end

-- Every destination with a time from a node, quickest first: { id, name,
-- time, estimated }. Routes only flown the other way are estimates.
function ns.TimesFrom(fromID)
    local list, seen = {}, {}
    for _, route in pairs(ns.db.routes) do
        if route.from == fromID and route.time then
            list[#list + 1] = { id = route.to, name = route.toName, time = route.time, estimated = false }
            seen[route.to] = true
        end
    end
    for _, route in pairs(ns.db.routes) do
        if route.to == fromID and route.time and not seen[route.from] then
            list[#list + 1] = { id = route.from, name = route.fromName, time = route.time, estimated = true }
        end
    end
    table.sort(list, function(a, b) return a.time < b.time end)
    return list
end

-- Picking a destination on the flight map.
function ns.OnTakeTaxiNode(slot)
    local ok, here, bySlot = pcall(ns.ReadTaxiMap)
    if not ok then return end
    local destination = bySlot and bySlot[slot]
    if not (here and destination) then return end
    pending = { from = here.id, fromName = here.name, to = destination.id, toName = destination.name, picked = time() }
end

local function Land()
    local flight = ns.flight
    ns.flight, ns.db.current = nil, nil
    if ns.UpdateBar then ns.UpdateBar() end
    if not flight then return end
    local seconds = time() - flight.started
    if seconds < MIN_FLIGHT then return end
    local key = RouteKey(flight.from, flight.to)
    local route = ns.db.routes[key]
    local before = route and route.time
    route = route or { from = flight.from, to = flight.to }
    route.fromName, route.toName = flight.fromName, flight.toName
    route.times = type(route.times) == "table" and route.times or {}
    table.insert(route.times, seconds)
    while #route.times > KEEP_TIMES do table.remove(route.times, 1) end
    route.time, route.lastTime = ns.UsualTime(route.times), seconds
    route.flown, route.last = (route.flown or 0) + 1, time()
    ns.db.routes[key] = route
    if not ns.db.chat then
        -- Quiet: no line in chat.
    elseif before then
        local note = ("usually %s"):format(ns.Clock(route.time))
        if seconds > route.time + 15 then
            note = note .. "; a slow one, which doesn't change the countdown"
        end
        ns.Print(("Landed at %s: %s (%s)."):format(ns.ShortName(flight.toName), ns.Clock(seconds), note))
    else
        ns.Print(("Flight recorded: %s to %s, %s. Next time FDR counts it down."):format(
            ns.ShortName(flight.fromName), ns.ShortName(flight.toName), ns.Clock(seconds)))
    end
    if ns.RefreshLogbook then ns.RefreshLogbook() end
end

-- Shortly before landing on a route with a recorded time (not an estimate
-- from the other way): a sound and a note on screen, once per flight.
local function MaybeAlert(flight)
    if not ns.db.alert or flight.alerted then return end
    local seconds, estimated = ns.Estimate(flight.from, flight.to)
    if not seconds or estimated then return end
    local left = seconds - (time() - flight.started)
    if left > ALERT_AHEAD or left < 0 then return end
    flight.alerted = true
    if PlaySound then pcall(PlaySound, ALERT_SOUND, "SFX") end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, ("Landing at %s in %d seconds"):format(
            ns.ShortName(flight.toName), math.max(1, math.floor(left + 0.5))), 0.4, 0.76, 1)
    end
end

-- Watches for take off and landing.
function ns.Tick()
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    if ns.flight then
        if not onTaxi then
            Land()
        else
            MaybeAlert(ns.flight)
            if ns.UpdateBar then ns.UpdateBar() end
        end
        return
    end
    if pending then
        if onTaxi then
            ns.flight = pending
            ns.flight.started = time()
            ns.db.current = ns.flight
            pending = nil
            if ns.UpdateBar then ns.UpdateBar() end
        elseif time() - pending.picked > BOARD_WAIT then
            pending = nil
        end
    end
end

-- After a /reload (or logging back in) in the air: carry on with the flight
-- that was saved, if it is still plausibly this one.
local function Resume()
    local saved = ns.db.current
    ns.db.current = nil
    if type(saved) == "table" and saved.started and UnitOnTaxi and UnitOnTaxi("player")
            and time() - saved.started < RESUME_LIMIT then
        ns.flight = saved
        ns.db.current = saved
    end
    if ns.UpdateBar then ns.UpdateBar() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        local newInstall = FlightDataRecorderDB == nil
        FlightDataRecorderDB = FlightDataRecorderDB or {}
        ns.db = FlightDataRecorderDB
        ns.db.routes = ns.db.routes or {}
        for key, value in pairs(DEFAULTS) do
            if ns.db[key] == nil then ns.db[key] = value end
        end
        -- Routes saved before 0.2.0 kept only the latest time.
        for _, route in pairs(ns.db.routes) do
            if type(route.times) ~= "table" and route.time then route.times = { route.time } end
        end
        -- The welcome line is for new players; existing ones know FDR.
        if ns.db.welcomed == nil then ns.db.welcomed = not newInstall end
    elseif event == "PLAYER_LOGIN" then
        if not ns.db.welcomed then
            ns.db.welcomed = true
            ns.Print("Times your flight-master flights and counts the next one down to landing. Type /fdr for the logbook and settings.")
        end
        if TakeTaxiNode then
            hooksecurefunc("TakeTaxiNode", function(slot) pcall(ns.OnTakeTaxiNode, slot) end)
        end
        Resume()
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(0.5, function() pcall(ns.Tick) end)
        end
    end
end)

SLASH_FLIGHTDATARECORDER1 = "/fdr"
SLASH_FLIGHTDATARECORDER2 = "/flightdatarecorder"
SlashCmdList.FLIGHTDATARECORDER = function(message)
    local command = (message or ""):lower():match("^%s*(%S*)")
    if command == "" or command == "log" or command == "logbook" then
        ns.ToggleLogbook()
    elseif command == "bar" then
        ns.db.bar = not ns.db.bar
        ns.Print("Flight bar " .. (ns.db.bar and "on." or "off."))
        ns.UpdateBar()
    elseif command == "panel" then
        ns.db.mapPanel = not ns.db.mapPanel
        ns.Print("Flight times beside the flight map " .. (ns.db.mapPanel and "on." or "off."))
    elseif command == "quiet" then
        ns.db.chat = not ns.db.chat
        ns.Print(ns.db.chat and "A line in chat on landing again." or "No more lines in chat on landing.")
    elseif command == "alert" then
        ns.db.alert = not ns.db.alert
        ns.Print(ns.db.alert and ("A sound and a note on screen %d seconds before landing."):format(ALERT_AHEAD)
            or "No alert before landing.")
    elseif command == "debug" then
        local routes = 0
        for _ in pairs(ns.db.routes) do routes = routes + 1 end
        local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
        ns.Print(("version %s; %d routes recorded; bar %s, map panel %s, chat %s, alert %s."):format(tostring(version), routes,
            ns.db.bar and "on" or "off", ns.db.mapPanel and "on" or "off", ns.db.chat and "on" or "off", ns.db.alert and "on" or "off"))
        local flight = ns.flight
        ns.Print(("in the air: %s; flight map API: %s; on a taxi: %s."):format(
            flight and (tostring(flight.from) .. " to " .. tostring(flight.to)) or "no",
            (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) and "C_TaxiMap" or (NumTaxiNodes and "TaxiNode" or "none"),
            tostring(UnitOnTaxi and UnitOnTaxi("player") or false)))
    elseif command == "reset" then
        ns.db.barPoint = nil
        ns.PlaceBar()
        ns.Print("The flight bar is back at the top of the screen.")
    elseif command == "clear" then
        if ns.clearArmed and time() - ns.clearArmed < 10 then
            ns.db.routes, ns.clearArmed = {}, nil
            ns.Print("Every recorded flight is forgotten.")
            if ns.RefreshLogbook then ns.RefreshLogbook() end
        else
            ns.clearArmed = time()
            ns.Print("Type /fdr clear again within 10 seconds to forget every recorded flight.")
        end
    else
        ns.Print("/fdr - the logbook of recorded flights")
        ns.Print("/fdr bar - the flight bar on or off")
        ns.Print("/fdr panel - flight times beside the flight map on or off")
        ns.Print("/fdr quiet - the line in chat on landing on or off")
        ns.Print("/fdr alert - the alert before landing on or off")
        ns.Print("/fdr reset - put the flight bar back at the top of the screen")
        ns.Print("/fdr clear - forget every recorded flight (one route: its x in the logbook)")
        ns.Print("/fdr debug - version and key facts, for a bug report at " .. ns.ISSUES)
    end
end

-- Forgets one route, so the next flight on it records it afresh.
function ns.ForgetRoute(key)
    local route = ns.db.routes[key]
    if not route then return false end
    ns.db.routes[key] = nil
    ns.Print(("Forgot %s to %s; the next flight there records it again."):format(
        ns.ShortName(route.fromName), ns.ShortName(route.toName)))
    if ns.RefreshLogbook then ns.RefreshLogbook() end
    return true
end

function FlightDataRecorder_OnAddonCompartmentClick()
    ns.ToggleLogbook()
end

-- Key binding (Options > Keybindings > AddOns).
BINDING_HEADER_FDR = "FDR - Flight Data Recorder"
BINDING_NAME_FDR_LOGBOOK = "Open the logbook"
function FlightDataRecorder_ToggleLogbook()
    ns.ToggleLogbook()
end
