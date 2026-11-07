"""Batch AI remasters for the Godot remake (see ai_remaster.py for the method).

  remaster_set.py briefing   ICON/MOUTH0 plus its mouth and screen animation frames
  remaster_set.py sprites    every soldier part strip in ANIMS (legs, torsos, heads)
  remaster_set.py faces      the 30 character portraits (FACES men / women)
  remaster_set.py cgen       chargen background photo and hardware objects (icons stay original)
  remaster_set.py buildings  BUILDING exterior, interior and terrain pieces (UI symbols stay original)
  remaster_set.py intro [N]  the 198 INTRO.LB frames (N = stop after N new ones; painted frames are skipped)
  add --recut to cut again from the saved painted sheets without the GPU

Animation overlays: each frame is pasted into the base picture and the whole picture is painted
with the base's seed, then the frame's rectangle is cut out with a feathered edge. That way
the remastered frames line up with the remastered base.
Sprites: strips are packed onto shared sheets so the model sees enough pixels and paints every
part in the same style; the original cut-out mask is upscaled smoothly and put back.
Output: godot/remastered/<LIB>/ (4x the original size) and assets_ai/<LIB>/*_compare.png.
"""
import os, sys
import numpy as np
from PIL import Image, ImageChops, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ai_remaster as ai  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG = os.path.join(ROOT, "godot", "original", "graphics")
OUT = os.path.join(ROOT, "godot", "remastered")
CMP = os.path.join(ROOT, "assets_ai")
S = 4                                   # stored remaster scale (Godot divides by it)


def save(lib, name, img, orig):
    os.makedirs(os.path.join(OUT, lib), exist_ok=True)
    os.makedirs(os.path.join(CMP, lib), exist_ok=True)
    img.save(os.path.join(OUT, lib, name + ".png"))
    ai.compare(orig, img, S).save(os.path.join(CMP, lib, name + "_compare.png"))
    print("wrote", lib, name, img.size)


BRIEF_PROMPT = ("officer in white shirt and dark tie on a green field telephone, black clipboard, "
                "office booth, computer terminal, red mug, papers, bookshelf")
SIGN = (22, 49, 74, 58)                # the RESTRICTED sign: lettering is copied from the original
OVERLAYS = [("MOUTH", (96, 60)), ("SCREEN", (24, 90))]


def paint_brief(img):
    # painted at 6x for detail, stored at 4x; AI lettering is gibberish, so the sign stays original
    out = ai.paint(img, BRIEF_PROMPT, 6).resize((img.width * S, img.height * S), Image.LANCZOS)
    sign = img.crop(SIGN).resize(((SIGN[2] - SIGN[0]) * S, (SIGN[3] - SIGN[1]) * S), Image.NEAREST)
    out.paste(sign, (SIGN[0] * S, SIGN[1] * S))
    return out


def briefing():
    base = Image.open(os.path.join(ORIG, "ICON", "MOUTH0.png")).convert("RGB")
    save("ICON", "MOUTH0", paint_brief(base), base)
    for prefix, (x, y) in OVERLAYS:
        for i in range(1, 7):
            name = "%s%d" % (prefix, i)
            fr = Image.open(os.path.join(ORIG, "ICON", name + ".png")).convert("RGB")
            comp = base.copy()
            comp.paste(fr, (x, y))
            painted = paint_brief(comp)
            cut = painted.crop((x * S, y * S, (x + fr.width) * S, (y + fr.height) * S)).convert("RGBA")
            # feathered border so the frame melts into the remastered base under it
            m = Image.new("L", cut.size, 0)
            m.paste(255, (6, 6, cut.width - 6, cut.height - 6))
            cut.putalpha(m.filter(ImageFilter.GaussianBlur(3)))
            save("ICON", name, cut, fr)


INTRO_PROMPT = ("cinematic wide shot in a post-nuclear war Poland of the year 2000: soldiers in gas "
                "masks and ragged uniforms, a burning city skyline, a tank silhouetted against smoke")


