#!/usr/bin/env python3
"""Make the manual-testing demo build: sync the Godot project to C:\\Twilight-2000_DOS_EN\\demo.

ALL manual testing happens through the demo folder - the development folder stays clean.

  python tools/make_demo.py            refresh the demo in place (fast)
  python tools/make_demo.py --clean    empty the demo folder first

Creates demo\\Peli.bat (start the game) and demo\\LUEMINUT.txt (how to start, what to try).
The demo's own project name keeps its saves and screenshots separate from the development
copy's user:// folder, and file logging writes an error log to user://logs/godot.log.
"""
import argparse
import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))   # C:\Twilight-2000_DOS_EN
SRC = os.path.join(ROOT, "remake", "godot")
DEMO = os.path.join(ROOT, "demo")
ENGINE = os.path.join(ROOT, "godot", "Godot_v4.7.2-stable_win64_console.exe")
PROJECT = os.path.join(DEMO, "project")

# also drop the AI art (remastered/) from the demo: the player runs only the 1991 originals
IGNORE = shutil.ignore_patterns("tests", ".git", "__pycache__", "*.bak", "*.bak_*", "*.pyc", "remastered")

BAT = """@echo off
rem Twilight: 2000 Remake - demo (manuaalitestaus)
start "" "%~dp0Godot_v4.7.2-stable_win64_console.exe" --path "%~dp0project"
"""

README = """TWILIGHT: 2000 REMAKE - DEMO (manuaalitestaus)
==============================================

Kaikki manuaalinen testaus tehdään tämän kansion kautta; kehityskansioon ei kosketa.

KÄYNNISTYS
----------
1. Tuplaklikkaa Peli.bat.
2. Avautuu myös musta konsoliikkuna - se on normaalia ja saa jäädä taakse.
3. Pelin ikkuna (1280 x 800) voi avautua muiden ikkunoiden taakse: napsauta pelin
   ikkunaa tai tehtäväpalkin Godot-riviä, jotta se saa fokuksen.
4. Sulje peli ikkunan ruksista; konsoliikkunan voi sulkea erikseen.

Jos napsautukset eivät mene läpi: napsauta ensin kerran pelin ikkunan yläpalkkia
(ikkuna fokukseen), ja yritä uudelleen.

VIRHELOKI
---------
Demo kirjoittaa virhelokin automaattisesti:
  %APPDATA%\\Godot\\app_userdata\\Twilight- 2000 Remake DEMO\\logs\\godot.log
Liitä tämä tiedosto raporttiin, jos peli toimii oudosti (lokin viimeiset rivit
kertovat syyn). Lokeja säilytetään 5 kpl.

Tallennukset ja kuvakaappaukset ovat omissa nimissään
(%APPDATA%\\Godot\\app_userdata\\Twilight- 2000 Remake DEMO), eivätkä sekoitu
kehityskopion aineistoon.

PIKAOHJE
--------
- Hiiri: yksi klikkaus riittää; hiiren päällä näkyy vihje; oikea nappi peruu.
- F5 pikatallennus / F9 lataus (maailmankartalla, toimistossa, kaupungissa).
- Alapalkki (kaupungissa, tienoella ja huoneissa) => 10 kuvaketta kuin alkuperäisessä:
  1 NECESSITY (kalastus/keruu/metsästys/nukkuminen), 2 OPTIONS (tallenna/lataa/aani/poistu),
  3 RADIO, 4 INVENTORY, 5 COMBAT, 6 TALK, 7 TAKE, 8 USE, 9 MAP (LCD) ja 0 LOOK.
  Numerot 1-9/0 nappavat suoraan näppäimistöltä; ESC sulkee alivalikon.
- Lisäksi: M = maailmankartalle, L = LCD-kartta, Space = pause.
- Toimisto: radio = tehtävä, tietokone = varat ja varasto, varikkohissi = ajoneuvot,
  lamppu = ulos kartalle.
- Maailmankartalla: klikkaa kohdetta; R = lepo; V = pysäköi / nouse kyytiin.
- Taistelussa: 1/2/3 = snap/aimed/burst, 4 = kranaatti, R = lataa, C = kyykky,
  P = makuu, F = ensiapu, E = vuoron loppu. Kun ammutaan, ampuja näkyy vasemmassa
  yläkulmassa ja kohde oikeassa.
- Vaikeustaso valitaan värväyksessä (NORMAL / STORY).

Kirjaa löydökset: mitä teit, mitä tapahtui, missä (kaupunki/tehtävä).
Uusin versio: python remake/tools/make_demo.py (kehityskansiosta).
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clean", action="store_true", help="empty the demo folder first")
    a = ap.parse_args()
    if a.clean and os.path.isdir(DEMO):
        shutil.rmtree(DEMO)
        print("demo folder emptied")
    print("syncing", SRC, "->", PROJECT)
    shutil.copytree(SRC, PROJECT, dirs_exist_ok=True, ignore=IGNORE)
    # the demo keeps its own user:// folder: saves and screenshots stay separate
    pg = os.path.join(PROJECT, "project.godot")
    with open(pg, encoding="utf-8") as f:
        cfg = f.read()
    cfg = cfg.replace('config/name="Twilight: 2000 Remake"', 'config/name="Twilight: 2000 Remake DEMO"')
    # file logging: the engine reads the .pc override on Windows, so write both keys
    cfg = re.sub(r"\n\[debug\]\n(?:[^\[]*?\n)*?\n", "\n", cfg)   # drop an old [debug] block if any
    cfg = cfg.rstrip() + (
        "\n\n[debug]\n\n"
        "file_logging/enable_file_logging=true\n"
        "file_logging/enable_file_logging.pc=true\n"
        "file_logging/log_path=\"user://logs/godot.log\"\n"
        "file_logging/max_log_files=5\n"
    )
    with open(pg, "w", encoding="utf-8", newline="") as f:
        f.write(cfg)
    for exe in ("Godot_v4.7.2-stable_win64_console.exe", "Godot_v4.7.2-stable_win64.exe"):
        src = os.path.join(ROOT, "godot", exe)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(DEMO, exe))   # the console wrapper starts the plain exe beside it
    with open(os.path.join(DEMO, "Peli.bat"), "w", encoding="ascii", newline="\r\n") as f:
        f.write(BAT)
    with open(os.path.join(DEMO, "LUEMINUT.txt"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(README)
    n, mb = 0, 0.0
    for dp, _, fs in os.walk(DEMO):
        for f in fs:
            n += 1
            mb += os.stat(os.path.join(dp, f)).st_size
    mb /= 1e6
    print("demo ready: %d files, %.0f MB in %s" % (n, mb, DEMO))


if __name__ == "__main__":
    main()