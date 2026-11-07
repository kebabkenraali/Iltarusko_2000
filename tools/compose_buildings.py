"""Compose whole isometric buildings from the BUILDING construction kits.

The 1991 kits (HOUSE, TAVERN, ...) hold wall patterns, roof strips, doors and windows drawn
in the 2:1 projection at K = 12 px per metre. The original's cut table was not found, so the
rectangles below are measured by hand from the kit pictures (see docs/SUUNNITELMA.md).
A building is a box W x D metres (W along east, D along south) with a gable roof whose ridge
runs east-west. The two faces seen from the camera are drawn: west (slopes down-right on screen)
and south (slopes up-right). Wall and roof surfaces are filled with the kit's own pattern,
sheared along the face like the art; doors and windows are pasted on top. The door goes on
the side the city template's facing names (0 S, 1 W, 2 N, 3 E; N and E are not visible).

Output: godot/original/graphics/BUILDING/composed/<TYPE>_<facing>.png (+ the same from the AI
remaster at 4x in godot/remastered/...), and buildings.json with the anchor and footprint.
Usage: compose_buildings.py [--preview out.png]
"""
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
K = 12.0                       # px per metre along the ground axes (1x, the kits' scale)
KZ = 18.0                      # px per metre upwards (a 1.8 m soldier is ~32 px)
TYPES = ["HOUSE", "TAVERN", "MARKET", "JAIL", "HOSPITAL", "BANK", "FACTORY", "BARN", "CHURCH"]

# Per kit, in original pixels. patch: (x, y, w, h, slope) a clean area inside a face whose rows
# run with that slope (+0.5 = like a west face, -0.5 = like a south face).
# decal: (x, y, w, h, face) with face "W" or "S" = the face the picture is drawn for.
KITS = {
    "HOUSE": {"size": (8, 6), "wall": 3.0, "rise": 2.2,
              "wall_w": (137, 100, 22, 16, 0.5), "wall_s": (113, 100, 22, 16, -0.5),
              "roof": (118, 14, 22, 16, 0.5),
              "door": (160, 0, 24, 56, "W"), "window": (64, 4, 44, 51, "W")},
    "TAVERN": {"size": (10, 8), "wall": 3.4, "rise": 2.4,
               "wall_w": (121, 30, 20, 16, 0.5), "wall_s": (99, 30, 20, 16, -0.5),
               "roof": (58, 14, 24, 18, 0.5),
               "door": (0, 0, 24, 48, "W"), "window": (0, 48, 24, 46, "W"),
               "door_s": (24, 0, 24, 48, "S"), "window_s": (24, 48, 24, 46, "S")},
    "MARKET": {"size": (12, 10), "wall": 3.4, "rise": 2.4,
               "wall_w": (122, 56, 20, 14, 0.5), "wall_s": (98, 56, 20, 14, -0.5),
               "roof": (58, 14, 24, 18, 0.5),
               "door": (0, 0, 24, 48, "W"), "window": (0, 48, 24, 46, "W"),
               "door_s": (24, 0, 24, 48, "S"), "window_s": (24, 48, 24, 46, "S")},
    "JAIL": {"size": (10, 8), "wall": 3.6, "rise": 0.6,
             "wall_w": (42, 56, 20, 14, 0.5), "wall_s": (66, 56, 20, 14, -0.5),
             "roof": (52, 116, 20, 8, -0.5),
             "door": (0, 0, 40, 52, "W"), "window": None},
    "HOSPITAL": {"size": (14, 10), "wall": 4.0, "rise": 1.0,
                 "wall_w": (146, 6, 18, 14, 0.5), "wall_s": (146, 44, 18, 14, -0.5),
                 "roof": (108, 50, 20, 8, -0.5),
                 "door": (0, 0, 48, 64, "W"), "window": (96, 0, 24, 48, "W"),
                 "door_s": (48, 0, 48, 64, "S"), "window_s": (120, 0, 24, 48, "S")},
    "BANK": {"size": (12, 10), "wall": 4.0, "rise": 1.2,
             "wall_w": (122, 6, 20, 12, 0.5), "wall_s": (98, 6, 20, 12, -0.5),
             "roof": (108, 36, 20, 8, -0.5),
             "door": (0, 0, 48, 62, "W"), "window": (0, 62, 48, 57, "W"),
             "door_s": (48, 0, 48, 62, "S"), "window_s": (48, 62, 48, 57, "S")},
    "FACTORY": {"size": (18, 12), "wall": 5.0, "rise": 1.5,
                "wall_w": (6, 8, 40, 16, 0.5), "wall_s": (86, 32, 36, 16, -0.5),
                "roof": (156, 4, 20, 8, -0.5),
                "door": (144, 60, 24, 37, "W"), "window": (144, 22, 24, 40, "W"),
                "door_s": (168, 60, 24, 37, "S"), "window_s": (168, 22, 24, 40, "S")},
    "CHURCH": {"size": (10, 16), "wall": 5.5, "rise": 4.0,
               "wall_w": (50, 60, 20, 14, 0.5), "wall_s": (26, 60, 20, 14, -0.5),
               "roof": (36, 18, 20, 14, -0.5),
               "door": (0, 0, 24, 50, "W"), "window": (72, 50, 16, 56, "W")},
}
KIT_OF = {"BARN": "TAVERN"}     # no kit of its own in BUILDING.LB
FACE = {"W": 0.5, "S": -0.5}