def intro(limit=0):
    """The 198 full-screen INTRO.LB frames, painted one by one at the stored 4x size.
    A fixed seed keeps the style steady across the frames; text screens get the model's own
    lettering (as with every other picture). Already painted frames are skipped, so an
    interrupted run continues where it stopped; limit N stops after N new frames."""
    src = os.path.join(ORIG, "INTRO")
    names = sorted(f for f in os.listdir(src) if f.lower().endswith(".png"))
    done = 0
    for f in names:
        name = os.path.splitext(f)[0]
        if os.path.exists(os.path.join(OUT, "INTRO", name + ".png")):
            continue
        orig = Image.open(os.path.join(src, f)).convert("RGB")
        img = ai.paint(orig, INTRO_PROMPT, S, denoise=0.3, refine=0.15)
        save("INTRO", name, img, orig)
        done += 1
        if limit and done >= limit:
            break
    painted = len([f for f in names if os.path.exists(os.path.join(OUT, "INTRO", os.path.splitext(f)[0] + ".png"))])
    print("intro: %d new frames now, %d of %d painted" % (done, painted, len(names)))


SPRITE_GROUPS = {
    "legs": (["L"], "sheet of small game sprites: soldiers' legs in olive drab combat trousers and black "
             "army boots, walking animation frames, plain background"),
    "torsos": (["AM", "AF", "EM"], "sheet of small game sprites: soldiers' upper bodies in camouflage "
               "combat jackets with webbing, carrying rifles, plain background"),
    "heads": (["AMH", "AFH", "EMH"], "sheet of small game sprites: soldiers' heads, male and female faces, "
              "helmets, berets and short hair, plain background"),
}
DIRS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
BG = (96, 104, 88)                     # neutral backdrop behind the cut-outs while painting
KEY = (255, 85, 255)                   # magenta cut-out colour of pictures without an _rgba version


def group_files(prefixes):
    names = []
    for f in sorted(os.listdir(os.path.join(ORIG, "ANIMS"))):
        if not f.endswith("_rgba.png"):
            continue
        n = f[:-9]
        for p in prefixes:
            rest = n[len(p):]
            if n.startswith(p) and (rest in DIRS if not p.endswith("H") else rest.isdigit()):
                names.append(n)
    return names


def pack(imgs, max_w):
    """Shelf packing with a 4 px gap. Returns positions and sheet size."""
    x = y = shelf = 0
    pos, w = [], 0
    for im in imgs:
        if x and x + im.width > max_w:
            x, y, shelf = 0, y + shelf + 4, 0
        pos.append((x, y))
        x += im.width + 4
        shelf = max(shelf, im.height)
        w = max(w, x)
    return pos, (w, y + shelf)


def match_colours(painted, orig):
    """Pull each channel's mean and spread (over the opaque pixels) back to the original's:
    neighbours on a shared sheet can bleed their colours into a strip."""
    o = np.asarray(orig.convert("RGBA")).astype(np.float32)
    m = o[..., 3] > 0
    if not m.any():
        return painted
    p = np.asarray(painted.convert("RGB")).astype(np.float32)
    pm = np.asarray(orig.convert("RGBA").getchannel("A").resize(painted.size, Image.NEAREST)) > 0
    for c in range(3):
        src, ref = p[..., c][pm], o[..., c][m]
        p[..., c] = (p[..., c] - src.mean()) / (src.std() + 1e-3) * ref.std() + ref.mean()
    return Image.fromarray(np.clip(p, 0, 255).astype(np.uint8))


def frame_boxes(name, im):
    """Frames of a strip in original pixels: head strips are 8 px rows (the first 7 px),
    the others are runs of non-empty columns."""
    if name[-1].isdigit():
        return [(0, max(0, r * 8 - 1), im.width, r * 8 + 7) for r in range(8)]
    a = np.asarray(im.getchannel("A")) > 0
    cols, boxes, start = a.any(0), [], -1
    for x in range(im.width + 1):
        empty = x == im.width or not cols[x]
        if not empty and start < 0:
            start = x
        elif empty and start >= 0:
            boxes.append((start, 0, x, im.height))
            start = -1
    return boxes


def load_rgba(lib, name):
    """Original picture with transparency: the extracted _rgba cut-out, or the magenta key colour."""
    f = os.path.join(ORIG, lib, name + "_rgba.png")
    if os.path.exists(f):
        return Image.open(f).convert("RGBA")
    a = np.asarray(Image.open(os.path.join(ORIG, lib, name + ".png")).convert("RGBA")).copy()
    a[..., 3] = np.where((a[..., :3] == KEY).all(-1), 0, 255)
    return Image.fromarray(a)


def batches(imgs, area):
    """Split pictures into sheets of about `area` original pixels each."""
    out, cur, tot = [], [], 0
    for i, im in enumerate(imgs):
        a = (im.width + 4) * (im.height + 4)
        if cur and tot + a > area:
            out.append(cur)
            cur, tot = [], 0
        cur.append(i)
        tot += a
    return out + ([cur] if cur else [])


