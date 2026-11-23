"""Match every chargen portrait (FACES men/women, 15 each) to the closest field head sprite
(ANIMS AMH0-14 / AFH0-14). The original does not pair them by index, so the pairing is made by
colour: the portrait's hair / headgear band against the top of the head sprite's front view.
Writes godot/data/face_heads.json: {"M": [head per face], "F": [...]} and a check sheet.

Usage: face_heads.py   (run from anywhere; paths are relative to this file)
"""
import json, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = os.path.join(ROOT, "godot", "original", "graphics")


def portrait_hair(sheet, i):
    cell = np.asarray(sheet.crop(((i % 5) * 48, (i // 5) * 43, (i % 5) * 48 + 48, (i // 5) * 43 + 43)).convert("RGB")).astype(float)
    # the background is the grey scanline pattern: the colours on the cell's left and right edges
    bg = {tuple(c) for c in np.concatenate([cell[:, :3].reshape(-1, 3), cell[:, -3:].reshape(-1, 3)])}
    band = cell[2:16, 8:40].reshape(-1, 3)
    keep = np.array([tuple(c) not in bg for c in band])
    return band[keep].mean(0) if keep.any() else band.mean(0)


def head_top(path):
    a = np.asarray(Image.open(path).convert("RGBA")).astype(float)
    front = a[31:39]                       # row 4 of the strip = facing south (towards the viewer)
    top = front[:3].reshape(-1, 4)         # hair / headgear
    top = top[top[:, 3] > 0][:, :3]
    return top.mean(0)


def main():
    out, sheet_rows = {}, []
    for g, name in (("M", "men"), ("F", "women")):
        sheet = Image.open(os.path.join(G, "FACES", name + ".png"))
        heads = [head_top(os.path.join(G, "ANIMS", "A%sH%d_rgba.png" % (g, i))) for i in range(15)]
        faces = np.array([portrait_hair(sheet, i) for i in range(15)])
        hs = np.array(heads)
        # the portraits and the field sprites use different palettes (the field one is tinted):
        # compare after normalising each set per channel, and use every head once (greedy on the
        # globally smallest distances)
        fz = (faces - faces.mean(0)) / (faces.std(0) + 1e-6)
        hz = (hs - hs.mean(0)) / (hs.std(0) + 1e-6)
        d = np.linalg.norm(fz[:, None, :] - hz[None, :, :], axis=2)
        pick = [-1] * 15
        used = set()
        for k in np.argsort(d, axis=None):
            f, h = divmod(int(k), 15)
            if pick[f] < 0 and h not in used:
                pick[f] = h
                used.add(h)
        out[g] = pick
        sheet_rows.append((sheet, g, pick))
    path = os.path.join(ROOT, "godot", "data", "face_heads.json")
    json.dump({"_doc": "portrait index -> head sprite index (colour match by tools/face_heads.py)", **out},
              open(path, "w", encoding="utf-8"), indent=1)
    # check sheet: portrait above its matched head
    img = Image.new("RGB", (15 * 52, 2 * 90), (60, 60, 60))
    for row, (sheet, g, pick) in enumerate(sheet_rows):
        for i in range(15):
            img.paste(sheet.crop(((i % 5) * 48, (i // 5) * 43, (i % 5) * 48 + 48, (i // 5) * 43 + 43)).convert("RGB"), (i * 52, row * 90))
            h = Image.open(os.path.join(G, "ANIMS", "A%sH%d_rgba.png" % (g, pick[i]))).convert("RGBA").crop((0, 31, 16, 39))
            h = h.resize((48, 24), Image.NEAREST)
            bgc = Image.new("RGBA", h.size, (90, 90, 90, 255))
            bgc.alpha_composite(h)
            img.paste(bgc.convert("RGB"), (i * 52, row * 90 + 46))
    img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(os.path.join(ROOT, "assets_ai", "face_heads_check.png"))
    print(out)


main()
