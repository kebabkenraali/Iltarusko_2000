# Twilight: 2000 Remake

A faithful remake of the 1991 DOS tactical RPG "Twilight: 2000" in Godot 4.7.
Turn-based AP combat, Jagged Alliance-style simultaneous planning, HQ economy,
world-map travel, and 12 mission types.

## Requirements
- **Godot 4.7.2+** (console edition recommended)
- **Your own copy of the original 1991 Twilight: 2000 DOS game** (for asset extraction)

## No original assets included
This repository contains **source code, extracted text data, documentation, tools and tests only**.
It deliberately contains **no graphics, audio or other copyrighted assets from the original game**.
The game will not display or play correctly until you supply those files yourself from your own
copy of the 1991 DOS game. Nothing in this repository is a substitute for the original game.

## Quick start

### 1. Clone the repository
```powershell
git clone https://github.com/kebabkenraali/Iltarusko_2000.git
cd Iltarusko_2000
```

### 2. Extract game assets
The game needs graphics, audio, and text data extracted from the original game.

If you have the original game installed, run the bundled extractor (Python 3.9+, Pillow):
```powershell
python -m pip install Pillow
python tools/extract_original.py --game "C:\path\to\original\T2000" --out godot/original
```

The extractor reads **only your own copy** of the 1991 DOS game and writes:

| Source | Output |
|---|---|
| `ART/*.LBM` | 7 decoded background pictures as PNG |
| `GAMEDATA/*.VOC` | 25 sound effects converted to WAV |
| `GAMEDATA/*.LB` | 296 raw sprite payloads as `.bin` + `_meta.json` |
| `GAMEDATA/*.CMF` | music copied as-is (AdLib format) |

**Known limitation:** the `.LB` sprites use the game's own token compression. The extractor recovers the raw payloads and their headers but does not yet decode them into PNG pixels, so the game is not fully playable from this output alone. The private decoder from the original project was never published. Contributions that crack the token format are very welcome.

Place extracted files in `godot/original/`:
```
godot/original/
  graphics/   (PNG files from LB/MCG/LBM archives)
  audio/music/  (WAV files from CMF)
  audio/sfx/    (WAV files from VOC)
  text/         (JSON files with extracted strings)
```

### 3. Run the game
```powershell
godot --path godot
```

### 4. Run tests
```powershell
# Headless unit tests
godot --headless --path godot --script tests/test_campaign.gd
godot --headless --path godot --script tests/test_battle.gd

# Windowed integration tests
godot --path godot -- --test=fullgame
godot --path godot -- --test=battle
```

## Project structure
```
Iltarusko_2000/
  godot/              Godot 4.7 project
    project.godot     Project configuration
    scenes/           Main scene (main.tscn)
    scripts/          All game logic (GDScript)
    data/             Game data (items, missions, cities, chargen, vehicles)
    tests/            Automated tests (headless + windowed)
    original/         Original game assets (extracted, not in repo - see above)
  docs/               SUUNNITELMA.md (detailed plan), AI_OHJE.md (agent guide)
  tools/              Python tools (extraction, composition, remastering)
  .github/workflows/  CI (GitHub Actions)
  README.md
  ARCHITECTURE.md
  CHANGELOG.md
  version.txt
```

## Build status
All headless tests pass: combat, spotting, reaction/morale, tank hunt, economy,
balance (fogged), campaign, chargen rules, save/load errors, performance, endings.

## Project status
- **M1-M8:** Complete (recruitment, cities, missions, turn-based combat, vehicles, integration)
- **M9:** Complete (balance round 2, food rations, six bar graphs, HQ resupply, error tests, performance)
- **M10:** Complete (export presets, documentation, CI, endings, melee combat)

## Features
- **Turn-based AP combat** (10 AP/turn, initiative, fog of war, reaction fire, morale/panic)
- **Jagged Alliance-style planning** (queue moves/fires, simultaneous execution, interrupts)
- **12 mission types** (supplies, spy, hostage, assassins, wounded, epidemic, exile, dump, defend, liberate, tank, vehicle)
- **HQ economy** (funds, stores, motor pool, resupply, food rations)
- **World map travel** (driving, fuel, encounters, wrecks)
- **Character generation** (careers, skills, faces, attributes)
- **Save/load** (F5/F9, autosave, version management)
- **Melee combat** (unarmed, adjacent range)
- **Endings** (final battle at Krakow, victory/defeat)

## Original assets only
The game uses only assets extracted from the original 1991 Twilight: 2000 DOS game.
No AI-generated art is used (AI art switch is disabled at compile time).

## License
See the original game's license for asset reuse. The remake code is original work.