# AI-OHJE — käsioitumisdokumentti tekoälyagentille

> Tämä dokumentti on kirjoitettu **seuraavalle LLM-agentille**, joka jatkaa tämän projektin
> työtä. Lue tämä ensin, sitten `docs/SUUNNITELMA.md` (yksityiskohtainen tila ja historia).
> Päivitä tämä tiedosto jokaisen työkokonaisuuden jälkeen (Tila-, Päätökset- ja Lokiosiot).

## 1. Mikä tämä on

Twilight: 2000 (1991, DOS) -remake Godot 4:llä. Alkuperäisen pelin data on purettu (kuvat,
tekstit, esineet, kaupungit, tehtävätekstit) ja peli rakennettu uudelleen vuoropohjaisella
taistelulla. M1–M8 (pystyleike → integraatio) ovat valmiit ja testatut; M9 (tasapaino ja
laatu) on puolivälissä; M10 (julkaisu) ei ole alkanut.

## 2. Polut ja ympäristö

| Kohde | Polku |
|---|---|
| Kehitysprojekti (Godot) | `C:\Twilight-2000_DOS_EN\remake\godot` (oma git-repo) |
| Dokumentit + työkalut | `C:\Twilight-2000_DOS_EN\remake` (oma git-repo; docs/ + tools/ versioitu) |
| **Manuaalitestauskansio (DEMO)** | `C:\Twilight-2000_DOS_EN\demo` — **KAIKKI manuaalinen testaus täällä**, ei koskaan kehityskansiossa |
| Demo-synkronointi | `python remake/tools/make_demo.py [--clean]` (kopioi projektin + moottorin, kirjoittaa `Peli.bat` ja `LUEMINUT.txt`; demon oma user:// on "Twilight- 2000 Remake DEMO") |
| Godot-binääri | `C:\Twilight-2000_DOS_EN\godot\Godot_v4.7.2-stable_win64_console.exe` (HUOM: wrapper käynnistää rinnalla olevan `Godot_v4.7.2-stable_win64.exe`:n — kopioi molemmat jos siirrät) |
| user:// (kehitys) | `%APPDATA%\Godot\app_userdata\Twilight- 2000 Remake\` (tallennukset, testikuvat `tests\<nimi>\`) |
| Natiivipuoli (purku, simulointi) | **POISTETTU 19.11.2026.** `t2k-native` oli erillinen x86-emulaattorikokeilu alkuperäisen DOS-pelin ajamiseen; ei osa peliä. Lähteitä ei ole jäljellä. Hyödylliset löydökset talletettu `docs/SUUNNITELMA.md`:hen. Älä etsi tai rakenna uudelleen. |
| Alkuperäisdata | `remake\assets_original` (graphics 825 png, audio 6+25 wav, text 9 moduulia) |

## 3. Työskentelysäännöt (tärkeimmät)

1. **Varmuuskopio ensin:** ennen muokkausta `tiedosto.gd` → `tiedosto.gd.bak_YYYYMMDD` (gitignoroitu).
2. **Testit ennen commitia:** kaikki headless-yksikkötestit PASS; isommat muutokset myös
   `--test=fullgame` (ikkunalla). Commit-message englanniksi, selkeä.
3. **Yksi repo:** `remake` sisältää nyt myös `godot/`-kansion (erillinen `godot/.git` poistettu
   19.11. mennessä) — kaikki gd-, docs- ja tools-muutokset commitoidaan samaan `remake`-repoon.
   Commitoija: `Cline <cline@local>` (git -c ...).
4. **Python:** älä aja monimutkaista pythonia PowerShellin `-c`-riviltä (escaping hajoaa) —
   kirjoita väliaikainen `.py`-tiedosto, aja, poista. Kaikki tiedostot `encoding="utf-8"`.
5. **Dokumentaatio:** SUUNNITELMA päivitetään joka työkokonaisuudella; uudet luvut mitataan,
   ei arvata. Tämä AI_OHJE pidetään ajan tasalla.
6. `t2k-native`-kokeilu poistettiin 19.11.2026 (ei lähteitä jäljellä). `unpacked$b.*`-tiedostot
   ovat edelleen alkuperäisen pelin purettuja moduuleja — älä koske niihin ilman varmuuskopiota.

## 4. Tila (7.11.2026)

- **VALMIIT:** M1 pystyleike, M2 hahmonluonti, M3 kaupungit+sisätilat, M4 tehtävät (12 tyyppiä),
  M5 vuoropohjainen taistelu (mukana panssarit), M6 ajoneuvot (ajo, polttoaine, romut, kauppa),
  M7 AI-grafiikka **pidetty tauolla** (käyttäjän päätös: pelissä aina alkuperäinen grafiikka),
  M8 integraatio + `--test=fullgame` läpi, M9 tasapaino 1. kierros (band-testi PASS),
  äänimaailma (musiikki näkymittäin + alkuperäiset efektit), HQ-computer + rahatalous
  (`Campaign.funds`), kulmakuvat ampumisessa, tulitusasennot, katoamiskorjaus (haalistus).
- **VALMIIT (M9):** tasapaino 1. ja 2. kierros (band-testi PASS), HQ-resupply (mags/medkits/grenades),
  ruokatalous: FIELD RATIONS + syönti unella + nälkä-sakko taistelussa, tietokoneen kuusi bar-grafia
  (food/ammo/medicine/fuel/people/morale), tietokoneen FOOD-rivi ja nälkä-merkkaus.
- **VALMIIT (M10+):** loppuratkaisu (endings): kun tarina ja ICON-uutiset on käytetty, seuraava tehtävä
  on lopputaistelu (Black Legionin hyökkäys Krakovaan). Voitolla näytetään endings.victory (2 kappaletta),
  tappiolla city_lost / captured-rivi. VICT2-musiikki voitolla. Save/load tukee uusia kenttiä.
  TWI3D-ajoneuvokuvaukset (8 kpl) vehicles.json:ssa ja motor poolissa. Korjattu vanha testivirhe
  (worldmap.gd "done"-metodikutsu). Mission-failure seuraukset: kun ryhmä tuhoutuu defend/tank/liberate-
  tehtävässä, kaupunki menee Czarnylle (lost_cities-lista, friends-erasing, city_lost-viesti).
  Melee-lähitaistelu: melee() battle.gd:ssä, M-näppäin + MELEE-nappi battle_view:ssä, UNARMED MELEE -taito,
  vain vierekkäiset kohteet.
- **KESKEN (M9):** UI-hionta, virheentestit (korruptoitu save, puuttuvat tiedostot),
  suorituskykymittaukset.
- **EI ALOITETTU (M10):** exportit, README/ARCHITECTURE/CHANGELOG/version.txt, CI.
- **PERUTTU 19.11.2026:** INTRO-remaster (198 ruutua) ei tehdä. Käyttäjän päätöksellä peliin
  jää **alkuperäinen intro**; uutta introa ei luoda eikä SDXL-mallia ajeta. SDXL-malli
  `C:\pinokio\api\stable-diffusion-webui\models\Stable-diffusion\sd_xl_base_1.0.safetensors`
  ladattiin koneelle 19.11., mutta generointi pysäytettiin (0/198 kuvaa, `godot/remastered/INTRO`
  ei ole olemassa). `tools/remaster_set.py intro` jää työkaluksi, mutta sitä EI saa ajaa.
  Älä käynnistä tätä tehtävää uudelleen.
- **Tarkistettu 7.11.2026 (tila-auditointi, mitattu uudelleen):** headless-unitit PASS —
  `test_campaign`, `test_chargen_rules`, `test_combat`, `test_vehicle`, `test_battle`
  (test_balancea ei ajettu uudelleen; 7.11. mitatut bändit voimaan).
  Demon `project.godot` sisältää `[debug] file_logging` -asetuksen (virheloki aktiivinen).
  remake-repon jääneet muutokset (demoloki, hiiritutkimusmuistiinpanot, LUEMINUT-fokus-
  ohjeet) on commitoitu tilapäivityksen yhteydessä; `remake/godot` puhtaana `4384e89`.
- **UUSI 7.11. (M9):** alapalkki + pikanäppäimet — alkuperäisen manuaalin 2-D Ground
  Icons -rivi palautettu (`action_bar.gd`, numerot 1–9/0, alivalikot numeroiduilla
  valinnoilla; kenttänäkymä + huoneet; Necessity-nukkuvaisuus `Healing.rest`-pohjaan;
  OPTIONS-lataus/tallennus/ääni/lopeta; RADIO/INVENTORY/COMBAT/TALK/MAP/LOOK toiminnassa).
  TAKE/USE ovat vielä tietoviestejä (M9 talous 2. kierros). Testit: uusi
  `tests/test_action_bar.gd` (headless PASS) + kaikki vanhat PASS + windowed
  rooms/towns/save/fullgame PASS. Demo synkronoitu (`make_demo.py --clean`), LUEMINUT
  päivätty. Katso SUUNNITELMA luku 12.
- **UUSI 7.11. (M9 taistelugrafiikka):** aseen→CMBT-tulitaiteen mappaus täydennetty
  (`battle_view._fire_pose_art`): CARL GUSTAV / TANK BREAKER / DRAGON / AT-5 / AT-7
  rakettilaukaisijat omalle BAZOOK-asetusteelle, UZI/M12/G11 konepistooleiksi (SMG),
  M9/MAGNUM/SNUBNOSE/HP-35 pistoliasetusteelle — aiemmin ne päätyivät yleiskiväärin
  HG-asetuun. Turvaverrokki `_place_units`: jos tulitaidetta ei ole jollekin suunnalle
  (yksikkö olisi muutenkin hävinnyt), seisova keho jää näkyviin. Uusi auditointitesti
  `tests/test_battle_art.gd` (headless, PASS): jokainen kädessä pidettävä ase (44 kpl)
  ja molemmat osapuolet (sotilaat/Black Legion) löytyvät taiteen kaikilla 8 suunnalla;
  lisäksi vartalot AM/AF/EM (AF putoaa AM:ään suuntiin N/NE/NW), jalat, päät 0–14 ja
  KNEEL/WOUND. Taistelunäytön `--test=battle` ajettu ikkunalla (1,5 min, läpi).
- **UUSI 8.11. (M9 talous alku):** HQ-varustekauppa tietokonenäytöllä (`computer.gd` +
  uusi `economy.gd`): MAG/MED/GRE-napit per sotilas, ostot `campaign.funds`ista, hinta-
  sääntö johdettu (mag = asehinta/10, minimi 10; med kit 100; kranaatti 4 — alkuperäisen
  datan ammushinnat ovat 0), kantamiskytkot (12/3/12), refusalit alkuperäisen
  OFFICE-merkkijonoilla ("ADD AMMO TO WHICH WEAPON?", "%s CANNOT CARRY ANY MORE AMMO
  FOR THE %s.", "%s ISN'T CARRYING ANY WEAPONS THAT USE %s AMMO."). Kulutus jo kiertää:
  `battle.gd write_back` kirjoittaa mags/medkits takaisin geariin taistelun jälkeen.
  Uusi testi `tests/test_economy.gd` PASS; `--test=computer` ja fullgame läpi.
  Jäljellä: ruoan kulutus, Krakowin kuusi bar-graafia, hintojen hienosäätö mitatun
  rahavirran kautta (SUUNNITELMA luku 16).
- **UUSI 8.11. (M9 taistelu-UX):** AP-varaus ("time units reserved for snapshot") —
  `battle.gd set_reserve` + `_flood`-rajaus: varattu sotilas ei kulje niin, että
  snap-ammunnan 3 AP katoaisi. Näppäin T ja nappi "T RES ON/OFF", ajoneuvoille ei.
  Idea OpenXComin `BattlescapeGame.checkReservedTU`-mekanismista (GPL): toteutus oma,
  koodia ei kopioitu (SUUNNITELMA luku 17). Testit `tests/test_reserve.gd` PASS,
  test_battle PASS.
- **UUSI 8.11. (M9 taistelu-UX, UFO-tyylinen sumu, SUUNNITELMA luku 19):**
  `battle.gd options["fog"]` (oletus false; pelin taistelut kytkevät sen
  `Forces.make_battle`/`make_room_battle`):
  - vihollinen näkyy kun joku sotilas näkee sen: `SIGHT_TILES` 20 (40 m kentällä,
    20 m sisätilassa) + `can_see`-näkölinja; kun nähty, pysyy havaittuna.
  - laukaisu paljastaa ampujan (`_reveal` fire- ja kranaattithrowissa).
  - `refresh_seen()` kahdensuuntainen päivitys siirron/ampumisen jälkeen; lokiin
    "%s IS SPOTTED." kun ryhmä näkee.
  - `fire()` ei ammu pimeään ("THE TARGET IS NOT IN SIGHT.").
  - puolustava AI odottaa paikallaan kun mitään ei näy.
  - `battle_view`: vihollissprite piirretään vain kun nähty (sijoittelussa kaikki),
    klikki ja kursorin vinkki vain näkyviin kohteisiin; ensimmäisen taistelun
    muistiloki (1/2/3 ammuntatavat, T-kytkin, "THE ENEMIES STAY IN THE DARK...").
  - Uusi testi `tests/test_spotted.gd` (headless PASS); `--test=battle` (ikkuna) ja
    fullgame läpi; legacy-testit toimivat fog=false-oletuksella.
- **UUSI 19.11.:** vihollisten omat naamat taistelussa — `FACES/enemies.png` (15 naamaa);
  `Battle.add_man` asettaa `u["face"]` (id % 15); `battle_view._face_tex` piirtää vihollisten
  napit uudestaan; AI-kuvageneraattori oli tasetty (insufficient balance), naamat generoitu
  ohjelmallisesti (PIL); testi `tests/test_enemy_faces.gd`.
- **UUSI 8.11. (M9 taistelu, lukujen 18-19 jatkot):** reaktiotuli ja paniikki.
  Reaktiotuli: move() astuu reitin portaittain; joka porras näkevä (sticky) vastustaja
  vastaa vapaalla snapilla (≤ 8 tilea, yksi ampuma per siirto, kerta per kierros
  `reacted`); matka katkeaa kun siirtjän pudotus haittaus; AP maksaa vain kuljetuksi
  sijastaen. Paniikkisysteemi: moraalit kertova (kuolema -30, putoa -20, tapto +15
  killerin joukkuelles; moraali 0 = FREEZES IN FEAR tai PANICS AND RUNS FOR COVER,
  toipuu 50; MORALE rivillä). Pelaajais-puolen auto-squad marssii `battle.seek` kun
  mitään ei näy (muuten sumu jumittaa; seek = vihollispuolen spawn koordinaattisa).
  Bändimittaus (T2K_FOGGED=1, 80 taistelua/solu): kaupungin garrison 55 % (AI kirkas
  57 %), SCAVENGERS 71 % (flavor), T-72 + LAW 68 %, room 55 % (aiemmin 65 %);
  legacy-mittapuu re-checked 57 % PASS. Uusi testi `test_reaction_morale.gd` PASS.
  Suunnitelma luvut 18-20.
- **Asset- ja tehtäväauditointi 7.11. (SUUNNITELMA luku 14):** pelin kaikki kuvat/äänet
  ovat alkuperäisen pelin omia — `ALLOW_AI_ART=false` (F2 kuollut), `main.remastered=false`,
  `Soldier.remastered=false`; ainoa res://remastered-viittaus sijaitsee näiden porttien
  takana. **Demo puhdistettu kokonaan AI-tiedostoista** (make_demo.py IGNORE sai
  "remastered": 6105→5447 tiedostoa; demossa 0 AI-tiedostoa). Tehtävätyyppien (12 kpl)
  intro/nag/done-rivit ovat alkuperäisen TWI2D.EXE:n omia merkkijonoja (offsetit
  SUUNNITELMA luku 14; missions.json "no retyping"); pelattavuuserot (vuoropohjainen
  taistelu, ei TWI3D-ajoa, tietokoneen bar-graafit puuttuvat vielä) dokumentoitu.
- **Natiivipuoli POISTETTU (19.11.2026):** `t2k-native` (x86-emulaattorikokeilu, Lataus-Enter-
  virhe, S_aAls-säännöt, TWI2D-purku `dis86.py`:llä) ei ole enää olemassa eikä sitä jatketa.
  Löydökset on talletettu SUUNNITELMAAN; peli ei riippunut kokeilusta millään tavoin.

## 5. Arkkitehtuurin pikakartta

- **`scripts/main.gd`** (~1150 riviä) — pelin valvomo: näkymävaihdot (show_office → show_briefing
  → show_world → enter_town → start_battle → battle_over), tallennus (`save_game`/`load_game`,
  `game_state`/`apply_state`, SAVE_VERSION 1, QUICKSAVE/AUTOSAVE), äänet (`set_music`/`play_sfx`,
  `stop_audio`), kampanjan kytkennät (`is_story`, `squad_size`), testiajo (`_setup_test`,
  `test_steps` + `_process`-tulkki: call/call1/screen/shot/key/quit).
- **`battle.gd`** — taistelulogiikka ilman grafiikkaa (ap, osumat, haavat, panssari, ajoneuvot,
  ai_step/auto_play, write_back; OpenXCom-tyylinen "reserve": `set_reserve` + `_flood`-rajaus,
  T = varaa AP yhtä snap-ammuntaa varten). **`battle_view.gd`** — näkymä: sijoittelu, klikkaukset,
  spritet (Soldier), efektien käsittely (`b.events`: fire/explode/tree_down/crater), äänet,
  tulitusasennot (`fire_pose`), kulmakuvat (`_show_faces`). **`economy.gd`** — HQ-varustek
  uppaan hinnat ja kantamiskytkot (mag = aseen hinta/10, MED 100, GRE 4; caps 12/3/12).
- **`forces.gd`** — varusteet (equip), vihollisryhmät (group: BLACK LEGION/MARAUDERS/
  STRAGGLERS/HUNTERS), taistelukenttä (make_battle/make_room_battle) ja sijoittelu (deploy_*).
- **`campaign.gd`** — tehtäväkierros (steps: talk/clear/treat/spy/search/reach/repair),
  sairaiden aikarajat (tick), palkinnot (stores + funds), tallennus (to_dict/from_dict),
  M9-formulat: `field_count` = squad+1..2, `room_count` = clamp(squad−2, 2, 5),
  `TANK_ESCORTS` = 3, `PAY_PER_MISSION` = 2000.
- **`world.gd`** — maailmankartta, GROUPS-kohtaamiset (partiot 2–4 jne.), romut (WRECKS, vain story).
  **`worldmap.gd`** — karttanäkymä ja ajo (A*, polttoaine).
- **`soldier.gd`** — hahmon koostaminen streipeistä: jalat (cells/L*), torso (AM/AF/EM + suunta,
  AF:lta puuttuvat N/NE/NW → fallback AM), pää (AMH/AFH 0–14, EMH0; 8 suuntaa 8 px/rivi, 63 px);
  `head_image()` julkisena kulmakuville; astuntapomppu _draw'ssa.
- **`tactical.gd`** — kenttänäkymä (kaupunki/maasto), syvyysjärjestys, ihmiset, ovet;
  `_fade_over` haalistaa rakennuksen jonka takana sotilas on. **`interior.gd`** — huonenäkymä
  (sama haalistus kalusteille). **`action_bar.gd`** — molempien näkymien alapalkki (alkuperäisen
  2-D Ground Icons, numerot 1–9/0, alivalikot; näkymät vetävät napit
  `_bar_def()`-listalla ja kutsuvat `_icon_*`-funktioita). **`computer.gd`** — HQ-tietokone
  (funds/stores/motor pool/squad + resupply-osio: MAG/MED/GRE-buttonit per sotilas,
  refusalit alkuperäisen OFFICE-riveillä).
  **`motor_pool.gd`** — ajoneuvokauppa (veloittaa `campaign.funds`).
- **Spritelogiikan verifiointi:** offline-kooste (PIL) toistaa Soldier._drawin — käytä jos
  spritet näyttävät rikkoutuneilta (katso git-historia: tools/_spr_probe.py-tyyppinen probe).

## 6. Testit — miten ajetaan, mitä odottaa

```powershell
# Yksikkötestit (headless, sekunteja–minuutteja):
godot --headless --path . --script tests/test_campaign.gd        # PASS odotettu
godot --headless --path . --script tests/test_chargen_rules.gd
godot --headless --path . --script tests/test_combat.gd          # legacy combat.gd
godot --headless --path . --script tests/test_vehicle.gd
godot --headless --path . --script tests/test_action_bar.gd      # alapalkki (headless)
godot --headless --path . --script tests/test_battle_art.gd      # taistelugrafiikan kartta
godot --headless --path . --script tests/test_reserve.gd         # AP-varaus (OpenXCom-tyyli)
godot --headless --path . --script tests/test_economy.gd         # HQ-varustekaupan säännöt
godot --headless --path . --script tests/test_spotted.gd         # UFO-sumu (spotting)
godot --headless --path . --script tests/test_reaction_morale.gd # reaktiotuli + paniikki
godot --headless --path . --script tests/test_tank_hunt.gd       # panssaridueli sumussa: tankit ajavat näkyviin
# Bändimittaus: pelinormaalit asetukset (fog+reaction+panic+seek) T2K_FOGGED=1:llä
T2K_FOGGED=1 godot --headless --path . --script tests/test_balance.gd
godot --headless --path . --script tests/test_battle.gd          # ~90 s
godot --headless --path . --script tests/test_balance.gd         # M9: 40-70 % band; -- --report = pelkkä taulukko
# Integraatiotestit (IKKUNALLA — headless ei tuota kuvia, frame_post_draw ei laukea):
godot --path . -- --test=chargen | city | rooms | towns | soldiers | battle | boom |
                                mission | drive | save | computer | fullgame
```

- Kuvat: `%APPDATA%\Godot\app_userdata\Twilight- 2000 Remake\tests\<nimi>\*.png`.
- `M9_ONLY=<sana>` rajaa tasapainoprofiilit; tulokset satunnaisia ±5–7 %-yks. (80 taistelua/solu).
- Taisteluprosentit (NORMAL, 6 hengen ryhmä): kaupungin varuskunta ~58 %, huone ~65 %,
  tankki ~57 % — pidä bandissä jos muuttaa taistelusääntöjä.

## 7. Kuopat, joihin kaatua älä

- **Headless + kuvakaappaus:** `await RenderingServer.frame_post_draw` ei koskaan palaa
  headlessissa → integraatiotestit ikkunalla, yksikkötestit headless.
- **GDScript:** tyypitetyt taulukot (`Array[Dictionary]`) vaativat tyypitetyn lähteen —
  `var x = []` ei kelpaa paluuarvoksi. `Campaign` on RefCounted-objekti, ei Dictionary.
- **Poistuessa testistä:** kutsu `stop_audio()` + lyhyt await ennen `quit()` (muuten
  AudioStreamWAV jää "in use at exit" -varoituksella).
- **PowerShell:** älä upota regexiä `-c`-kutsuihin; käytä skriptitiedostoja.
- **Uusi `class_name` (esim. Economy):** headless-testit eivät näe sitä ennen kuin projekti
  on skannattu kerran editorilla: `godot --headless --path . --editor --quit`. Sen jälkeen
  se on kaikkialla käytettävissä (Cline-komponentti kuten Healing/Forces).
- **Käyttäjäkansiot:** projektin nimi sisältää kaksoispisteen → Windowsissa user://-kansio on
  sanitisoitu muotoon `Twilight- 2000 Remake` (demonilla `...- 2000 Remake DEMO`).
- **Testisyötteet:** testiajo syöttää syötteet TEST_DEVICE:llä ja `main.input_ok` ohittaa
  oikean hiiren/näppäimistön — älä poista tätä.
- **Värit/encoding:** python-tiedostot aina `encoding="utf-8"`; Windowsin oletus (cp1252)
  sotkee dokumentit.

## 7b. Demo (manuaalitestaus) — virheloki, tunnetut ongelmat ja debug-ohje

- **VIRHELOKI (7.11. alkaen):** demon projektiin on lisätty `debug/file_logging/enable_file_logging=true` → joka ajosta syntyy loki: `%APPDATA%\Godot\app_userdata\Twilight- 2000 Remake DEMO\logs\godot.log` (5 rotaatiota). **Kun käyttäjä raportoi ongelman demon kanssa, lue tämä loki ensin.** make_demo.py lisää asetuksen synkronoinnin yhteydessä (kehityskopio pysyy ilman).
- **Käynnistys:** `demo\Peli.bat`. Konsolirutiini avaa myös mustan konsoliikkunan — se on normaalia ja saa jäädä taakse. Pelin ikkuna voi avautua muiden ikkunoiden taakse: napsauta pelin ikkunaa kerran, jotta se saa fokuksen.
- **CHARGEN EI OLE RIKKI:** demon user:// on oma kansionsa — uusi pelaaja näkee tyhjän rosterin (SQUAD 0/4) ja LOAD SQUAD on enabled vain jos `user://squad.json` on olemassa. Kehityskopiossa vanha squad.json latautuu rosterin mukaan — tarkoitus, ei bugi.
- **HIIRIONGELMA RATKAISTU (7.11.):** juurisyy oli, että näkymät roikkuvat tavallisen `Node`-vanhemman (main.tscn:n root) alla — `set_anchors_preset(FULL_RECT)` ei silloin saa kokoa mistään, joten **toimisto- (ja muut) Control-näkymät olivat 0×0** ja niiden oma `_gui_input` ei koskaan saanut klikkauksia (tausta piirtyi, koska bg:llä on eksplisiittinen koko; chargenin napit toimivat, koska niillä on omat rectit). Korjaus: `main._swap` pinnee jokaisen Control-näkymän TOP_LEFT-ankkuriin ja asettaa koon 1280×800. Uusi testi `tests/test_gui_input.gd` (headless) lähettää oikeita InputEventMouse-klikkauksia `Input.parse_input_event`-kautta läpi koko ketjun: chargen-nappi → deploy → office → radio → briefing — PASS. Huom: headless-juuri on 64×64, joten testi asettaa `root.size` 1280×800 ennen klikkauksia (stretch-muunnos nielaisi muuten koordinaatit); älä käytä PostMessagea (Godot ei reagoi) ja muista että skriptoitu SetCursorPos kärsii DPI-virtualisaatiosta — käyttäjän oikea hiiri ei.
- **Debug-työkalut:** pelin ikkuna kuuluu lapsiprosessille `Godot_v4.7.2-stable_win64` (console-wrapperin MainWindowHandle on aina 0); kuvakaappaus `PrintWindow(PW_RENDERFULLCONTENT)` tai `CopyFromScreen`; ikkunan koko/paikka `SetWindowPos(h, 0, 0, 1280, 800, 0x0040)`.

## 8. Seuraavat tehtävät (ehdotettu järjestys)

1. **M9 talous 2. kierros: VALMIS** (ruokatalous + kuusi bar-grafia, commitoitu 18.11.).
2. **Loppuratkaisu (endings): VALMIS** (lopputaistelu Krakovassa, voitto/tappio, jammed-viesti, VICT2-musiikki).
3. **TWI3D-ajoneuvokuvaukset: VALMIS** (8 kuvausta motor poolissa).
   Jäljellä M9:ssä: UI-hionta (alapalkin TAKE/USE toteutettu tactical.gd:ssä), kaikki
   virheentestit ja suorituskykymittaukset tehty.

2. **M9 virheentestit: VALMIS** (`tests/test_save_errors.gd` via `--test=save_errors`:
   puuttuva tiedosto, korruptoitu tiedosto, väärä versio, kelvollinen kierrätys — kaikki PASS).

3. **M9 suorituskyky: VALMIS** (`tests/test_performance.gd`: auto_play 200 kierrosta
   0.107 s, vaatimus < 1 s).

4. **M10: VALMIS** — `export_presets.cfg`, README, ARCHITECTURE.md, CHANGELOG,
   version.txt lisätty remake-repoon; GitHub Actions CI (`.github/workflows/ci.yml`)
   lisätty headless-testisarjalle.

5. **INTRO-remaster: PERUTTU (19.11.2026).** Käyttäjä päätti, ettei peliin tehdä uutta introa —
   alkuperäinen INTRO.LB jää käyttöön. SDXL-malli on nyt ladattu, mutta `remaster_set.py intro`
   pysäytettiin (0/198 kuvaa) eikä sitä ajeta. Älä käynnistä uudelleen.

6. **Natiivipuoli: POISTETTU / PERUTTU 19.11.2026.** `t2k-native`-kokeilu (Lataus-Enter-korjaus,
   S_aAls-säännöt, TWI2D:n purku `dis86.py`:llä) poistettiin; lähteitä ei ole jäljellä eikä niitä
   rakenneta uudelleen. Älä käynnistä näitä tehtäviä.

7. **Pelin avaus ja ensimmäinen tehtävä (SUUNNITELMA luku 18):** design dokumentoitu.

7. **Alkuperäisestä vielä konvertoimatta (8.11. katveiskannaus):**
   - HQ-varustekauppa: OFFICE-rivit ("ADD AMMO TO WHICH WEAPON?" ym.): VALMIS (computer.gd).
     EQUIP.json-kuvausteekstit Inventoryn INFO/DESCRIPTION-valintoihin: VALMIS (19.11.,
     godot `93b1986` — `data/item_desc_map.json` johdettu EQUIP.TXT:n osoitetaulukosta,
     `GameData.item_description()`, valittavat DESCRIPTION-kohdat kenttä- ja huonenäkymän
     Inventoryssa; ammuksilla/poistetuilla esineillä ei ole kuvausta).
   - Kuorma-auto supplies/dump-tehtävään: VALMIS (campaign.arrived tarkistaa 2 1/2 TON
     TRUCKin squad_vehicle:n kautta; data/lines/need_truck).
   - ICON-lisäuutiset radioketjuun: VALMIS (icon_news 8 viestiä missions.json:ssa, näkyvät
     tarinaviestien jälkeen done_count % 2 == 1 -ehtona).
   - Taisteluloki TWI2D-riveihin: VALMIS (COMBAT ROUND X BEGINS, reload-viestit, THE ENEMY
     TURN BEGINS battle.gd:ssä; matala prioriteetti).

## 9. Commit-loki (lyhennetty)

- remake/godot: `6e8304e` M8 fullgame läpi → `54a47cb` M9 balance-harness + skaalautuvat
  varuskunnat + combat.gd-korjaukset → `1f5d989` äänet + computer + rahatalous →
  `4384e89` tulitusasennot + kulmakuvat + katoamiskorjaus → `aeead10` alapalkki
  (action_bar.gd) + numeronäppäimet kenttä- ja huonenäkymään → `5306b68` taistelun
  CMBT-tulitaidemappaus kattavaksi + turvaverrokki (ei enää tyhjää kehoa) + auditointitesti
  → `2e42652` alkuperäisrivityö (necessity-rivit, captured-rivi, endings-data) →
  economy/reserve: economy.gd + computer-resupply + set_reserve (testit test_economy,
  test_reserve).
- remake: `fe570fb` docs+tools repoon, SUUNNITELMA auditoitu → `5fa9d24` intro-set + ääni/
  computer-dokumentointi → `2981046` mallin puuttumisen huomio → `9965c58` M5-lisäykset 7.11.
  → demovirheloki + hiiritutkimusmuistiinpanot (7.11.) → tila-auditointi 7.11.2026 (testit
  mitattu uudelleen, kaikki PASS; SDXL yhä puuttuu; molemmat repon muutokset commitoitu)
  → alapalkki + pikanäppäimet (SUUNNITELMA luku 12; demo synkronoitu, LUEMINUT päivätty)
  → taistelun tuliasetuudet kunnossa (CMBT-mappaus täydennetty + turvaverrokki + auditointi
  `tests/test_battle_art.gd`; godot `5306b68`) → asset- ja tehtäväauditointi, demo puhtaana
  AI-tiedostoista (SUUNNITELMA luku 14) → 8.11.: alkuperäisrivityö (Necessity-rivit
   sängyssä/avomaalla, kalastus/keruu/metsästys tulokset; `_game_over` alkuperäisrivi;
   loppuaineisto data/missions.json "endings"-lohkoon) + katveiskannaus ja konvertointi-
   backlogi (SUUNNITELMA luku 15). Testit 8.11.: campaign/chargen/combat/battle_art
   headless PASS; save ja fullgame ilman skriptivirheitä.
- remake/godot 8.11.: `2e42652` alkuperäisrivityö → `31537b4` economy/reserve (economy.gd,
  computer-resupply, set_reserve; testit test_economy, test_reserve) → UFO-sumu
  (fog/spotting/reveal/AI-hold; testit test_spotted + battle/battle_config + fullgame;
  fog ON pelissä, OFF legacytesteissä) → `4100b5b` reaktiotuli + paniikki + seek
  (test_reaction_morale; T2K_FOGGED=1-bändimitta: garrison 55 %, T-72 68 %, room 55 %;
  luvut 18-20 dokumentoitu SUUNNITELMAAN) → `7687f64` JA-tyylinen suunnitteluvaihe +
   samanaikainen kävelyanimaatio (SUUNNITELMA luku 22) → `d772894` ch.22 follow-ups:
   EXECUTE-keskeytys + REPLAN, haamupolun reittinäkymä, per-sotilaan plan_ap-näyttö,
   QUICK BATTLE -valitsin (SUUNNITELMA luku 25) → `693834d` näkymättömän vihollisen
   korjaus sumussa (ajoneuvot silminäkijöiksi refresh_seen'ssä + panssari liittyy jahtiin;
   test_tank_hunt; SUUNNITELMA luku 23) → 18.11.: vihollisten omat kasvokuvat
   FACES-arkista (_face_tex; ei jaettuja indeksejä joukkueen kanssa _used_faces:n kautta,
   vihollisen kulmalaatikko punasävytettynä) + kranaatin ystävätulisuojat
   (throw_grenade/plan_grenade eivät hyväksy oman miehen ruutua; SUUNNITELMA luku 24).
   Testit 18.11.: tank_hunt/spotted/reaction_morale/economy/balance (T2K_FOGGED=1),
   save, windowed battle, fullgame — kaikki PASS.

- remake 19.11.: INTRO-remaster **peruttu** käyttäjän päätöksellä — peliin jää alkuperäinen
  intro, uutta ei tehdä. SDXL-malli ladattu, mutta generointi pysäytetty (0/198 kuvaa,
  `godot/remastered/INTRO` ei ole olemassa). `remaster_set.py intro` jää työkaluksi mutta
  sitä ei ajeta. AI_OHJE luku 4 ja 8 päivitetty.
- remake 19.11.: `t2k-native` (erillinen x86-emulaattorikokeilu) todettu poistetuksi eikä sen
  lähteitä löydy koneelta — kokeilu päättynyt, ei jatketa. AI_OHJE luvut 2/3/4/8/9 päivitetty
  ja SUUNNITELMA merkitty; hyödylliset löydökset (alkuperäisen Enter-bugi, sääntövertailu,
  manuaalitarkistus) säilyvät SUUNNITELMASSA.
- remake/godot 19.11.: `93b1986` Inventory INFO/DESCRIPTION — EQUIP.TXT-kuvaukset Inventoryyn
  (item_desc_map.json 71/96 esineelle, GameData.item_description(), valittavat DESCRIPTION-
  kohdat tactical.gd/interior.gd, test_item_desc.gd). Kaikki headless- jaikkunatestit PASS.
- remake 19.11.: paketit rakennettu uudelleen — `Iltarusko_2000.zip` (koko lähdeprojekti
  2487 tiedostoa, 52,6 Mt; vanha talletettu `Iltarusko_2000_old_backup.zip`) sisältää nyt
  Inventory-ominaisuuden; purettu paketti testattu (test_item_desc + campaign PASS).
  `tools/Twilight-2000-Remake.zip` (pack_game.exe: original/ 2347 tiedostoa + Godot-exe,
  139,8 Mt) päivitetty. Huom: `pack_game.exe` ei sisällä peliprojektia, vain original/ + moottorin.

## 10. Näin päivität tätä dokumenttia

Työn jälkeen: päivitä luvut 4 (Tila), 9 (Loki), tarvittaessa 5 (Arkkitehtuuri) ja 7 (Kuopat).
Commitoi `remake`-repoomme viestillä, joka alkaa "Docs:". SUUNNITELMA.md on yksityiskohtainen
historia — pidä sen ja tämän tiedoston tiedot yhdenmukaisina.

- remake/godot 18.11.: `d772894` JA planning follow-ups → `5860e6e` M9 economy round 2:
  FIELD RATIONS item + Campaign food counter (feed/buy_food/add_food, saved in savegame),
  scrounge returns rations, hungry soldiers take -1 initiative in battle, HQ computer
  shows six bar graphs (food/ammo/medicine/fuel/people/morale) and marks hungry squad
  members (SUUNNITELMA luku 26) → `fbdf3c5` konversiobacklog luku 15:
  dump-tehtävä vaatii 2 1/2 TON TRUCKin (campaign.arrived + squad_vehicle Callable),
  ICON-uutisviestit (icon_news 8 kpl missions.jsonissa), taistelulokiin TWI2D-rivit
  (COMBAT ROUND X BEGINS, reload, THE ENEMY TURN BEGINS). Testit 18.11.:
  campaign/chargen/economy/balance/spotted/reaction_morale/tank_hunt/performance/
  battle/combat/reserve/action_bar/battle_art/save/save_errors/computer/fullgame — kaikki PASS.