def load(lib_root, scale):
    out = {}
    for t, kit in KITS.items():
        p = os.path.join(lib_root, "BUILDING", t + "_rgba.png")
        if os.path.exists(p):
            out[t] = Image.open(p).convert("RGBA")
    return out


def fill_face(dst, poly, origin, slope, patch, src, s):
    """Fill polygon `poly` (screen px) with the patch texture sheared along `slope`.
    origin: a point on the face's top edge where face coordinates start."""
    px, py, pw, ph, pslope = patch
    a = np.asarray(src).astype(np.float32)
    flip = (pslope > 0) != (slope > 0)          # the patch was drawn for the other face: mirror
    H, W = dst.shape[:2]
    xs = [p[0] for p in poly]; ys = [p[1] for p in poly]
    x0, x1 = int(max(0, min(xs))), int(min(W, max(xs) + 1))
    y0, y1 = int(max(0, min(ys))), int(min(H, max(ys) + 1))
    yy, xx = np.mgrid[y0:y1, x0:x1]
    inside = _in_poly(xx + 0.5, yy + 0.5, poly)
    u = (xx - origin[0]) / s
    w = (yy - origin[1]) / s - slope * u
    uu = np.mod(u, pw)
    ww = np.mod(w, ph)
    if flip:
        sx = px + (pw - 1 - uu)
        sy = py + pslope * (pw - 1 - uu) + ww
    else:
        sx = px + uu
        sy = py + pslope * uu + ww
    sx = np.clip((sx * s).astype(int), 0, a.shape[1] - 1)
    sy = np.clip((sy * s).astype(int), 0, a.shape[0] - 1)
    col = a[sy, sx]
    m = inside & (col[..., 3] > 0)
    region = dst[y0:y1, x0:x1]
    region[m] = col[m]
    # holes in the patch (transparent pixels): fill with the patch's average colour
    hole = inside & ~(col[..., 3] > 0)
    if hole.any():
        avg = a[int(py * s):int((py + ph) * s), int(px * s):int((px + pw) * s)]
        avg = avg[avg[..., 3] > 0][:, :4].mean(0)
        region[hole] = avg


def _in_poly(x, y, poly):
    inside = np.zeros(x.shape, bool)
    n = len(poly)
    for i in range(n):
        xa, ya = poly[i]; xb, yb = poly[(i + 1) % n]
        cond = ((ya > y) != (yb > y)) & (x < (xb - xa) * (y - ya) / (yb - ya + 1e-9) + xa)
        inside ^= cond
    return inside


def paste_decal(dst_img, src, decal, face, at, s):
    """Paste a door/window so that its bottom-left corner sits at `at` (screen px) on `face`."""
    x, y, w, h, dface = decal
    piece = src.crop((int(x * s), int(y * s), int((x + w) * s), int((y + h) * s)))
    if dface != face:
        piece = piece.transpose(Image.FLIP_LEFT_RIGHT)
    # the bottom-left of a west-face piece is its lowest-left point; a south-face piece's
    # bottom-left is lower than its bottom-right by w/2
    if face == "W":
        top = at[1] - piece.height + (w * s) * 0.5
    else:
        top = at[1] - piece.height
    dst_img.alpha_composite(piece, (int(round(at[0])), int(round(top))))


