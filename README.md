# CursedSurges

A small tracker for **Cursed Surge** events on the Coiled Isle (Midnight, patch 12.1). It reads the game's own event schedule and shows a compact always-current panel:

- **Countdown** to the next surge, and an **Active** timer while one is running — using the community rule that a surge is effectively over ~5 minutes after it starts
- **Next surge preview** with its real name while one is active
- **Waypoint** button: drops a map pin (and a TomTom waypoint if TomTom is installed) at the surge's location — works for upcoming surges too, since every surge has a fixed spot
- **Announce** button: posts the surge, its coordinates, and a **clickable map pin link** — to zone chat, or to your party/raid/instance chat if you'd rather not spam the zone (right-click the panel to choose)
- **Audio alert**: the ready-check sound the moment a surge goes live (on by default; toggle in the settings menu)
- **Zone-only mode** (off by default): hide the panel and silence the alert while you're away from the Coiled Isle — entering the zone mid-surge still alerts

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
| `/surge zoneonly on\|off` | hide + silence the addon outside the Coiled Isle |
| `/surge announce zone\|group` | announce to zone chat or party/raid/instance chat |
| `/surge debug` | copyable diagnostic dump |

Right-clicking the panel opens the same settings as a menu.

## Localization

UI, alerts, and announces are localized for **deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW** (machine-assisted — corrections welcome via PR/issue). Surge names and the zone name come from the game client itself, so they're always in your language once each surge has been seen. The zone General channel is found locale-independently.

## Installation

Install from CurseForge or Wago, or drop the `CursedSurges` folder into `Interface/AddOns`.

## Development

`tools/SurgeProbe` is a local-only API probe (never packaged) used while reverse-engineering the 12.1 event scheduler. Slash command: `/csp`.
