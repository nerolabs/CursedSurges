# CursedSurges

A small tracker for **Cursed Surge** events on the Coiled Isle (Midnight, patch 12.1). It reads the game's own event schedule and shows a compact always-current panel:

- **Countdown** to the next surge, and an **Active** timer while one is running — using the community rule that a surge is effectively over ~5 minutes after it starts
- **Next surge preview** with its real name while one is active
- **Waypoint** button: drops a map pin (and a TomTom waypoint if TomTom is installed) at the surge's location — works for upcoming surges too, since every surge has a fixed spot
- **Announce** button: posts the surge, its coordinates, and a **clickable map pin link** — to zone chat, or to your party/raid/instance chat if you'd rather not spam the zone (right-click the panel to choose)
- **Audio alert**: the ready-check sound the moment a surge goes live (on by default; toggle in the right-click menu)

## How it works

The world map's Events tab is backed by `C_EventScheduler`; CursedSurges requests the same schedule (epoch start/end times per event) and tracks the five-surge rotation on the Coiled Isle. Names and locations are built in and additionally self-correct from live event data, so nothing needs manual updates when your client sees a surge run.

## Commands

| Command | Effect |
| --- | --- |
| `/surge` (or `/cursedsurges`) | toggle the panel |
| `/surge lock` / `/surge unlock` | lock/unlock the panel position |
| `/surge reset` | reset position |
| `/surge refresh` | re-request schedule data |
| `/surge sound on\|off` | toggle the surge-start audio alert |
| `/surge announce zone\|group` | announce to zone chat or party/raid/instance chat |
| `/surge debug` | copyable diagnostic dump |

Right-clicking the panel opens the same settings as a menu.

## Installation

Install from CurseForge or Wago, or drop the `CursedSurges` folder into `Interface/AddOns`.

## Development

`tools/SurgeProbe` is a local-only API probe (never packaged) used while reverse-engineering the 12.1 event scheduler. Slash command: `/csp`.
