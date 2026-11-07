"""Split the original leg strips (ANIMS/L<dir>_rgba.png) into separate frames.

The strips hold 5 frames of different widths (standing + 4 walking) that touch each other, so
cutting at empty columns gives wrong frames (a stride split in half, a boot in the next frame).
Every frame has its belt on the top row: the opaque runs of row 0 find the frames, then each
pixel goes to the belt that reaches it first through the legs (loose pieces to the nearest belt). Output:
ANIMS/cells/L<dir>.png, one cell per frame, all cells the same width with the belt centred, and
data/leg_frames.json {dir: {"cell": [w, h], "frames": n}}.
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANIMS = os.path.join(ROOT, "godot", "original", "graphics", "ANIMS")
DIRS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


def main():
    meta = {}
    os.makedirs(os.path.join(ANIMS, "cells"), exist_ok=True)
    for d in DIRS:
        img = np.array(Image.open(os.path.join(ANIMS, "L%s_rgba.png" % d)).convert("RGBA"))
        mask = img[..., 3] > 128
        # belts: runs on the top row
        belts = []
        x = 0
        row = mask[0]
        while x < len(row):
            if row[x]:
                s = x
                while x < len(row) and row[x]:
                    x += 1
                belts.append((s, x))
            x += 1
        centres = [(a + b) / 2 for a, b in belts]
        # grow every belt down its own legs (breadth first, 4-connected): where two frames
        # touch, the pixels go to the belt that reaches them first
        own = np.full(mask.shape, -1, int)
        queue = []
        for i, (a0, b0) in enumerate(belts):
            for x0 in range(a0, b0):
                own[0, x0] = i
                queue.append((0, x0))
        k = 0
        while k < len(queue):
            cy, cx0 = queue[k]
            k += 1
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = cy + dy, cx0 + dx
                if 0 <= ny < mask.shape[0] and 0 <= nx < mask.shape[1] and mask[ny, nx] and own[ny, nx] < 0:
                    own[ny, nx] = own[cy, cx0]
                    queue.append((ny, nx))
        for y0, x0 in zip(*np.nonzero(mask & (own < 0))):       # loose pieces: nearest belt
            own[y0, x0] = int(np.argmin([abs(x0 - c) for c in centres]))
        frames = []
        for i, cx in enumerate(centres):
            sel = own == i
            ys, xs = np.nonzero(sel)
            half = int(np.ceil(max(cx - xs.min(), xs.max() + 1 - cx)))
            frames.append((sel, cx, half))
        half = max(f[2] for f in frames)
        w, h = 2 * half, img.shape[0]
        out = np.zeros((h, w * len(frames), 4), np.uint8)
        for i, (sel, cx, _) in enumerate(frames):
            ys, xs = np.nonzero(sel)
            nx = (xs - cx + half).astype(int) + i * w
            out[ys, nx] = img[ys, xs]
        Image.fromarray(out, "RGBA").save(os.path.join(ANIMS, "cells", "L%s.png" % d))
        meta[d] = {"cell": [w, h], "frames": len(frames)}
        print(d, len(frames), "frames, cell", w, h)
    with open(os.path.join(ROOT, "godot", "data", "leg_frames.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