def strips(lib, names, prompt, tag, boxes=None, keep_gaps=False, area=10 ** 9, max_w=300, pixel=True,
           denoise=0.3, refine=0.15, out_suffix="_rgba"):
    """Paint cut-out pictures on shared sheets and cut them back out (see module doc).
    boxes(name, im): frames whose colours are matched separately (default: the whole picture).
    keep_gaps: keep every fully transparent column transparent (strip frame boundaries)."""
    imgs = [load_rgba(lib, n) for n in names]
    for b, idx in enumerate(batches(imgs, area)):
        sub = [imgs[i] for i in idx]
        pos, size = pack(sub, max(max_w, max(im.width for im in sub)))
        sheet = Image.new("RGB", size, BG)
        for im, p in zip(sub, pos):
            sheet.paste(im.convert("RGB"), p, im.getchannel("A"))
        # paint large enough for detail, bounded to ~1 megapixel for 12 GB of VRAM
        k = max(4, min(8, int((1.0e6 / (size[0] * size[1])) ** 0.5)))
        saved = os.path.join(CMP, "%s_sheet_%s%s.png" % (lib, tag, b if b else ""))
        if RECUT and os.path.exists(saved):
            painted = Image.open(saved).convert("RGB")      # reuse the last painting, no GPU
        else:
            painted = ai.paint(sheet, prompt, k, denoise=denoise, refine=refine, pixel=pixel)
            painted.save(saved)
        for i, im, (x, y) in zip(idx, sub, pos):
            n = names[i]
            cut = painted.crop((x * k, y * k, (x + im.width) * k, (y + im.height) * k))
            cut = cut.resize((im.width * S, im.height * S), Image.LANCZOS)
            for fb in (boxes(n, im) if boxes else [(0, 0, im.width, im.height)]):
                # per frame: one frame can drift on its own
                fr = match_colours(cut.crop(tuple(v * S for v in fb)), im.crop(fb))
                cut.paste(fr, (fb[0] * S, fb[1] * S))
            cut = cut.convert("RGBA")
            # smooth silhouette: bicubic mask, then a steep threshold curve
            a = im.getchannel("A").resize(cut.size, Image.BICUBIC)
            a = a.point(lambda v: 0 if v < 96 else 255 if v > 160 else (v - 96) * 4)
            # never smaller than the original pixels, so thin columns cannot split a frame
            cut.putalpha(ImageChops.lighter(a, im.getchannel("A").resize(cut.size, Image.NEAREST)))
            if keep_gaps:
                # frame boundaries (fully transparent columns) must stay where the original has them
                cols = (np.asarray(im.getchannel("A")) > 0).any(0)
                for cx in np.where(~cols)[0]:
                    cut.paste((0, 0, 0, 0), (int(cx) * S, 0, (int(cx) + 1) * S, cut.height))
            save(lib, n + out_suffix, cut, im)


def sprites():
    for group, (prefixes, prompt) in SPRITE_GROUPS.items():
        strips("ANIMS", group_files(prefixes), prompt, group, boxes=frame_boxes, keep_gaps=True)


FACE_REGION = (0, 0, 240, 129)          # 5 x 3 portraits of 48 x 43 on each FACES sheet
FACE_PROMPT = {"men": "grid of fifteen portraits of male soldiers, helmets, berets, camouflage, "
                      "weathered faces, dark scanline background",
               "women": "grid of fifteen portraits of tough female soldiers, natural faces, no make-up, "
                        "varied hairstyles, olive uniforms, dark scanline background"}


def faces():
    for name, prompt in FACE_PROMPT.items():
        orig = Image.open(os.path.join(ORIG, "FACES", name + ".png")).convert("RGB")
        reg = orig.crop(FACE_REGION)
        # painted at 6x, stored at 4x. 48 px faces lose their features (cigar, grimace) and drift
        # towards glamour make-up with the blur pre-step, so Scale2x and a lighter touch as for sprites
        saved = os.path.join(CMP, "FACES_sheet_%s.png" % name)
        if RECUT and os.path.exists(saved):
            painted = Image.open(saved).convert("RGB")
        else:
            painted = ai.paint(reg, prompt, 6, denoise=0.3, refine=0.15, pixel=True)
            painted = painted.resize((reg.width * S, reg.height * S), Image.LANCZOS)
            painted.save(saved)
        for r in range(3):
            for c in range(5):                 # colours matched per portrait
                b = (c * 48, r * 43, c * 48 + 48, min(reg.height, r * 43 + 43))
                fr = match_colours(painted.crop(tuple(v * S for v in b)), reg.crop(b))
                painted.paste(fr, (b[0] * S, b[1] * S))
        out = orig.resize((orig.width * S, orig.height * S), Image.NEAREST)
        out.paste(painted, (FACE_REGION[0] * S, FACE_REGION[1] * S))
        save("FACES", name, out, orig)


