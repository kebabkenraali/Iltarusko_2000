"""City layout templates from TWI2D.EXE (unpacked) -> godot/data/city_templates.json.

Each city record in TWI2D (see t2k-native/tools/extract_data.py) points to a template shared
by all cities of the same size class. A template is a list of 7-byte records
    u8 type, u8 facing, u8 0, i16 dx, i16 dy
ending with type 0xFF. type indexes the building name table in the exe (HOUSE, TAVERN, MARKET,
JAIL, HOSPITAL, BANK, FACTORY, BARN, CHURCH); facing indexes the interior picture order
(S, W, N, E: ISHOUSE, IWHOUSE, INHOUSE, IEHOUSE). dx / dy are metres east / south of the city
point (the remake's reading; the building spacing of 15-30 m fits houses of 8 x 6 m).

Usage: extract_city_templates.py <unpacked TWI2D.EXE> <out json>
"""
import json, struct, sys

NAMEBASE = 130768                  # file offset of the data segment strings (extract_data.py)
TYPES = ["HOUSE", "TAVERN", "MARKET", "JAIL", "HOSPITAL", "BANK", "FACTORY", "BARN", "CHURCH"]
SIZES = {0: 13976, 1: 14110, 2: 14202, 3: 14266, 4: 14322}    # template offset per size class


def main():
    d = open(sys.argv[1], "rb").read()
    # the type names must sit in the exe in this order (guards against a different build)
    names = d[0x1ff80:0x1ffb4].split(b"\0")
    assert [n.decode() for n in names[:7]] == TYPES[:7], names
    out = {"_doc": __doc__.strip().splitlines()[0], "types": TYPES, "facings": ["S", "W", "N", "E"], "sizes": {}}
    for size, q in SIZES.items():
        o = NAMEBASE + q
        recs = []
        while d[o] != 0xFF:
            t, f, z, x, y = struct.unpack("<BBBhh", d[o:o + 7])
            recs.append({"type": TYPES[t], "facing": f, "dx": x, "dy": y})
            o += 7
        out["sizes"][str(size)] = recs
    json.dump(out, open(sys.argv[2], "w", encoding="utf-8"), indent=1)
    print({k: len(v) for k, v in out["sizes"].items()})


main()
