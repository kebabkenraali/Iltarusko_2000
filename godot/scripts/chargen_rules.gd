## Character generation rules (data: res://data/careers.json, names: chargen.json).
## Follows the 1991 manual: 32 attribute points (1-10), four background skills at +2, four-year
## terms in schools / civilian jobs / the forces, skill levels above the controlling attribute
## count half, a war check after every term (1D10 <= terms served) and one term under fire.
## A recruit is a plain Dictionary so it saves straight to JSON.
class_name ChargenRules
extends RefCounted

var rules: Dictionary
var names: Dictionary              # chargen.json: countries, skills, languages, ...
var rng := RandomNumberGenerator.new()
var face_heads: Dictionary = {}    # face_heads.json: portrait -> field head sprite, per gender

const PHYSICAL := ["STRENGTH", "CONSTITUTION", "AGILITY"]
const FIRST := {"M": ["JAN", "PIOTR", "JOHN", "MIKE", "HANS", "ERIK", "IVAN", "LASZLO", "KAREL", "DAVE", "TOM", "SERGEI"],
		"F": ["ANNA", "MARIA", "KATE", "SUSAN", "ERIKA", "INGRID", "OLGA", "EVA", "JANA", "LISA", "MARTA", "NADIA"]}
const LAST := ["NOWAK", "SMITH", "WEBER", "HANSEN", "KOWALSKI", "PETROV", "NAGY", "NOVAK", "MILLER", "JONES",
		"BAKER", "KRAUSE", "LARSEN", "IVANOV", "HORVATH", "DVORAK", "WALSH", "MORGAN", "TREMBLAY"]

func _init(careers: Dictionary, chargen: Dictionary, seed_value: int = 0) -> void:
	rules = careers
	names = chargen
	var fh = GameData._json("res://data/face_heads.json")
	if fh != null:
		face_heads = fh
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

func career(cname: String) -> Dictionary:
	for c in rules["careers"]:
		if c["name"] == cname:
			return c
	return {}

## Default field head sprite for a portrait (colour-matched; the player may change it).
func head_for(gender: String, face: int) -> int:
	var m: Array = face_heads.get(gender, [])
	return int(m[face]) if face < m.size() else face

func new_recruit() -> Dictionary:
	var r := {"name": "", "gender": "M", "face": 0, "head": head_for("M", 0), "country": "", "nationality": "",
		"attrs": {}, "skills": {}, "languages": {}, "flags": [], "terms": [], "rank": "", "officer": false,
		"branch": "", "war": false, "war_done": false, "done": false, "log": [], "hungry": false}
	for a in names["attributes"]:
		r["attrs"][a] = 1
	return r

# ---------------- origin ----------------
func nationalities(country: String) -> Array:
	return rules["nationalities"].get(country, [])

## Native and second language for a country / nationality (manual: native at +10).
func set_origin(r: Dictionary, country: String, nationality: String = "") -> void:
	r["country"] = country
	var nats := nationalities(country)
	if nats.is_empty():
		nationality = ""
	elif nationality == "" or not nats.has(nationality):
		nationality = nats[0]
	r["nationality"] = nationality
	var key := nationality if nationality != "" else country
	var langs: Array = rules["languages"].get(key, ["ENGLISH"])
	r["languages"] = {}
	r["languages"][langs[0]] = float(rules["native_language_level"])
	if langs.size() > 1:
		r["languages"][langs[1]] = float(rules["second_language_level"])

# ---------------- attributes ----------------
func points_left(r: Dictionary) -> int:
	var used := 0
	for a in r["attrs"]:
		used += int(r["attrs"][a])
	return int(rules["attribute_points"]) - used

func change_attr(r: Dictionary, attr: String, delta: int) -> bool:
	var v: int = int(r["attrs"][attr]) + delta
	if v < 1 or v > 10 or (delta > 0 and points_left(r) < delta):
		return false
	r["attrs"][attr] = v
	return true

## Random generation: every attribute 1-10, the total kept near the allocation total.
func random_attrs(r: Dictionary) -> void:
	while true:
		var total := 0
		for a in names["attributes"]:
			r["attrs"][a] = rng.randi_range(2, 10)
			total += int(r["attrs"][a])
		if abs(total - int(rules["attribute_points"])) <= 3:
			return

# ---------------- skills ----------------
func controlling(skill: String) -> String:
	return rules["skill_attribute"].get(skill, "INTELLIGENCE")

