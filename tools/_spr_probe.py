#!/usr/bin/env python3
# Reproduce Soldier._draw offline: legs cell + torso frame + head strip for every body, direction
# and walk frame - to find the situation where everything above the torso goes missing.
import os, json
from PIL import Image

ROOT = r'C:\Twilight-2000_DOS_EN\remake\godot\original\graphics\ANIMS'
DIRS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

def load_rgba(p):
    return Image.open(p).convert("RGBA")

def frames_of(strip):
    """Same split as Soldier._frames: empty-column runs, wide runs split by the typical width."""
    w, h = strip.size
    px = strip.load()
    runs, start = [], None
    for x in range(w + 1):
        empty = True
        if x < w:
            for y in range(h):
                if px[x, y][3] > 128:
                    empty = False
                    break
        if not empty and start is None:
            start = x
        elif empty and start is not None:
            runs.append((start, x - start))
            start = None
    widths = sorted(r[1] for r in runs)
    typical = widths[len(widths) // 2] if widths else 1
    out = []
    for rx, rw in runs:
        n = max(1, round(rw / typical))
        for i in range(n):
            out.append(strip.crop((rx + rw * i // n, 0, rx + rw * (i + 1) // n, h)))
    return out

def waist(tf):
    w, h = tf.size
    cx = w // 2
    px = tf.load()
    row = h - 1
    while row > 0:
        if all(px[x, row][3] >= 128 for x in (cx - 1, cx, cx + 1)):
            break
        row -= 1
    return row

def head_img(body, row):
    name = {"AM": "AMH0", "AF": "AFH0", "EM": "EMH0"}[body]
    img = load_rgba(os.path.join(ROOT, name + "_rgba.png"))
    top = max(0, row * 8 - 1)
    return img.crop((0, top, img.width, min(img.height, row * 8 + 7)))

leg_n = json.load(open(r'C:\Twilight-2000_DOS_EN\remake\godot\data\leg_frames.json', encoding='utf-8'))

for body in ("AM", "AF", "EM"):
    sheet = Image.new("RGBA", (8 * 240, 6 * 110), (60, 70, 55, 255))
    for di, d in enumerate(DIRS):
        legs_path = os.path.join(ROOT, "cells", "L%s.png" % d)
        cells = []
        if os.path.exists(legs_path):
            img = load_rgba(legs_path)
            n = int(leg_n[d]["frames"])
            cw = img.width // n
            cells = [img.crop((i * cw, 0, (i + 1) * cw, img.height)) for i in range(n)]
        torso_frames = frames_of(load_rgba(os.path.join(ROOT, "%s%s_rgba.png" % (body, d)))) if os.path.exists(os.path.join(ROOT, "%s%s_rgba.png" % (body, d))) else frames_of(load_rgba(os.path.join(ROOT, "AM%s_rgba.png" % d)))
        for k, lf in enumerate(cells):
            tf = torso_frames[0]
            x0 = di * 240
            y0 = (k % 6) * 110 + 100
            base = (x0 + 60, y0)  # feet anchor
            sheet.alpha_composite(lf, (x0 + 60 - lf.width // 2, y0 - lf.height))
            top = y0 - lf.height - waist(tf)
            sheet.alpha_composite(tf, (x0 + 60 - tf.width // 2, top))
            hf = head_img(body, di)
            sheet.alpha_composite(hf, (x0 + 60 - hf.width // 2, top + 2 - hf.height))
        # label column: the direction
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    out = r'C:\temp\sprprobe_%s.png' % body
    sheet.convert("RGB").save(out)
    print("wrote", out, sheet.size)