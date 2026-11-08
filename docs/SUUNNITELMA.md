# Twilight: 2000 – uudelleenrakennus Godot 4:llä

Tavoite: rakentaa peli uudelleen modernilla moottorilla niin, että tehtävät, kaupungit,
hahmonluonti, esineet ja säännöt säilyvät, mutta käyttöliittymä ja pelattavuus päivitetään
nykyaikaan. Uusi grafiikka tehdään tekoälyllä alkuperäisiä kuvia lähtökohtana käyttäen.

> **Tekoälyagentti (LLM):** aloita tästä → `docs/AI_OHJE.md` (tila, säännöt, kuopat, tehtävälista).

Moottori: **Godot 4.4** (projektin `config/features`; ajettu 4.7.2-binäärillä, ks. luku 11). Valittu FOnlinen sijaan, koska peli
on yksinpeli: FOnline vaatisi palvelin–asiakasrakenteen myös yksinpeliin.

## 1. Pelin "atomit" – purun tila

| Atomi | Lähde | Tila | Tulos (`remake/assets_original/`) |
|---|---|---|---|
| Kuvakirjastot | GAMEDATA/*.LB, INTRO/INTRO.LB | **valmis**: 548 alkuperäiskuvaa + 277 `_rgba` = 825 PNG:tä (aluksi laskettu 494); purku varmistettu pelin omaa purkajaa vasten (0 eroa) | `graphics/<LIB>/*.png`, spriteistä `_rgba.png` |
| Yksittäiskuvat | ART/*.MCG | **valmis**: samaa kuvatietueformaattia | `graphics/ART/` |
| Taustat | ART/*.LBM (IFF PBM) | **valmis** | `graphics/ART/*.png` + paletti |
| Varjostustaulukot | ART/*.CM (32×256) | raakana | `graphics/ART/*.colormap.bin` |
| Paletit | pelin VGA-DAC ajon aikana | **valmis** (toimisto, CGEN, ICON, 2D päivä/yö, varikko) | `remake/palettes/` |
| Musiikki | *.CMF | **valmis**: renderöity omalla OPL2-syntetisaattorilla | `audio/music/*.wav` (6 kappaletta) |
| Äänitehosteet | *.VOC | **valmis** | `audio/sfx/*.wav` (25 kpl) |
| Tekstit | moduulien merkkijonot | **valmis**: 6296 merkkijonoa yhdeksässä moduulissa (TWI2D 1530, ICON 1616, CGEN 1516, OFFICE 846, …); 3108 oli ensimmäisen purun luku | `text/<MODUULI>.json` |
| Esinekuvaukset | EQUIP.TXT | **valmis**: 80 kuvausta | `text/EQUIP.json` |
| Esineet ja asearvot | ITEMS.DAT | **valmis**: 95 esinettä, ROF/vahinko/läpäisy/rekyyli/kantama | `data/items.json` |
| Kaupungit | TWI2D.EXE-taulukko | **valmis**: 56 kaupunkia, koordinaatit (1 yksikkö ≈ 1 m), koko 0–4, pohjapiirroksen osoitin | `data/cities.json` |
| Hahmonluonti | CGEN.EXE | **valmis**: maat, kansallisuudet, attribuutit, 52 taitoa, 33 kieltä, urat, arvot | `data/chargen.json` |
| Tallennukset | *.SVE | osittain: joukkueen sijainti (0x35ED) | `t2k-native/tools/save_move.py` |
| Valmiit joukkueet | SAVES/PLATOONS.SAV | purkamatta | – |
| Kaupunkien pohjapiirrokset | TWI2D (kokoluokittain) | purkamatta: osoittimet löytyneet | – |
| Tehtävälogiikka | ICON.EXE (radio), TWI2D.EXE (kaupungit) | tekstit purettu, logiikka purkamatta | – |
| 3D-ajoneuvot | TWI3D.EXE, TWIVCLS/TWIOBS/TWISHP.PIN | purkamatta | – |
| Fontti | GAMEDATA/FONT.LY | purkamatta | – |

Työkalut (`t2k-native/tools/`): `lb.py` (LB-formaatti), `extract_graphics.py`, `cmf2wav.c`,
`voc2wav.py`, `extract_text.py`, `extract_data.py`, `items.py`, `dis86.py` (x86-16-disassembler).
Alkuperäinen peli pyörii natiiviajoympäristössä (`t2k-native`), jonka avulla purettua dataa
voi verrata peliin (esim. `catchpic=MODULI;OFFSET` kaappaa pelin oman purkajan tuloksen).

### Havaintoja rakenteesta
- Hahmot ovat koottuja: pää (AFH0–14, 15 päätä × 7 suuntaa), vartalo (AM/AF/EM × 8 suuntaa,
  myös haavoittunut) ja jalat (L × 8 suuntaa, kävelyruudut). Viholliset (EM) ovat harmaapukuisia.
- Rakennukset ovat isometrisiä palasarjoja (seinät, ovet, katot) kirjastossa BUILDING.LB.
- Maastonäkymä on isometrinen 2:1-projektio, ja pohjoinen on vasemmalla ylhäällä. Valaistus vaihtelee vuorokauden mukaan.
- Kaupungit rakennetaan kokoluokan (0–4) mallista. Taulukon toinen osoitin on sama kaikilla saman kokoluokan kaupungeilla.

## 2. Uuden pelin rakenne (Godot)

```
remake/godot/
  project.godot
  original/        <- purettu aineisto (kuvat, äänet, data, tekstit)
  scenes/          vain main.tscn; näkymät rakennetaan koodissa (office.gd, chargen.gd,
                   briefing.gd, worldmap.gd, tactical.gd, battle_view.gd, motor_pool.gd)
  scripts/         pelilogiikka GDScriptillä, data JSONista
  tests/           automaattitestit (headless + kuvakaappaukset)
```

Säilytetään: kaupungit ja niiden sijainnit, tehtävätyypit ja -tekstit, hahmonluonti ja taidot,
esineet ja asearvot, osumakohtamalli, säteily, ruoka ja uni, ajoneuvot sekä toimisto- ja varikkorakenne.

Modernisoidaan:
- Yksi klikkaus riittää kaikkialla. Hiiren päällä näkyy vihje, ja oikea nappi peruu.
- Taktinen taistelu vuoropohjaisena (M5); alkuperäinen reaaliaikainen `combat.gd` on legacy eikä peli käytä sitä.
- Kartta on samassa suunnassa kuin maasto, ja matkustus kartalta valitsemalla (nopeutus maaseudulla).
- Pöytäroolipelin säännöt valinnaisina (ks. `t2k-native/docs/SAANNOT_VERTAILU.md`): tähdätty laukaus,
  coolness under fire, kaatuminen ja kokemuspisteet.
- Tasapainotus: kranaattien sirpaleet, M2HB:n läpäisy ja käyttämättömille taidoille käyttö.
- Tallennus kartalla, toimistossa ja kaupungissa (F5/F9) sekä automaattitallennus kartalle palatessa; ei kesken taistelun eikä sisätilassa.

## 3. Tekoälygrafiikka
SDXL base 1.0 (malli Pinokion SD WebUI -kansiosta) ajetaan suoraan diffusersilla RTX 4070 Ti:llä.
WebUI:n omassa venvissä ei ole torchia, joten työkalulla on oma venv `remake/tools/.venv_ai`.
Se käyttää koneen valmista CUDA-torchia .pth-linkin kautta (C:\coloring111\venv) ja asentaa itse vain
diffusers-, transformers- ja accelerate-paketit.
Työkalu: `remake/tools/ai_remaster.py IN.png OUT --prompt "..." --denoise 0.35 --refine 0.25`

1. Alkuperäinen kuva skaalataan ×4 bikuubisesti ja sitä sumennetaan hieman. Ilman sumennusta malli
   kopioi 320×200-pikseliruudukon.
2. Ensimmäinen img2img-ajo tehdään denoise-arvolla 0,35 ja toinen terävöittävä ajo arvolla 0,25.
   Kokeillut arvot:
   - 0,30 terävällä pohjalla: ruudukko jää näkyviin.
   - 0,45: yksityiskohtia katoaa (muotokuva ja radio).
   - 0,35 + 0,25: sommittelu pysyy pikselintarkasti, joten klikattavat alueet osuvat edelleen.
3. Kehotteessa on tyylilause ja jokaisen kuvassa näkyvän esineen nimi. Nimeämättömät esineet
   (esim. radio) muuttuvat helposti joksikin muuksi.
4. Spriteille alkuperäinen läpinäkyvyysmaski skaalataan ja sovitetaan (`_rgba.png`).
5. Vertailukuva (`*_compare.png`, alkuperäinen ja uusi rinnakkain) tarkistetaan ennen kuin kuva
   kopioidaan kansioon `godot/remastered/<LIB>/`.

Godot valitsee kuvan funktiolla `main.art(lib, name)`: remaster vain jos `remastered`-lippu on päällä – ja lippu kytkeytyy vain F2:sta, joka on pois päältä, joten peli käyttää **aina alkuperäistä** grafiikkaa.
`F2`-vaihto on koodattu mutta **pois päältä** (`main.gd`: `ALLOW_AI_ART = false` – käyttäjän päätös 24.10.2026).
Erätyökalu `remake/tools/remaster_set.py briefing | sprites [legs torsos heads]`:
- **Briefing (ICON/MOUTH0 sekä MOUTH1–6 ja SCREEN1–6).**
  - Kuva maalataan 6×-koossa ja tallennetaan 4×-kokoisena.
  - RESTRICTED-kyltti kopioidaan alkuperäisestä, koska tekoäly sotkee tekstin.
  - Animaatioruudut liitetään peruskuvaan ja koko kuva maalataan samalla siemenluvulla.
    Ruudun alue leikataan pehmeäreunaisena, joten suun ja päätteen animaatiot sopivat
    uuteen peruskuvaan.
- **Sotilaiden osat (ANIMS, 60 nauhaa).**
  - Nauhat pakataan yhteisille arkeille (jalat, vartalot, päät), jotta tyyli on yhtenäinen.
  - Pikkuspriteillä sumennus tuhosi yksityiskohdat ("pikselimössöä"). Siksi ne suurennetaan
    ensin Scale2x-algoritmilla (EPX) kahdesti.
  - Asetukset: denoise 0,3 ja refine 0,15.
  - Maski: pehmeä bikuubinen maski yhdistettynä alkuperäiseen.
  - Kokonaan läpinäkyvät sarakkeet pidetään paikallaan, jotta soldier.gd:n ruutujako ei muutu.
  - Godot piirtää ne mipmap-suodatuksella.
- Muistiraja: VAE tiling ja noin 1 Mpx:n arkit. Yli 1,2 Mpx:n kuvat valuivat jaettuun muistiin
  ja hidastuivat noin kymmenkertaisesti.

- Värit sovitetaan alkuperäiseen ruutu kerrallaan (kanavien keskiarvo ja hajonta). Yhteisellä
  arkilla viereisen nauhan väri saattoi vuotaa yhteen ruutuun: AFW harmaantui EM-vartaloiden vieressä.
- `--recut` leikkaa nauhat uudelleen tallennetuista arkeista ilman GPU:ta.
- GPU:n jakaminen toisen ohjelman kanssa (esim. BW2COLOR) hidastaa SDXL:ää moninkertaisesti.

Spritejen rakenne (korjattu soldier.gd:hen):
- Päänauhassa on 8 päätä DIRS-järjestyksessä (N, NE, E, SE, S, SW, W, NW), kukin 8 px korkea.
  Nauha alkaa yhden rivin verran ensimmäisen pään sisältä, joten korkeus on 63 px.
- Vartalo- ja jalkanauhoissa osa ruuduista koskettaa toisiaan. Liian leveä yhtenäinen alue
  jaetaan tasan tyypillisen ruutuleveyden mukaan.
- AF-vartaloita ei ole suunnille N, NE ja NW, joten käytetään AM-vartaloita.
- Sotilaat piirretään 3×-koossa. Testi `--test=soldiers` piirtää kaikki suunnat ja vartalotyypit.

Kirjastokohtaiset ratkaisut (`remaster_set.py faces | cgen [TANK] | buildings [ryhmä]`):
- **FACES (30 muotokuvaa).**
  - Muotokuva-alue on 240×129 px: 5×3 kasvoa, kukin 48×43 px.
  - Käsittely tehdään Scale2x-tilassa: 6×-koko, denoise 0,3, refine 0,15. Värit sovitetaan
    kasvo kerrallaan.
  - Sumennustila hävitti piirteet (sikari, irvistys) ja toi naisille glamour-meikin.
    Naisten kehotteeseen lisättiin "natural faces, no make-up".
- **CGEN.**
  - TANK (mustavalkokuva) tehdään kevyesti: denoise 0,22, refine 0,12.
  - BASE, JOY1, JOY2 ja OBJWALL tehdään yhdellä arkilla. Läpinäkyvyys otetaan magentasta
    avainväristä, koska `_rgba`-versiota ei ole.
  - Punaiset viivakuvakkeet (CAR*, ICONS), BODY ja FLAGS jätetään alkuperäisiksi, koska ne ovat symboleja.
- **BUILDING (83 palaa, noin 62 000 alkuperäistä pikseliä arkkia kohden).**
  - Ryhmät:
    - ulko: 8
    - sisä: 38 (IN/IE/IS/IW = sisätilat ilmansuunnittain, I0–I5)
    - maasto: 12 (FO/PO/SO/WO)
    - ajoneuvot: 16
  - Ajoneuvot: V = ehjä, CV/DV = muunnelmat ja romut. Niille kehote "no markings", koska malli
    keksi vaunuun tunnuksen "09".
  - Tiet (9 kpl, *ROAD*) tehdään pelkällä Scale2x ×2:lla. Tekoäly hävitti ohuet reunakivet
    taustaväriin, eikä tasaiseen palaan saa siitä mitään lisää.
  - Symbolit (ARROWS, BOX, COMPASS, ICON, INFRARED) jätetään alkuperäisiksi.
- Ajoaika Varitan (BW2COLOR) jakaessa GPU:n: koko BUILDING noin 1,5 h. Vapaalla GPU:lla arviolta
  noin 25 min.
- Huom: Python-muokkausskriptit kirjoitetaan aina `encoding="utf-8"`-asetuksella. Windowsin
  oletus (cp1252) sotki tämän dokumentin kerran.

Tila: valmiina ovat OFFICE (2), briefing/ICON (13), ANIMS (60), FACES (2 arkkia, 30 kasvoa), CGEN (5), BUILDING (83), ART (48) ja CMBT (81) (`remake/assets_ai`).
Kansiossa `godot/remastered/` on 658 tiedostoa (noin 71,5 Mt). CGEN, FACES ja BUILDING otetaan
käyttöön, kun hahmonluonti (M2) ja kaupungit (M3) rakennetaan. `main.art()` löytää ne automaattisesti.
Testi kuvaa tilat; F2-vertailu on pois päältä (ks. yllä).

- **INTRO (198 kuvaa, M7 – AJO MAHDOLLINEN):** `remaster_set.py intro [N]` (lisätty 7.11.) maalaa ruudut 4×-koossa (denoise 0,3 / refine 0,15, kiinteä siemen), jo maalatut ohitetaan ja `N` pysäyttää N uuden jälkeen. Kansiossa `godot/remastered/INTRO` on vielä 0/198 (aiempi yritys katkesi, tuotokset eivät tallentuneet). Ajo: `python tools/remaster_set.py intro` (vaatii `.venv_ai`-ympäristön ja CUDA-GPU:n). Tekstiruudut saavat mallin oman kirjainasun. Mallitiedosto sd_xl_base_1.0.safetensors puuttuu Pinokion WebUI:n models-kansiosta (todettu 7.11.2026: kansio tyhjä) – se on ladattava uudelleen ennen ajoa.

## 4. Etenemissuunnitelma
1. **M1 Pystyleike:** toimisto (alkuperäinen kuva, klikattavat kohteet), radio-briefing
   tekstidatasta, siirtyminen maastoon, 4 sotilaan joukkue, liikkuminen, kartta oikeassa suunnassa
   ja Skawinaan saapuminen. Automaattitesti ottaa kuvat.
2. **M2 Hahmonluonti – VALMIS (perusversio).** Tiedostot: `scripts/chargen.gd` (näkymä),
   `scripts/chargen_rules.gd` (säännöt) ja `data/careers.json` (data).
   - **Manuaalin mukaan:**
     - Attribuutit 1–10: joko 32 pistettä jaettavaksi tai satunnaisesti.
     - Neljä taustataitoa tasolle +2.
     - Äidinkieli +10.
     - Neljän vuoden kaudet: koulutus, siviili tai neljä puolustushaaraa.
     - Pääsyvaatimukset: attribuutit, summat, taidot ja tutkinnot (ROTC, OCS = INT ja EDU 7+, akatemia).
     - Puolitason sääntö: kun taito ylittää hallitsevan attribuutin, uusi taso lasketaan puolikkaana.
     - Peruskoulutus ja sivuharrastukset.
     - Sodan arvonta kauden jälkeen: 1D10 ≤ palvellut kaudet. Sen jälkeen yksi kausi tulen alla.
       Agent ja Politician jatkavat virassaan, Doctor, Civil Engineer ja Commercial Pilot saavat
       suoran upseerinarvon.
     - Ikä 17 + 4 × kaudet.
     - Initiative 1–7.
     - Osumanumerot ×2, ×1, ×½ ja ×¼.
   - **Remaken suunnittelemaa:** alkuperäiset taulukot ovat CGEN.EXE:n koodissa eivätkä vielä purettuja.
     - Urakohtaiset taitolistat ja taitomäärät kautta kohden (3–6).
     - Ylennysheitto: 1D10 + (INT + CHA)/4 ≥ 8.
     - Ikääntyminen 37 vuoden iästä alkaen.
     - Toinen kieli tasolle 4 (manuaali ei kerro tasoa).
     - Kuorma 2 × (STR + CON) kg.
     - Heittomatka 4 × STR m.
     - Osumakestävyys: pää 2 × CON, rinta 3 × (STR + CON), muut 2 × (STR + CON). Kaava on
       sovitettu PC-pelin arvoihin 14/45/30.
   - **Nykyaikaistukset:**
     - Suljettu ura kertoo syyn.
     - Esikatselu näyttää, miten taidot muuttuvat kauden aikana.
     - AUTO jakaa pisteet ja BACK peruu kauden.
     - Satunnainen värvätty yhdellä klikkauksella.
     - Joukkueen tallennus ja lataus (`user://squad.json`).
     - Johtajan valinta: Exor 1 kutsuu johtajaa nimeltä.
     - F2 vaihtaa grafiikan paikallaan ilman, että tila katoaa.
   - **Muotokuva ja kenttäsprite:**
     - Alkuperäinen ei yhdistä niitä indeksin perusteella.
     - `tools/face_heads.py` valitsee oletussuunnan värin perusteella. Ensin molemmat sarjat
       normalisoidaan, koska paletit poikkeavat toisistaan, ja sitten päät jaetaan yksi kullekin.
     - Pelaaja voi vaihtaa spriten ‹ ›-painikkeilla.
     - Miesten selkeät tunnusmerkit osuvat (valkoinen tukka, punainen baretti, vaalea tukka).
       Mustatukkaiset ja naisten pienet päät ovat epävarmoja.
   - **Testit:**
     - `-s tests/test_chargen_rules.gd`: 300 satunnaista värvättyä, invariantit ja manuaalin
       puolitasoesimerkki. Tulos PASS.
     - `--test=chargen`: koko kulku kuvina, kaksi satunnaista ja yksi käsin tehty värvätty.
       Johtajaksi valitaan ANNA, minkä jälkeen briefing alkaa "ANNA, THIS IS EXOR 1".
       Maastossa näkyy kolme sotilasta.
   - **Puuttuu:** varusteiden osto rahalla (vaihe 13) ja kontaktit. Toimiston arkistokaappiin
     tarvitaan vielä joukkueen kokoonpano.
3. **M3 Kaupungit – perusversio VALMIS.**
   - **Pohjapiirrokset puretaan TWI2D:stä** (`tools/extract_city_templates.py` →
     `data/city_templates.json`).
     - Jokainen kokoluokka (0–4) on lista 7 tavun tietueita: `tyyppi, suunta, 0, dx i16, dy i16`.
       Lista päättyy arvoon 0xFF.
     - Tyyppijärjestys tulee exen nimitaulukosta: HOUSE, TAVERN, MARKET, JAIL, HOSPITAL, BANK,
       FACTORY, BARN, CHURCH.
     - Suunnat ovat sisäkuvien järjestyksessä S, W, N, E (ISHOUSE, IWHOUSE, INHOUSE, IEHOUSE).
     - Rakennusmäärät: 18, 12, 8, 7 ja 7.
     - Kokoluokka ei vastaa todellista kokoa: Krakova on luokkaa 3 (seitsemän taloa).
     - dx/dy tulkitaan metreiksi itään ja etelään kaupungin pisteestä.
   - **Rakennukset koostetaan** BUILDING-rakennussarjoista (`tools/compose_buildings.py` →
     `BUILDING/composed/<TYYPPI>_<suunta>.png` ja `data/buildings.json`).
     - Sarjat ovat valmiiksi isometrisiä palasia mittakaavassa K = 12 px/m: V-kulmat oville ja
       ikkunoille, Λ-seinäkuviot, kattosuikaleet ja lattialaatat.
     - Alkuperäisen leikkaustaulukkoa ei löytynyt, joten suorakulmiot on mitattu käsin.
     - Seinä- ja kattokuvio kaakeloidaan julkisivun suuntaisesti vinoutettuna. Ovi tulee
       templaatin suunnan puolelle, ikkunat muille segmenteille.
     - Ovi ja ikkuna otetaan V-palan oikeasta puolikkaasta, koska peilaus kääntäisi BANK-kyltin.
     - BARN käyttää TAVERNin puusarjaa, koska omaa sarjaa ei ole.
   - **Pelissä** (`scripts/town.gd`, `tactical.gd`):
     - Rakennukset järjestetään syvyyden mukaan sotilaiden kanssa (pohjan keskipiste).
     - Seinät estävät liikkumisen, ja seinän kohdalla väistetään 30° askelin.
     - Rakennuksen klikkaus vie ovelle ja sisään: paneeli, jossa sisäkuvan kalusteet ja kuvaus.
     - Hiiren rulla zoomaa (0,35–1,5, oletus 0,6).
   - **Korjattiin samalla:**
     - Maastonäkymän mittakaava K = 36 (3×), joka sopii sotilaisiin ja rakennussarjoihin.
     - Leikkauskuvien avainväri on nyt reunojen yleisin väri. Vasen yläkulma pettää, kun pala
       koskettaa kulmaa, ja BUILDING-kuvista jäi sininen tausta.
   - **Testi:** `--test=city`. Krakova rakennetaan, ryhmä kävelee lähimmälle ovelle, käy sisällä,
     tulee ulos, kiertää talon ja matkustaa Skawinaan.
   - **Sisätilat – VALMIS** (`tools/compose_rooms.py` → `BUILDING/rooms/`, `data/rooms.json`,
     `scripts/interior.gd`).
     - Sisäkuvat IS/IW/IN/IE + tyyppi sisältävät saman kalustuksen neljässä kierrossa (oven suunta).
       Kalusteet ovat erillisiä saarekkeita, ja ne leikataan yhtenäisinä alueina.
       I0–I5 eivät ole sisätiloja vaan metsästys- ja kalastuskuvia.
     - Huone on rakennuksen pohjan kokoinen. Lattia ladotaan ulkosarjan lattialaatasta
       vinoneliöinä. Takaseinät (pohjoinen ja itä, Λ-muoto) täytetään ulkoseinien kuvioilla.
     - Kalusteiden sijoittelu:
       - Seisovat kalusteet takaseinille.
       - Suurin matto keskelle.
       - Oven edustalle jätetään 2,5 m vapaata.
       - Matot ovat kävelyalustaa. Ovet ja korkeat kapeat palat jätetään pois.
     - Pelissä maastonäkymä jäätyy taustalle. Ryhmä kävelee ovesta sisään ja kiertää kalusteet,
       ja kalusteet ja sotilaat piirtyvät oikeassa syvyysjärjestyksessä. Ovelle kävely
       (tai Esc) palauttaa ryhmän ulos oven eteen.
     - BARN käyttää talon kalustusta, koska omaa sarjaa ei ole.
     - Testit: `--test=rooms` kuvaa kaikki yhdeksän tyyppiä kahdella ovisuunnalla, ja
       `--test=city` käy talossa sisällä.
   - **Puuttui (tehty myöhemmin):**
     - ~~Asukkaat ja dialogit~~ **tehty M4:ssä** (`townsfolk.gd`, `talk_scene.gd`).
     - ~~Kadut ja kaupunkien omat tiet~~ maailmankartan tiet tehty M6:ssa (`World.DRIVE`, tie 50 km/h); kaupungin sisäiset kadut yhä suoria.
   - **24.10.2026: käyttäjä päätti, että uusi (tekoäly)grafiikka unohdetaan toistaiseksi.**
     Peli käynnistyy alkuperäisellä grafiikalla. AI-kuvat ovat tallessa kansiossa
     `godot/remastered/`, ja F2 on koodattu vertailuun mutta pois päältä (`ALLOW_AI_ART = false`).
4. **M4 Tehtävät – perusversio VALMIS.** Tiedostot: `tools/build_missions.py` → `data/missions.json`,
   `scripts/campaign.gd`, `townsfolk.gd`, `dialog.gd` ja `tactical.gd`.
   - **Tekstit tulevat suoraan alkuperäisestä:**
     - ICON: radiotiedotteet paloina, joiden väliin peli tulostaa nimet. Pohjat on kirjattu
       offset-listoina, joten mitään ei kirjoitettu käsin.
     - TWI2D: kaupunginjohtajan avaus (palkinnon kanssa), kolme muistutusta ja kiitos.
     - Listat: 12 tehtävätyyppiä, 2–4 tiedoteversiota kutakin, 12 Exorin tarinaviestiä, 9 tautia,
       tavarat, alueet ja ajoneuvot.
     - Tehtäväesineet ovat ITEMS-listalla: CRATE / LARGE CRATE OF SUPPLIES, SPY PAPERS ja
       HOSTAGE PAPERS.
   - **Pelattavat tyypit:** aluksi 10 (supplies, spy, hostage, assassins, wounded, epidemic, exile,
     dump, defend, liberate); M5/M6 toivat tank- ja vehicle-tehtävät, yhteensä 12.
   - **Tehtävän kulku:**
     - Radio antaa tehtävän, ja ensimmäiset kohteet ovat lähellä Krakovaa (etäisyys kasvaa).
     - Johtaja odottaa kaupungin keskustassa ("IS WAITING FOR YOU IN THE CENTER OF TOWN").
     - Vaiheita ovat esimerkiksi talk, clear, treat, spy, search ja reach.
     - Palkinto menee Krakovan varastoon. Joka toisen tehtävän jälkeen jonoon tulee tarinaviesti.
   - **Ihmiset:**
     - Johtaja, kävelevät asukkaat ja tehtävän mukaan epäillyt (5), haavoittuneet tai sairaat
       (punainen +) sekä Black Legion -sotilaat.
     - Ihminen syntyy, kun ryhmä tulee 250 m:n päähän kaupungista.
   - **Taidot käytössä:**
     - Language: asukkaat puhuvat puolaa ja johtajat myös venäjää ja englantia. Jos kukaan ei
       osaa, näytetään alkuperäinen "…NOBODY BACK AT HQ WHO CAN TRANSLATE".
     - Interrogation: alkuperäiset vakoojarepliikit.
     - Medical: hoito.
     - Rifle: väliaikainen tulitaistelu.
   - **Väliaikainen tulitaistelu (M5 korvaa):**
     - Paras ampuja vastaan yksi vihollinen, kierroksittain.
     - Osumat kertyvät värvätyn haavoihin. Kun haavat ylittävät rinnan kestävyyden, värvätty kaatuu.
     - Jos koko ryhmä kaatuu, se kannetaan Krakovaan.
     - Krakovan lääkintämiehet parantavat haavat.
   - **Korjattiin samalla:**
     - Maailman koordinaatit ovat ~260 000 m, ja 32-bittinen Vector2 erottaa vain noin 3 cm.
       Askel ruutua kohden on 2,7 cm, joten ryhmä ajautui ja jumittui. Sijainti on nyt 64-bittinen
       (pa, pb), piirto tapahtuu suhteessa siihen, ja asukkaat liikkuvat pieninä siirtyminä.
       Aiemmin pyöristys oli myös nopeuttanut kävelyä.
     - Testien aikana todellinen hiiri ja näppäimistö ohitetaan (`main.input_ok`). Ikkuna on
       työpöydällä, ja välilyönti oli pysäyttänyt testin.
   - **Testit:**
     - `-s tests/test_campaign.gd` vie kaikki 12 tyyppiä läpi logiikkatasolla ja tarkistaa,
       ettei teksteihin jää paikkamerkkejä.
     - `--test=mission` pelaa kentällä supplies-, assassins-, wounded- ja spy-tehtävät:
       tiedote, johtaja, työ ja palkinto.
   - **Puuttuu:**
     - ~~Krakovan resurssinäkymä (computer)~~ **tehty 7.11.:** `computer.gd` – FUNDS, SQUAD/VEHICLE, MOTOR POOL, STORE ROOM, SQUAD STATUS; CLOSE tai Esc palaa toimistoon.
     - Tallennus.
     - Rekka-vaatimus (M6).
     - Oikea taistelu (M5).
     - ~~Aikarajat~~ **tehty 3.11.:** wounded- ja epidemic-tehtävissä potilaat (3–5) ovat olemassa
       tiedotteesta lähtien, ja kello käy (`Campaign.tick`, `sick_times`). Armonaika on marssi
       Krakovasta (20 min/km linnuntietä) + 8 h, sen jälkeen yksi hoitamaton kuolee 6 h (wounded) /
       8 h (epidemic) välein. Jos yli puolet kuolee, johtaja sanoo alkuperäisen "TOO MANY OF THE
       CITIZENS OF THIS COMMUNITY HAVE DIED" eikä anna palkintoa (tehtävä päättyy, ei lasketa
       suoritetuksi). STORY: armonaika ×1,5, väli ×2. Alkuperäisen ajastuksia ei ole purettu, joten
       luvut ovat remaken arvioita. Kentällä kuollut potilas poistuu ("THE PATIENT DIED BEFORE…").
       Testi: `test_campaign.gd` (ajoissa / myöhässä molemmissa moodeissa) ja
       `--test=mission --types=wounded,epidemic`.
5. **M5 Taistelu – VALMIS (vuoropohjainen).** Alkuperäisen katsottavat kierrokset ja 3D-panssarisimulaattori
   on korvattu yhdellä vuoropohjaisella taistelulla.
   - **Tiedostot:** `scripts/battle.gd` (logiikka ilman grafiikkaa), `battle_view.gd` (näkymä),
     `forces.gd` (varusteet, vihollisryhmät, sijoittelu), `healing.gd`, `data/vehicles.json`
     ja `tests/test_battle.gd`.
   - **Kenttä:** 2 m:n ruudukko maastosarjan ruuduista. Puunrungot ja talojen seinät estävät
     liikkeen ja näkyvyyden. Pensaat peittävät (−10 %), runko tai seinä edessä antaa raskaan
     suojan (−35 %, jalat ja vatsa piilossa).
   - **Vuorot:** initiatiivi ja ketteryys, tasatilanteessa noppa. Jokaisella yksiköllä on 10 AP:
     - liike 1/ruutu, kyykyssä 2, maaten 4
     - kylmä laukaus 3, tähdätty 5, sarja 4
     - kranaatti 4, lataus 3, asento 1, ensiapu 6.
   - **Aseet** ovat ITEMS.DAT:n arvoista:
     - vahinko D6:ina
     - läpäisy etäisyysluokittain
     - kantama manuaalin mukaan: lyhyt / ×2 / ×4 / ×8.
   - **Osuma:** 20 + 7 × taito + 2 × AGL %, ja siihen etäisyys-, asento-, suoja-, tähtäys-
     ja haavamuutokset.
   - **Osumakohdat (d10)** ovat hahmolomakkeen kestävyyksiä vastaan:
     - Kevyt, vakava tai kriittinen osuma; vakava tai kriittinen aloittaa verenvuodon.
     - Pää tai rinta kestävyyden yli tarkoittaa kuolemaa, vatsa kaatumista.
     - Kova osuma (≥ CON + 3) kaataa (pöytäroolipelin knock-down).
     - Verenhukka: 3 × CON kaataa, 5 × CON tappaa (alkuperäinen "BECAUSE OF SEVERE BLOOD LOSS…").
   - **Panssarit:** kevlarliivi AV 2, kypärä 3, sirpaleliivi 1. Ne vähentävät luotien vahinkoa
     määrällä (AV − läpäisy) × 2 ja pysäyttävät sirpaleen, jos sen vahinko ≤ 3 × AV.
   - **Kranaatit:**
     - Tarkkuus riippuu heittotaidosta; ohi mennyt kranaatti poikkeaa 1–3 ruutua.
     - Paineaalto 3 m:n säteellä.
     - Sirpaleita enintään 1D3 henkeä kohden (tasapainotus, jotta kranaatti ei pyyhi ryhmää).
     - Maassa makaaminen tai suoja puolittaa osumatodennäköisyyden.
   - **Ajoneuvot** (manuaalin taulukko: HMMWV, 2 1/2 t, M2A2, M1A1, M1A2, T-72, T-80, T-90):
     - Panssari määräytyy suunnan (etu, sivu, taka) ja rungon tai tornin mukaan; Sp = kaksinkertainen
       HEAT-ammuksia vastaan, Cp = ×1,2 tai ×2.
     - Läpäisy ja ylimääräinen energia vaurioittavat miehistöä, moottoria, polttoainetta, tykkiä,
       tornia tai ammuksia; ammukset voivat räjähtää.
     - Pyöriin osuu myös pienaseilla.
     - Miehistö pelastautuu ulos pistoolein.
     - Ryhmä voi ajaa omalla ajoneuvollaan, jolloin miehistön taidot ovat käytössä.
     - Pääaseiden läpäisy on remaken arvio 2. painoksen asteikolla (manuaali ei kerro sitä).
   - **Sijoittelu:**
     - Ryhmä asettuu riviin vihollista kohti, kukin parhaaseen suojaan, kyykkyyn.
     - Pelaaja voi siirtää ketä tahansa enintään 10 ruudun päähän lähimmästä ryhmätoverista,
       mutta ei 6 ruutua lähemmäs vihollista.
   - **Tekoäly:** ensiapu vieressä vuotavalle, paras laukaus ja tapa (todennäköisyys × vahinko),
     raketit ajoneuvoja vastaan, kranaatti ryhmään, siirtyminen suojaan ja ampumaetäisyydelle
     sekä pakeneminen moraalin pettäessä.
   - **Taistelun jälkeen:**
     - Lääkintämies hoitaa vuotajat; ellei kukaan pysty, haavoittunut kuolee.
     - Kaatuneet siirtyvät `main.fallen`-listaan.
     - Jos koko ryhmä kuolee, peli päättyy ja aloitetaan uudella ryhmällä.
   - **Kehitys:** jokaisesta onnistumisesta saa kokemuspisteen asianomaiseen taitoon, tapoista
     kaksi. Kun pisteitä on 3 + taso, taito nousee hahmonluonnin puolitason säännöllä.
   - **Paraneminen** (R maailmankartalla, 8 h): CON/3 pistettä kohtaa kohden. Onnistunut
     lääkintä kaksinkertaistaa, kaupungin sänky kolminkertaistaa ja Krakovan lääkärit parantavat
     kaiken.
   - **Testit:**
     - `test_battle.gd`, satoja tekoälytaisteluja:
       - marodöörit: ryhmä voittaa 88 %
       - Black Legion: ryhmä voittaa 58 %, noin 2 kaatunutta taistelua kohden (pelaaja voi
         pelata varovaisemmin)
       - kranaatti 4 miehen ryhmään tappaa keskimäärin 0,1, liivien kanssa 0,07
       - M1A1 voittaa T-72:n edestä 75 %, ja T-72 voittaa sivusta ampuen 56 %
       - kaksi LAWia T-72:n kylkeen 96 %, kivääri tuhoaa HMMWV:n.
     - `--test=battle`: sijoittelu, siirto (sekä luvallinen että kielletty), taistelu, yhteenveto,
       lepo ja panssaritaistelu.
   - **Lisäykset 28.10.–3.11.2026:**
     - **Pelimoodit:** NORMAL ja STORY valitaan värväyksessä (tallentuu joukkuetiedostoon).
       - STORY: ryhmän osumatodennäköisyys ×1,2 ja vihollisen ×0,8.
       - Pään tai rinnan "tappava" osuma tainnuttaa, ellei vahinko ole yli kaksinkertainen.
       - Verenhukka ei tapa, ja haavat sidotaan taistelun jälkeen.
       - Tajuton herää taistelun jälkeen 50 % kunnossa: mikään kehonosa ei ole yli puolen
         kestostaan, verenhukka on enintään puolet tappavasta ja vuoto tyrehtyy (3.11.).
       - Lepo parantaa kaksinkertaisesti.
       - Automaattitaisteluissa kaatuneita noin 90 % vähemmän.
       - NORMAL: Black Legionin partiot ovat 2–4 miestä (kaupungin varuskunta skaalautuu ryhmän koon mukaan, M9/luku 9), ja Krakova antaa täydennysmiehiä kaatuneiden
         tilalle (toimistossa).
     - **Puut:** raskas telaketjuajoneuvo (≥ 20 t) ajaa puiden läpi ja kaataa ne (myös rungon
       vierestä). Kaatunut latvus on pensas-suojaa. Pyöräajoneuvot kiertävät puut.
     - **Kraaterit:**
       - Kranaatti tekee kuopan (1).
       - Raketti, ohjus ja panssarikranaatti tekevät kraaterin (2), jonka ympärille jää kuoppamaata. Iso
         räjähdys kaataa puun.
       - Telat ylittävät kaiken, mutta hitaasti (×2 / ×3). Pyörät ylittävät vain kuopat (×2,5) ja
         kiertävät kraaterit.
       - Kyykyssä tai maassa makaava mies saa kraaterista suojaa.
     - **Näkymä:**
       - Räjähdyksessä on alkuperäinen CMBT/EXPLOD-tulipallo (3 ruutua), savu, sinkoutuva maa ja
         kameran tärähdys.
       - Kraaterit piirretään maahan.
       - Kaatuva puu kaatuu kyljelleen ja kanto litistyy.
       - `--test=boom` näyttää tämän.
     - **Grafiikkakorjaukset:**
       - Tasakattoisista rakennuksista puuttui katon takalape, ja länsiseinä "leijui"
         (`compose_buildings.py`).
       - Maata piirretään koko näkyvälle alueelle zoomattaessa.
       - Checiny sai kaupunkipohjan.
       - Sotilaiden vyötärön rako on korjattu: torso asetetaan vyön päälle.
       - Jalkojen kävelyruudut leikataan oikein (`tools/split_leg_frames.py` → `ANIMS/cells/`).
     - `--test=towns` kuvaa jokaisen kokoluokan kaupungin.
     - **Sisätilat:**
       - Kamera sovittaa huoneen ruutuun, joten huone näkyy 1–2,6 kertaa aiempaa isompana.
       - Rakennuksissa on asukkaita: talo 2, taverna 3, tori 2, muut 1, lato 0.
       - Henkilön klikkaus avaa keskustelunäkymän (`talk_scene.gd`): taustalla huoneen kuva ilman
         henkilöitä ja himmennettynä, johtaja ja puhekumppani isoina, vastaukset ylälaatikossa ja
         valinnat (taito + %) alalaatikossa.
       - Logiikka on sama kuin ulkona (`tactical.interact`). `--test=city` kuvaa keskustelun.
     - **Kaikki 12 tehtävätyyppiä pelattavissa:**
       - **tank:** johtaja → Black Legionin T-72/T-80 kaupungissa (näkyy kartalla vaununa) →
         taistelu (vaunu ja 3 jalkaväkeä, M9) → johtaja. Vaihe valmistuu, kun vaunu on tuhottu.
       - **vehicle:** romuttunut T-90 tai HMMWV kaupungin laidalla. Ensin romunkerääjät (marodöörit; M9: ryhmän koko + 1…2),
         sitten Mechanic-korjaus (2 h). Ajoneuvo menee Krakovan varikolle
         (`campaign.motor_pool`), ja seuraavalla toimistokäynnillä ryhmä ottaa sen mukaan taisteluihin.
       - **dump:** etsintävaihetta ei ollut kytketty rakennuksiin. Nyt rakennukseen meneminen etsii
         laatikot (`tactical._search`).
       - `--test=mission` pelaa kaikki 12 tyyppiä kentällä (story-moodissa).
       - **Panssarivaunutaistelun korjaukset (testeistä):**
         - Tekoäly ei käyttänyt sinkoja, koska ITEMS.DATin damage on 0 ja taistelukärki on damage_c.
         - Ajoneuvon jokainen ase ampuu kerran vuorossa.
         - Singot varataan panssariajoneuvoille.
         - Singon kantaja kiertää vaunun kylkeen useamman vuoron aikana (kylkipanssari 16 vs. etupanssari 100).
         - Story-moodissa tainnutettu ei enää ole "kuollut" seuraavassa taistelussa.
         - Story-moodissa vihollisvaunujen miehistö on kokemattomampi (taito 2).
         - Tank-tehtävässä Krakova antaa LAW 80:n jokaiselle, jolla ei ole heitintä.
       - **Tulos (T-72 ja 2 jalkaväkeä, satunnainen ryhmä):** ryhmä voittaa noin 50 % (normaali) ja noin 65 % (story); M9:n kolmella escortilla 57 % / 80 % (luku 9).
         Ryhmä, jossa ei ole Heavy Weapons -osaajia, voittaa 20–30 %: panssarivaunu vaatii
         panssarintorjujan tai oman vaunun.
     - **Puhuvat päät:**
       - Alkuperäisessä on päät vain värvätyille (FACES), Exor 1:lle (MOUTH0–6) ja Czarnylle.
       - `tools/make_portraits.py` tekee kaupunkilaiset värvättyjen kasvoista:
         - siviilivaatteet neljässä värissä
         - johtajalle tumma puku
         - potilaalle pääside
         - kypärä- ja maastokasvot jätetään pois.
       - Jokaisella on avoimen suun ruutu.
       - Keskustelulaatikossa näkyy puhujan pää (Exor, värvätty nimen mukaan tai puhekumppani), ja suu
         liikkuu tekstin tulostuessa (`portraits.gd`, `dialog.gd`, `talk_scene.gd`).
     - **Lisäykset 7.11.2026 (animaatiot ja tulitus):**
       - Tulitusasento: ampuva sotilas vaihtaa 0,5 s:n ajaksi CMBT-tulitusasentoon aseen mukaan
         (HG/SMG/PISTOL/BAZOOK/PUNCH; vihollisilla omat EHG/ESMG/EPISTE-sarjat).
       - Kulmakuvat: kun ammutaan, ampujan muotokuva näkyy vasemmassa yläkulmassa ja kohteen
         oikeassa (1,2 s). Rekryllä on oikea keskustelumuotokuva, vihollisella kenttäpää kameran suuntaan.
       - Astuntapomppu: kävellessä keho pomppii 1,2 px kaksi kertaa askelsyklin aikana.
       - Katoamisen korjaus: kenttä- ja huonenäkymässä rakennus/kaluste haalistuu (45 %), kun
         sotilas on sen takana – yksikään asento ei enää katoa taiteen taakse (sama keino kuin
         taistelun puissa).
     - **Tallennus (3.11.):** F5 pikatallentaa maailmankartalla, toimistossa tai kaupungissa (ei
       taistelussa eikä sisällä), F9 lataa. Automaattitallennus aina kartalle palatessa. Värväysruudussa
       CONTINUE (AUTOSAVE) ja LOAD QUICKSAVE. Kaupungissa tehty tallennus jatkuu samasta kaupungista.
       Testi `--test=save` tallentaa, sotkee koko tilan ja tarkistaa, että lataus palauttaa sen (testit
       käyttävät `user://tests/`-polkuja, pelaajan omat tallennukset jäävät rauhaan).
     - **Sisätaistelu (3.11.):** hostage- ja assassins-tehtävien viholliset (2–4, pieni solu)
       piileskelevät yhdessä kaupungin rakennuksista (`Campaign.HIDEOUT_TYPES`, `hideout`).
       Kentällä oven yllä lukee HIDEOUT, kun ryhmä on lähellä. Sisään astuminen aloittaa taistelun
       huoneessa (`main.battle_indoors`, `battle_view` + `setup.room`):
       - Ruutu 1 m (`Battle.tile`), askel maksaa 0,5 AP (sama nopeus metreissä kuin ulkona).
       - Pohjana huoneen oma kuva ja kalusteet (`Forces.make_room_battle`). Seisovat kalusteet
         estävät liikkeen ja antavat raskaan suojan, mutta niiden yli näkee (`furniture`).
       - "YOU CAN'T USE THAT WEAPON INDOORS": raketin- ja ohjusheittimet, kranaatinheittimet ja
         raskaat konekiväärit (`Battle.NOT_INDOORS`). Käsikranaatit sallitaan. Ei kraatereita.
       - Ryhmä tulee ovesta, puolustajat ovat hajallaan huoneen perällä kalusteiden takana
         kyykyssä (`Forces.deploy_defenders`, vähintään 3 m väli).
       - Taistelun jälkeen ryhmä on oven edessä.
       - Tasapaino (4 vs 3 Black Legion tavernassa, 200 taistelua): NORMAL voittaa 44 %,
         kuolleita 2,4; STORY voittaa 64 %, kuolleita 0,2. Sisätaistelu on tarkoituksella tappava.
6. **M6 Ajoneuvot:** **VALMIS**. Hankinta: vehicle-tehtävän korjattu ajoneuvo menee
   Krakovan varikolle (`campaign.motor_pool`) ja ryhmälle seuraavalla toimistokäynnillä.
   - **Ajaminen maailmankartalla (3.11.):**
     - `World.DRIVE` min/km: pyörillä tie 1,2 (50 km/h), kaupunki 2, aukea 4, maasto 5, metsä 10;
       teloilla tie 1,7, aukea 2,5, maasto 3, metsä 5. Joet vain siltoja pitkin, vesi ei koskaan.
       Kummallekin oma AStarGrid2D. Esim. Krakova–Checiny jalan 20 h, HMMWV 1 h 41 min.
     - Polttoaine: vehicles.json `fuel_cons` luetaan litroina ajotunnilta (HMMWV 90 L / 30 L/h =
       3 h). Reitin vihjeessä näkyy kulutus ja "NOT ENOUGH FUEL".
     - Polttoaineen loppuessa alkuperäinen "YOU RUN OUT OF FUEL ON YOUR WAY THERE.": ajoneuvo jää
       paikalleen ja ryhmä jatkaa jalan. Krakovan toimistossa varikko hinaa kuivan ajoneuvon takaisin
       ja tankkaa.
     - Tankkaus: Krakovan varikko, ja kaupungin johtaja, jolle on tehty tehtävä (`campaign.friends`):
       "I'VE TAKEN THE LIBERTY OF REFUELING YOUR …" (alkuperäinen repliikki).
     - V pysäköi / nousee kyytiin (pitää seistä ajoneuvon luona). Pysäköity ajoneuvo näkyy kartalla,
       eikä ole mukana taisteluissa. Taistelussa tuhoutunut ajoneuvo menetetään.
     - Ajaessa kohtaamisia puolet vähemmän per km ("AFTER … OF DRIVING"), ja väistäminen onnistuu
       50 %:lla ajoneuvon ansiosta.
     - **Romut (3.11., vain STORY-moodissa – alkuperäisessä ei ole tätä mekaniikkaa):** kartalla
       löytyy harvoin (0,6 % / km, noin kerran 170 km:llä, ei taattua väliä) tuhoutuneita ajoneuvoja
       ja tankkeja (`World.WRECKS`). Paneelissa näkyy alkuperäinen romukuva (DV*).
       DRAIN THE FUEL vie 30 min. Romu ei ole koskaan turvallinen:
       - 15 % väijytys: romu oli syötti (Black Legion Czarnyn mailla, muuten marodöörit) → taistelu.
       - 35 % ansa. Ryhmän paras COMBAT ENGINEER / OBSERVATION huomaa sen 30 % + 10 %/taso
         (enintään 85 %) ja purkaa sen. Laukeava ansa: polttoaine palaa, tutkija haavoittuu
         raajaan tai vatsaan (ei koskaan kuolettavasti, ei vuotoa) ja menettää usein osan
         varusteistaan (lippaita, puolet kranaateista, ehkä ensiapupakkauksen).
       - Muuten: 40 % romuista palaneita, muissa 5–35 % tankista. Polttoaine ensin omaan tankkiin
         (jos ryhmä ajaa), loput kanistereihin (20 L/mies). Kanisterit kaadetaan tankkiin, kun ryhmä
         nousee ajoneuvoon (V).
     - Testi `--test=drive`.
    - **Ajoneuvojen ostaminen:** `campaign.purchase_vehicle()`, `get_purchasable_vehicles()`, `get_vehicle_price()` – ostaminen Krakovan varikolle, hinta vehicles.json `price`-kentästä, veloitus kassasta `campaign.funds` (M9).
    - **Korjaus kentällä:** `campaign.field_repair()` – COMBAT ENGINEER -taidolla (20 % + 5 %/tasoa korjaus per yritys), palauttaa moottorin toimintaan jos moottorin vahinko < 100 %.
    - **Polttoainetyypit (D/G/A):** vehicles.json:ssa `fuel_type`-kenttä (D=diesel, G=bensiini, A=avgas). `Vehicle.can_use_fuel()`, `Campaign.can_refuel_with()` tarkistavat yhteensopivuuden. Monipolttoisille (turbini, M) kaikki tyypit kelpaavat.
7. **M7 Tekoälygrafiikka** vaiheittain kaikille kuville ja musiikin remasterointi.

Työ jatkuu tästä dokumentista: jokaisen vaiheen tila päivitetään tähän.

## 8. **M8 Pelilogikan integrointi** – kaikki alijärjestelmät yhteen toimivaksi kokonaisuudeksi.

- **Toimisto (HQ) virtaus:** rekrytointi → toimisto → radio → maailman kartta → kaupunki/taistelu → takaisin toimistoon.
- **Tallennus/lataus:** `main.gd`:n `save_game()`/`load_game()` (yksi järjestelmä, aiempi save_manager.gd poistettu) – koko pelitila (joukkue, maailma, kampanja, ajoneuvot) JSON-muodossa.
- **Tehtävien pelattavuus:** kaikki 12 tehtävää (supplies, spy, hostage, assassins, wounded, epidemic, exile, dump, defend, liberate, tank, vehicle) pelattavissa lopusta loppuun.
- **Sisätaistelun integrointi:** hostage/assassins siirtää ryhmän `interior.gd`:n kautta `battle_view.gd`:hen (tile=1 m) ja takaisin.
- **Ajoneuvojen hallinta:** osto, tankkaus, korjaus, romut, kenttätaisteluissa ajoneuvo mukana.
- **Tekoälyvastustajat:** taistelussa molemmat puolet AI:lla (auto_play), maailman kartalla kohtauslogiikka.
- **Testi:** `--test=fullgame` ajaa pelin alusta loppuun simuloiduilla syötteillä.

## 9. **M9 Tasoitus ja laatu** – pelattavuus, tasapaino, virheenkäsittely.

- **Vaikeustasot:** NORMAL/STORY tasapaino kaikissa tehtävätyypeissä (voitettavuus 40–70 %).
  - **Toteutettu (M9 tasapaino, 1. kierros):** `tests/test_balance.gd` (headless, `godot --headless --path . --script tests/test_balance.gd`) ajaa kampanjan todelliset kohtaamiset 6 hengen ryhmällä NORMAL- ja STORY-vaikeustasoilla ja mittaa voitto-%:n (80 taistelua/solu). Vihollismäärät skaalautuvat ryhmän koon mukaan (`Campaign.field_count` = ryhmä+1..2, `room_count` = ryhmä−2, `TANK_ESCORTS` = 3; main kytkee `campaign.squad_size`). Mittaus: kaupungin varuskunta 58 %, huonetaistelu 65 %, tankkitehtävä 57 % – kaikki 40–70 %-bandissa; STORY aina helpompi (80–100 %). Tien kohtaamiset ovat "flavor"-luokkaa (sallittu rajat 40–100 %, ne voi myös välttää).
- **Resurssitasapaino:** raha, polttoaine, ammukset, lääkkeet, korjausosat – ei trivialisaa eikä mahdottomaksi.
  - **Toteutettu (7.11., 1. kierros):** rahatalous `Campaign.funds` (värvättyjen rahat + `PAY_PER_MISSION` 2000 MK/tehtävä); HQ-computer näyttää FUNDS/SQUAD/VEHICLE/MOTOR POOL/TOWNS/STORE ROOM/SQUAD STATUS (`computer.gd`); Motor Pool käyttää samaa kassaa ja veloittaa ostokset. Ammus-/lääke-/ruokatalous yhä auki.
- **Käyttöliittymä:** hiiri + näppäimistö, tooltipit, nopeampaa navigoimista, selkeäristä viestilaatikko.
- **Äänimaailma:** musiikki kiertokulussa, efektit (laukaus, räjähdys, moottori, kävely) ilman järkyttäviä leikkaumia.
  - **Toteutettu (7.11.):** `main.set_music`/`play_sfx` – teema näkymän mukaan (TWICHAR3 toimisto/chargen, XPLORE1 kartta/kaupunki, BATTLE1 taistelu, LOSE1 häviö; musiikki loopaa). Efektit alkuperäisistä äänistä: laukaus aseen mukaan (TRIFLE/TMGUN1/TSHOTGUN/TROCKET1/TTNKGUN), räjähdys TEXPLOS/TGRENLAN, ovi DOOR. Neljä puuttunutta musiikkitiedostoa kopioitu `godot/original/audio/music`iin ja importattu.
- **Virheentestit:** puuttuvat tiedostot, korruptoitu save, OOM, nollatiedot JSONista – peli ei kaadu vaan antaa selkeän virheilmoituksen.
- **Suorituskyky:** 60 FPS 1280×720, latausajat < 2 s, taistelun auto_play 200 kierrosta < 1 s.

## 10. **M10 Julkaisukelpoisuus** – buildit, dokumentaatio, jakelu.

- **Kääntöskriptit:** Windows (x64), Linux (x64), macOS (arm64/x64) – Godot 4.4 export templates.
- **Asennuspaketit:** `.exe` (Windows), `.AppImage` (Linux), `.dmg` (macOS) – sisältää kaikki assetit.
- **Käyttöohje:** `README.md` peliohjeilla, näppäinkartalla, tehtävätyyppien kuvauksilla.
- **Kehittäjädokumentaatio:** `ARCHITECTURE.md` koodirakenteella, datamuodoilla, lisäämisohjeilla (uusi tehtävä, uusi ajoneuvo, uusi kaupunki).
- **Versiointi:** `version.txt` (semver), `CHANGELOG.md`, Git-tägitys.
- **Testaus:** CI/CD pipeline (GitHub Actions) ajaa kaikki headless-testit jokaisella pushilla.

## 11. Testit ja ajaminen – miten kaikki ajetaan

Godot-binääri: `C:\Twilight-2000_DOS_EN\godot\Godot_v4.7.2-stable_win64_console.exe`
(projekti ilmoittaa `config/features` = 4.4). Projektin juuri: `C:\Twilight-2000_DOS_EN\remake\godot`.

### Yksikkötestit (headless, ei ikkunaa)

```
godot --headless --path . --script tests/test_campaign.gd       # 12 tehtävätyyppiä, palkinnot, motor pool
godot --headless --path . --script tests/test_chargen_rules.gd  # 300 värvättyä, invariantit
godot --headless --path . --script tests/test_combat.gd         # legacy-combat.gd:n puhtaat funktiot
godot --headless --path . --script tests/test_vehicle.gd        # ajoneuvofysiikka, polttoaine, vauriot
godot --headless --path . --script tests/test_battle.gd         # sadat AI-taistelut + sääntötarkistukset
godot --headless --path . --script tests/test_balance.gd        # M9-tasapaino, 80 taistelua/solu
godot --headless --path . --script tests/test_balance.gd -- --report   # vain taulukko, ei band-tarkistusta
```

`M9_ONLY` rajaa tasapainoprofiilit (esim. PowerShell: `$env:M9_ONLY='tavern'` ennen ajoa).

### Integraatiotestit (ikkunalla – kuvakaappaukset)

Headless-tilassa `RenderingServer.frame_post_draw` ei laukea, joten kuvakaappaus-await ei palaa:
**kuvia tuottavat testit on ajettava ikkunalla** (ne sulkeutuvat itsestään).

```
godot --path . -- --test=chargen    # hahmonluonti, briefing, maasto
godot --path . -- --test=city       # Krakova, taloon sisään, matka Skawinaan
godot --path . -- --test=rooms      # kaikki yhdeksän huonetyyppiä
godot --path . -- --test=towns      # kaupunkikokoluokat
godot --path . -- --test=soldiers   # sprite-suunnat ja vartalotyypit
godot --path . -- --test=battle     # sijoittelu, taistelu, lepo, panssaritaistelu
godot --path . -- --test=boom       # räjähdykset, kaatuvat puut, kraaterit
godot --path . -- --test=mission    # kentällä pelattavat tehtävätyypit
godot --path . -- --test=drive      # ajaminen, polttoaine, romut, väijytys
godot --path . -- --test=save       # tallennus/lataus round-trip
godot --path . -- --test=computer   # HQ-computer: funds, stores, motor pool
godot --path . -- --test=fullgame   # koko peli alusta loppuun (story)
```

Kuvat: `%APPDATA%\Godot\app_userdata\Twilight- 2000 Remake\tests\<testi>\*.png`.

### Demo-versio (manuaalitestaus)

Kaikki manuaalinen testaus tehdään kansion `C:\Twilight-2000_DOS_EN\demo` kautta – ei koskaan
kehityskansiossa. Päivitä demo aina muutosten jälkeen: `python remake/tools/make_demo.py`
(`--clean` tyhjentää ensin). Demo sisältää `Peli.bat`-käynnistäjän ja `LUEMINUT.txt`-ohjeen;
demon tallennukset ja kuvat menevät omaan user://-kansioonsa ("Twilight- 2000 Remake DEMO"). Huom: pelin ikkuna voi avautua muiden ikkunoiden taakse – napsauta sitä kerran, jotta se saa fokuksen; musta konsoliikkuna on normaali.

### Tila 7.11.2026

Kaikki yllä olevat testit menevät läpi (PASS). SUUNNITELMAN luvut on tarkistettu koodia
vasten: esineet 95, kaupungit 56, esinekuvaukset 80, taidot 52, kielet 33, musiikki 6,
efektit 25, tehtävätyypit 12, tekstit 6296 merkkijonoa yhdeksässä moduulissa.

**Tilapäivitys 7.11.2026 (mitattu):** headless-yksikkötestit ajettu uudelleen — campaign,
chargen_rules, combat, vehicle ja battle kaikki PASS. Demon `project.godot` vahvistettu
sisältävän `[debug] file_logging` -asetuksen (virheloki `%APPDATA%\Godot\app_userdata\
Twilight- 2000 Remake DEMO\logs\godot.log`, 5 rotaatiota) ja `config/name` on
`Twilight: 2000 Remake DEMO`. SDXL-malli `sd_xl_base_1.0.safetensors` puuttuu yhä —
INTRO-remaster pysyy estettynä. `remake/godot` puhtaana `4384e89` (M8+M9-työt). Demo-
LUEMINUT.txt:ssä käynnistys- ja virhelokiohjeet, AI_OHJE luku 7b pitää demo-debugin tiedot.


## 12. **M9 Alapalkki ja pikanäppäimet (7.11.2026)** — alkuperäisen "2-D Ground Icons" -ikonirivi takaisin.

**Lähde:** manuaali s. 55–58 (näytön alla kymmenen kuvaketta; numeroilla 1–9/0 suoraan). Tila ennen:
kenttä- ja huonenäkymissä ei ollut lainkaan alhaista komentopalkkia; toiminnot vain hiirellä ja
piilonäppäimin (M/L/Space).

### Uusi komponentti: `scripts/action_bar.gd`
- Paneeli y = 708–800 (peli-ikkunan alla), kymmenen nappia alkuperäisessä järjestyksessä:
  **1 NECESSITY, 2 OPTIONS, 3 RADIO, 4 INVENTORY, 5 COMBAT, 6 TALK, 7 TAKE, 8 USE, 9 MAP, 0 LOOK**.
- `hotkey()`: näppäimet 1–9/0; alivalikossa numerot valitsevat sen vaihtoehdot ja ESC sulkee
  (näkymän `_unhandled_input` kutsuu; dialogin puhevalinnat ratkaisevat numerot ensin).
- `choose(title, buttons)`: alivalikkoikkuna palkin yllä otsikolla ja numeroiduilla valinnoilla.

### Kenttänäkymä (tactical.gd)
- 1 NECESSITY: kalastus (FISHING), keruu (FORAGING), metsästys (RIFLE) — parhaan taidon
  random-baseline, kesto 60/60/120 min — ja **nukkuminen 8 h** (`Healing.rest`,
  `main.world.minutes += 480`).
- 2 OPTIONS: tallenna (QUICKSAVE), lataa, ääni päälle/pois, lopeta.
- 3 RADIO: tehtävän tila Exor 1:n suussa (`campaign.objective_text`); jos tehtävää ei ole, ilmoitus.
- 4 INVENTORY: ryhmän rivit: nimi — ase — tila (`Healing.condition`) — ensiapupakkaukset.
- 5 COMBAT: vihollinen 40 m säteellä → valinta aggressive / tactical / retreat
  (retreat kunnioittaa NO_MOVE-sääntöä).
- 6 TALK: lähin ei-vihollinen 5 m säteellä → kävellään luo; muuten viesti.
- 7 TAKE / 8 USE: tietoviestit (ruoka/lääkejakeet M9:n talous 2. kierrokselle).
- 9 MAP: LCD-kartta päälle/pois (sama kuin L). 0 LOOK: edessä olevan kuvauksen (henkilö/
  rakennus/puu/maastotyyppi).

### Huonenäkymä (interior.gd)
- Sama palkki; COMBAT, TAKE, USE, MAP poistettu käytöstä (selittävä viesti); NECESSITY = nukkuminen
  8 h (sängyssä), TALK = lähin ihminen `open_talk`, LOOK = huonepohjainen kuvaus,
  OPTIONS/RADIO/INVENTORY kuten kentällä.

### Muut muutokset
- `main.gd`: `sound_on` + `toggle_sound()` (musiikki pysähtyy heti, track muistiin
  `set_music`-poliitkalla; efektit estetään `play_sfx`-alussa).
- `tactical.gd`: msg-rivi nostettu y = 760 → y = 682; palkki lisätty ennen dialogin luontia
  (dialogin sivut tulevat palkin päälle).
- Uusi testi `tests/test_action_bar.gd` (headless): 10 nappia, numerot, alivalikon numerot
  ja sulku-avaus — PASS.
- Ajetut testit 7.11.: test_campaign/chargen_rules/combat/vehicle/battle (headless PASS),
  test_action_bar PASS; ikkunalla rooms, towns, save (PASS) ja fullgame (1.9 min, läpi
  ilman skriptivirheitä). Demo päivitetty (`make_demo.py --clean`) ja LUEMINUT.txt:n
  PIKAOHJE saa palkki- ja numeronapit.
- Toteutustaso: TAKE/USE ovat tietoviestejä, NECESSITY-ruoat sanallisia ilmoituksia —
  täydellinen samanvertaisuus (saalistaulujen palkitseminen, ruokatalous jne.) M9/M10:een.


## 14. Asset and mission audit 7.11.2026: only original assets; missions from the original's own strings

Assets (verified against the code):
- main.gd: main.remastered starts false and ALLOW_AI_ART = false (the F2 switch is dead at
  compile time), so main.art() always returns the res://original/... path.
- soldier.gd: Soldier.remastered is false and only the (dead) F2 branch could set it.
- A scan of every res:// reference in scripts: res://remastered appears only behind those
  disabled gates; every other load goes to res://original/... (19 direct loads), res://data
  or res://scripts. Music and effects load from res://original/audio/....
- The demo build is now physically free of AI files: make_demo.py IGNORE gained a
  "remastered" filter - the demo went from 6105 files / 375 MB to 5447 files / 303 MB, and
  demo/project/remastered does not exist. The development copy keeps the unused folder.
- The AI tooling (tools/remaster_set.py, remake/assets_ai) stays outside the game project.

Missions vs. the original:
- The 12 remake mission types (supplies, spy, hostage, assassins, wounded, epidemic, exile,
  dump, defend, liberate, tank, vehicle) are built from the original's own strings:
  every intro/nag/done line is found in the extracted TWI2D.EXE texts (data/missions.json
  is documented as "assembled from the original texts (no retyping)").
- Examples (TWI2D offsets): supplies intro @157190, epidemic intro @152314, wounded intro
  @152990, assassins @153734, exile @154659/@155152, spy done @125225, hostage done
  @123968, liberate done @125794, vehicle/tank destroy done @126487; the campaign-story
  monologue (HMMWV speech) is the original's own text (missions.json story list).
- defend (the original's ATTACK ON KRAKOW / DEFEND strings live in ICON) and the downed
  own-vehicle repair story (the remake's 'wreck' person) trace to the same source set.

Playability differences, intentional and documented:
- Combat: the 1991 game used PAL automatic combat in the field (you start it and may only
  retreat, manual p.59); the remake adds a full turn-based AP battle on the same grid (the
  automatic ai_step/auto_play path exists too and is band-tested in tests/test_balance.gd).
  NOTE (fix 8.11.): the original's TWI2D strings show the 2-D module HAD a manual combat
  action menu of its own (CONTINUE / BREAK OFF / INTERACTIVE / DESCRIPTIVE / QUICK COMBAT,
  "SELECT ACTION FOR %s", "AIM AT WHO" - TWI2D @146254-@146743): the remake's manual battle
  recreates that mode, so it is faithful, not an invention.
- The 3-D driving module (TWI3D) is not reproduced; vehicles drive on the world map (M6).
- The Krakow computer screen: the original had six bar graphs (food, ammunition, medicine,
  fuel, people, morale); the remake shows funds/stores/motor pool/squad. Bringing the
  graphs + consumption into balance is the M9 economy round 2 task (AI_OHJE item 1).
- New conveniences: click-to-move, the bottom icon bar with number keys (ch. 12), quick
  save F5/F9, difficulty NORMAL/STORY, day/night light, zoom.
- Rules fidelity is tracked on the native side: t2k-native/docs/RAPORTTI.md and
  SAANNOT_VERTAILU.md.


## 15. Conversion backlog from the original strings (gap scan 8.11.2026)

Method: every string of the 9 extracted modules (2000, CGEN, EQUIP, ICON, INFO, INTRO,
OFFICE, TWI2D, TWI3D - 648 readable strings) was n-gram-matched against the remake corpus
(data/*.json + all .gd literals). Uncovered strings were bucketed by theme; the backlog
below keeps only findings that are real missing content (many uncovered strings are UI
labels the remake intentionally redesigned).

Already converted on this day (commit 0235-missions):
- Necessity lines: sleep variants (real bed / open + no tent, TWI2D @147836-@148225) moved
  into healing.gd; fish/forage/hunt result lines ("YOU SPEND A FEW HOURS %sING." +
  "AFTER ... %s COMES BACK %s/EMPTY HANDED." + "WITH SOME FISH" / "WITH BERRIES AND ROOTS"
  / "WITH HIS KILL", TWI2D @148761-@148828) moved into tactical.gd _survive.
- Defeat line wired: lines.captured = "YOU HAVE BEEN AMBUSHED AND CAPTURED..." (TWI2D
  @143476) now shown by main.gd _game_over.
- endings block stored in data/missions.json: victory p1 (ICON @74076), victory p2 /
  epilogue (ICON @74668), news_bravo (ICON @89511), jammed comms (ICON), city lost
  ("YOU FOUGHT WELL...", TWI2D @161104). Data ready; wiring is M10 work.

Backlog (the remaining real gaps, in suggested order):
1. Endings (M10): a victory path - "ATTACK ON KRAKOW" as the final battle: when the story
   reaches its last paragraph, spawn the Black Legion assault in Krakow; win ->
   endings.victory (2 paragraphs + music), lose -> defeat. The jammed-comms line replaces
   radio dialogue during the assault (ICON: "%sSTATIC AS CZARNY'S TROOPS JAM...").
2. Mission-failure consequences (M9/M10): when a defend/clear mission is lost or expires,
   the city goes to Czarny (world map ownership + the city_lost line in the next briefing);
   the failure-arc message ("YOU FOUGHT WELL, MY FRIEND, BUT THE BATTLE WAS LOST ON OTHER
   FRONTS. CZARNY HAS FORCED US TO JOIN HIS SIDE.") is already stored. The original also
   ends the whole campaign if caps violations (captured) happen to Krakow itself.
3. HQ gear sale / ammunition purchase (M9 economy round 2): OFFICE strings
   ("ADD AMMO TO WHICH WEAPON?", "%s CANNOT CARRY ANY MORE AMMO FOR THE %s.",
   "%s ISN'T CARRYING ANY WEAPONS THAT USE %s AMMO.") - the squad re-equips at the office
   cabinet for funds; also EQUIP.json long item descriptions belong to the Inventory
   icon's INFO/DESCRIPTION options (manual p.63) --------------
4. Truck-bound supplies (M9 economy): dump mission recall line "YOU MUST HAVE A 2 1/2 TON
   TRUCK CLOSE BY IN ORDER TO LOAD THE SUPPLIES." (TWI2D @151563) - the crates should be
   truck-loadable (ICON: "IN OUR 2 1/2 TON TRUCK AND RECOVER THESE SUPPLIES..."). The
   rematch's dump mission currently ignores vehicles.
5. The other-squads news cycle (M10 flavour): ICON radio stage messages (Czarny conquers
   cities / Andrekov news / Bravo Company / Americans captured) beyond the 12 store
   paragraphs in missions.json story - at least the remaining ICON stage lines should be
   added as timed pending_story events driven by campaign progress.
6. Quick fixes on combat strings (low priority): the battle screen's own lines
   ("YOU SPEND ANOTHER COMBAT ROUND RELOADING YOUR WEAPON.", "THE ENEMY SPENDS..." etc.,
   TWI2D) partly overlap the remake battle log wording; keep or splice on next battle
   polish. Also TWI2D @161579 "IT'S HIM!  HE'S THE SPY!  CATCH HIM, QUICK!" is in the
   data but only usable if the suspect flees - the remake interrogates in place.
7. TWI3D vehicle descriptions (12 items) can dress the motor pool / I.V.A.N. view text.
8. Not converting on purpose: CGEN UI labels (the remake chargen is redesigned), 2000
   module's memory-kit advertisement + COM error strings, joysticks prompts, DOS bits.


## 16. M9 economy round 2, first slice: HQ resupply (8.11.2026)

What was built:
- scripts/economy.gd (new, class_name Economy): the derived prices and carry caps.
  The original data has no ammunition prices (items.json ammunition prices are all 0)
  and no explicit caps, so OUR rules: one spare magazine costs the weapon price / 10
  (minimum 10) - AKM 30, M16A2 40, M9 15, G3 50; a med kit its item price (PERSONAL
  MEDICAL KIT 100), a grenade its item price (FRAGMENTATION GRENADE 4). Caps per
  recruit: 12 magazines, 3 med kits, 12 grenades.
- scripts/computer.gd rebuilt around the resupply: one row per recruit (name, weapon,
  mags, med kits, grenades) with MAG/MED/GRE buy buttons. Funds come from
  campaign.funds (missions pay 2000 each, plus hastened by recruit purses and rewards).
- Consumption already flowed: battle.gd write_back passes mags/medkits/grenades back to
  the recruit's gear after every battle, so battles are paid in ammunition and first aid.
- The original's OFFICE strings are the interface: the section header (a splice of
  "ADD AMMO TO WHICH WEAPON?"), and the refusals "%s CANNOT CARRY ANY MORE AMMO FOR
  THE %s." and "%s ISN'T CARRYING ANY WEAPONS THAT USE %s AMMO." (also used when the
  recruit has no gear at all yet - Forces.equip issues the loadout at the first battle,
  so an early investor is told plainly that the soldier carries nothing).
- Tests: tests/test_economy.gd (headless, PASS) checks the derived prices, the caps and
  the no-gear refusal; --test=computer (windowed) shows the screen; --test=fullgame
  passed.

Still open in this work item:
- Food: the original demanded food every 8 hours ("required to sleep and eat every
  eight hours... hindered"); the remake has no food state yet. Plan: a rations counter
  per squad, consumed by Sleep (icon 1 / world-map R), scrounged with fish/forage/hunt,
  hungry soldiers pay initiative/aim penalties; the computer's FOOD line follows.
- The computer screen's six bar graphs (food, ammunition, medicine, fuel, people,
  morale) from the original; only funds/stores/motor pool/squad exist now.
- Price tuning: the money flow over 12 measured missions decides whether 2000/mission
  covers the mags burn (the balance harness prints stores/funds at the end of a run).

## 17. OpenXCom as the battle-mechanics reference (8.11.2026)

- Source read: OpenXcom/OpenXcom (github) src/Battlescape/BattlescapeGame.cpp + friends.
  License: GPL-3.  RULE: ideas and mechanics are taken as a reference only; NO code is
  copied into the remake (copying GPL code would force this project under GPL). The
  actually binding rules reference remains the 1991 manual + t2k-native verification.
- Adopted now: the reserved time units (OpenXCom checkReservedTU). In the remake:
  battle.gd set_reserve toggles a unit's "reserve"; _flood clamps the movement frontier
  so every reachable tile still leaves AP >= COST snap (3). The battle bar gains a
  "T RES ON/OFF" button and the hotkey T; the unit line shows "RESERVED FOR A SNAP
  SHOT". Vehicles cannot reserve. The AI ignores the flag (OpenXCom reserves AI TUs as
  percentages - a future AI option, low priority). Persist until the battle ends, as
  in OpenXCom.
- Candidate mechanics read but NOT adopted (each needs a rules decision first):
  reaction fire (OpenXCom checks reaction on kneel/move; the T2K battle screen has no
  data-driven reaction curves in the extraction -> design needed), panic/morale flow
  (the remake has a coolness-based run rule at half strength; OpenXCom's morale events
  could map onto it later), grenade fusing (the original data has no timed-delay
  explosive item - removed per readme), melee/hand-to-hand states (T2K has melee skills;
  the battle has no melee action yet - candidate for M9 polish), path preview with
  obstacles (the remake shows a reach zone instead).
- Tests: tests/test_reserve.gd (headless, PASS): reach-with-reserve boundary cases,
  reserved in-range move accepted, beyond-reserve move rejected with the new log line,
  vehicles refuse, toggle free. tests/test_battle.gd re-run after the change: PASS
  (the band values stay - reserve defaults off everywhere).


## 18. The game's opening: the first mission - and what a UFO-engine battle could lend us (8.11.2026 design note)

The opening as it plays NOW (facts, checked from the code):
- chargen -> deploy() -> the OFFICE screen (radio / computer / filing cabinet / wall map /
  lamp, the original's five hotspots).
- Radio = main.show_briefing() -> the EXOR 1 split-screen scene with the mission brief
  (the original's own strings from missions.json types[brief]).
- Lamp = out to the world map. The first mission's type is RANDOM from the 12 playable
  types (normal mode; campaign.new_mission, campaign.gd:106); the target is within
  6 + 3 x done-cities of Krakow, so the first errand is short.
- In the target town the squad talks to the city leader ("Ask about the mission"), then
  the clear step spawns the garrison: field_count = squad_size + 1..2 soldiers
  (a few more later on the map, hideout types fight in a room - campaign.gd:142-144).
- The battle screen appears when the squad clicks the enemy group. The turn system is
  our own: unit-by-unit in initiative order (battle.gd:187-224), AP per unit, new round
  when everyone has acted. Enemies are ALL VISIBLE from the start; there is no fog of
  war, no enemy blips, no reaction fire, no individual panic.

What the UFO engine (OpenXCom, the UFO Defense reimplementation) does per round and
what that maps to in this remake:
1. Fog of war + enemy blips: aliens are invisible until a soldier has line of sight;
   unseen movement is a moving red blip. NEEDED for tension in the remake's very first
   firefight (the garrison could sit unseen behind houses). RULE DECISION: the 1991
   original's auto-battle shows enemies walking, but the remake's manual battle has no
   faithful counterpart - the proposal is to ADOPT spot-hidden enemies (sprite dark +
   a blip when only heard/moving, spotted = in line of sight + range, once spotted
   stays until out of sight for N rounds). Default ON, story NORMAL both.
2. Reaction fire (checkReactionFire): when a hostile moves within a watching unit's
   view, the watcher gets a snap shot. Data problem: the extracted rules have no
   reaction curves; proposal: 1 reaction snap per moving enemy per round, range <= 8
   tiles, front hex-arc (Facing 0-7), chance from the standard snap formula with the
   mover's stance penalty. Implementation if adopted: hooks in move() + fire().
3. Reserved time units: DONE (ch. 17, key T).
4. Panic states (freeze / flee) and morale events: the remake runs a coolness check at
   half losses (battle.gd:1036-1038). OpenXCom-style: per-soldier morale events on
   kills/wounds/friendly deaths, freeze = skip AP, flee = one run to cover. Candidate;
   map the original's own "coolness ~ initiative" line and keep it simple.
5. Alien AI extras: 2 actions per unit (ours already, via AP budget), charging,
   item attraction (ours: the wreck scavengers), objective tracking (ours: campaign
   step counts). Nothing else to take from here.
6. Mission-complete popup: ours is the campaign's own done lines; keep.

Proposed first-mission work order (small slices, each testable):
a) SPOTTED/BLIP fog for the battle screen (battle.gd spots per round, battle_view
   draws blips over unseen movers, log line "ENEMIES SPOTTED"; the tactical screen's
   encounter already shows people - only the battle grid changes).
b) One-time first-battle tutorial line in the battle log (the F5/T/E hints + "left
   click to move, right button cancels"), only when done_count == 0.
c) Reaction fire with the rule above, symmetric both teams, off in tests? (it shifts
   the balance bands: test_balance must be re-measured and the new bands recorded -
   the ch. 11 band rule).
d) Per-soldier panic/morale events.
Decision needed from the player: fog default (nice-to-have ON) and reaction-fire ON/OFF
(it changes the feel most).


## 19. The UFO-style battle fog implemented (8.11.2026)

The player's call (ch. 18): make the remake's battle feel like the UFO-engine's instead of
the original's standing shootout. This slice ships the spotting:

- battle.gd:
  - options["fog"] (default false so the legacy harnesses stay untouched; the real
    battles set it in Forces.make_battle / make_room_battle).
  - is_seen(u, team): the team's knowledge; sticky - once spotted, remembered.
  - SIGHT_TILES = 20 (40 m on the field with the 2 m tile, 20 m indoors): sighting
    distance is NOT firing range; a distant tank stays dark until it fires.
  - _reveal(u): the muzzle flash reveals the shooter (fire() and grenade throws).
  - refresh_seen(): two-way refresh over the units; a move, a shot or the setup calls
    it; the log line "%s IS SPOTTED." arrives when the squad's eye catches someone.
  - fire() refuses shots into the dark ("THE TARGET IS NOT IN SIGHT." for the squad).
  - the defensive AI (ai_step) holds its ground while nothing is seen - the garrison
    waits inside the town until the squad closes in.
- battle_view.gd:
  - enemy sprites are drawn only when seen (deploy phase shows everyone);
  - clicks and hover tips only work on seen targets;
  - the first battle prints the chalk talk: click = move/fire, 1/2/3 fire modes,
    4 grenade, T reserve, E end turn, and "THE ENEMIES STAY IN THE DARK UNTIL THEY
    ARE SPOTTED - MOVE UP CAREFULLY."

Tests: tests/test_spotted.gd (headless, PASS): dark at 66 m, hold ground, spotted at
36 m, sticky, muzzle reveal, blind shots refused. --test=battle and --test=fullgame
passed with the fog on (the battle screenshots deploy dark).

Reaction fire (ch. 18 item 2) is the next slice; it shifts the balance bands, so the
ch. 11 measurement round runs with it before any band text is updated.
