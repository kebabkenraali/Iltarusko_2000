## Headless check of the chargen rules: godot --headless --path . -s tests/test_chargen_rules.gd
## Generates many random recruits and checks the manual's invariants; prints a summary.
extends SceneTree

func _init() -> void:
	var data := GameData.new()
	data.load_all()
	var careers = GameData._json("res://data/careers.json")
	var fails := 0
	var terms_total := 0
	var war_terms := {}
	var careers_seen := {}
	var officers := 0
	var N := 300
	for i in range(N):
		var cr := ChargenRules.new(careers, data.chargen, 1000 + i)
		var r := cr.random_recruit()
		var n: int = r["terms"].size()
		terms_total += n
		war_terms[n] = int(war_terms.get(n, 0)) + 1
		officers += 1 if r["officer"] else 0
		for t in r["terms"]:
			careers_seen[t["career"]] = true
		var problems: Array = []
		for a in r["attrs"]:
			if int(r["attrs"][a]) < 1 or int(r["attrs"][a]) > 10:
				problems.append("attr %s=%d" % [a, r["attrs"][a]])
		if not r["done"] or not r["war_done"]:
			problems.append("not finished")
		if r["age"] != 17 + 4 * n:
			problems.append("age")
		if n < 1 or n > 11:
			problems.append("terms %d" % n)
		if r["initiative"] < 1 or r["initiative"] > 7:
			problems.append("initiative")
		if not is_military_last(cr, r) and not cr.career(r["terms"][-1]["career"]).get("war_exempt", false):
			problems.append("war term not in the forces: " + r["terms"][-1]["career"])
		for s in r["skills"]:
			if r["skills"][s] > 25:
				problems.append("skill %s %.1f" % [s, r["skills"][s]])
		if not problems.is_empty():
			fails += 1
			if fails <= 5:
				print("FAIL seed ", 1000 + i, ": ", problems, " ", r["terms"].map(func(t): return t["career"]))
	# half-level rule, straight from the manual example: AGL 4, Wheeled Vehicle 3 -> 4 -> 4.5
	var cr2 := ChargenRules.new(careers, data.chargen, 7)
	var x := cr2.new_recruit()
	x["attrs"]["AGILITY"] = 4
	cr2.add_skill(x, "WHEELED VEHICLE", 3)
	cr2.add_skill(x, "WHEELED VEHICLE", 1)
	var a4: float = x["skills"]["WHEELED VEHICLE"]
	cr2.add_skill(x, "WHEELED VEHICLE", 1)
	var a45: float = x["skills"]["WHEELED VEHICLE"]
	if a4 != 4.0 or a45 != 4.5 or cr2.level(x, "WHEELED VEHICLE") != 4:
		fails += 1
		print("FAIL half-level rule: ", a4, " ", a45)
	# entry requirements: Ranger needs CON+STR+AGL 17
	var y := cr2.new_recruit()
	for a in y["attrs"]:
		y["attrs"][a] = 5
	var why := cr2.entry_problem(y, cr2.career("ENLISTED RANGER"))
	if why == "":
		fails += 1
		print("FAIL ranger entry allowed with 15")
	y["attrs"]["STRENGTH"] = 7
	if cr2.entry_problem(y, cr2.career("ENLISTED RANGER")) != "":
		fails += 1
		print("FAIL ranger entry refused with 17")
	print("recruits %d  avg terms %.2f  officers %d  careers used %d/%d  terms histogram %s" % [
		N, float(terms_total) / N, officers, careers_seen.size(), careers["careers"].size(), str(war_terms)])
	print("RULES TEST ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)

func is_military_last(cr: ChargenRules, r: Dictionary) -> bool:
	return cr.is_military(cr.career(r["terms"][-1]["career"]))