def compose(t, facing, src, s):
    kt = KIT_OF.get(t, t)
    kit = dict(KITS[kt])
    if t == "BARN":
        kit.update({"size": (12, 8), "window": None, "window_s": None})
    Wm, Dm = kit["size"]
    Hz = kit["wall"] * KZ * s
    Rz = kit["rise"] * KZ * s
    k = K * s
    pad = int(8 * s)
    # screen coordinates relative to the NW ground corner (a=0, b=0)
    def P(a, b, z=0.0):
        return ((a + b) * k, (b - a) * k / 2 - z)
    pts = [P(0, 0), P(Wm, 0), P(Wm, Dm), P(0, Dm), P(0, 0, Hz + Rz), P(Wm, Dm / 2, Hz + Rz), P(Wm, 0, Hz)]
    minx = min(p[0] for p in pts); maxx = max(p[0] for p in pts)
    miny = min(p[1] for p in pts) - Rz; maxy = max(p[1] for p in pts)
    ox, oy = -minx + pad, -miny + pad
    Wimg, Himg = int(maxx - minx + 2 * pad), int(maxy - miny + 2 * pad)
    def S(a, b, z=0.0):
        x, y = P(a, b, z)
        return (x + ox, y + oy)
    dst = np.zeros((Himg, Wimg, 4), np.float32)
    nw, sw, se = S(0, 0), S(0, Dm), S(Wm, Dm)
    nw_t, sw_t, se_t = S(0, 0, Hz), S(0, Dm, Hz), S(Wm, Dm, Hz)
    ridge_w, ridge_e = S(0, Dm / 2, Hz + Rz), S(Wm, Dm / 2, Hz + Rz)
    # west wall + gable, south wall
    fill_face(dst, [nw_t, sw_t, sw, nw], nw_t, 0.5, kit["wall_w"], src, s)
    fill_face(dst, [nw_t, ridge_w, sw_t], nw_t, 0.5, kit["wall_w"], src, s)
    fill_face(dst, [sw_t, se_t, se, sw], sw_t, -0.5, kit["wall_s"], src, s)
    # north roof slope: seen from above when the roof is low (flat-roofed JAIL, BANK, HOSPITAL,
    # FACTORY); without it the back half of the west wall stands alone. The south slope covers it
    # on steep roofs.
    ne_t = S(Wm, 0, Hz)
    fill_face(dst, [nw_t, ne_t, ridge_e, ridge_w], nw_t, -0.5, kit["roof"], src, s)
    # south roof slope (rows run like the south eave)
    fill_face(dst, [sw_t, se_t, ridge_e, ridge_w], sw_t, -0.5, kit["roof"], src, s)
    img = Image.fromarray(np.clip(dst, 0, 255).astype(np.uint8), "RGBA")
    # openings: one door on the facing side (if visible), windows on the rest of both faces
    door_face = {0: "S", 1: "W"}.get(facing)
    for face, length in (("W", Dm), ("S", Wm)):
        seg = 2.0 if kit["door"][2] <= 24 else 4.0
        n = max(1, int(length // seg))
        mid = n // 2
        for i in range(n):
            centre = (i + 0.5) * length / n
            if face == "W":
                bl = S(0, centre - seg / 4)
            else:
                bl = S(centre - seg / 4, Dm)
            # the V pieces have a half for each face; mirroring would turn the BANK sign around
            door = kit.get("door_s") if face == "S" and kit.get("door_s") else kit["door"]
            window = kit.get("window_s") if face == "S" and kit.get("window_s") else kit["window"]
            if face == door_face and i == mid:
                paste_decal(img, src, door, face, bl, s)
            elif i % 2 == (0 if n % 2 else 1) and window:
                up = (bl[0], bl[1] - 0.7 * KZ * s)
                paste_decal(img, src, window, face, up, s)
    anchor = (sw[0], sw[1])                       # the south-west ground corner
    return img, {"anchor": [anchor[0] / s, anchor[1] / s], "nw": [nw[0] / s, nw[1] / s],
                 "size": [Wm, Dm], "kit": kt}


def main():
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    meta = {}
    for lib_root, s in ((os.path.join(ROOT, "godot", "original", "graphics"), 1),
                        (os.path.join(ROOT, "godot", "remastered"), 4)):
        srcs = load(lib_root, s)
        if not srcs:
            continue
        out = os.path.join(lib_root, "BUILDING", "composed")
        os.makedirs(out, exist_ok=True)
        tiles = []
        for t in TYPES:
            kt = KIT_OF.get(t, t)
            if kt not in srcs:
                continue
            for f in range(4):
                img, m = compose(t, f, srcs[kt], s)
                img.save(os.path.join(out, "%s_%d.png" % (t, f)))
                meta["%s_%d" % (t, f)] = m
                if f in (0, 1):
                    tiles.append(img)
        if preview and s == 1:
            wsum = sum(i.width for i in tiles) + 8 * len(tiles)
            pv = Image.new("RGBA", (min(wsum, 1800), 600), (70, 90, 60, 255))
            x = y = rowh = 0
            for i in tiles:
                if x + i.width > pv.width:
                    x, y, rowh = 0, y + rowh + 8, 0
                pv.alpha_composite(i, (x, y))
                x += i.width + 8
                rowh = max(rowh, i.height)
            pv.resize((pv.width * 2, pv.height * 2), Image.NEAREST).convert("RGB").save(preview)
    json.dump(meta, open(os.path.join(ROOT, "godot", "data", "buildings.json"), "w", encoding="utf-8"), indent=1)
    print("composed", len(meta))


if __name__ == "__main__":
    main()
