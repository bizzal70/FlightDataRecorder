# FDR - Flight Data Recorder

Times flight-master flights and remembers each route. One addon, one repository: `bizzal70/FlightDataRecorder` (folder and TOC `FlightDataRecorder`, title "FDR - Flight Data Recorder", `/fdr`). Built 2026-11-23 at the user's request; the user picked the name after "Flight Clock" turned out to be taken on CurseForge (other Forever flight timers there: Flight Clock, InFlight Taxi Timer, TaxiTimer, FlashTaxiTimer).

## Workflow

- **No local `.git`.** GitHub holds all history; work in a throwaway clone.
- `python tests/run.py` runs `tests/test_fdr.lua` in real Lua 5.1 (`lupa`) against `tests/wow_stub.lua` (copied from MouseTip). It proves the addon's own logic only.
- A tag starting with `v` runs `.github/workflows/release.yml` (BigWigs packager). CurseForge upload needs `## X-Curse-Project-ID` in the TOC and the `CF_API_KEY` secret.

## How it works

- `Core.lua`: `hooksecurefunc("TakeTaxiNode")` notes the picked destination (`ns.ReadTaxiMap()`: `C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID())`, node with `state == Enum.FlightPathState.Current` is "here", others by `slotIndex`; falls back to `NumTaxiNodes`/`TaxiNodeName`/`TaxiNodeGetType` with names as IDs). A 0.5 s ticker (`ns.Tick`) starts the flight when `UnitOnTaxi("player")` turns true (within 20 s of picking) and lands it when it turns false; flights under 5 s are not recorded. Routes in `FlightDataRecorderDB.routes["from>to"]` = { from, to, fromName, toName, time (latest, seconds), flown, last }. The flight in the air is saved in `db.current` and resumed on login if still on a taxi (under 2 h). All times use `time()`.
- `Bar.lua`: the flight bar (`FlightDataRecorderBar`, draggable, `db.barPoint`): countdown on a known route, REC and counting up on a new one. `FlightDataRecorderPanel` beside `FlightMapFrame`/`TaxiFrame` on TAXIMAP_OPENED (0.1 s later), hidden on TAXIMAP_CLOSED; GameTooltip OnShow hook adds "Flight time" when its first line matches a destination from here.
- `Logbook.lua`: `/fdr` window, routes grouped by origin; wheel, arrows, D-pad. `PadClose.lua` borrows PAD2 (close) plus PADDUP/PADDDOWN while shown, handed back on PLAYER_REGEN_DISABLED.
- Taxi API use is the same as GatherLog's (seen working in game: node IDs and names like "Sentinel Hill, Westfall"). Not yet seen in game: the TakeTaxiNode hook, UnitOnTaxi timing, the panel's anchor and the tooltip line.
