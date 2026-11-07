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
| Natiivipuoli (purku, simulointi) | `C:\Twilight-2000_DOS_EN\t2k-native` (tools/, docs/RAPORTTI.md, SAANNOT_VERTAILU.md) |
| Alkuperäisdata | `remake\assets_original` (graphics 825 png, audio 6+25 wav, text 9 moduulia) |

## 3. Työskentelysäännöt (tärkeimmät)

1. **Varmuuskopio ensin:** ennen muokkausta `tiedosto.gd` → `tiedosto.gd.bak_YYYYMMDD` (gitignoroitu).
2. **Testit ennen commitia:** kaikki headless-yksikkötestit PASS; isommat muutokset myös
   `--test=fullgame` (ikkunalla). Commit-message englanniksi, selkeä.
3. **Kaksi repoa:** gd-muutokset commitoidaan `remake/godot`-repoon, docs/tools-muutokset
   `remake`-repoon. Commitoija: `Cline <cline@local>` (git -c ...).
4. **Python:** älä aja monimutkaista pythonia PowerShellin `-c`-riviltä (escaping hajoaa) —
   kirjoita väliaikainen `.py`-tiedosto, aja, poista. Kaikki tiedostot `encoding="utf-8"`.
5. **Dokumentaatio:** SUUNNITELMA päivitetään joka työkokonaisuudella; uudet luvut mitataan,
   ei arvata. Tämä AI_OHJE pidetään ajan tasalla.
6. Älä koske `t2k-native`-suorittaviin pelitiedostoihin tai `unpacked$b.*`-tiedostoihin ilman
   erillistä varmuuskopiota.

## 4. Tila (7.11.2026)

- **VALMIIT:** M1 pystyleike, M2 hahmonluonti, M3 kaupungit+sisätilat, M4 tehtävät (12 tyyppiä),
  M5 vuoropohjainen taistelu (mukana panssarit), M6 ajoneuvot (ajo, polttoaine, romut, kauppa),
  M7 AI-grafiikka **pidetty tauolla** (käyttäjän päätös: pelissä aina alkuperäinen grafiikka),
  M8 integraatio + `--test=fullgame` läpi, M9 tasapaino 1. kierros (band-testi PASS),
  äänimaailma (musiikki näkymittäin + alkuperäiset efektit), HQ-computer + rahatalous
  (`Campaign.funds`), kulmakuvat ampumisessa, tulitusasennot, katoamiskorjaus (haalistus).
- **KESKEN (M9):** ammus-/lääke-/ruokatalous, UI-hionta, virheentestit (korruptoitu save,
  puuttuvat tiedostot), suorituskykymittaukset.
- **EI ALOITETTU (M10):** exportit, README/ARCHITECTURE/CHANGELOG/version.txt, CI.
- **ESTETTY:** INTRO-remaster (198 ruutua) — `remaster_set.py intro [N]` on valmis, mutta
  SDXL-malli `C:\pinokio\api\stable-diffusion-webui\models\Stable-diffusion\sd_xl_base_1.0.safetensors`
  **puuttuu** (kansio tyhjä; tarkistettu tilapäivityksessä 7.11.2026 — yhä puuttuu).
  Lataa malli → aja `python remake/tools/remaster_set.py intro`.
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
- **Asset- ja tehtäväauditointi 7.11. (SUUNNITELMA luku 14):** pelin kaikki kuvat/äänet
  ovat alkuperäisen pelin omia — `ALLOW_AI_ART=false` (F2 kuollut), `main.remastered=false`,
  `Soldier.remastered=false`; ainoa res://remastered-viittaus sijaitsee näiden porttien
  takana. **Demo puhdistettu kokonaan AI-tiedostoista** (make_demo.py IGNORE sai
  "remastered": 6105→5447 tiedostoa; demossa 0 AI-tiedostoa). Tehtävätyyppien (12 kpl)
  intro/nag/done-rivit ovat alkuperäisen TWI2D.EXE:n omia merkkijonoja (offsetit
  SUUNNITELMA luku 14; missions.json "no retyping"); pelattavuuserot (vuoropohjainen
  taistelu, ei TWI3D-ajoa, tietokoneen bar-graafit puuttuvat vielä) dokumentoitu.
- **Natiivipuoli (ei SUUNNITELMASSA, katso t2k-native/docs/RAPORTTI.md):**
  Lataus-Enter-virhe, S_aAls-säännöt, TWI2D-purku.

## 5. Arkkitehtuurin pikakartta

