"""Mission data for the remake, assembled from the original texts (no retyping).

ICON.EXE holds the radio briefings as fragments: the game prints them with names in between.
TWI2D.EXE holds what the city leaders say: the opening (with the reward), the reminders while
the job is not done, and the thanks. Each template below is a list of text offsets and
placeholders:  {leader} squad leader, {target} the city in trouble, {source} where the goods or
the exiles are, {home} the exiles' occupied home city, {hostage} the city the hostage was moved
to, {goods}, {disease}, {area}, {vehicle}, {reward}. A %s in a TWI2D text is the city named in
the mission spec ("pct").  Which name goes between two fragments is read from the sentences.

Output: godot/data/missions.json
Usage: build_missions.py
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TXT = os.path.join(ROOT, "assets_original", "text")
L, T, S, H, X, G, D, A, V, R = ("{leader}", "{target}", "{source}", "{home}", "{hostage}", "{goods}",
                                "{disease}", "{area}", "{vehicle}", "{reward}")

TYPES = {
    "supplies": {
        "brief": [[95342, L, 95368, T, 95450, G, 95502, S, 95594, T, 95673, T, 95734],
                  [95811, L, 95820, T, 95939, G, 95982, S, 96083, T, 96164, T, 96209],
                  [L, 96337, L, 96390, T, 96472, G, 96498, S, 96662, G, 96686, T, 96722],
                  [L, 96805, T, 96880, G, 97015, S, 97061, T, 97101, S, 97165, T, 97239]],
        "intro": [[157190], [157479], [157800]], "pct": G,
        "nag": [[162761], [162835], [162902]], "done": [[124960]],
        "steps": ["talk:source", "talk:target"], "item": "CRATE OF SUPPLIES"},
    "spy": {
        "brief": [[97393, L, 97403, L, 97453, T, 97664, L, 97839], [97931, L, 97947, T, 98044, L, 98351]],
        "intro": [[158108], [158459], [158807]], "nag": [[163012], [163076], [163162]], "done": [[125225]],
        "steps": ["talk:target", "spy:target", "talk:target"]},
    "hostage": {
        "brief": [[98410, L, 98421, T, 98527], [98802, L, 98826, T, 98944, T, 99015]],
        "intro": [[156309], [156576], [156870]], "pct": X,
        "nag": [[161866], [161935], [162041]], "done": [[123968]],
        "steps": ["talk:target", "clear:hostage", "talk:target"], "item": "HOSTAGE PAPERS"},
    "assassins": {
        "brief": [[99253, L, 99270, T, 99377], [L, 99726, T, 99885, L, 100160]],
        "intro": [[153734, R], [154008, R], [154241, R]],
        "nag": [[162148], [162220], [162347]], "done": [[124251]],
        "steps": ["talk:target", "clear:target", "talk:target"]},
    "wounded": {
        "brief": [[L, 100254, T, 100327, T, 100486], [100700, L, 100725, T, 100780, T, 100949]],
        "intro": [[152990, R], [153206, R], [153431, R]],
        "nag": [[162394], [162451], [162536]], "done": [[124598]],
        "steps": ["talk:target", "treat:target", "talk:target"]},
    "epidemic": {
        "brief": [[101209, L, 101220, T, 101297, D, 101366, T, 101469, T, 101559],
                  [101644, L, 101660, D, 101705, T, 101735, L, 101980]],
        "intro": [[152314, 160229, R, 160280], [152602, T, 160143, 160229, R, 160280], [152788, 160229, R, 160280]],
        "nag": [[162587], [162635], [162699]], "done": [[124787]],
        "steps": ["talk:target", "treat:target", "talk:target"]},
    "exile": {
        "brief": [[102215, L, 102227, H, 102281, S, 102432, H, 102518],
                  [L, 102583, H, 102690, S, 102803, S, 102877, H, 102941]],
        "intro": [[154659], [155152], [155724]], "pct": H,
        "nag": [[163508], [163654], [163799]], "done": [[125794]], "wait": [[160298]],
        "steps": ["talk:source", "clear:home", "talk:source"]},
    "dump": {
        "brief": [[103106, L, 103124, L, 103135, T, 103165, T, 103333], [L, 103561, T, 103653, T, 103818]],
        "intro": [[159359], [159469], [159773]], "nag": [[163279], [163378], [163437]], "done": [[125484]],
        "steps": ["talk:target", "search:target", "reach:KRAKOW"], "item": "LARGE CRATE OF SUPPLIES"},
    "tank": {
        "brief": [[104318, T, 104359, T, 104571, L, 104603]],
        "intro": [[164812]], "nag": [[164672], [164755]], "done": [[126487]],
        "steps": ["talk:target", "clear:target", "talk:target"], "needs": "M5/M6 (vehicle combat)"},
    "defend": {
        "brief": [[104833, L, 104860, T, 104978, T, 105050, A, 105136, L, 105244],
                  [L, 105429, T, 105557, A, 105773, L, 105932],
                  [105976, L, 106015, T, 106147, T, 106278, A, 106351]],
        "intro": [[160106]], "nag": [[163899], [163978], [164108]], "done": [[126212]],
        "steps": ["talk:target", "clear:target", "talk:target"]},
    "liberate": {
        "brief": [[106534, L, 106543, T, 106642, T, 106781], [L, 106951, L, 106972, T, 107020, T, 107205, L, 107364]],
        "intro": [[164228]], "nag": [[164375], [164524]], "done": [[126373]],
        "steps": ["talk:target", "clear:target", "talk:target"]},
    "vehicle": {
        "brief": [[107422, L, 107438, L, 107451, T, 107596, L, 107930], [107958, L, 107967, V, 108056, T, 108073]],
        "intro": [[160106]], "nag": [], "done": [[160659]],
        "steps": ["repair:target"], "needs": "M6 (vehicles)"},
}
STORY = [87866, 88221, 88604, 89029, 89511, 90127, 90843, 91612, 92228, 92629, 93426, 93779]
LISTS = {
    "goods": [84859, 84868],
    "diseases": [84891, 84901, 84909, 84921, 84931, 84941, 84955, 84962, 84977],
    "areas": [104695, 104726, 104755, 104785, 104814],
    "vehicles": [84994, 144214],
    "city_goods": [144116, 144150, 144170, 144194],
}
LINES = {   # TWI2D: what the squad and the people say around the missions
    "leader_hello": 160106, "leader_waiting": 160617, "loyalty": 160551, "papers": 160730,
    "too_many_died": 160951, "city_lost": 161104, "nothing_to_say": 164982, "not_interested": 165384,
    "talk_time": 165436, "not_close": 165332, "initiates": 165096, "recommends_hq": 165150,
    "no_translator": 165185, "speaking": 165278, "spy_unsure": 161361, "spy_not_good": 161441,
    "spy_best": 161507, "spy_get_other": 161543, "spy_found": 161579, "spy_fight": 161623,
    "spy_fun": 161658, "spy_innocent": 161718, "spy_denies": 161807, "thanks_again": 164935,
    "slow": 85706, "crate_loaded": 151528, "need_truck": 151563, "no_room": 151695,
}


def load():
    out = {}
    for f in ("ICON", "TWI2D"):
        for x in json.load(open(os.path.join(TXT, f + ".json"), encoding="utf-8")):
            out[(f, x["offset"])] = x["text"]
    return out


def text(db, off):
    for f in ("ICON", "TWI2D"):
        t = db.get((f, off))
        if t is not None:
            # a stray byte from the neighbouring code sometimes precedes the text
            while t and not (t[0].isalnum() or t[0] in ".,!'\"{(%" or t[0] == " "):
                t = t[1:]
            if t[:1] in "[_x" and t[1:2] in ", COMEMA" and t[:2] != "x ":
                t = t[1:] if t[0] in "[_" else t
            return t
    raise KeyError(off)


def clean_lead(t):
    """Fragments of the briefings start with a printing-control letter in a few places
    (e.g. 'pj, THIS IS', 'eEXOR', 'mCOME', 'qEXOR', 'MuEXOR', 'xMAYDAY', '_cCOME', '{1 KILO')."""
    for junk in ("pj", "MuE", "_c", "_", "[", "e", "m", "q", "x", "{", "Mu", "c"):
        if t.startswith(junk) and len(t) > len(junk) and (t[len(junk)] in ",. " or t[len(junk):].startswith(("EXOR", "COME", "MAYDAY", "1 KILO", "E"))):
            rest = t[len(junk):]
            if junk == "MuE":
                rest = "E" + rest
            if rest.startswith(("EXOR", "COME", ",", ".", " ", "1 KILO", "MAYDAY", "EX")):
                return rest
    return t


def parts(db, spec):
    out = []
    for p in spec:
        out.append(p if isinstance(p, str) else clean_lead(text(db, p)))
    return out


def main():
    db = load()
    res = {"_doc": __doc__.strip().splitlines()[0], "types": {}, "story": [], "lists": {}, "lines": {}}
    for name, t in TYPES.items():
        e = {"steps": t["steps"]}
        for k in ("brief", "intro", "nag", "done", "wait"):
            if k in t:
                e[k] = [parts(db, v) for v in t[k]]
        for k in ("pct", "item", "needs"):
            if k in t:
                e[k] = t[k]
        res["types"][name] = e
    res["story"] = [clean_lead(text(db, o)) for o in STORY]
    for k, offs in LISTS.items():
        vals = [clean_lead(text(db, o)) for o in offs]
        if k == "city_goods":
            vals = [v[v.index("AMMUNITION"):] if "AMMUNITION" in v else v for v in vals]
        res["lists"][k] = vals
    res["lines"] = {k: clean_lead(text(db, o)) for k, o in LINES.items()}
    json.dump(res, open(os.path.join(ROOT, "godot", "data", "missions.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    # print the first briefing of every type as a check
    for n, e in res["types"].items():
        print(n, "|", " ".join(e["brief"][0])[:220])
    print(res["lists"])


main()
