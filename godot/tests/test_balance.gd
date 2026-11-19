## M9 balance harness: godot --headless --path . --script tests/test_balance.gd [-- --report]
## Runs the encounters the campaign actually generates - road patrols (world.gd GROUPS), a
## town's Black Legion (campaign clear steps), the scavengers of a repair step, the tank
## mission (T-72 + two men against the squad's anti-tank weapons) and a hideout room - for a
## mid-game squad under NORMAL and STORY, and reports win rates and losses. M9 target: a
## NORMAL encounter is winnable 40-70% of the time; STORY must not be harder than NORMAL.
extends SceneTree

const N := 80                      # battles per profile and difficulty
const SQUAD := 6                   # a mid-game squad (the manual's patrol size)
const BAND := [40, 70]             # M9 target win-rate band, percent

var data := GameData.new()
var fails := 0

func _init() -> void:
	data.load_all()
	var report_only := "--report" in OS.get_cmdline_user_args()
	var careers = GameData._json("res://data/careers.json")
	var cr := ChargenRules.new(careers, data.chargen, 41)
	print("M9 BALANCE REPORT  (%d battles per cell, squad %d, world GROUPS + campaign counts)" % [N, SQUAD])
	var only := OS.get_environment("M9_ONLY")   # run just the profiles whose label contains this
	if only != "":
		print("(only profiles matching '%s')" % only)
	if _wanted(only, "PATROL"):
		_report(cr, "road  BLACK LEGION PATROL x4", func(c, k): return _field_group(c, "BLACK LEGION PATROL", 4, k), true)
	if _wanted(only, "MARAUDERS"):
		_report(cr, "road  MARAUDERS x6", func(c, k): return _field_group(c, "MARAUDERS", 6, k), true)
	if _wanted(only, "STRAGGLERS"):
		_report(cr, "road  STRAGGLERS x3", func(c, k): return _field_group(c, "STRAGGLERS", 3, k), true)
	if _wanted(only, "town LEGION"):
		_report(cr, "town  BLACK LEGION squad+1..2", func(c, k): return _field_group(c, "BLACK LEGION", -1, k))
	if _wanted(only, "SCAVENGERS"):
		_report(cr, "town  SCAVENGERS (MARAUDERS) squad+1..2", func(c, k): return _field_group(c, "MARAUDERS", -1, k), true)
	if _wanted(only, "T-72"):
		_report(cr, "town  T-72 + 3 LEGION and LAWs", func(c, k): return _tank(c, k))
	if _wanted(only, "tavern"):
		_report(cr, "room  BLACK LEGION squad-2 in a tavern", func(c, k): return _room(c, k, SQUAD))
	if report_only:
		print("M9 BALANCE REPORT ONLY (no band checks)")
		quit(0)
		return
	print("BALANCE TEST ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

## M9_ONLY filter: an empty filter runs everything.
func _wanted(only: String, label: String) -> bool:
	return only == "" or label.contains(only)

func _squad(cr: ChargenRules, n: int) -> Array:
	var sq: Array = []
	for i in range(n):
		var r := cr.random_recruit()
		Forces.equip(r)
		sq.append(r)
	return sq
## A field: 40x30 m with scattered tree trunks for cover (as test_battle.gd).
## T2K_FOGGED=1 measures with the game-facing options (fog + reaction fire on).
func _field(seed_value: int) -> Battle:
	var b := Battle.new(40, 30, data.items, Forces.vehicle_guns(), seed_value)
	if OS.get_environment("T2K_FOGGED") == "1":
		b.options["fog"] = true
		b.options["reaction"] = true
		b.seek = Vector2i(33, 15)             # the squad searches toward the enemy side
		b.refresh_seen()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(60):
		b.set_blocked(Vector2i(rng.randi_range(8, 31), rng.randi_range(0, 29)))
	return b

## Squad (SQUAD) in a line against an enemy group; count -1 = the campaign's M9 formula.
func _field_group(cr: ChargenRules, name: String, count: int, seed_v: int) -> Dictionary:
	var b := _field(seed_v)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 1000
	if count < 0:
		count = Campaign.field_count(SQUAD, rng)   # the garrison turns out in strength
	var sq := _squad(cr, SQUAD)
	var mine: Array = []
	for i in range(sq.size()):
		mine.append(b.add_man("squad", sq[i], Vector2i(2, 10 + i * 3), i))
	Forces.deploy_squad(b, mine, Vector2i(4, 15), Vector2(1, 0))
	var g := Forces.group(name, count, rng)
	var foes: Array = []
	for t in g["men"]:
		foes.append(b.add_man("enemy", t, Vector2i(35, 15)))
	Forces.deploy_enemies(b, foes, Vector2i(34, 15), Vector2(-1, 0), rng)
	return {"b": b, "mine": mine}

## The tank mission: the squad on foot, Krakow handing a one-shot at-weapon to everyone,
## against the T-72 and two of its crew's comrades (main.gd battle_in_town).
func _tank(cr: ChargenRules, seed_v: int) -> Dictionary:
	var b := _field(seed_v + 7)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 2000
	var sq := _squad(cr, SQUAD)
	var mine: Array = []
	for i in range(sq.size()):
		mine.append(b.add_man("squad", sq[i], Vector2i(2, 10 + i * 3), i))
	Forces.issue_at_weapons(mine)
	Forces.deploy_squad(b, mine, Vector2i(4, 15), Vector2(1, 0))
	b.add_vehicle("enemy", Forces.vehicle_data("T-72"), Vector2i(35, 15), 6, 4)
	var g := Forces.group("BLACK LEGION", Campaign.TANK_ESCORTS, rng)
	var foes: Array = []
	for t in g["men"]:
		foes.append(b.add_man("enemy", t, Vector2i(33, 15)))
	Forces.deploy_enemies(b, foes, Vector2i(33, 15), Vector2(-1, 0), rng)
	return {"b": b, "mine": mine}

## A hideout: the hostage-takers / assassins in a tavern room (data/rooms.json).
func _room(cr: ChargenRules, seed_v: int, n: int) -> Dictionary:
	var rooms = GameData._json("res://data/rooms.json")
	var room: Dictionary = rooms["TAVERN_0"]
	var bb := Forces.make_room_battle(room, data.items, seed_v + 3000)
	var sq := _squad(cr, n)
	var men: Array = []
	for k in range(n):
		men.append(bb.add_man("squad", sq[k], Vector2i(5, 7), k))
	var foes: Array = []
	for t in Forces.group("BLACK LEGION", Campaign.room_count(n), bb.rng)["men"]:
		foes.append(bb.add_man("enemy", t, Vector2i(5, 1)))
	Forces.deploy_defenders(bb, foes, Vector2i(5, 7), bb.rng)
	Forces.deploy_near(bb, men, Vector2i(5, 7), Vector2(0, -1))
	if OS.get_environment("T2K_FOGGED") == "1":
		bb.seek = Vector2i(5, 1)              # the squad pushes into the room
	return {"b": bb, "mine": men}

func _run(cr: ChargenRules, setup: Callable, story: bool) -> Dictionary:
	var wins := 0
	var dead := 0
	var rounds := 0
	for k in range(N):
		var ctx: Dictionary = setup.call(cr, 5000 + k)
		var b: Battle = ctx["b"]
		b.options["story"] = story
		b.auto_play(30)
		b.aftermath()
		if b.winner == "squad":
			wins += 1
		dead += ctx["mine"].filter(func(u): return u["state"] == "dead").size()
		rounds += b.round_no
	return {"wins": wins, "dead": dead, "rounds": rounds}

## Run one profile under both difficulties, print the row and check it against M9.
## flavor: a road encounter or a mob of scavengers - it may be lopsided, but the squad
## must not be the underdog (at least 40%); a mission fight must land in the 40-70% band.
func _report(cr: ChargenRules, label: String, setup: Callable, flavor := false) -> void:
	var normal := _run(cr, setup, false)
	var story := _run(cr, setup, true)
	var nw: int = normal["wins"] * 100 / N
	var sw: int = story["wins"] * 100 / N
	var tag := "FLAVOR" if flavor else ("IN BAND" if nw >= int(BAND[0]) and nw <= int(BAND[1]) else "OUT OF BAND")
	print("%-34s NORMAL wins %3d%%  dead/battle %.2f  rounds %.1f %s | STORY wins %3d%%  dead %.2f" % [
		label, nw, float(normal["dead"]) / N, float(normal["rounds"]) / N, tag, sw, float(story["dead"]) / N])
	if flavor:
		_check(nw >= int(BAND[0]), label + ": NORMAL winnable (flavor, wins %d%%)" % nw)
	else:
		_check(nw >= int(BAND[0]) and nw <= int(BAND[1]), label + ": NORMAL in the 40-70%% band (wins %d%%)" % nw)
	_check(sw + 5 >= nw, label + ": STORY not harder than NORMAL (%d%% vs %d%%)" % [sw, nw])