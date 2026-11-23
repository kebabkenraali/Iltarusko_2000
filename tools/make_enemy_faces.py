#!/usr/bin/env python3
"""Generates the enemies' own portraits: godot/original/graphics/FACES/enemies.png.

The sheet: 5 cols x 3 rows of 48x43 cells (5*48 x 3*43 = 240x129), black background,
15 faces (one per enemy unit slot), skin tones + dark hair like the FACES sheets.
The AI image generator (opencode.ai console) was out of balance, so the faces are
drawn procedurally here. Run: python tools/make_enemy_faces.py
"""
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "godot", "original", "graphics", "FACES", "enemies.png")

CW, CH = 48, 43
COLS, ROWS = 5, 3
SKIN = [(185, 155, 120), (200, 160, 130), (210, 160, 120), (225, 170, 130),
        (160, 120, 80), (240, 190, 150), (180, 130, 90)]
HAIR = [(12, 10, 8), (30, 20, 10), (60, 40, 20), (90, 60, 30), (120, 80, 40), (50, 30, 5)]
BLOOD = [(170, 30, 30), (150, 20, 20)]
HELMET_FACES = {0, 1, 2, 3, 4, 5, 6, 8, 10}


def face(img, i):
    draw = ImageDraw.Draw(img)
    rng = random.Random(100 + i * 7919)
    cx, cy = (i % COLS) * CW + CW / 2, (i // COLS) * CH + CH / 2
    skin = SKIN[rng.randrange(len(SKIN))]
    rw, rh = rng.randrange(24, 27), rng.randrange(13, 16)
    draw.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], fill=skin)
    if rng.randrange(6) > 1:  # a few are bald
        hcol = HAIR[rng.randrange(len(HAIR))]
        hw, hh = rng.randrange(18, 20), rng.randrange(5, 7)
        draw.ellipse([cx - hw, cy - hh - 10, cx + hw, cy + hh], fill=hcol)
    if i in HELMET_FACES:
        draw.ellipse([cx - 20, cy - 22, cx + 20, cy + 22], fill=(45, 35, 25))
        draw.ellipse([cx - 14, cy - 18, cx + 14, cy + 18], fill=(70, 50, 30))
        draw.ellipse([cx - 5, cy - 6, cx + 5, cy + 6], fill=(20, 18, 14))
    draw.ellipse([cx - 9, cy + 0, cx - 2, cy + 7], fill=(40, 30, 20))
    draw.ellipse([cx + 2, cy + 0, cx + 9, cy + 7], fill=(40, 30, 20))
    draw.ellipse([cx - 8, cy - 1, cx - 4, cy + 3], fill=(230, 200, 160))
    draw.ellipse([cx + 4, cy - 1, cx + 8, cy + 3], fill=(230, 200, 160))
    draw.ellipse([cx - 4, cy + 9, cx + 4, cy + 14], fill=(40, 24, 16))
    if i in (2, 7, 9):
        draw.ellipse([cx - 6, cy + 14, cx + 6, cy + 17], fill=(80, 24, 18))
        draw.line([cx - 5, cy + 15, cx + 5, cy + 15], fill=(40, 12, 8))
    else:
        draw.ellipse([cx - 5, cy + 15, cx + 5, cy + 16], fill=(60, 20, 16))
    if i in (1, 7):
        for _ in range(3):
            px = int(rng.randrange(int(cx - 12), int(cx + 12)))
            py = int(rng.randrange(int(cy - 8), int(cy + 6)))
            draw.point((px, py), fill=BLOOD[rng.randrange(len(BLOOD))])


def main():
    img = Image.new("RGB", (CW * COLS, CH * ROWS), (0, 0, 0))
    for i in range(15):
        face(img, i)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print("wrote", OUT, img.size)


main()
