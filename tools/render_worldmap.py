"""Draw the world map picture from the original terrain grid (data/worldmap.json).

A clean military-map look made only from the game's own data: fields in muted ochre-greens
(the four ground variants of the original as slight tone changes), forest darker with small
spruce marks, water and rivers in blue, roads as lines along the road cells (the network the
original builds from its road pieces), bridges marked. Towns are drawn by the game itself
(names, mission marks), so they are left out here.
Output: godot/original/graphics/WORLD/worldmap.png (CELL px per km).
Usage: render_worldmap.py
"""
import json, os, random
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CELL = 16


def main():
    m = json.load(open(os.path.join(ROOT, "godot", "data", "worldmap.json"), encoding="utf-8"))
    W, H, ter, codes = m["w"], m["h"], m["terrain"], m["codes"]
    t = lambda x, y: ter[y * W + x] if 0 <= x < W and 0 <= y < H else "?"
    img = Image.new("RGB", (W * CELL, H * CELL), (0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = random.Random(1991)
    ground = [(156, 152, 104), (148, 150, 98), (162, 156, 110), (144, 146, 96)]
    for y in range(H):
        for x in range(W):
            c, v = t(x, y), codes[y * W + x] & 0x3F
            box = (x * CELL, y * CELL, x * CELL + CELL - 1, y * CELL + CELL - 1)
            if c == "F":
                col = (74 + (v - 50) * 2, 100 + (v - 50) * 2, 62)
            elif c == "W":
                col = (92, 122, 140)
            else:
                col = ground[v % 4] if v <= 3 else ground[0]
            d.rectangle(box, fill=col)
    img = img.filter(ImageFilter.GaussianBlur(2.2))           # soft edges between terrains
    d = ImageDraw.Draw(img)
    # forest marks: small spruce triangles
    for y in range(H):
        for x in range(W):
            if t(x, y) == "F":
                for k in range(2):
                    px = x * CELL + rnd.randint(2, CELL - 3)
                    py = y * CELL + rnd.randint(4, CELL - 2)
                    d.polygon([(px, py - 5), (px - 3, py + 1), (px + 3, py + 1)], fill=(46, 72, 44))
    # rivers and roads: the exact shapes of the original LCD map. Every cell code indexes an
    # 8x8 tile of ICON/MAPSPR (40 per row); the bright green pixels of a tile are its road, the
    # red line pixels of a river tile its river. The pixel masks are smoothed at 2x.
    import numpy as np
    spr = np.asarray(Image.open(os.path.join(ROOT, "godot", "original", "graphics", "ICON", "MAPSPR.png")).convert("RGB")).astype(int)
    def tile(i):
        return spr[(i // 40) * 8:(i // 40) * 8 + 8, (i % 40) * 8:(i % 40) * 8 + 8]
    road_m = np.zeros((H * 8, W * 8), bool)
    river_m = np.zeros((H * 8, W * 8), bool)
    for y in range(H):
        for x in range(W):
            v = codes[y * W + x] & 0x3F
            tl = tile(v)
            r, g, b = tl[..., 0], tl[..., 1], tl[..., 2]
            if 5 <= v <= 20 or v == 4:
                road_m[y * 8:y * 8 + 8, x * 8:x * 8 + 8] = (g > 180) & (r < 160)
            if 22 <= v <= 49:
                river_m[y * 8:y * 8 + 8, x * 8:x * 8 + 8] = (r > 150) & (g < 90) & (b < 90)
    def smooth(mask, grow):
        im = Image.fromarray((mask * 255).astype(np.uint8)).resize((W * CELL, H * CELL), Image.NEAREST)
        a = np.asarray(im.filter(ImageFilter.GaussianBlur(1.6)))
        return a > (128 - grow)
    def paint(mask, rgb):
        arr = np.asarray(img).copy()
        arr[mask] = rgb
        return Image.fromarray(arr)
    img = paint(smooth(river_m, 30), (70, 108, 150))
    img = paint(smooth(road_m, 90), (66, 56, 44))
    img = paint(smooth(road_m, 10), (198, 174, 126))
    d = ImageDraw.Draw(img)
    # 10 km grid, as on a military map
    for x in range(0, W * CELL, 10 * CELL):
        d.line((x, 0, x, H * CELL), fill=(0, 0, 0), width=1)
    for y in range(0, H * CELL, 10 * CELL):
        d.line((0, y, W * CELL, y), fill=(0, 0, 0), width=1)
    out = os.path.join(ROOT, "godot", "original", "graphics", "WORLD")
    os.makedirs(out, exist_ok=True)
    img.save(os.path.join(out, "worldmap.png"))
    print("worldmap", img.size)


main()
