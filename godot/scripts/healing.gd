## Recovering from wounds between battles (the tabletop's healing, scaled to the PC game's hit
## capacities): every 8 hours of rest each wounded location heals CON/3 points (at least 1),
## twice that when the squad's best medic passes a Medical check, three times in a real bed in
## a town, and Krakow's doctors heal everyone fully. Lost blood comes back with rest. Untreated
## bleeding is stopped by the medic first; if he fails, it goes on. Story mode: twice as fast,
## and bleeding always stops.
class_name Healing
extends RefCounted

const LOCS := ["HEAD", "CHEST", "ABDOMEN", "LEFT ARM", "RIGHT ARM", "LEFT LEG", "RIGHT LEG"]

## "UNHURT", "WOUNDED (CHEST 12/36)", "SERIOUSLY WOUNDED", "BLEEDING", "DOWN".
static func condition(r: Dictionary) -> String:
	if r.get("dead", false):
		return "KILLED IN ACTION"
	var dmg: Dictionary = r.get("damage", {})
	var hits: Dictionary = r.get("hits", {})
	var worst := 0.0
	var where := ""
	for l in LOCS:
		var v := float(dmg.get(l, 0)) / maxf(1.0, float(hits.get(l, 10)))
		if v > worst:
			worst = v
			where = l
	var s := "UNHURT"
	if worst >= 1.0:
		s = "CRITICAL (%s)" % where
	elif worst >= 0.5:
		s = "SERIOUSLY WOUNDED (%s)" % where
	elif worst > 0.0:
		s = "WOUNDED (%s)" % where
	if int(r.get("bleed", 0)) > 0:
		s += ", BLEEDING"
	return s

static func rest(squad: Array, hours: float, in_town: bool, at_hq: bool, story := false) -> Array:
	var lines: Array = []
	var medic: Dictionary = {}
	for r in squad:
		if not r.get("dead", false) and (medic.is_empty() or float(r["skills"].get("MEDICAL", 0.0)) > float(medic["skills"].get("MEDICAL", 0.0))):
			medic = r
	var mlvl := int(medic.get("skills", {}).get("MEDICAL", 0.0)) if not medic.is_empty() else 0
	var periods := maxi(1, int(hours / 8.0))
	if at_hq:
		lines.append("THE DOCTORS AT KRAKOW SEE TO THE SQUAD.")
	elif in_town:
		var lucky: String = squad[0].get("name", "SOMEBODY") if not squad.is_empty() else "SOMEBODY"
		lines.append("THE PARTY SPENDS 8 HOURS SLEEPING.  %s GETS TO SLEEP IN A REAL BED!" % lucky)
	else:
		lines.append("THE PARTY SPENDS 8 HOURS SLEEPING IN THE OPEN.  THE LACK OF A TENT MADE FOR A COLD AND UNCOMFORTABLE SLUMBER.")
	for r in squad:
		if r.get("dead", false):
			continue
		var dmg: Dictionary = r.get("damage", {})
		var con := int(r["attrs"].get("CONSTITUTION", 5))
		if int(r.get("bleed", 0)) > 0:
			if story or randf() < 0.4 + 0.08 * mlvl:
				r["bleed"] = 0
				lines.append("%s STOPS %s'S BLEEDING." % [medic.get("name", "SOMEONE"), r["name"]])
			else:
				r["blood"] = int(r.get("blood", 0)) + int(r["bleed"]) * 4
				lines.append("%s IS STILL BLEEDING." % r["name"])
				if int(r["blood"]) >= 5 * con:
					r["dead"] = true
					lines.append("BECAUSE OF SEVERE BLOOD LOSS, %s DIES." % r["name"])
					continue
		var healed := 0
		for p in range(periods):
			var amount := maxi(1, con / 3)
			if mlvl > 0 and randf() < 0.3 + 0.08 * mlvl:
				amount *= 2
			if in_town:
				amount *= 3
			if story:
				amount *= 2
			for l in dmg.keys():
				var before := int(dmg[l])
				dmg[l] = maxi(0, before - amount)
				healed += before - int(dmg[l])
			r["blood"] = maxi(0, int(r.get("blood", 0)) - 2 * con)
		if at_hq:
			for l in dmg.keys():
				healed += int(dmg[l])
				dmg[l] = 0
			r["blood"] = 0
			r["bleed"] = 0
		r["damage"] = dmg
		if healed > 0:
			lines.append("%s RECOVERS %d POINTS: %s." % [r["name"], healed, condition(r)])
	return lines
