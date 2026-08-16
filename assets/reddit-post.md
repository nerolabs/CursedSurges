# r/WoWAddons release post draft (post once CurseForge approves)

**Title:** [Release] CursedSurges — countdown, waypoint & zone announce for Cursed Surge events on the Coiled Isle (12.1)

**Body:**

AI Disclaimer: This addon was developed with AI assistance (Claude), with all functionality tested in-game before release.

If you're chasing the Cursed Surge events on the Coiled Isle, this is a small quality-of-life tracker so you never miss one:

- **Countdown to the next surge** read from the game's own event schedule (the world map's Events tab data), plus an **Active** timer while one is running. It treats a surge as over ~5 minutes after it starts — if you weren't there at the start, it's done.
- **Next surge preview** by name while one is active.
- **Waypoint button** — drops a map pin (and a TomTom waypoint if you have TomTom) at the surge's fixed location. Works for upcoming surges too.
- **Announce button** — posts the surge, coords, and a clickable map pin link to zone chat. (This came from zone-chat feedback during testing — people kept asking for the pin.)

The panel auto-appears when the scheduler has Coiled Isle events and hides otherwise. `/surge` to toggle; the window is draggable/lockable.

All five surges and their locations are built in, and the addon self-corrects from live event data, so nothing needs manual updates.

**Downloads:**
- CurseForge: https://www.curseforge.com/wow/addons/cursedsurges
- Wago: https://addons.wago.io/addons/cursedsurges
- Source (MIT): https://github.com/nerolabs/CursedSurges

Feedback very welcome — especially if a surge name or location ever looks wrong on your realm.
