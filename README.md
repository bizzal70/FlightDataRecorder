# FDR - Flight Data Recorder

FDR times every flight-master flight in World of Warcraft: Forever, from take off to landing, and remembers each route. The next time you fly that route, a bar counts down to landing.

## What it does

- **Records every flight.** Pick a destination at a flight master and FDR notes the route; it times the flight from take off to landing. Each route keeps its last 5 flights and counts down from the middle one, so one flight slowed by lag or a loading screen doesn't spoil it. Routes are shared by all your characters.
- **Counts down to landing.** On a route it has timed before, a bar at the top of the screen shows where you are going and how long is left, and 10 seconds before landing a sound and a note at the top of the screen tell you to get ready. On a new route the bar says **REC** and counts up while it records.
- **Times at the flight master.** Beside the flight map, a panel lists the recorded times from where you are standing, quickest first; hovering a destination adds its time to the tooltip. A route flown so far only the other way shows that time as an estimate, marked **~** (flights take about as long either way), and the bar counts down from it while it records.
- **The logbook.** Type `/fdr` (or set a key in Options > Keybindings > AddOns) for every recorded route, grouped by where it starts, with its time and how often you have flown it. Press a route's **x** twice to forget it, so the next flight records it afresh. The settings are at the bottom: the flight bar, the times beside the flight map, the line in chat on landing, and the alert. FDR is also in Esc > Options > AddOns.
- **Survives a /reload in the air:** the flight in progress is saved and carries on.

## Commands

| Command | What it does |
| --- | --- |
| `/fdr` | The logbook (also from the addon list on the minimap) |
| `/fdr bar` | The flight bar on or off |
| `/fdr panel` | The flight times beside the flight map on or off |
| `/fdr quiet` | The line in chat on landing on or off |
| `/fdr alert` | The alert 10 seconds before landing on or off |
| `/fdr reset` | Put the flight bar back at the top of the screen (drag it to move it) |
| `/fdr clear` | Forget every recorded flight (type it twice) |
| `/fdr debug` | Version and key facts, to paste into a [bug report](https://github.com/bizzal70/FlightDataRecorder/issues) |

## Controller

While the logbook is open, the D-pad scrolls it and **B** closes it, like Escape. As soon as a fight starts, or once it is closed, those buttons go back to whatever you have them set to. The logbook shrinks itself to fit small screens such as the Legion Go, ROG Ally and Steam Deck, and remembers where you drag it.

## Good to know

- A time is recorded only for a flight that took off and landed while FDR was running; one picked but never boarded, or cancelled straight away, is ignored.
- A route is the same flight from the same place, so A to B and B to A are timed separately.
- **Nothing is sent anywhere.** Times are saved on your own computer with the game's other saved settings.

## More from this author

Other small addons for World of Warcraft: Forever, all free:

- **[MouseTip](https://www.curseforge.com/wow/addons/mousetip)** shows tooltips at the mouse cursor instead of the corner of the screen.
- **[GatherLog](https://www.curseforge.com/wow/addons/gatherlog)** remembers ore, herbs, fishing pools, skinning spots, chests and rares across all your characters, and guides you back to the best spots.
- **[RangeShade](https://www.curseforge.com/wow/addons/rangeshade)** shades action buttons red when your target is out of range.
- **[JunkMate](https://www.curseforge.com/wow/addons/junkmate)** sells junk and repairs at vendors, makes room for loot when your bags are full, and tidies your bank.
- **[AltGlance](https://www.curseforge.com/wow/addons/altglance)** shows all your characters at a glance: level, gold, rested and where you left them.
- **[SwiftQuest](https://www.curseforge.com/wow/addons/swiftquest)** accepts quests and hands them in as soon as you talk to the quest giver, without ever choosing a reward for you.
- **[SessionRecap](https://www.curseforge.com/wow/addons/sessionrecap)** keeps a running tally of your play session: gold, experience per hour, quests, gathering and loot.
- **[MacroKit](https://www.curseforge.com/wow/addons/macrokit)** adds ready-made macros for your class and spec, for all nine classes, and never overwrites your own.
- **[ZoomPad](https://www.curseforge.com/wow/addons/zoompad)** puts big + and - buttons on screen that zoom the camera, made for the Steam Deck touchscreen.
- **[GamepadMacros](https://www.curseforge.com/wow/addons/gamepadmacros)** adds ready-made macros for controller and Steam Deck players: heal yourself, use a quest item, save and wear gear, leave a group, emotes.

## Installing

Copy this folder into `World of Warcraft\_forever_\Interface\AddOns\` as `FlightDataRecorder`, restart the game, and enable FDR on the character select screen.

## Developing

- `tools\Link-Addon.ps1` links this folder into the game's AddOns folder, so edits are live after `/reload`.
- `python tests/run.py` runs the tests (`pip install lupa` once). They run the addon in real Lua 5.1 against a fake of the game's API.
- `tools\Publish.ps1 -Message "..."` runs the tests and pushes to GitHub. GitHub runs the tests again on every push.

## Releasing

`tools\Publish.ps1 -Message "Release x.y.z" -Tag vx.y.z` publishes and tags. The tag makes GitHub package the addon and attach the zip to a GitHub release.

To also upload to CurseForge and Wago, two things are needed once:

1. Create the project on each site, then add its ID to `FlightDataRecorder.toc`:
   `## X-Curse-Project-ID: 123456` and `## X-Wago-ID: abc123`.
2. Create an upload token on each site and add it to this repository's secrets (Settings, Secrets and variables, Actions) as `CF_API_KEY` and `WAGO_API_TOKEN`.

Before each release: raise `## Version:` in `FlightDataRecorder.toc` and add the version to `CHANGELOG.md`.

## Licence

MIT. See `LICENSE`.
