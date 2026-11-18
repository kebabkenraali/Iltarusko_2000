# Twilight: 2000 Remake

A faithful remake of the 1991 DOS tactical RPG "Twilight: 2000" in Godot 4.7.
Turn-based AP combat, Jagged Alliance-style simultaneous planning, HQ economy,
world-map travel, and 12 mission types - all using only the original 1991 game assets.

## Build status

All headless tests pass: combat, spotting, reaction/morale, tank hunt, economy,
balance (fogged), campaign, chargen rules, save/load errors, performance.

## Quick start

### Players
1. Download the latest demo build from the releases page.
2. Run `demo/Peli.bat` (Windows) or the Godot-exported binary for your platform.
3. No installation required - the demo is self-contained.

### Developers
1. Clone this repo (docs + tools) and the Godot project repo:
   ```powershell
   git clone <this-repo> remake
   git clone <godot-repo> remake/godot
   ```
2. Install Godot 4.7.2+ (console edition).
3. Run headless tests:
   ```powershell
   godot --headless --path remake/godot --script tests/test_balance.gd
   ```
4. Run the windowed test harness:
   ```powershell
   godot --path remake/godot -- --test=fullgame
   ```

## Project status

- **M1-M8:** Complete (recruitment, cities, missions, turn-based combat, vehicles,
  integration, balance round 1, sound, computer screen, economy round 1)
- **M9:** Complete (balance round 2, food rations, six bar graphs, HQ resupply)
- **M10:** In progress (export presets, documentation, CI)

## Original assets only

The game uses only assets extracted from the original 1991 Twilight: 2000 DOS game.
No AI-generated art or code is used in the demo build (see SUUNNITELMA.md ch. 14).

## License

See the original game's license for asset reuse. The remake code is original work.
