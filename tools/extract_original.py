#!/usr/bin/env python3
"""Extract the ORIGINAL 1991 Twilight: 2000 DOS game assets.

This tool reads only files from YOUR OWN copy of the original game. It writes:

  <out>/graphics/<ARCHIVE>/<NAME>.bin   raw sprite payload from an .LB archive
  <out>/graphics/<ARCHIVE>/_meta.json   sprite header (palette map, w, h, payload size)
  <out>/graphics/ART/<NAME>.png         decoded IFF-ILBM pictures (requires Pillow)
  <out>/graphics/ART/<NAME>.mcg         raw small sprites from ART/
  <out>/audio/music/<NAME>.cmf          AdLib music (original format)
  <out>/audio/sfx/<NAME>.wav             SoundBlaster VOC converted to 8-bit WAV
  <out>/manifest.json                   what was extracted

IMPORTANT LIMITATION
--------------------
The .LB sprites use the game's custom token compression. This tool exposes the raw
payload and its decoded header, but does NOT yet turn those tokens into PNG pixels.
The IFF-ILBM pictures and VOC sounds are fully decoded. The old project's private
t2k-native/tools/extract_graphics.py could decode the sprites, but it was never
published; if it resurfaces, drop it next to this file and re-run.

Usage:
    python tools/extract_original.py --game "C:\\path\\to\\original\\T2000" \
        --out godot/original

Requires: Python 3.9+, Pillow (only for the ILBM -> PNG step).
"""
import argparse
import json
import os
import shutil
import struct
import sys

LB_NAMES = ("ANIMS", "BUILDING", "CGEN", "CMBT", "FACES", "ICON", "OFFICE")
LB_DATA_START = 6          # u16 count, u16 unknown, then the member data
LB_ENTRY_SIZE = 12         # u32 offset + 8-byte name, directory at EOF


def find_game(arg):
    if arg:
        return arg
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    candidates = [
        os.path.join(here, "gamedata", "C", "T2000"),
        os.path.join(here, "..", "gamedata", "C", "T2000"),
        os.path.join(here, "..", "Twilight-2000_DOS_EN", "gamedata", "C", "T2000"),
    ]
    for c in candidates:
        if os.path.isfile(os.path.join(c, "GAMEDATA", "ANIMS.LB")):
            return os.path.abspath(c)
    return None


def read_lb(path):
    """Yield (name, data) for every member of a Twilight 2000 .LB archive."""
    with open(path, "rb") as fh:
        blob = fh.read()
    count = struct.unpack_from("<H", blob, 0)[0]
    directory = blob[len(blob) - count * LB_ENTRY_SIZE:]
    entries = []
    for i in range(count):
        rec = directory[i * LB_ENTRY_SIZE:(i + 1) * LB_ENTRY_SIZE]
        offset = struct.unpack_from("<I", rec, 0)[0]
        name = rec[4:].split(b"\0", 1)[0].decode("ascii", "replace")
        entries.append((offset, name))
    for i, (offset, name) in enumerate(entries):
        end = entries[i + 1][0] if i + 1 < len(entries) else len(blob) - count * LB_ENTRY_SIZE
        yield name, blob[LB_DATA_START + offset:LB_DATA_START + end]


def sprite_header(data):
    """The first 22 bytes of an .LB member describe a 16-colour compressed sprite."""
    if len(data) < 22:
        return None
    w, h, payload = struct.unpack_from("<HHH", data, 16)
    return {
        "palette_map": list(data[:16]),
        "width": w,
        "height": h,
        "payload_size": payload,
        "has_payload": len(data) >= 22 + payload,
    }


def ilbm_rle(data, expected):
    """Unpack the game's flat PackBits stream (the whole BODY, not per-plane rows)."""
    out = bytearray()
    pos = 0
    while pos < len(data) and len(out) < expected:
        n = data[pos]
        pos += 1
        if n < 128:
            out += data[pos:pos + n + 1]
            pos += n + 1
        elif n > 128:
            b = data[pos]
            pos += 1
            out += bytes([b]) * (257 - n)
    return bytes(out[:expected])