## The level of a skill as used in play (half levels are kept but rounded down).
func level(r: Dictionary, skill: String, lang: String = "") -> int:
	if skill == "LANGUAGE":
		if lang != "":
			return int(r["languages"].get(lang, 0.0))
		var best := 0.0
		for l in r["languages"]:
			if not _is_native(r, l):
				best = maxf(best, r["languages"][l])
		return int(best)
	return int(r["skills"].get(skill, 0.0))

func _is_native(r: Dictionary, lang: String) -> bool:
	return r["languages"].get(lang, 0.0) >= float(rules["native_language_level"]) and r["languages"].keys()[0] == lang

## Award skill levels one at a time: once the skill equals its controlling attribute,
## each further level counts only a half (manual p.27).
func add_skill(r: Dictionary, skill: String, levels: int = 1, lang: String = "") -> void:
	var cap := float(r["attrs"][controlling(skill)])
	for i in range(levels):
		if skill == "LANGUAGE":
			var l := lang if lang != "" else _default_language(r)
			var v: float = r["languages"].get(l, 0.0)
			r["languages"][l] = v + (0.5 if v >= cap else 1.0)
		else:
			var v: float = r["skills"].get(skill, 0.0)
			r["skills"][skill] = v + (0.5 if v >= cap else 1.0)

## LANGUAGE without a choice goes to the best non-native language, else the second language.
func _default_language(r: Dictionary) -> String:
	var best := ""
	for l in r["languages"]:
		if not _is_native(r, l) and (best == "" or r["languages"][l] > r["languages"][best]):
			best = l
	if best == "":
		for l in names["languages"]:
			if not r["languages"].has(l):
				return l
	return best

func apply_background(r: Dictionary, picks: Array, lang: String = "") -> void:
	for s in picks:
		add_skill(r, s, int(rules["background_level"]), lang if s == "LANGUAGE" else "")

# ---------------- careers ----------------
func can_be_officer(r: Dictionary) -> bool:
	var f: Array = r["flags"]
	if f.has("academy") or f.has("rotc") or f.has("commission"):
		return true
	return int(r["attrs"]["INTELLIGENCE"]) >= 7 and int(r["attrs"]["EDUCATION"]) >= 7     # OCS

## Empty string when the recruit may enter the career, else the reason (shown as a tooltip).
func entry_problem(r: Dictionary, c: Dictionary) -> String:
	if c.is_empty():
		return "unknown career"
	var terms: Array = r["terms"]
	if not terms.is_empty():
		var last: Dictionary = career(terms[-1]["career"])
		if last.get("group", "") == "EDUCATION" and terms[-1]["career"] == c["name"] and not c.get("repeat", false):
			return "schools last one term"
		if terms[-1]["career"] == "NATIONAL MILITARY ACADEMY" and not c.get("officer", false):
			return "academy graduates must serve as officers"
	if r["war"]:
		if c["group"] in ["EDUCATION", "CIVILIAN"]:
			return "war: drafted into the armed forces"
	var be: Dictionary = rules["branch_entry"].get(c["group"], {})
	var p := _req_problem(r, be)
	if p != "":
		return c["group"] + ": " + p
	return _req_problem(r, c["req"])

func _req_problem(r: Dictionary, req: Dictionary) -> String:
	if req.get("never", false):
		return "only after being caught as a criminal"
	if req.has("any"):
		var reasons: Array = []
		for alt in req["any"]:
			var p := _req_problem(r, alt)
			if p == "":
				reasons.clear()
				break
			reasons.append(p)
		if not reasons.is_empty():
			return " or ".join(reasons)
	for a in req.get("attr", {}):
		if int(r["attrs"][a]) < int(req["attr"][a]):
			return "%s %d+" % [a.capitalize(), int(req["attr"][a])]
	if req.has("sum"):
		var total := 0
		for a in req["sum"][0]:
			total += int(r["attrs"][a])
		if total < int(req["sum"][1]):
			return "%s %d+" % [" + ".join(req["sum"][0].map(func(x): return x.substr(0, 3))), int(req["sum"][1])]
	for s in req.get("skill", {}):
		if level(r, s) < int(req["skill"][s]):
			return "%s %d+" % [s.capitalize(), int(req["skill"][s])]
	if req.has("skill_any"):
		var ok := false
		for s in req["skill_any"][0]:
			ok = ok or level(r, s) >= int(req["skill_any"][1])
		if not ok:
			return "%s %d+" % [" or ".join(req["skill_any"][0]), int(req["skill_any"][1])]
	if req.has("flag"):
		var ok := false
		for f in req["flag"]:
			ok = ok or r["flags"].has(f)
		if not ok:
			return "needs " + " or ".join(req["flag"].map(_flag_name))
	for f in req.get("no_flag", []):
		if r["flags"].has(f):
			return "no %s record" % f
	if req.get("officer", false) and not can_be_officer(r):
		return "needs OCS (INT and EDU 7+), academy, ROTC or a commission"
	return ""

