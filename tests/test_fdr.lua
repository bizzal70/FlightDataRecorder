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
    and FlightDataRecorderPanel.lines[1].name:GetText():find("None from here yet", 1, true) ~= nil,
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

-- From Stormwind, the way back is estimated from the way there.
TAXI_NODES[1].state, TAXI_NODES[2].state = 0, 1
Fire("TAXIMAP_OPENED")
RunAfters()
check(FlightDataRecorderPanel.lines[1].name:GetText() == "Sentinel Hill" and FlightDataRecorderPanel.lines[1].time:GetText() == "~2:14"
    and FlightDataRecorderPanel.note:IsShown(), "a route flown only the other way shows that time as an estimate (~)")
TakeTaxiNode(2)
Fire("TAXIMAP_CLOSED")
ON_TAXI = true
Tick()
CLOCK = CLOCK + 14
Tick()
check(FlightDataRecorderBar.clock:GetText() == "~2:00" and FlightDataRecorderBar.where:GetText():find("REC", 1, true),
    "and counts down from it, marked ~, while this way is recorded: " .. FlightDataRecorderBar.clock:GetText())
CLOCK = CLOCK + 116
ON_TAXI = false
Tick()
check(ns.Route(2, 10) and ns.Route(2, 10).time == 130 and ns.Estimate(2, 10) == 130, "landing records this way's own time")
ns.db.routes["2>10"] = nil
TAXI_NODES[1].state, TAXI_NODES[2].state = 1, 0

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
check(ns2.Route(10, 2).flown == 2 and ns2.Route(10, 2).time == 134 and ns2.Route(10, 2).lastTime == 135
    and PRINTED[#PRINTED]:find("2:15 (usually 2:14)", 1, true),
    "and is recorded on landing; the usual time is the quicker middle of the last flights: " .. PRINTED[#PRINTED])
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

-- 0.2.0: the usual time, one slow flight, the alert, forgetting one route,
-- quiet, settings in the logbook, binding, debug.
check(ns.UsualTime({ 134 }) == 134 and ns.UsualTime({ 134, 300 }) == 134 and ns.UsualTime({ 140, 134, 300 }) == 140,
    "the usual time is the middle of the recent flights, the quicker one of two")
local function Fly(fromSlot, toSlot, seconds)
    for _, node in ipairs(TAXI_NODES) do node.state = node.slotIndex == fromSlot and 0 or 1 end
    TakeTaxiNode(toSlot)
    ON_TAXI = true
    Tick()
    CLOCK = CLOCK + seconds
    ON_TAXI = false
    Tick()
end
Fly(2, 1, 134)
Fly(2, 1, 400)
check(ns.Route(10, 2).time == 134 and PRINTED[#PRINTED]:find("a slow one", 1, true),
    "one slow flight (lag, a loading screen) doesn't replace a good time: " .. PRINTED[#PRINTED])
for _ = 1, 6 do Fly(2, 1, 150) end
check(#ns.Route(10, 2).times == 5 and ns.Route(10, 2).time == 150, "only the last 5 flights count, so a changed route catches up")

-- The alert, 10 seconds before landing on a known route.
local sounds, said = SOUNDS, nil
UIErrorsFrame = { AddMessage = function(_, text) said = text end }
for _, node in ipairs(TAXI_NODES) do node.state = node.slotIndex == 2 and 0 or 1 end
TakeTaxiNode(1)
ON_TAXI = true
Tick()
CLOCK = CLOCK + 130
Tick()
check(SOUNDS == sounds and said == nil, "no alert while there's longer to go")
CLOCK = CLOCK + 10
Tick()
check(SOUNDS == sounds + 1 and said == "Landing at Stormwind in 10 seconds", "a sound and a note 10 seconds before landing: " .. tostring(said))
CLOCK = CLOCK + 3
Tick()
check(SOUNDS == sounds + 1, "only once")
ON_TAXI = false
CLOCK = CLOCK + 7
Tick()

-- Quiet.
local printedBefore = #PRINTED
SlashCmdList.FLIGHTDATARECORDER("quiet")
check(ns.db.chat == false, "/fdr quiet turns the landing line off")
printedBefore = #PRINTED
Fly(2, 1, 150)
check(#PRINTED == printedBefore, "and then landing says nothing in chat")
SlashCmdList.FLIGHTDATARECORDER("quiet")

-- An old route saved before 0.2.0 keeps its time.
ns.db.routes["99>98"] = { from = 99, to = 98, fromName = "Old", toName = "Older", time = 77, flown = 3 }
Fire("ADDON_LOADED", "FlightDataRecorder")
check(ns.db.routes["99>98"].times and ns.db.routes["99>98"].times[1] == 77, "routes saved by 0.1 keep their time")

-- The logbook: settings ticks, forgetting one route, its spot.
if not FlightDataRecorderLogbook:IsShown() then SlashCmdList.FLIGHTDATARECORDER("") end
FlightDataRecorderLogbook.__scripts.OnShow(FlightDataRecorderLogbook)
local ticks = ns.LogbookTicks()
check(#ticks == 4, "the logbook has the four settings")
for _, t in ipairs(ticks) do
    if t.key == "alert" then t.__scripts.OnClick(t) end
end
check(ns.db.alert == false, "ticking one in the logbook changes it")
ns.db.alert = true
check(not ns.PressForget("99>98") and ns.db.routes["99>98"], "the x on a route asks first")
check(ns.PressForget("99>98") and ns.db.routes["99>98"] == nil and PRINTED[#PRINTED]:find("Forgot Old to Older", 1, true),
    "and forgets it on the second press")
ns.db.routes["99>98"] = { from = 99, to = 98, fromName = "Old", toName = "Older", time = 77, times = { 77 } }
ns.PressForget("99>98")
CLOCK = CLOCK + 10
RunAfters()
check(not ns.PressForget("99>98") and ns.db.routes["99>98"], "a second press long after the first asks again")

-- The flight map panel goes left of a map near the screen's right edge.
UIParent.GetRight = function() return 1000 end
check(ns.PanelSide({ GetRight = function() return 600 end }) == "right", "the panel sits right of the flight map when there's room")
check(ns.PanelSide({ GetRight = function() return 900 end }) == "left", "and left of it when there isn't")
UIParent.GetRight = nil

check(BINDING_NAME_FDR_LOGBOOK and type(FlightDataRecorder_ToggleLogbook) == "function", "a key binding opens the logbook")
printedBefore = #PRINTED
SlashCmdList.FLIGHTDATARECORDER("debug")
check(PRINTED[printedBefore + 1]:find("version", 1, true), "/fdr debug starts with the version")