def decode_ilbm(path, out_png):
    from PIL import Image  # imported lazily: text/audio-only runs need no Pillow

    with open(path, "rb") as fh:
        d = fh.read()
    if d[:4] != b"FORM" or d[8:12] not in (b"ILBM", b"PBM "):
        return False
    w = h = planes = compression = 0
    palette = []
    body = b""
    pos = 12
    while pos + 8 <= len(d):
        cid = d[pos:pos + 4]
        size = struct.unpack_from(">I", d, pos + 4)[0]
        chunk = d[pos + 8:pos + 8 + size]
        pos += 8 + size + (size & 1)
        if cid == b"BMHD":
            w, h = struct.unpack_from(">HH", chunk, 0)
            planes, compression = chunk[8], chunk[10]
        elif cid == b"CMAP":
            palette = [tuple(chunk[i:i + 3]) for i in range(0, len(chunk), 3)]
        elif cid == b"BODY":
            body = chunk
    if not (w and h and planes and body):
        return False
    # The original writes an indexed (chunky) picture into the IFF BODY, even though
    # BMHD advertises 8 planes. The stream is PackBits-compressed as one flat block.
    flat = ilbm_rle(body, w * h) if compression == 1 else body[:w * h]
    img = Image.new("RGB", (w, h))
    img.putdata([palette[i] if i < len(palette) else (0, 0, 0) for i in flat])
    img.save(out_png)
    return True


def voc_to_wav(path, out_wav):
    """Copy the first 8-bit PCM chunk of a Creative Voice file into a WAV file."""
    with open(path, "rb") as fh:
        d = fh.read()
    if d[:19] != b"Creative Voice File" or d[19] != 0x1A:
        return False
    pos = struct.unpack_from("<H", d, 20)[0] or 0x1A
    pcm = b""
    rate = 8000
    while pos + 4 <= len(d):
        kind = d[pos]
        length = d[pos + 1] | (d[pos + 2] << 8) | (d[pos + 3] << 16)
        body = d[pos + 4:pos + 4 + length]
        pos += 4 + length
        if kind == 1 and length >= 2:
            div = body[0]
            codec = body[1]
            rate = 1000000 // (256 - div) if div else 8000
            if codec == 0:
                pcm = body[2:]
                break
        elif kind == 0:
            break
    if not pcm:
        return False
    hdr = b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt " + struct.pack(
        "<IHHIIHH", 16, 1, 1, rate, rate, 1, 8) + b"data" + struct.pack("<I", len(pcm))
    with open(out_wav, "wb") as fh:
        fh.write(hdr + pcm)
    return True


