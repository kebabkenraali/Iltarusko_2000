# Architecture - Twilight: 2000 Remake

## Overview

The remake replaces the original 1991 game's executable with a Godot 4.7 GDScript
implementation. Original graphics, audio, and text data are used unchanged; only the
game logic is re-implemented.

## Repositories

- `remake/` - documentation and tools (this repo)
- `remake/godot/` - Godot project: all GDScript code, scenes, and the original game data
  under `original/` (separate repo, gitignored here)

## Core modules (godot/scripts/)

| Module | Responsibility |
|--------|---------------|
| `main.gd` | Game flow: chargen → office → radio → world map → town/encounter → battle |
| `battle.gd` | Pure combat logic: AP turns, initiative, fog of war, reactions, morale, JA planning |
| `battle_view.gd` | Combat view: isometric rendering, walkers, planning UI, close-up portraits |
| `campaign.gd` | Mission logic: 12 mission types, rewards, funds, food, sick timers |
| `economy.gd` | HQ resupply: derived prices, carry caps, rations |
| `computer.gd` | HQ computer screen: funds, stores, motor pool, six bar graphs |
| `tactical.gd` | Field view: towns, people, buildings, missions, TAKE/USE/SLEEP/MAP/LOOK |
| `worldmap.gd` | World map: travel, encounters, rest, fuel, vehicle |
| `chargen.gd` / `chargen_rules.gd` | Recruit generation: careers, faces from FACES sheets |
| `forces.gd` | Battle setup: squad and enemy deployment, vehicles |
| `healing.gd` | Rest and recovery: wounds, bleeding, medics |
| `soldier.gd` | Soldier art: body/head strips, directions, poses |
| `portraits.gd` | Talk portraits: recruits, Exor, civilians |
| `office.gd` | HQ office screen: radio, computer, filing cabinet, wall map |
| `game_data.gd` | Loading all data JSON files |
| `vehicle.gd` | Vehicle data: prices, fuel, components |

## Data files (godot/data/)

| File | Contents |
|------|----------|
| `items.json` | 96 items: weapons, ammo, medkits, grenades, rations |
| `missions.json` | 12 mission types, story, rewards, item lists |
| `careers.json` | Recruit careers and skill tables |
| `chargen.json` | Chargen configuration |
| `portraits.json` | Talk portrait definitions |

## Original data (godot/original/graphics/)

`ANIMS/`, `FACES/`, `CMBT/`, `BUILDING/`, `ART/`, `ICON/`, `INTRO/`, `OFFICE/`, `WORLD/`

## Save format

`user://autosave.sav` (and named saves) stores a Godot Variant dictionary with:
version, squad, leader, fallen, mode, vehicle, world, campaign, fuel, vehicle_at,
cans, town, saved timestamp. SAVE_VERSION is incremented on breaking changes.

## Combat design

- Turn-based AP (10 per turn), initiative order
- Jagged Alliance-style planning phase: queue move/fire/grenade, then simultaneous execution
- Fog of war: enemies unseen until in sight (20 tiles), then remembered
- Reaction fire: enemies react to movement within 8 tiles
- Vehicles: crew, components (engine, suspension, gun), armour per facing

## Constraints

- Windows-only build (Godot 4.7 console export)
- `num_workers=0` on DataLoader (Windows multiprocessing pickling)
- No nested classes in multithreaded contexts
- ASCII-only console output (Windows encoding)
