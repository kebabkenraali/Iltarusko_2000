"""Interior rooms from the BUILDING interior kits (IS/IW/IN/IE + HOUSE, TAVERN, ...).

An interior kit holds the furniture of one building type drawn for one of four rotations
(S, W, N, E: the side the door is on). The pieces are separate islands in the picture, so they
are cut by connected components. A room is the building's footprint: floor tiled with the kit's
floor tile, the two far walls (north and east, the Lambda shape of the exterior kit's wall
piece) filled with the exterior wall patterns, furniture stood along the far walls with the
rug in the middle and the way from the door kept clear.

Output (original art at 1x; the AI remasters are set aside for now):
  BUILDING/rooms/<TYPE>_<facing>.png          floor + far walls
  BUILDING/rooms/<TYPE>_<facing>_<n>.png      one picture per furniture piece
  godot/data/rooms.json                       size, door, and per piece: ground centre, footprint,
                                              anchor (bottom centre in the picture), flat / wall
Usage: compose_rooms.py [--preview out.png]
"""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compose_buildings as cb               # noqa: E402

ROOT = cb.ROOT
K = cb.K
INTERIOR = {"HOUSE": "HOUSE", "TAVERN": "TAVERN", "MARKET": "MARKET", "JAIL": "JAIL", "HOSPITAL": "HOSP",
            "BANK": "BANK", "FACTORY": "FACT", "CHURCH": "CHURCH", "BARN": "HOUSE"}
FACINGS = ["S", "W", "N", "E"]
# floor tile of each exterior kit (x, y, w, h): the flat diamond
FLOOR = {"HOUSE": (66, 108, 44, 22), "TAVERN": (96, 0, 48, 24), "MARKET": (96, 24, 48, 24),
         "JAIL": (40, 110, 48, 23), "HOSPITAL": (96, 44, 48, 22), "BANK": (96, 30, 48, 22),
         "FACTORY": (144, 0, 48, 24), "CHURCH": (24, 84, 48, 22)}
WALL_H = 2.6                                 # interior walls lower than outside: furniture stays visible


def pieces(img):
    a = np.asarray(img)[..., 3] > 0
    lab, n = ndimage.label(a, structure=np.ones((3, 3)))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if (lab[sl] == i + 1).sum() <= 20:
            continue
        x0, y0, x1, y1 = sl[1].start, sl[0].start, sl[1].stop, sl[0].stop
        w, h = x1 - x0, y1 - y0
        kind = "flat" if h / w < 0.6 else ("wall" if w <= 26 and h >= 45 and h / w >= 2 else "stand")
        out.append({"rect": (x0, y0, w, h), "mask": lab[sl] == i + 1, "kind": kind})
    return out


def cut(img, p, s):
    x, y, w, h = p["rect"]
    piece = img.crop((x * s, y * s, (x + w) * s, (y + h) * s))
    m = Image.fromarray((p["mask"] * 255).astype(np.uint8)).resize(piece.size, Image.NEAREST)
    arr = np.asarray(piece).copy()
    arr[..., 3] = np.minimum(arr[..., 3], np.asarray(m))     # only this island (no neighbour bits)
    return Image.fromarray(arr)


def floor_tiles(dst, rect, ext, s, W, D, S):
    """Lay the kit's floor diamond on the ground grid (one tile = rect width / 2K metres),
    clipped to the room."""
    fx, fy, fw, fh = rect
    tile = ext.crop((fx * s, fy * s, (fx + fw) * s, (fy + fh) * s))
    side = fw / (2 * K)
    layer = Image.new("RGBA", (dst.shape[1], dst.shape[0]))
    for i in range(int(np.ceil(W / side)) + 1):
        for j in range(int(np.ceil(D / side)) + 1):
            x, y = S(i * side, j * side)               # the tile's left vertex
            layer.alpha_composite(tile, (int(round(x)), int(round(y - tile.height / 2))))
    yy, xx = np.mgrid[0:dst.shape[0], 0:dst.shape[1]]
    inside = cb._in_poly(xx + 0.5, yy + 0.5, [S(0, 0), S(W, 0), S(W, D), S(0, D)])
    arr = np.asarray(layer).astype(np.float32)
    m = inside & (arr[..., 3] > 0)
    dst[m] = arr[m]


def layout(W, D, facing, items):
    """Place furniture on a 1 m grid: standing pieces along the far walls (north, then east),
    flat pieces in the middle, nothing within 2.5 m of the door."""
    door = [(W / 2, D), (0, D / 2), (W / 2, 0), (W, D / 2)][facing]
    taken = []
    def free(c, r):
        if np.hypot(c[0] - door[0], c[1] - door[1]) < r + 2.5:
            return False
        if c[0] - r < 0.3 or c[1] - r < 0.3 or c[0] + r > W - 0.3 or c[1] + r > D - 0.3:
            return False
        return all(np.hypot(c[0] - t[0], c[1] - t[1]) >= r + t[2] + 0.3 for t in taken)
    spots_n = [(a + 0.5, None) for a in np.arange(0, W, 0.5)]
    placed = []
    centre_used = False
    for it in sorted(items, key=lambda i: -i["r"]):
        r = it["r"]
        if it["kind"] == "flat" and not centre_used:
            centre_used = True                 # the biggest rug lies in the middle
            placed.append((it, (W / 2, D / 2)))
            continue
        if it["kind"] == "wall":
            continue
        cands = [(a, r + 0.3) for a, _ in spots_n] + [(W - r - 0.3, b + 0.5) for b in np.arange(0, D, 0.5)]
        cands += [(a + 0.5, b + 0.5) for a in np.arange(0, W, 1.0) for b in np.arange(0, D, 1.0)]
        for c in cands:
            if free(c, r):
                taken.append((c[0], c[1], r))
                placed.append((it, c))
                break
    return placed, door


