"""The original world map: GAMEDATA/DW_GFY.UYB -> godot/data/worldmap.json.

156 x 92 little-endian 16-bit words, one per square kilometre. Cell (col, row) covers
a = 100 km + col .. +1, b = 178 km + row .. +1 (a east, b south; found by laying the city table
over it: every city falls on a code-4 cell). Reading of the bits (from what the cells are next
to, see docs/SUUNNITELMA.md):
  low 6 bits  0-3 open ground (variants)   50-55 forest (variants)   4 town
              5-20 road pieces (17 of 18 networks touch towns)       21 water
              22-49 river pieces                                     other: rare features
  bits 6-7    flags on towns (and a few others)
  high byte   0x80 water (a road with it is a bridge); multiples of 8 (8..112) on land:
              probably the territory number

Output: {"w", "h", "origin_km": [100, 178], "codes": [...], "terrain": "FFfR..." one letter per
cell}. Letters: G ground, F forest, W water, R road, B bridge, V river, T town, X other.
Usage: extract_worldmap.py <game dir> <out json>
"""
import json, struct, sys

W, H = 156, 92


def classify(v):
    lo, hi = v & 0x3F, v >> 8
    if lo == 4:
        return "T"
    if 5 <= lo <= 20:
        return "B" if hi & 0x80 else "R"
    if lo == 21 or (hi & 0x80 and lo <= 3):
        return "W"
    if 22 <= lo <= 49:
        return "V"
    if lo >= 50:
        return "F"
    if lo <= 3:
        return "G"
    return "X"


def main():
    game, out = sys.argv[1], sys.argv[2]
    d = open(game + "/GAMEDATA/DW_GFY.UYB", "rb").read()
    assert len(d) == W * H * 2, len(d)
    codes = list(struct.unpack("<%dH" % (W * H), d))
    terrain = "".join(classify(v) for v in codes)
    json.dump({"_doc": __doc__.strip().splitlines()[0], "w": W, "h": H, "origin_km": [100, 178],
               "codes": codes, "terrain": terrain}, open(out, "w", encoding="utf-8"))
    from collections import Counter
    print(Counter(terrain))


main()