static func _flag_name(f: String) -> String:
	return {"undergrad": "undergraduate degree", "masters": "master's degree", "phd": "Ph.D.", "law": "law school",
		"med": "medical school", "tech": "technical school", "academy": "military academy"}.get(f, f)

func is_military(c: Dictionary) -> bool:
	return c.get("group", "") in ["ARMY", "MARINES", "NAVY", "AIR FORCE"]

## Begin a term: basic training on the first military term, starting rank. Returns the term record.
func start_term(r: Dictionary, cname: String) -> Dictionary:
	var c := career(cname)
	var t := {"career": cname, "picks": int(c["picks"]), "secondary": int(c["secondary"]), "gained": {}}
	if is_military(c):
		var first_mil := true
		for old in r["terms"]:
			first_mil = first_mil and not is_military(career(old["career"]))
		if first_mil:
			for s in rules["basic_training"]:
				add_skill(r, s, int(rules["basic_training"][s]))
			_log(r, "Basic training: Rifle, Pistol, Thrown Weapon, Unarmed Melee")
		var officer: bool = c.get("officer", false)
		if officer and not r["officer"]:
			r["officer"] = true
			r["rank"] = rules["officer_ranks"][0]
		elif not officer and not r["officer"] and r["rank"] == "":
			r["rank"] = rules["enlisted_ranks"][0]
		r["branch"] = c["group"]
	return t

## End the term: skill picks are already applied by the caller (allocate / random).
## Grants degrees, rolls promotion, ageing, arrest and the outbreak of war. Returns event lines.
func end_term(r: Dictionary, t: Dictionary) -> Array:
	var c := career(t["career"])
	var ev: Array = []
	r["terms"].append(t)
	var n: int = r["terms"].size()
	var again := false
	for old in r["terms"].slice(0, n - 1):
		again = again or old["career"] == t["career"]
	for f in (c.get("grants_again", []) if again else c.get("grants", [])):
		if not r["flags"].has(f):
			r["flags"].append(f)
			ev.append("Gained: " + _flag_name(f))
	if is_military(c):
		var ranks: Array = rules["officer_ranks"] if r["officer"] else rules["enlisted_ranks"]
		var i := ranks.find(r["rank"])
		var roll := rng.randi_range(1, 10) + (int(r["attrs"]["INTELLIGENCE"]) + int(r["attrs"]["CHARISMA"])) / 4
		if roll >= 8 and i < ranks.size() - 1:
			r["rank"] = ranks[i + 1]
			ev.append("Promoted to " + r["rank"])
	if c.has("arrest_chance") and rng.randf() < float(c["arrest_chance"]):
		r["flags"].append("prison")
		r["prison_next"] = true
		ev.append("Caught! Next term in prison.")
	# ageing from 37 on: each physical attribute may drop a point
	var age := 17 + 4 * n
	if age >= 37:
		for a in PHYSICAL:
			if rng.randi_range(1, 10) <= n - 4 and int(r["attrs"][a]) > 1:
				r["attrs"][a] = int(r["attrs"][a]) - 1
				ev.append("Age %d: %s -1" % [age, a.capitalize()])
	if r["war"]:
		r["war_done"] = true
		r["done"] = true
		ev.append("Survived a term under fire. The recruit is ready.")
	elif rng.randi_range(1, 10) <= n or n >= 10:
		r["war"] = true
		ev.append("WAR BREAKS OUT (term %d)." % n)
		if c.get("war_exempt", false):
			ev.append("Serves on in the same post through the war.")
		elif c.has("war_commission"):
			r["flags"].append("commission")
			r["war_rank"] = c["war_commission"][0]
			ev.append("Directly commissioned as %s, %s." % [c["war_commission"][0], c["war_commission"][1]])
		elif not is_military(c):
			ev.append("Drafted: choose a branch of service for one term.")
		else:
			ev.append("Stays in the %s for a term under fire." % c["group"])
	for e in ev:
		_log(r, e)
	return ev

## Careers allowed now: the forced ones first (prison, war in the same post).
func forced_career(r: Dictionary) -> String:
	if r.get("prison_next", false):
		return "PRISON"
	if r["war"] and not r["terms"].is_empty():
		var last := career(r["terms"][-1]["career"])
		if is_military(last) or last.get("war_exempt", false):
			return last["name"]
	return ""

func begin_forced(r: Dictionary) -> String:
	var f := forced_career(r)
	if f == "PRISON":
		r.erase("prison_next")
	return f