- **`scripts/main.gd`** (~1150 riviä) — pelin valvomo: näkymävaihdot (show_office → show_briefing
  → show_world → enter_town → start_battle → battle_over), tallennus (`save_game`/`load_game`,
  `game_state`/`apply_state`, SAVE_VERSION 1, QUICKSAVE/AUTOSAVE), äänet (`set_music`/`play_sfx`,
  `stop_audio`), kampanjan kytkennät (`is_story`, `squad_size`), testiajo (`_setup_test`,
  `test_steps` + `_process`-tulkki: call/call1/screen/shot/key/quit).
- **`battle.gd`** — taistelulogiikka ilman grafiikkaa (ap, osumat, haavat, panssari, ajoneuvot,
  ai_step/auto_play, write_back). **`battle_view.gd`** — näkymä: sijoittelu, klikkaukset,
  spritet (Soldier), efektien käsittely (`b.events`: fire/explode/tree_down/crater), äänet,
  tulitusasennot (`fire_pose`), kulmakuvat (`_show_faces`).
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
  `_bar_def()`-listalla ja kutsuvat `_icon_*`-funktioita). **`computer.gd`** — HQ-tietokone (funds/stores/motor pool/squad).
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
godot --headless --path . --script tests/test_battle.gd          # ~90 s
godot --headless --path . --script tests/test_balance.gd         # M9: 40–70 % band; -- --report = pelkkä taulukko
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

1. **M9 talous 2. kierros:** ammusten/lääkkeiden/ruoan kulutus ja hankinta (kauppa computer-
   näytöltä? varastosta nouto?), hinnat ja palkkiot tasapainoon (mitattuna: rahavirta 12
   tehtävän yli). **Alapalkin jatko:** TAKE/USE todellisiksi toiminnoiksi
   (Necessity-kalastukseen/keruuseen oikeat tuotokset, eivät vain viestit).
2. **M9 virheentestit:** korruptoitu save (uusi `tests/test_save_errors.gd` tai laajennus),
   puuttuva data — peli ei saa kaatua.
3. **M9 suorituskyky:** auto_play 200 kierrosta < 1 s -mittaus ja FPS-raportti (uusi testi).
4. **M10:** export_presets.cfg + buildit, README (pelaajalle), ARCHITECTURE.md (kehittäjälle),
   CHANGELOG + version.txt, GitHub Actions (headless-testit). **Lisäksi loppupeli
   (SUUNNITELMA luku 15):** Black Legionin hyökkäys tarinan lopussa; voitto ->
   `missions.json endings.victory` (datassa jo), häviö -> `city_lost`-rivi (datassa jo),
   ja "jammed"-viesti hyökkäyksen ajalle.
5. **INTRO-remaster:** kun SDXL-malli palautettu → `python tools/remaster_set.py intro`
   (resumoitava; ~1–2 min/ruutu, 198 kpl).
6. **Natiivipuoli:** Lataus-Enter-korjaus, S_aAls-säännöt, TWI2D:n purku `tools/dis86.py`:llä.
7. **Alkuperäisestä vielä konvertoimatta (8.11. katveiskannaus):**
   - HQ-varustekauppa: OFFICE-rivit ("ADD AMMO TO WHICH WEAPON?" ym.) ja
     EQUIP.json-kuvausteekstit Inventoryn INFO/DESCRIPTION-valintoihin.
   - Kuorma-auto supplies/dump-tehtävään (TWI2D @151563).
   - ICON-lisäuutiset radioketjuun (12 story-kappaletta jo datassa, muut
     ajastettuihin pending_story-tapahtumiin).
   - Taisteluloki TWI2D-riveihin (matala prioriteetti).

## 9. Commit-loki (lyhennetty)

- remake/godot: `6e8304e` M8 fullgame läpi → `54a47cb` M9 balance-harness + skaalautuvat
  varuskunnat + combat.gd-korjaukset → `1f5d989` äänet + computer + rahatalous →
  `4384e89` tulitusasennot + kulmakuvat + katoamiskorjaus → `aeead10` alapalkki
  (action_bar.gd) + numeronäppäimet kenttä- ja huonenäkymään → `5306b68` taistelun
  CMBT-tulitaidemappaus kattavaksi + turvaverrokki (ei enää tyhjää kehoa) + auditointitesti.
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

## 10. Näin päivität tätä dokumenttia

Työn jälkeen: päivitä luvut 4 (Tila), 9 (Loki), tarvittaessa 5 (Arkkitehtuuri) ja 7 (Kuopat).
Commitoi `remake`-repoomme viestillä, joka alkaa "Docs:". SUUNNITELMA.md on yksityiskohtainen
historia — pidä sen ja tämän tiedoston tiedot yhdenmukaisina.