def copy_reference_png(ref_root, lib, name, dest_dir):
    """Use a previously extracted PNG as the sprite payload's picture.

    This is a FALLBACK, not the token codec: the .LB member still tells us the
    exact sprite name, and the reference directory supplies its decoded pixels.
    Prefers an *_rgba.png (already has transparency); otherwise converts the
    indexed picture by turning the game's magenta chroma key transparent.
    """
    from PIL import Image

    base = os.path.join(ref_root, "graphics", lib, name)
    src = base + "_rgba.png"
    if not os.path.isfile(src):
        src = base + ".png"
    if not os.path.isfile(src):
        return False
    os.makedirs(dest_dir, exist_ok=True)
    dst = os.path.join(dest_dir, name + ".png")
    im = Image.open(src)
    if im.mode == "RGBA":
        im.save(dst)
    else:
        rgb = im.convert("RGB")
        data = []
        for r, g, b in rgb.getdata():
            data.append((0, 0, 0, 0) if (r, g, b) == (255, 85, 255) else (r, g, b, 255))
        out = Image.new("RGBA", rgb.size)
        out.putdata(data)
        out.save(dst)
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", help="directory containing GAMEDATA/ANIMS.LB etc.")
    ap.add_argument("--out", default="godot/original", help="output directory")
    ap.add_argument("--reference-dir", help="directory with already extracted graphics/<LIB>/*.png; used as a sprite fallback")
    ap.add_argument("--verify", action="store_true", help="only report, write nothing")
    args = ap.parse_args()

    game = find_game(args.game)
    if not game or not os.path.isfile(os.path.join(game, "GAMEDATA", "ANIMS.LB")):
        ap.error("original game not found; pass --game <dir containing GAMEDATA>")
    gd = os.path.join(game, "GAMEDATA")
    out = os.path.abspath(args.out)
    manifest = {"game": game, "archives": {}, "illbm": [], "voc": [], "copied": []}

    for lib in LB_NAMES:
        path = os.path.join(gd, lib + ".LB")
        if not os.path.isfile(path):
            continue
        members = {}
        pngs = 0
        for name, data in read_lb(path):
            info = sprite_header(data)
            members[name] = info or {"length": len(data)}
            if not args.verify:
                dest = os.path.join(out, "graphics", lib)
                os.makedirs(dest, exist_ok=True)
                with open(os.path.join(dest, name + ".bin"), "wb") as fh:
                    fh.write(data)
                if args.reference_dir and copy_reference_png(args.reference_dir, lib, name, dest):
                    pngs += 1
        manifest["archives"][lib] = members
        extra = f" (+{pngs} PNG from reference)" if pngs else ""
        print(f"{lib}.LB: {len(members)} members{extra}")

    art = os.path.join(game, "ART")
    if os.path.isdir(art):
        for fn in sorted(os.listdir(art)):
            src = os.path.join(art, fn)
            if not os.path.isfile(src):
                continue
            stem, ext = os.path.splitext(fn)
            if ext.lower() == ".lbm":
                ok = False
                if not args.verify:
                    dest = os.path.join(out, "graphics", "ART")
                    os.makedirs(dest, exist_ok=True)
                    try:
                        ok = decode_ilbm(src, os.path.join(dest, stem + ".png"))
                    except Exception as exc:
                        print(f"  ! {fn}: {exc}", file=sys.stderr)
                manifest["illbm"].append({"file": fn, "decoded": ok})
                print(f"ART/{fn}: ILBM {'OK' if ok else '(raw only)'}")
            elif ext.lower() in (".mcg", ".cm", ".cmap"):
                if not args.verify:
                    dest = os.path.join(out, "graphics", "ART")
                    os.makedirs(dest, exist_ok=True)
                    shutil.copy2(src, os.path.join(dest, fn))
                manifest["copied"].append("ART/" + fn)

    music = os.path.join(out, "audio", "music")
    sfx = os.path.join(out, "audio", "sfx")
    for fn in sorted(os.listdir(gd)):
        src = os.path.join(gd, fn)
        if not os.path.isfile(src):
            continue
        stem, ext = os.path.splitext(fn)
        if ext.lower() == ".cmf":
            if not args.verify:
                os.makedirs(music, exist_ok=True)
                shutil.copy2(src, os.path.join(music, fn))
            manifest["copied"].append("GAMEDATA/" + fn)
        elif ext.lower() == ".voc":
            ok = False
            if not args.verify:
                os.makedirs(sfx, exist_ok=True)
                ok = voc_to_wav(src, os.path.join(sfx, stem + ".wav"))
            manifest["voc"].append({"file": fn, "converted": ok})
            print(f"GAMEDATA/{fn}: VOC {'-> WAV' if ok else '(unsupported)'}")

    equip = os.path.join(gd, "EQUIP.TXT")
    if os.path.isfile(equip) and not args.verify:
        os.makedirs(os.path.join(out, "text"), exist_ok=True)
        shutil.copy2(equip, os.path.join(out, "text", "EQUIP.txt"))

    if not args.verify:
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, indent=2)
        print(f"\nWrote {sum(len(m) for m in manifest['archives'].values())} raw sprites, "
              f"{sum(1 for i in manifest['illbm'] if i['decoded'])} ILBM pictures and "
              f"{sum(1 for v in manifest['voc'] if v['converted'])} WAV files to {out}")
        print("NOTE: .LB sprite payloads are still token-compressed; PNG decoding is not implemented.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