def main():
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    meta = json.load(open(os.path.join(ROOT, "godot", "data", "buildings.json"), encoding="utf-8"))
    rooms = {}
    shots = []
    for lib_root, s in ((os.path.join(ROOT, "godot", "original", "graphics"), 1),):
        out_dir = os.path.join(lib_root, "BUILDING", "rooms")
        if not os.path.exists(os.path.join(lib_root, "BUILDING", "ISHOUSE_rgba.png")):
            continue
        os.makedirs(out_dir, exist_ok=True)
        for t in cb.TYPES:
            kt = cb.KIT_OF.get(t, t)
            ext = Image.open(os.path.join(lib_root, "BUILDING", kt + "_rgba.png")).convert("RGBA")
            kit = cb.KITS[kt]
            for f in range(4):
                key = "%s_%d" % (t, f)
                W, D = meta[key]["size"]
                # the kit pieces are cut at 1x from the original (the islands), applied at scale s
                orig_kit = Image.open(os.path.join(ROOT, "godot", "original", "graphics", "BUILDING",
                                                   "I" + FACINGS[f] + INTERIOR[t] + "_rgba.png")).convert("RGBA")
                kit_img = Image.open(os.path.join(lib_root, "BUILDING", "I" + FACINGS[f] + INTERIOR[t] + "_rgba.png")).convert("RGBA")
                ps = pieces(orig_kit)
                items = []
                for p in ps:
                    w = p["rect"][2]
                    items.append({**p, "r": max(0.4, w / (2 * K) * 0.5)})
                placed, door = layout(W, D, f, items)
                # background: floor + far walls
                k = K * s
                Hz = WALL_H * cb.KZ * s
                pad = int(8 * s)
                def P(a, b, z=0.0):
                    return ((a + b) * k, (b - a) * k / 2 - z)
                xs = [P(0, 0)[0], P(W, D)[0]]
                ys = [P(W, 0, Hz)[1], P(0, D)[1]]
                ox, oy = -min(xs) + pad, -min(ys) + pad
                Wimg, Himg = int(max(xs) - min(xs) + 2 * pad), int(max(ys) - min(ys) + 2 * pad)
                def S(a, b, z=0.0):
                    x, y = P(a, b, z)
                    return (x + ox, y + oy)
                dst = np.zeros((Himg, Wimg, 4), np.float32)
                floor_tiles(dst, FLOOR[kt], ext, s, W, D, S)
                # far walls: north (NW -> NE, rises to the right) and east (NE -> SE)
                cb.fill_face(dst, [S(0, 0, Hz), S(W, 0, Hz), S(W, 0), S(0, 0)], S(0, 0, Hz), -0.5, kit["wall_s"], ext, s)
                cb.fill_face(dst, [S(W, 0, Hz), S(W, D, Hz), S(W, D), S(W, 0)], S(W, 0, Hz), 0.5, kit["wall_w"], ext, s)
                bg = Image.fromarray(np.clip(dst, 0, 255).astype(np.uint8), "RGBA")
                bg.save(os.path.join(out_dir, key + ".png"))
                furn = []
                for n, (it, c) in enumerate(placed):
                    pic = cut(kit_img, it, s)
                    pic.save(os.path.join(out_dir, "%s_%d.png" % (key, n)))
                    furn.append({"pic": "%s_%d" % (key, n), "centre": [float(c[0]), float(c[1])], "r": it["r"],
                                 "flat": it["kind"] == "flat", "size": [it["rect"][2], it["rect"][3]]})
                if s == 1:
                    nw = S(0, 0)
                    rooms[key] = {"size": [W, D], "door": [float(door[0]), float(door[1])],
                                  "facing": f, "nw": [nw[0], nw[1]], "furniture": furn}
                    if preview and t in ("HOUSE", "TAVERN", "HOSPITAL", "CHURCH") and f == 0:
                        shot = bg.copy()
                        for fi in sorted(furn, key=lambda q: (not q["flat"], q["centre"][0] + q["centre"][1])):
                            pic = Image.open(os.path.join(out_dir, fi["pic"] + ".png"))
                            cx, cy = S(fi["centre"][0], fi["centre"][1])
                            bottom = cy + fi["r"] * k
                            shot.alpha_composite(pic, (int(cx - pic.width / 2), int(bottom - pic.height)))
                        shots.append(shot)
    json.dump(rooms, open(os.path.join(ROOT, "godot", "data", "rooms.json"), "w", encoding="utf-8"), indent=1)
    if preview and shots:
        w = sum(i.width for i in shots) + 10 * len(shots)
        h = max(i.height for i in shots)
        pv = Image.new("RGBA", (w, h), (30, 30, 30, 255))
        x = 0
        for i in shots:
            pv.alpha_composite(i, (x, 0))
            x += i.width + 10
        pv.resize((pv.width * 2, pv.height * 2), Image.NEAREST).convert("RGB").save(preview)
    print("rooms", len(rooms))


if __name__ == "__main__":
    main()
