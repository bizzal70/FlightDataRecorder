-- FDR's own logic against the fake API in wow_stub.lua.

CLOCK = 100000
time = function() return CLOCK end
TAKEN = {}
TakeTaxiNode = function(slot) TAKEN[#TAKEN + 1] = slot end
Enum.FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 }
BINDINGS = {}
SetOverrideBinding = function(owner, _, key, action) BINDINGS[key] = action end
ClearOverrideBindings = function() BINDINGS = {} end

local ns = LoadAddon(ADDON_DIR, "FlightDataRecorder")
local function check(cond, what) if not cond then error("CHECK FAILED: " .. what, 2) end; io.write("pass  ", what, "\n") end
local function Tick() for _, fn in ipairs(TICKERS) do fn() end end
local function RunAfters() local list = AFTERS; AFTERS = {}; for _, fn in ipairs(list) do fn() end end
local function Printed() return PRINTED[#PRINTED] or "" end

Fire("ADDON_LOADED", "FlightDataRecorder")
check(FlightDataRecorderDB and ns.db.bar and ns.db.mapPanel and next(ns.db.routes) == nil, "settings start with their defaults")
Fire("PLAYER_LOGIN")
check(#TICKERS == 1, "a ticker watches for take off and landing")

check(ns.Clock(65) == "1:05" and ns.Clock(760) == "12:40" and ns.Clock(3723) == "1:02:03", "times are written as a clock")
check(ns.ShortName("Sentinel Hill, Westfall") == "Sentinel Hill" and ns.ShortName("Ironforge") == "Ironforge", "names lose the zone after the comma")

-- At Sentinel Hill, flying to Stormwind.
TAXI_NODES = {
    { nodeID = 2, name = "Stormwind, Elwynn", slotIndex = 1, state = 1 },
    { nodeID = 10, name = "Sentinel Hill, Westfall", slotIndex = 2, state = 0 },
    { nodeID = 6, name = "Ironforge, Dun Morogh", slotIndex = 3, state = 1 },
}
Fire("TAXIMAP_OPENED")
RunAfters()
check(FlightDataRecorderPanel:IsShown() and FlightDataRecorderPanel.title:GetText() == "Flight times from Sentinel Hill"
    and FlightDataRecorderPanel.lines[1].name:GetText():find("None recorded yet", 1, true) ~= nil,
    "at a flight master with nothing recorded, the panel says so")

TakeTaxiNode(1)
check(TAKEN[1] == 1, "the game's TakeTaxiNode still runs")
Tick()
check(not FlightDataRecorderBar:IsShown(), "nothing shows before take off")
Fire("TAXIMAP_CLOSED")
check(not FlightDataRecorderPanel:IsShown(), "the panel closes with the flight map")
ON_TAXI = true
CLOCK = CLOCK + 1
Tick()
check(ns.flight and ns.flight.to == 2 and FlightDataRecorderBar:IsShown(), "taking off starts the flight and shows the bar")
CLOCK = CLOCK + 42
Tick()
check(FlightDataRecorderBar.where:GetText():find("To Stormwind", 1, true) and FlightDataRecorderBar.where:GetText():find("REC", 1, true)
    and FlightDataRecorderBar.clock:GetText() == "0:42", "a new route is recorded, counting up: " .. FlightDataRecorderBar.clock:GetText())
check(ns.db.current and ns.db.current.to == 2, "the flight in the air is saved, in case of a /reload")
CLOCK = CLOCK + 92
ON_TAXI = false
Tick()
local route = ns.Route(10, 2)
check(route and route.time == 134 and route.flown == 1 and route.toName == "Stormwind, Elwynn", "landing records the route: 2:14")
check(not FlightDataRecorderBar:IsShown() and ns.db.current == nil and Printed():find("Flight recorded: Sentinel Hill to Stormwind, 2:14", 1, true),
    "the bar goes and chat says what was recorded: " .. Printed())

-- The same route again counts down.
Fire("TAXIMAP_OPENED")
RunAfters()
check(FlightDataRecorderPanel.lines[1].name:GetText() == "Stormwind" and FlightDataRecorderPanel.lines[1].time:GetText() == "2:14",
    "the panel shows the recorded time from here")
GameTooltip.__shown = true
GameTooltipTextLeft1.__text = "Stormwind, Elwynn"
local lines = {}
GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
check(ns.AddTooltipTime(GameTooltip) and lines[1] == "Flight time: 2:14", "hovering the destination shows its flight time")
GameTooltip.AddLine = nil
TakeTaxiNode(1)
Fire("TAXIMAP_CLOSED")
ON_TAXI = true
Tick()
CLOCK = CLOCK + 34
Tick()
check(FlightDataRecorderBar.clock:GetText() == "1:40" and not FlightDataRecorderBar.where:GetText():find("REC", 1, true),
    "a known route counts down to landing: " .. FlightDataRecorderBar.clock:GetText())

-- A /reload in the air carries on.
local saved = ns.db.current
ns.flight = nil
FlightDataRecorderDB = { routes = ns.db.routes, current = saved, bar = true, mapPanel = true }
-- The old copy stops listening, as a /reload throws it away.
for _, f in ipairs(Frames()) do f.__events = {} end
local ns2 = LoadAddon(ADDON_DIR, "FlightDataRecorder")
TICKERS = {}
Fire("ADDON_LOADED", "FlightDataRecorder")
Fire("PLAYER_LOGIN")
check(ns2.flight and ns2.flight.to == 2 and ns2.flight.started == saved.started, "after a /reload in the air the flight carries on")
CLOCK = CLOCK + 101
ON_TAXI = false
for _, fn in ipairs(TICKERS) do fn() end
check(ns2.Route(10, 2).flown == 2 and ns2.Route(10, 2).time == 135 and PRINTED[#PRINTED]:find("last time 2:14", 1, true),
    "and is recorded on landing, compared with last time: " .. PRINTED[#PRINTED])
ns = ns2

-- Picking a destination but not flying is forgotten; so is a cancelled take off.
Fire("TAXIMAP_OPENED")
TakeTaxiNode(3)
CLOCK = CLOCK + 30
Tick()
ON_TAXI = true
Tick()
check(ns.flight == nil, "a destination picked without taking off is forgotten")
ON_TAXI = false
Tick()
TakeTaxiNode(3)
ON_TAXI = true
Tick()
CLOCK = CLOCK + 2
ON_TAXI = false
Tick()
check(ns.Route(10, 6) == nil, "a take off cancelled straight away is not recorded")

-- The logbook.
SlashCmdList.FLIGHTDATARECORDER("")
FlightDataRecorderLogbook.__scripts.OnShow(FlightDataRecorderLogbook)
local entries = ns.LogbookEntries()
check(FlightDataRecorderLogbook:IsShown() and entries[1].heading == "Sentinel Hill, Westfall" and entries[2].route.to == 2,
    "/fdr opens the logbook, routes under where they start")
check(BINDINGS.PAD2 and BINDINGS.PADDUP and BINDINGS.PADDDOWN, "while it is open the controller's B closes it and the D-pad scrolls")
IN_COMBAT = false
Fire("PLAYER_REGEN_DISABLED")
check(next(BINDINGS) == nil, "a fight hands the controller's buttons back at once")
Fire("PLAYER_REGEN_ENABLED")
check(BINDINGS.PAD2 ~= nil, "and they are borrowed again afterwards")
FlightDataRecorderLogbook:Hide()
FlightDataRecorderLogbook.__scripts.OnHide(FlightDataRecorderLogbook)
check(next(BINDINGS) == nil, "closing it hands them back")

-- Settings.
SlashCmdList.FLIGHTDATARECORDER("bar")
check(ns.db.bar == false, "/fdr bar turns the bar off")
SlashCmdList.FLIGHTDATARECORDER("bar")
SlashCmdList.FLIGHTDATARECORDER("clear")
check(next(ns.db.routes) ~= nil, "/fdr clear asks to be typed twice")
SlashCmdList.FLIGHTDATARECORDER("clear")
check(next(ns.db.routes) == nil, "and then forgets every flight")
