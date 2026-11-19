## Headless combat checks: godot --headless --path . -s tests/test_battle.gd
## Many auto-played battles (both sides by the AI) for the numbers, plus rule checks:
## armour against fragments, bleeding to death, first aid, vehicles against vehicles and
## infantry against armour, experience written back to the recruits.
extends SceneTree

var data := GameData.new()
var fails := 0

func _init() -> void:
	data.load_all()
	var careers = GameData._json("res://data/careers.json")
	var cr := ChargenRules.new(careers, data.chargen, 31)
	_infantry(cr, "MARAUDERS", 4, 150)
	_infantry(cr, "BLACK LEGION PATROL", 5, 150)
	_infantry(cr, "BLACK LEGION PATROL", 3, 150)
	_infantry(cr, "MARAUDERS", 4, 150, true)
	_infantry(cr, "BLACK LEGION PATROL", 5, 150, true)
	_infantry(cr, "BLACK LEGION PATROL", 3, 150, true)
	_grenades(cr)
	_bleeding(cr)
	_tanks()
	_trees_and_craters(cr)
	_tank_mission(cr, false)
	_tank_mission(cr, true)
	_indoors(cr)
	_infantry_vs_armour(cr)
	_experience(cr)
	print("BATTLE TEST ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _squad(cr: ChargenRules, n: int) -> Array:
	var sq: Array = []
	for i in range(n):
		var r := cr.random_recruit()
		Forces.equip(r)
		sq.append(r)
	return sq

func _field(seed_value: int) -> Battle:
	var b := Battle.new(40, 30, data.items, Forces.vehicle_guns(), seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(60):                     # a few trees for cover
		b.set_blocked(Vector2i(rng.randi_range(8, 31), rng.randi_range(0, 29)))
	return b

func _infantry(cr: ChargenRules, gname: String, count: int, n: int, story := false) -> void:
	var wins := 0
	var dead := 0
	var rounds := 0
	var hits := 0
	for k in range(n):
		var b := _field(500 + k)
		b.options["story"] = story
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + k
		var sq := _squad(cr, 4)
		var mine: Array = []
		for i in range(sq.size()):
			mine.append(b.add_man("squad", sq[i], Vector2i(2, 10 + i * 3), i))
		Forces.deploy_squad(b, mine, Vector2i(4, 15), Vector2(1, 0))
		var g := Forces.group(gname, count, rng)
		var foes: Array = []
		for t in g["men"]:
			foes.append(b.add_man("enemy", t, Vector2i(35, 15)))
		Forces.deploy_enemies(b, foes, Vector2i(34, 15), Vector2(-1, 0), rng)
		b.auto_play(30)
		b.aftermath()
		if b.winner == "squad":
			wins += 1
		dead += mine.filter(func(u): return u["state"] == "dead").size()
		rounds += b.round_no
		hits += b.log.filter(func(l): return String(l).contains(" AND HITS ")).size()
	print("%-6s %-20s x%d: squad wins %d%%, squad dead per battle %.2f, rounds %.1f, hits %.1f" % ["STORY" if story else "NORMAL", gname, count, wins * 100 / n, float(dead) / n, float(rounds) / n, float(hits) / n])
	_check(wins * 100 / n >= 25 and wins * 100 / n <= 98, gname + " balance (wins %d%%)" % [wins * 100 / n])

func _grenades(cr: ChargenRules) -> void:
	# a grenade into four men standing 2 m apart, with and without vests
	var killed := [0, 0]
	var wounded := [0, 0]
	for vest in [0, 1]:
		for k in range(200):
			var b := Battle.new(20, 20, data.items, Forces.vehicle_guns(), 100 + k)
			var sq := _squad(cr, 5)
			var thrower := b.add_man("enemy", sq[4], Vector2i(2, 10))
			thrower["skills"]["THROWN WEAPON"] = 10
			var group: Array = []
			for i in range(4):
				if vest == 0:
					sq[i]["gear"]["armor"] = []
				group.append(b.add_man("squad", sq[i], Vector2i(12 + i % 2, 9 + i / 2), i))
			b.order = [thrower["id"]]
			b.turn_i = 0
			b.throw_grenade(thrower, Vector2i(12, 9))
			for u in group:
				if u["state"] == "dead":
					killed[vest] += 1
				elif u["dmg"].values().any(func(v): return int(v) > 0):
					wounded[vest] += 1
	print("grenade into 4 men: without armour %.2f killed / %.2f wounded, with vest+helmet %.2f / %.2f" % [killed[0] / 200.0, wounded[0] / 200.0, killed[1] / 200.0, wounded[1] / 200.0])
	_check(killed[1] < killed[0], "armour should save lives from fragments")
	_check(killed[0] / 200.0 < 2.0, "a grenade should not wipe out a group")

func _bleeding(cr: ChargenRules) -> void:
	var r: Dictionary = _squad(cr, 1)[0]
	var b := Battle.new(10, 10, data.items, Forces.vehicle_guns(), 7)
	var u := b.add_man("squad", r, Vector2i(2, 2), 0)
	var e := b.add_man("enemy", r.duplicate(true), Vector2i(8, 8))
	u["bleed"] = 3
	var con := int(u["attrs"]["CONSTITUTION"])
	var turns := 0
	while u["state"] != "dead" and turns < 40:
		b._bleed(u)
		turns += 1
	_check(u["state"] == "dead", "untreated bleeding kills")
	print("bleeding 3 a turn: dead after %d turns (CON %d)" % [turns, con])
	var u2 := b.add_man("squad", r, Vector2i(3, 3), 0)
	var medic := b.add_man("squad", r, Vector2i(4, 3), 0)
	medic["skills"]["MEDICAL"] = 6
	u2["bleed"] = 2
	medic["ap"] = Battle.AP_MAX
	b.first_aid(medic, u2)
	print("first aid by MEDICAL 6: ", b.log[-1])

func _duel(a_name: String, b_name: String, a_face: int, b_face: int, dist: int, n: int) -> float:
	var a_wins := 0
	for k in range(n):
		var b := Battle.new(dist + 10, 12, data.items, Forces.vehicle_guns(), 3000 + k)
		var a := b.add_vehicle("squad", Forces.vehicle_data(a_name), Vector2i(3, 6), a_face, 5)
		var e := b.add_vehicle("enemy", Forces.vehicle_data(b_name), Vector2i(3 + dist, 6), b_face, 5)
		b.auto_play(20)
		if b.winner == "squad":
			a_wins += 1
	return float(a_wins) / n

func _tanks() -> void:
	# head-on at 160 m (80 tiles): east-facing (2) against west-facing (6)
	var m1 := _duel("M1A1", "T-72", 2, 6, 80, 100)
	var t72 := _duel("T-72", "T-72", 2, 6, 80, 100)
	var flank := _duel("T-72", "M1A1", 2, 0, 80, 100)        # M1A1 shows its side
	print("M1A1 vs T-72 head-on: M1A1 wins %d%%; T-72 vs T-72: %d%%; T-72 vs M1A1 side-on: T-72 wins %d%%" % [m1 * 100, t72 * 100, flank * 100])
	_check(m1 > 0.6, "M1A1 should beat a T-72 head-on")
	_check(flank > m1 * 0.0 + 0.3, "a flank shot should give the T-72 a chance")
	var b := Battle.new(40, 10, data.items, Forces.vehicle_guns(), 5)
	var hum := b.add_vehicle("enemy", Forces.vehicle_data("HMMWV"), Vector2i(20, 5), 6, 3)
	var rifle := b.add_man("squad", {"name": "RIFLEMAN", "skills": {"RIFLE": 8}, "attrs": {"AGILITY": 8}, "hits": {"CHEST": 30}, "gear": {"weapon": "M16A2", "mags": 9}}, Vector2i(5, 5))
	var pen := 0
	for i in range(30):
		rifle["ap"] = Battle.AP_MAX
		rifle["ammo"] = 20
		b.fire(rifle, hum, "aimed")
		if hum["state"] != "ok":
			break
	pen = b.log.filter(func(l): return String(l).contains("PENETRATES") or String(l).contains("SUSPENSION")).size()
	print("rifle against a HMMWV: %d penetrating / suspension hits, state %s" % [pen, hum["state"]])
	_check(pen > 0, "rifle rounds should get through a HMMWV's armour 1")

## The "tank" mission's fight: the squad (rifles, a LAW or RPG each) against a T-72 with two men.
func _tank_mission(cr: ChargenRules, story: bool) -> void:
	var wins := 0
	var dead := 0
	var tank_out := 0
	var n := 60
	for k in range(n):
		var b := _field(700 + k)
		b.options["story"] = story
		var rng := RandomNumberGenerator.new()
		rng.seed = 300 + k
		var sq := _squad(cr, 4)
		var mine: Array = []
		for i in range(sq.size()):
			mine.append(b.add_man("squad", sq[i], Vector2i(2, 10 + i * 3), i))
		Forces.issue_at_weapons(mine)
		Forces.deploy_squad(b, mine, Vector2i(4, 15), Vector2(1, 0))
		var g := Forces.group("BLACK LEGION", 2, rng)
		var foes: Array = []
		for t in g["men"]:
			foes.append(b.add_man("enemy", t, Vector2i(35, 15)))
		Forces.deploy_enemies(b, foes, Vector2i(34, 15), Vector2(-1, 0), rng)
		var tank := b.add_vehicle("enemy", Forces.vehicle_data("T-72"), Vector2i(33, 12), 6, 4)
		b.auto_play(30)
		b.aftermath()
		if b.winner == "squad":
			wins += 1
		if tank["state"] != "ok":
			tank_out += 1
		dead += mine.filter(func(u): return u["state"] == "dead").size()
	print("%-6s tank mission (T-72 + 2): squad wins %d%%, tank knocked out %d%%, squad dead per battle %.2f" % ["STORY" if story else "NORMAL", wins * 100 / n, tank_out * 100 / n, float(dead) / n])

func _trees_and_craters(cr: ChargenRules) -> void:
	# a wall of trees across the field (x = 10): a tank drives through and flattens them, a
	# HMMWV cannot; then a TOW crater: tracks cross it slowly, wheels go round, men take cover in it
	var b := Battle.new(30, 30, data.items, Forces.vehicle_guns(), 9)
	for y in range(30):
		b.set_blocked(Vector2i(10, y))
		b.tree[b.idx(Vector2i(10, y))] = 1
	var tank := b.add_vehicle("squad", Forces.vehicle_data("M1A1"), Vector2i(8, 5), 2)
	var car := b.add_vehicle("squad", Forces.vehicle_data("HMMWV"), Vector2i(8, 20), 2)
	tank["ap"] = 40
	car["ap"] = 40
	_check(b.reachable(tank).has(Vector2i(12, 5)), "a tank can drive through trees")
	_check(not b.reachable(car).has(Vector2i(12, 20)), "a HMMWV cannot drive through trees")
	b.move(tank, Vector2i(12, 5))
	_check(b.tree[b.idx(Vector2i(10, 5))] == 0 and not b.is_blocked(Vector2i(10, 5)), "the tree the tank drove over is down")
	_check(b.tree[b.idx(Vector2i(10, 4))] == 0, "the hull flattens the trees beside its path too")
	_check(b.tree[b.idx(Vector2i(10, 9))] == 1, "trees away from the path still stand")
	var downs := b.events.filter(func(e): return e["type"] == "tree_down").size()
	print("tank through a tree line: %d trees down, log: %s" % [downs, b.log[-1]])
	# craters on open ground
	var c := Battle.new(30, 30, data.items, Forces.vehicle_guns(), 9)
	var shooter := c.add_man("enemy", {"name": "GUNNER", "skills": {}, "attrs": {}, "hits": {"CHEST": 30}, "gear": {}}, Vector2i(0, 0))
	var tow: Dictionary = Forces.vehicle_guns()["TOW II"].duplicate()
	tow["name"] = "TOW II"                    # as Battle.weapon_of gives it
	c._explode(shooter, Vector2i(15, 15), tow, {})
	c._explode(shooter, Vector2i(15, 5), data.items.filter(func(i): return i["name"] == "FRAGMENTATION GRENADE")[0], {})
	_check(c.crater[c.idx(Vector2i(15, 15))] == 2 and c.crater[c.idx(Vector2i(16, 15))] == 1, "a TOW leaves a crater with a ring")
	_check(c.crater[c.idx(Vector2i(15, 5))] == 1 and c.crater[c.idx(Vector2i(16, 5))] == 0, "a grenade leaves a shell hole")
	var t2 := c.add_vehicle("squad", Forces.vehicle_data("M1A1"), Vector2i(13, 15), 2)
	var h2 := c.add_vehicle("squad", Forces.vehicle_data("HMMWV"), Vector2i(13, 18), 2)
	t2["ap"] = 40
	h2["ap"] = 40
	var tr := c.reachable(t2)
	_check(tr.has(Vector2i(15, 15)), "a tank crosses a big crater")
	_check(not c.reachable(h2).has(Vector2i(15, 15)), "a HMMWV cannot enter a big crater")
	var step := c.move_cost(t2)
	_check(float(tr[Vector2i(14, 15)]) > step * 1.5, "crossing the crater ring is slow for a tank")
	var p := c.path_to(h2, Vector2i(17, 12))
	_check(not p.is_empty() and not p.has(Vector2i(15, 15)), "the HMMWV drives round the crater")
	var r: Dictionary = _squad(cr, 1)[0]
	var man := c.add_man("squad", r, Vector2i(15, 15), 0)
	man["stance"] = "prone"
	_check(c.cover(man["pos"], Vector2i(25, 15)) == 2, "a man lying in a crater has heavy cover")
	man["stance"] = "stand"
	_check(c.cover(man["pos"], Vector2i(25, 15)) == 0, "standing in a crater gives no cover")
	# story mode: a recruit knocked out by a head hit over its capacity is alive in the next battle
	var hurt: Dictionary = _squad(cr, 1)[0]
	hurt["damage"] = {"HEAD": int(hurt["hits"]["HEAD"]) + 3}
	var nb := Battle.new(10, 10, data.items, Forces.vehicle_guns(), 3)
	var hu := nb.add_man("squad", hurt, Vector2i(2, 2), 0)
	_check(hu["state"] == "ok", "a spared recruit starts the next battle alive")
	# story mode: knocked out by a chest hit, comes to at half strength after the battle
	for story in [true, false]:
		var kb := Battle.new(10, 10, data.items, Forces.vehicle_guns(), 3)
		kb.options["story"] = story
		var sq := [_squad(cr, 1)[0]]
		var k := kb.add_man("squad", sq[0], Vector2i(2, 2), 0)
		var cap := int(k["hits"]["CHEST"])
		kb._wound(k, "CHEST", cap + 2, {})
		kb._wound(k, "LEFT ARM", int(k["hits"]["LEFT ARM"]), {})
		kb.aftermath()
		kb.write_back(sq, cr)
		if story:
			_check(not sq[0]["dead"] and int(sq[0]["damage"]["CHEST"]) == cap / 2 and int(sq[0]["damage"]["LEFT ARM"]) <= int(k["hits"]["LEFT ARM"]) / 2 and int(sq[0]["bleed"]) == 0,
				"story: an unconscious recruit comes to at half strength")
			print("story knockout: chest %d/%d, %s" % [int(sq[0]["damage"]["CHEST"]), cap, Healing.condition(sq[0])])
		else:
			_check(sq[0]["dead"], "normal: the same chest hit kills")
	print("crater: tank cost into the ring %.1f AP (open ground %.1f), HMMWV path round it %d tiles" % [float(tr[Vector2i(14, 15)]), step, p.size()])

## A fight inside a building: furniture blocks the way but not the eye, the launchers stay
## silent, a step costs half; then the squad (4) against hostage-takers (3) in a tavern.
func _indoors(cr: ChargenRules) -> void:
	var rooms = GameData._json("res://data/rooms.json")
	var room: Dictionary = rooms["TAVERN_0"]
	var b := Forces.make_room_battle(room, data.items, 5)
	var furn: Array = []
	for y in range(b.h):
		for x in range(b.w):
			if b.furniture[b.idx(Vector2i(x, y))] == 1:
				furn.append(Vector2i(x, y))
	_check(not furn.is_empty(), "the tavern has furniture in the way")
	var r: Dictionary = _squad(cr, 1)[0]
	r["gear"]["launcher"] = "LAW 80 ROCKET LAUNCHER"
	r["gear"]["rockets"] = 1
	var man := b.add_man("squad", r, Vector2i(0, 0), 0)
	var f0: Vector2i = furn[0]
	_check(not b.passable(man, f0), "furniture blocks the way")
	# someone on each side of a piece of furniture sees the other over it
	var a := f0 + Vector2i(-1, 0)
	var c := f0 + Vector2i(1, 0)
	if b.inside(a) and b.inside(c) and b.furniture[b.idx(a)] == 0 and b.furniture[b.idx(c)] == 0:
		_check(b.can_see(a, c), "seen over the furniture")
		_check(b.cover(a, c) == 2, "heavy cover behind the furniture")
	var foe := b.add_man("enemy", Forces.group("BLACK LEGION", 1, b.rng)["men"][0], Vector2i(b.w - 1, b.h - 1))
	man["pos"] = Vector2i(0, b.h - 1)
	foe["pos"] = Vector2i(b.w - 1, b.h - 1)
	b.start()
	man["ap"] = 10
	_check(not b.fire(man, foe, "snap", "LAW 80 ROCKET LAUNCHER") and b.log[-1] == "YOU CAN'T USE THAT WEAPON INDOORS.", "no rockets indoors")
	_check(is_equal_approx(b.move_cost(man), 0.5), "a step indoors costs half an AP")
	for story in [false, true]:
		var wins := 0
		var dead := 0
		var n := 200
		for i in range(n):
			var bb := Forces.make_room_battle(room, data.items, 1000 + i)
			bb.options["story"] = story
			var sq := _squad(cr, 4)
			var men: Array = []
			for k in range(4):
				Forces.equip(sq[k])
				men.append(bb.add_man("squad", sq[k], Vector2i(5, 7), k))
			var foes: Array = []
			for t in Forces.group("BLACK LEGION", 3, bb.rng)["men"]:
				foes.append(bb.add_man("enemy", t, Vector2i(5, 1)))
			Forces.deploy_defenders(bb, foes, Vector2i(5, 7), bb.rng)
			Forces.deploy_near(bb, men, Vector2i(5, 7), Vector2(0, -1))
			bb.auto_play(60)
			if bb.winner == "squad":
				wins += 1
			dead += men.filter(func(u): return u["state"] == "dead").size()
		print("%-6s indoors (tavern, 4 vs 3 Black Legion): squad wins %d%%, squad dead per battle %.2f" % ["STORY" if story else "NORMAL", wins * 100 / n, float(dead) / n])

func _infantry_vs_armour(cr: ChargenRules) -> void:
	# a LAW 80 team against a T-72: from the front (HF 100) and the side (HS 16)
	for face in [6, 0]:
		var kills := 0
		var shots := 0
		for k in range(200):
			var b := Battle.new(40, 20, data.items, Forces.vehicle_guns(), 7000 + k)
			var t := b.add_vehicle("enemy", Forces.vehicle_data("T-72"), Vector2i(25, 10), face, 4)
			var r: Dictionary = _squad(cr, 1)[0]
			r["skills"]["HEAVY WEAPONS"] = 5
			r["gear"]["launcher"] = "LAW 80 ROCKET LAUNCHER"
			r["gear"]["rockets"] = 2
			var u := b.add_man("squad", r, Vector2i(8, 10), 0)
			for s in range(2):
				u["ap"] = Battle.AP_MAX
				var keep: String = u["weapon"]
				u["weapon"] = "LAW 80 ROCKET LAUNCHER"
				u["ammo"] = 1
				b.fire(u, t, "aimed")
				shots += 1
				u["weapon"] = keep
				if t["state"] != "ok":
					break
			if t["state"] != "ok" or int(t["comp"]["engine"]) >= 100 or int(t["crew_left"]) < 3:
				kills += 1
		print("two LAW 80 rockets at a T-72 %s: knocked out or crippled %d%%" % ["from the front" if face == 6 else "from the side", kills * 100 / 200])
		if face == 0:
			_check(kills > 40, "side shots with LAWs should hurt a T-72")

func _experience(cr: ChargenRules) -> void:
	var sq := _squad(cr, 1)
	var r: Dictionary = sq[0]
	var before := cr.level(r, "RIFLE")
	var b := Battle.new(10, 10, data.items, Forces.vehicle_guns(), 9)
	var u := b.add_man("squad", r, Vector2i(1, 1), 0)
	u["xp"]["RIFLE"] = 3 + before + 1
	var lines := b.write_back(sq, cr)
	print("experience: ", lines)
	_check(cr.level(r, "RIFLE") > before or r["skills"].get("RIFLE", 0.0) > before, "skill should improve with experience")
