# Ferrum Frontier roadmap

**Where it is now (v0.3):** the core factory loop works end to end: nodes → miners → belts → smelting → parts → milestones → Space Elevator. On top of that:

- power grids
- overclocking
- alternate recipes
- wildlife
- seeded worlds with tunable settings
- host-by-IP multiplayer that stays in sync

Each phase below ends in a build you can hand to testers. Phases are ordered so that each one makes the next one more fun to test. Every item in a phase is shippable on its own, so you can stop mid-phase and still have a better game.

---

## Phase 0 · Playtest v0.3 (now)

Goal: find what breaks and what feels bad before building more.

- Play a full session with a friend on the LAN. Try to reach Milestone 3.
- Things to note: lag or rubber-banding, buildings that fail to place, confusing UI, anything that desyncs ("Resynced" count in the player list), crashes.
- Keep a short list of "this annoyed me" moments. Those drive Phase 1.

## Phase 1 · Feel and quality of life (v0.4) ✅ done

- ✅ **Loading screen** with progress steps for new worlds, hosting, joining ("Downloading world from host") and loading saves.
- ✅ **Sound and music.** Placement, removal, pickups, zapper, hits, milestone fanfare, chat and ping sounds, a factory hum near working machines, and an ambient music loop.
- ✅ **Settings menu.** Player name, master/music/effects volume, fullscreen, VSync, interface size, hints on/off.
- ✅ **Save slots.** Named worlds, a load screen, three rotating autosaves per world, and play or host any save.
- ✅ **Multiplayer feel.** Placement ghosts for clients, chat (Enter), map pings (G or middle click), and players' names everywhere.
- ✅ **Building tools.** Underground belts (5-tile range, unlocked at Milestone 2), copy/paste of machine settings (Shift + right/left click), and dragging to lay poles 6 tiles apart.
- ✅ **First-time hints.** A six-step "Getting started" panel that follows what you've actually built.
- ✅ **Error log.** `ferrum.log` in the saves folder, with a button in Settings to open it.
- ⏳ **Still open:** rebindable keys. Carried into v0.5.

## Phase 2 · Logistics depth (v0.5)

This is where factory games get their puzzle depth.

- **Production stats screen.** Items per minute made and consumed, with graphs. The single most useful screen in Factorio and Satisfactory.
- **Fluids.** Water extractors, pipes and pumps. Coal generators start needing water.
- **Oil chain.** Oil nodes → refinery → plastic, rubber and fuel. Fuel generators as a second power tier.
- **Smart splitters.** Filter by item, overflow routing.
- **Storage tiers and batteries** for power storage.
- **Map overlays.** Toggle views for power coverage and belt contents.

## Phase 3 · A bigger world (v0.6)

Give players a reason to explore and expand.

- **Larger maps.** Chunked loading so maps can be 512×512 tiles or more.
- **Biomes with their own ores.** Caterium, quartz, sulfur and bauxite, found away from the start.
- **Fog of war and a resource scanner.** You discover nodes instead of seeing them all.
- **Day/night cycle with lighting.** Lamps become a building.
- **Dangerous zones.** Tougher wildlife guarding the richest nodes. Crash-pod "research sites" with better rewards.
- **Vehicles.** A truck with recorded routes for hauling between outposts.

## Phase 4 · Mid and late game (v0.7–0.8)

Enough content for a long playthrough.

- **Tiers 5–8.** Computers, motors, heavy modular frames, aluminium, and nuclear power at the very end.
- **Trains.** Rails, stations and signals, Factorio style.
- **Drones** for long-distance light freight.
- **Research tree UI.** The HUB research tab grows into a Satisfactory-style MAM tree.
- **Space Elevator.** Expanded to five phases with a proper endgame project and a launch sequence.

## Phase 5 · Always-on multiplayer (v0.9)

The simulation already runs headless, so this fits your Linux box well.

- **Dedicated server mode.** `FerrumFrontier.x86_64 --server` hosts a persistent world 24/7 with no window. Friends join whenever; the world keeps running.
- **Server admin.** Password, whitelist, kick, save on a timer, simple console commands.
- **Player identity.** Choose a suit colour. Optional per-player permissions (who can deconstruct what).
- **Steam invites** (GodotSteam), for when it goes beyond the LAN.

## Phase 6 · Release polish (v1.0)

- **Art pass.** Animated sprites, higher resolution, more varied terrain and flora.
- **Tutorial campaign.** A guided first map.
- **Achievements.**
- **Modding.** Move items, recipes and buildings into JSON files players can edit.
- **Localisation.**
- **Distribution.** Store page (itch.io first, then Steam) and code signing, so Windows stops warning.

---

### Rules that hold across every phase

- **Keep the simulation deterministic.** New content goes through `Sim` with integers and commands (see `docs/MULTIPLAYER.md`).
- **Bump `Data.VERSION` for every build you hand out.** The game refuses mismatched versions.
- **Run `--selftest` and the two-instance `--nettest` before each release.**