def cgen():
    # the background photo on its own, the hardware objects on one sheet;
    # the red scanline icons, body outlines and flags stay original (symbols, not paintings)
    tank = Image.open(os.path.join(ORIG, "CGEN", "TANK.png")).convert("RGB")
    # dark, low-contrast photo: the model moves things around at the usual strength, so go lighter
    save("CGEN", "TANK", ai.paint(tank, "black and white war photograph, tanks advancing across a "
                                  "muddy battlefield in smoke, grainy film", S, denoise=0.22, refine=0.12), tank)
    if CGEN_ONLY == ["TANK"]:
        return
    strips("CGEN", ["BASE", "JOY1", "JOY2", "OBJWALL"], "game interface objects: brown plastic arcade "
           "joystick base, joystick handle, red arrows, brushed steel panel with rivets", "objects",
           pixel=False, denoise=0.35, refine=0.2, out_suffix="")


UI_PIECES = {"ARROWS", "BOX", "COMPASS", "ICON", "INFRARED"}   # symbols: kept original


def building_groups():
    names = sorted(f[:-9] for f in os.listdir(os.path.join(ORIG, "BUILDING")) if f.endswith("_rgba.png"))
    names = [n for n in names if n not in UI_PIECES]
    inter = [n for n in names if n[:2] in ("IN", "IE", "IS", "IW") or (n[0] == "I" and n[1:].isdigit())]
    veh = [n for n in names if n not in inter and n.rstrip("0123456789") in ("V", "CV", "DV")]
    terr = [n for n in names if n not in inter and n not in veh and n[-1].isdigit() and "ROAD" not in n]
    ext = [n for n in names if n not in inter and n not in veh and n not in terr and "ROAD" not in n.upper()]
    return {
        "exterior": (ext, "isometric game tiles: walls, roofs, doors and windows of an eastern European "
                     "town, church, bank, hospital, tavern, jail, factory, weathered brick and wood"),
        "interior": (inter, "isometric game tiles: building interiors seen from above, floors, inner walls, "
                     "furniture, beds, tables, counters, rugs"),
        "terrain": (terr, "isometric game tiles: grass, mud, water, forest floor, tree stumps, bushes, rubble"),
        "vehicles": (veh, "isometric game sprites: olive military tanks and armoured vehicles, burnt-out "
                     "wrecks with shell holes and scorched metal, no markings"),
    }


def roads():
    """Flat road tiles: AI adds nothing but loses the thin kerbs, so a clean Scale2x x2 only."""
    for n in sorted(f[:-9] for f in os.listdir(os.path.join(ORIG, "BUILDING")) if f.endswith("_rgba.png")):
        if "ROAD" in n.upper():
            im = load_rgba("BUILDING", n)
            big = ai.scale2x(ai.scale2x(im.convert("RGB"))).convert("RGBA")
            big.putalpha(im.getchannel("A").resize(big.size, Image.NEAREST))
            save("BUILDING", n + "_rgba", big, im)


def buildings():
    groups = building_groups()
    for tag in (BUILDING_ONLY or groups):
        names, prompt = groups[tag]
        strips("BUILDING", names, prompt, tag, area=62000, max_w=260)
    if not BUILDING_ONLY:
        roads()


RECUT = "--recut" in sys.argv                # cut strips again from the saved sheets
if RECUT:
    sys.argv.remove("--recut")
BUILDING_ONLY, CGEN_ONLY = [], []             # optional group filters from the command line

if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "sprites":    # only some groups, e.g. "sprites torsos"
        SPRITE_GROUPS = {g: SPRITE_GROUPS[g] for g in sys.argv[2:]}
    BUILDING_ONLY = sys.argv[2:] if sys.argv[1] == "buildings" else []
    CGEN_ONLY = sys.argv[2:] if sys.argv[1] == "cgen" else []
    if sys.argv[1] == "intro":
        intro(int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 0)
    else:
        {"briefing": briefing, "sprites": sprites, "faces": faces, "cgen": cgen,
         "buildings": buildings}[sys.argv[1]]()
