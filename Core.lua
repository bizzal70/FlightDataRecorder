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

local DEFAULTS = { bar = true, mapPanel = true }
local BOARD_WAIT = 20       -- seconds to wait for take off after picking a destination
local MIN_FLIGHT = 5        -- shorter "flights" (a cancelled take off) are not recorded
local RESUME_LIMIT = 2 * 3600

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
    route.time, route.flown, route.last = seconds, (route.flown or 0) + 1, time()
    ns.db.routes[key] = route
    if before then
        ns.Print(("Landed at %s: %s (last time %s)."):format(ns.ShortName(flight.toName), ns.Clock(seconds), ns.Clock(before)))
    else
        ns.Print(("Flight recorded: %s to %s, %s. Next time FDR counts it down."):format(
            ns.ShortName(flight.fromName), ns.ShortName(flight.toName), ns.Clock(seconds)))
    end
    if ns.RefreshLogbook then ns.RefreshLogbook() end
end

-- Watches for take off and landing.
function ns.Tick()
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    if ns.flight then
        if not onTaxi then Land() elseif ns.UpdateBar then ns.UpdateBar() end
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
        FlightDataRecorderDB = FlightDataRecorderDB or {}
        ns.db = FlightDataRecorderDB
        ns.db.routes = ns.db.routes or {}
        for key, value in pairs(DEFAULTS) do
            if ns.db[key] == nil then ns.db[key] = value end
        end
    elseif event == "PLAYER_LOGIN" then
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
        ns.Print("/fdr reset - put the flight bar back at the top of the screen")
        ns.Print("/fdr clear - forget every recorded flight")
    end
end

function FlightDataRecorder_OnAddonCompartmentClick()
    ns.ToggleLogbook()
end