func _log(r: Dictionary, s: String) -> void:
	r["log"].append(s)

# ---------------- derived values ----------------
## Profile values computed at the end (manual p.29-30). Hit capacity per location follows the
## PC game's sheet (head 2xCON, chest 3x(STR+CON), others 2x(STR+CON)).
func finish(r: Dictionary) -> void:
	var a: Dictionary = r["attrs"]
	var s := int(a["STRENGTH"])
	var con := int(a["CONSTITUTION"])
	var n: int = r["terms"].size()
	r["age"] = 17 + 4 * n
	r["hits"] = {"HEAD": 2 * con, "CHEST": 3 * (s + con), "ABDOMEN": 2 * (s + con),
		"LEFT ARM": 2 * (s + con), "RIGHT ARM": 2 * (s + con), "LEFT LEG": 2 * (s + con), "RIGHT LEG": 2 * (s + con)}
	r["load"] = 2 * (s + con)
	r["throw"] = 4 * s
	var mil := 0
	for t in r["terms"]:
		mil += 1 if is_military(career(t["career"])) else 0
	var elite := 0
	for t in r["terms"]:
		var nm: String = t["career"]
		if "RANGER" in nm or "SEAL" in nm or "RECON" in nm or "SPECIAL" in nm or nm == "SNIPER":
			elite = 1
	r["initiative"] = clampi(1 + mil + elite + (1 if int(a["AGILITY"]) >= 8 else 0), 1, 7)
	r["rads"] = rng.randi_range(0, 20)
	r["money"] = 500 + 500 * mil
	var hit := {}
	for k in ["PISTOL", "RIFLE", "HUNTING BOW", "HEAVY WEAPONS"]:
		var v := level(r, k)
		hit[k] = [2 * v, v, v / 2, v / 4]
	r["hit_numbers"] = hit
	r["unarmed_damage"] = maxi(1, (s + 2 * level(r, "UNARMED MELEE")) / 4)
	if r.has("war_rank"):
		r["rank"] = r["war_rank"]
		r["officer"] = true
	if r["rank"] == "":
		r["rank"] = rules["enlisted_ranks"][0]
	r["done"] = true

# ---------------- random recruit ----------------
func random_recruit() -> Dictionary:
	var r := new_recruit()
	r["gender"] = "M" if rng.randf() < 0.5 else "F"
	r["face"] = rng.randi_range(0, 14)
	r["head"] = head_for(r["gender"], r["face"])
	var first: Array = FIRST[r["gender"]]
	r["name"] = "%s %s" % [first[rng.randi_range(0, first.size() - 1)], LAST[rng.randi_range(0, LAST.size() - 1)]]
	var country: String = names["countries"][rng.randi_range(0, names["countries"].size() - 1)]
	var nats := nationalities(country)
	set_origin(r, country, "" if nats.is_empty() else nats[rng.randi_range(0, nats.size() - 1)])
	random_attrs(r)
	var bg: Array = rules["background_skills"].duplicate()
	bg.shuffle()
	apply_background(r, bg.slice(0, int(rules["background_picks"])))
	var guard := 0
	while not r["done"] and guard < 14:
		guard += 1
		var cname := begin_forced(r)
		if cname == "":
			cname = _random_career(r)
		var t := start_term(r, cname)
		random_picks(r, t)
		end_term(r, t)
	finish(r)
	return r

func _random_career(r: Dictionary) -> String:
	var ok: Array = []
	var mil: Array = []
	for c in rules["careers"]:
		if entry_problem(r, c) == "":
			ok.append(c["name"])
			if is_military(c):
				mil.append(c["name"])
	# soldiers make better squad members: prefer the forces half the time
	if not mil.is_empty() and (rng.randf() < 0.5 or r["war"]):
		return mil[rng.randi_range(0, mil.size() - 1)]
	return ok[rng.randi_range(0, ok.size() - 1)]

## Spend a term's skill picks and secondary activities at random (weighted towards the first
## skills of the career list, which are its core skills).
func random_picks(r: Dictionary, t: Dictionary) -> void:
	var c := career(t["career"])
	var list: Array = c["skills"]
	for i in range(int(t["picks"])):
		var k := mini(rng.randi_range(0, list.size() - 1), rng.randi_range(0, list.size() - 1))
		add_skill(r, list[k])
		t["gained"][list[k]] = int(t["gained"].get(list[k], 0)) + 1
	var sec: Array = rules["secondary_skills"]
	for i in range(int(t["secondary"])):
		var s: String = sec[rng.randi_range(0, sec.size() - 1)]
		add_skill(r, s)
		t["gained"][s] = int(t["gained"].get(s, 0)) + 1
