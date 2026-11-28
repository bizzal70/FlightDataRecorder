# FDR - Flight Data Recorder

## 0.2.0

- **One slow flight no longer spoils a route's time.** Each route keeps its last 5 flights, and the countdown uses the middle one, so a flight slowed by lag or a loading screen doesn't replace a good time, and a route the game has changed catches up after a few flights. Landing says the usual time, and says so when a flight was a slow one.
- **An alert 10 seconds before landing:** a sound and a note at the top of the screen, on routes with a recorded time. Untick it in the logbook if you don't want it.
- **Forget one route** from the logbook: press its **x** twice, and the next flight there records it afresh.
- **Settings in the logbook, no typing needed:** the flight bar, the times beside the flight map, the line in chat on landing (now one tick, or `/fdr quiet`) and the alert.
- The flight map's panel stays on screen: it moves to the left of the map when there's no room on the right.
- The logbook remembers where you drag it.
- FDR is listed in Esc > Options > AddOns, and has a key binding to open the logbook (Options > Keybindings > AddOns).
- `/fdr debug` prints the version and key facts to paste into a bug report; a one-time welcome line for new installs.

## 0.1.1

- **The way back is estimated from the way there:** a route flown only in the other direction so far shows that time, marked **~**, beside the flight map and in its tooltip, and the bar counts down from it (still marked REC while this direction is recorded).
- The flight map panel's "nothing recorded" line is shorter, so it is no longer cut off.

## 0.1.0

- First release: times every flight-master flight from take off to landing and remembers each route; a bar counts the next flight on that route down to landing (or records a new route, marked REC); flight times beside the flight map and in its tooltips; the `/fdr` logbook, which the controller's D-pad scrolls and B closes; carries on after a /reload in the air.
