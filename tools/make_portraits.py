"""Talking heads for the conversations, made from the original art only.

The 1991 game has portraits for the recruits (FACES men/women, 15 each, 48x43), Exor 1 (ICON
MOUTH0 with mouth frames MOUTH1-6 at 96,60) and Czarny, but none for the people in the towns.
These are made from the recruits' portraits:
  - civilians: the uniform (the green ramp, below the chin) recoloured into a coat or sweater
    (grey, blue, brown, maroon); faces under helmets or camouflage caps are left out
  - leaders: a dark suit
  - patients: a civilian with a bandage round the head
Every portrait gets a second frame with the mouth open (the dark line of the lips made one
pixel taller), so the head can talk. Exor 1's frames are cut from MOUTH0 with MOUTH2 / MOUTH4
pasted over the mouth.

Output: godot/original/graphics/FACES/talk/<set>.png (row i = face i, columns closed | open) and
godot/data/portraits.json.
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = os.path.join(ROOT, "godot", "original", "graphics")
OUT = os.path.join(G, "FACES", "talk")
CW, CH = 48, 43

GREENS = [(32, 48, 0), (56, 72, 0), (64, 97, 0), (80, 97, 0), (72, 72, 8), (97, 97, 8), (113, 145, 0),
          (145, 145, 16), (161, 194, 0), (194, 194, 16), (32, 56, 40)]
PALETTES = {   # 5 shades, dark to light
    "grey": [(22, 22, 26), (46, 46, 54), (76, 76, 86), (112, 112, 122), (150, 150, 160)],
    "blue": [(14, 18, 38), (30, 38, 70), (52, 62, 108), (82, 94, 148), (122, 134, 186)],
    "brown": [(30, 18, 8), (56, 36, 18), (86, 56, 30), (116, 80, 44), (152, 108, 62)],
    "maroon": [(38, 8, 8), (68, 18, 16), (104, 34, 28), (142, 56, 42), (180, 86, 66)],
    "suit": [(10, 10, 12), (24, 24, 28), (40, 40, 46), (60, 60, 68), (86, 86, 96)],
}
# faces under helmets / camouflage: soldiers, not townspeople
MILITARY = {"M": [0, 2, 4, 5, 6], "F": []}
COLLAR = 26          # rows from here down are clothing (above: hair, which may be blond-green)


def cells(sheet):
    out = []
    for i in range(15):
        c = np.array(sheet.crop(((i % 5) * CW, (i // 5) * CH, (i % 5) * CW + CW, (i // 5) * CH + CH)))
        pink = (c[..., 0] == 255) & (c[..., 1] == 85) & (c[..., 2] == 255)   # the sheet's background
        c[pink] = c[:, -2:-1][pink[:, -1:]].mean(0) if False else (32, 32, 32)
        out.append(Image.fromarray(c))
    return out


def lum(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def recolour(cell, pal):
    a = np.array(cell.convert("RGB"))
    ramp = sorted(GREENS, key=lum)
    lo, hi = lum(ramp[0]), lum(ramp[-1])
    for y in range(COLLAR, CH):
        for x in range(CW):
            c = tuple(int(v) for v in a[y, x])
            if c in GREENS:
                k = int(round((lum(c) - lo) / (hi - lo) * (len(pal) - 1)))
                a[y, x] = pal[k]
    return Image.fromarray(a)


def bandage(cell):
    """A white bandage wound round the head (over the hair), with a spot of blood."""
    a = np.array(cell.convert("RGB")).astype(int)
    bg = lambda c: tuple(c) in ((32, 32, 32), (64, 64, 64), (0, 0, 0))
    top = next((y for y in range(CH) if not all(bg(a[y, x]) for x in range(20, 29))), None)
    if top is None:
        return cell
    for y in range(top + 5, top + 8):
        xs = [x for x in range(2, CW - 2) if not bg(a[y, x])]
        if not xs:
            continue
        for x in range(min(xs), max(xs) + 1):
            a[y, x] = (232, 230, 220) if y < top + 7 else (180, 178, 168)
    a[top + 6, 29] = (160, 20, 20)
    a[top + 6, 30] = (120, 10, 10)
    a[top + 5, 30] = (150, 30, 30)
    return Image.fromarray(a.astype(np.uint8))


def open_mouth(cell):
    """The lips' dark line one pixel taller (and dark red inside): the mouth opens. The line is
    found as dark pixels with skin two rows above and two below, in the lower middle of the face."""
    a = np.array(cell.convert("RGB")).astype(int)
    skin = lambda c: c[0] > 95 and c[0] > c[1] + 15 and c[1] >= c[2]
    dark = lambda c: c.sum() < 260 and not skin(c)
    best, row, xs = 0, None, []
    for y in range(24, 37):
        cand = [x for x in range(15, 33) if dark(a[y, x]) and skin(a[y - 2, x]) and skin(a[min(CH - 1, y + 2), x])]
        if len(cand) > best:
            best, row, xs = len(cand), y, cand
    if row is None or best < 3:
        return cell.copy()
    x0, x1 = min(xs), max(xs)
    for x in range(x0, x1 + 1):
        a[row, x] = (28, 8, 8)
        if x0 < x < x1:
            a[row + 1, x] = (96, 24, 20)
    return Image.fromarray(a.astype(np.uint8))


def sheet(name, faces):
    img = Image.new("RGB", (CW * 2, CH * len(faces)))
    for i, f in enumerate(faces):
        img.paste(f, (0, i * CH))
        img.paste(open_mouth(f), (CW, i * CH))
    img.save(os.path.join(OUT, name + ".png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    meta = {"cell": [CW, CH], "sets": {}, "civil": {}}
    for g, fn in (("M", "men.png"), ("F", "women.png")):
        base = cells(Image.open(os.path.join(G, "FACES", fn)).convert("RGB"))
        sheet("squad_" + g, base)
        meta["sets"]["squad_" + g] = "squad_" + g
        for p in ("grey", "blue", "brown", "maroon"):
            sheet("civ_%s_%s" % (p, g), [recolour(c, PALETTES[p]) for c in base])
            meta["sets"]["civ_%s_%s" % (p, g)] = "civ_%s_%s" % (p, g)
        sheet("leader_" + g, [recolour(c, PALETTES["suit"]) for c in base])
        sheet("patient_" + g, [bandage(recolour(c, PALETTES["grey"])) for c in base])
        meta["sets"]["leader_" + g] = "leader_" + g
        meta["sets"]["patient_" + g] = "patient_" + g
        meta["civil"][g] = [i for i in range(15) if i not in MILITARY[g]]
    # Exor 1: his head from the briefing picture, with the mouth frames pasted on
    off = MOUTH = (96, 60)
    crop = (52, 6, 52 + 112, 6 + 100)
    officer = Image.open(os.path.join(G, "ICON", "MOUTH0.png")).convert("RGB")
    frames = [officer.crop(crop)]
    for m in (2, 4):
        o = officer.copy()
        mo = Image.open(os.path.join(G, "ICON", "MOUTH%d.png" % m)).convert("RGBA")
        o.paste(mo, off, mo)
        frames.append(o.crop(crop))
    w, h = frames[0].size
    ex = Image.new("RGB", (w * len(frames), h))
    for i, f in enumerate(frames):
        ex.paste(f, (i * w, 0))
    ex.save(os.path.join(OUT, "exor.png"))
    meta["exor"] = {"cell": [w, h], "frames": len(frames)}
    with open(os.path.join(ROOT, "godot", "data", "portraits.json"), "w") as f:
        json.dump(meta, f, indent=1)
    # a sheet to look at
    look = Image.new("RGB", (CW * 2 * 7, CH * 15), (30, 30, 30))
    for k, s in enumerate(["squad_M", "civ_grey_M", "civ_blue_F", "civ_maroon_M", "leader_M", "leader_F", "patient_F"]):
        look.paste(Image.open(os.path.join(OUT, s + ".png")), (k * CW * 2, 0))
    look.save(os.path.join(OUT, "_check.png"))
    print("portraits written:", len(meta["sets"]), "sets")


if __name__ == "__main__":
    main()
