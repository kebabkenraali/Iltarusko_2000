# Changelog - Twilight: 2000 Remake

## 19.11.2026 (vihollisten omat naamat taistelussa)

- **Vihollisten omat naamat taistelun lähetyskuvauksissa:** uusi arkki
  `FACES/enemies.png` (15 naamaa, 5x3, 48x43-ruutuja, tumma tausta);
  `Battle.add_man` asettaa jokaisen vihollisen yksikön `u["face"]` (id % 15) ja
  `battle_view._face_tex` piirtää napit uudestaan — jokaisella vihollisella oma
  naama, ei jakua squadin kanssa
- AI-kuvageneraattori oli tasetty ulkoapäin (insufficient balance); naamat
  generoitu ohjelmallisesti PIL:llä vastaamaan pelin omien FACES-arkkien
  tyyliä (skin/hair palette)
- Uusi headless-testi `tests/test_enemy_faces.gd` (PASS): face-arvot, arkki olemassa,
  naamat erilliset

## Unreleased (M10)

- export_presets.cfg, README, ARCHITECTURE.md, CHANGELOG, version.txt added
- GitHub Actions CI with headless test suite

## 18.11.2026 (M9 economy round 2, battle follow-ups)

- **M9 economy round 2:** FIELD RATIONS item (10 MK), Campaign food counter,
  rations consumed on every 8-hour sleep, fishing/foraging/hunting return rations,
  hungry soldiers take −1 initiative in battle, HQ computer shows six bar graphs
  (food, ammunition, medicine, fuel, people, morale)
- **Battle follow-ups (SUUNKITELMA ch.22/25):** EXECUTE interrupt with REPLAN when a
  new enemy is spotted mid-execution, ghost waypoint preview of queued paths,
  per-unit PLAN AP display, QUICK BATTLE toggle
- **Enemy portraits:** distinct FACES-sheet portraits (no shared face with squad),
  enemy corner boxes tinted red
- **Grenade friendly-fire guard:** cannot throw on own or friendly active man
- **Invisible enemy fix:** vehicles count as eyes in fog, enemy vehicles hunt squad

## 17.11.2026 (Invisible enemy fix)

- Fixed tank never appearing in fogged duels: refresh_seen now treats every vehicle
  as eyes; enemy vehicles drive toward squad engine noise under fog
- New test_tank_hunt.gd: enemy tank spotted within 3 rounds
- Balance re-measured: tank 62%, town 48%, room 53% - all IN BAND

## 8.11.2026 (M9 economy round 1, JA planning, UFO fog)

- HQ resupply: magazines, med kits, grenades bought with campaign funds
- Jagged Alliance-style planning phase with simultaneous walk animation
- UFO-style fog of war with vehicle eyes and armour hunt AI
- Reaction fire + morale/panic system
- Time-unit reserve (OpenXCom-style)

## Earlier

- M1-M8: recruitment, cities, missions, turn-based combat, vehicles, integration,
  balance round 1, sound, computer screen, economy round 1
