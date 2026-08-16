# CursedSurges

**Work in progress — not yet released.**

A small tracker for **Cursed Surge** events on the Coiled Isle (Midnight, patch 12.1):

- Countdown to the next surge, read from the game's own event data
- One click to set a **TomTom waypoint** (if installed) or drop a **map pin** at the surge location
- One click to **announce the incoming surge in zone chat**

## Development

`tools/SurgeProbe` is a local-only API probe (never packaged) used to discover
which API backs the world map's Events tab in 12.1. Slash command: `/csp`.
