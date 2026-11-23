## Turn-based combat (replaces the original's watch-only rounds and its 3-D tank sim).
## Pure logic, no drawing: the battle view and the headless tests drive it the same way.
##
## The ground is a grid of 2 m tiles (the terrain kits' tiles); indoors 1 m tiles, the furniture
## in the way (cover, but no wall to the eye), and no rockets, grenade launchers or heavy machine
## guns ("YOU CAN'T USE THAT WEAPON INDOORS"). Every unit gets 10 action points
## a turn, in initiative order. Weapons are the items of the original (data/items.json, the
## 2nd-edition scale the PC game uses: damage = D6s, penetration per range band, short range in
## metres with medium x2, long x4, extreme x8 as the manual says). Hit locations and capacities
## come from the recruits' sheets; body armour, bleeding, first aid, knock-down, grenades with
## fragments, and vehicles with armour per facing (the manual's HF/HS/HR/TF/TS/TR) and hit
## components. Units are plain Dictionaries so a battle can be saved.
class_name Battle
extends RefCounted

const TILE := 2.0
const AP_MAX := 10
const ENEMY_FACE_N := 15            # the enemies' own portraits (FACES/enemies.png): 15 faces
const LOCS := ["HEAD", "CHEST", "ABDOMEN", "LEFT ARM", "RIGHT ARM", "LEFT LEG", "RIGHT LEG"]
const DIRS8 := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
const COST := {"move": 1, "move_crouch": 2, "move_prone": 4, "snap": 3, "aimed": 5, "burst": 4, "grenade": 4,
	"reload": 3, "stance": 1, "aid": 6, "gun": 6}
const ARMOR_AV := {"KEVLAR VEST": 2, "FLAK JACKET": 1, "KEVLAR HELMET": 3}
const ARMOR_COVERS := {"KEVLAR VEST": ["CHEST", "ABDOMEN"], "FLAK JACKET": ["CHEST", "ABDOMEN", "LEFT ARM", "RIGHT ARM"], "KEVLAR HELMET": ["HEAD"]}

var w := 30
var h := 30
var blocked := PackedByteArray()      # 1 = wall / tree trunk
var bush := PackedByteArray()         # 1 = bushes: concealment
var road := PackedByteArray()         # 1 = road (vehicles move faster)
var tree := PackedByteArray()         # 1 = a standing tree (blocked too); heavy tracked vehicles knock it down
var crater := PackedByteArray()       # 0 none, 1 shell hole (grenade), 2 crater (shell, rocket, missile)
var furniture := PackedByteArray()    # 1 = furniture indoors (blocked too, but it is seen over)
var tile := TILE                      # metres a tile (indoors 1)
var units: Array = []                 # Dictionaries, see add_man / add_vehicle
var items := {}                       # name -> item dict
var guns := {}                        # vehicle weapons
var rng := RandomNumberGenerator.new()
var round_no := 1
var order: Array = []                 # unit ids this round
var turn_i := 0
var interrupted := false              # execute_plan() was stopped by a newly spotted enemy
var interrupt_enemies: Array = []     # the enemy ids that triggered the interrupt
var log: Array = []                   # lines for the message box
var events: Array = []                # {type, ...} for the view's effects
var over := false
var winner := ""
var seek := Vector2i(-1, -1)           # where the squad should search when nothing is seen
var options := {"frag_limit": true, "story": false, "indoors": false, "fog": false}
#                                      # fog: the UFO-style spotting (hidden until in sight);
#                                      # ON in the real battles, OFF in the legacy tests
                                      # story: story mode, the squad shoots better, is hit less and is not killed outright
var next_id := 1

func _init(width: int, height: int, item_list: Array, vehicle_guns: Dictionary, seed_value := 0) -> void:
	w = width
	h = height
	blocked.resize(w * h)
	bush.resize(w * h)
	road.resize(w * h)
	tree.resize(w * h)
	crater.resize(w * h)
	furniture.resize(w * h)
	for it in item_list:
		items[it["name"]] = it
	guns = vehicle_guns
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

func idx(t: Vector2i) -> int:
	return t.y * w + t.x

func inside(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < w and t.y < h

func set_blocked(t: Vector2i, v := true) -> void:
	if inside(t):
		blocked[idx(t)] = 1 if v else 0

func is_blocked(t: Vector2i) -> bool:
	return not inside(t) or blocked[idx(t)] == 1

# ---------------- units ----------------
## A person. r: recruit (chargen Dictionary with skills, attrs, hits, gear) or an enemy template.
func add_man(team: String, r: Dictionary, at: Vector2i, ref := -1) -> Dictionary:
	var g: Dictionary = r.get("gear", {})
	var u := {"id": next_id, "team": team, "kind": "man", "name": r.get("name", "SOLDIER"), "pos": at, "facing": 4,
		"skills": r.get("skills", {}), "attrs": r.get("attrs", {}), "hits": r.get("hits", {}),
		"dmg": r.get("damage", {}).duplicate(), "bleed": int(r.get("bleed", 0)), "blood": int(r.get("blood", 0)),
		"state": "ok", "stance": "stand", "weapon": g.get("weapon", "M16A2"), "ammo": 0, "mags": int(g.get("mags", 4)),
		"grenades": int(g.get("grenades", 0)), "launcher": g.get("launcher", ""), "rockets": int(g.get("rockets", 0)),
		"armor": g.get("armor", []), "medkits": int(g.get("medkits", 0)), "initiative": int(r.get("initiative", 3)),
		"ap": AP_MAX, "ref": ref, "xp": {}, "kills": 0, "in_vehicle": -1, "knocked": false, "fled": false,
		"reserve": false,                     # OpenXCom-style: keeps AP for one snap shot
		"morale": 100.0, "reacted": false,    # panic system; one reaction shot per round
		"plan": [], "plan_ap": AP_MAX,        # Jagged Alliance-style planning phase
		"head": int(r.get("head", r.get("face", 0))), "gender": r.get("gender", "M"),
		"hungry": bool(r.get("hungry", false))}   # M9: hungry soldiers are slower
	if team == "enemy":
		u["face"] = u["id"] % ENEMY_FACE_N        # the enemies' own portraits: FACES/enemies.png
	next_id += 1
	var wp: Dictionary = items.get(u["weapon"], {})
	u["ammo"] = int(wp.get("magazine", 0)) if int(wp.get("magazine", 0)) > 0 else 1
	if team == "squad" and ref >= 0 and not r.get("dead", false):
		_survivor(u["dmg"], u["hits"])         # alive, whatever the wounds say (story mode)
	if _dead_already(u):
		u["state"] = "dead"
	units.append(u)
	return u

## Someone who lived through a hit to the head or chest over its capacity (story mode spares
## them) keeps a critical wound, one point short of deadly: alive at the next battle.
static func _survivor(dmg: Dictionary, hits: Dictionary) -> void:
	for l in ["HEAD", "CHEST"]:
		var cap := int(hits.get(l, 99))
		if int(dmg.get(l, 0)) >= cap:
			dmg[l] = cap - 1

func _dead_already(u: Dictionary) -> bool:
	for l in ["HEAD", "CHEST"]:
		if int(u["dmg"].get(l, 0)) >= int(u["hits"].get(l, 99)):
			return true
	return false

## A vehicle (data/vehicles.json entry). crew: ids of men inside (their skills are used), or
## an int for a nameless crew with the given gunnery / driving skill.
func add_vehicle(team: String, v: Dictionary, at: Vector2i, facing: int, crew_skill := 4) -> Dictionary:
	var u := {"id": next_id, "team": team, "kind": "vehicle", "name": v["name"], "pos": at, "facing": facing,
		"data": v, "state": "ok", "ap": AP_MAX, "comp": {"engine": 0, "susp": 0, "gun": 0, "turret": 0, "fuel": 0},
		"crew_left": int(v["crew"]), "crew_skill": crew_skill, "occupants": [], "ammo": v.get("ammo", {}).duplicate(),
		"fired_main": false, "fired": {}, "moved": false, "initiative": 4, "xp": {}, "kills": 0, "ref": -1}
	for g in v.get("weapons", []):
		if not u["ammo"].has(g):
			u["ammo"][g] = int(guns.get(g, {}).get("magazine", 100)) * 3
	next_id += 1
	units.append(u)
	return u

## Put a man into a vehicle (he drives / guns it with his own skills).
func board(man: Dictionary, veh: Dictionary) -> void:
	man["in_vehicle"] = veh["id"]
	veh["occupants"].append(man["id"])
	man["pos"] = veh["pos"]

func unit(id: int) -> Dictionary:
	for u in units:
		if u["id"] == id:
			return u
	return {}

func active(u: Dictionary) -> bool:
	return u["state"] == "ok" and not u.get("fled", false) and int(u.get("in_vehicle", -1)) < 0

func team_units(team: String) -> Array:
	return units.filter(func(u): return u["team"] == team and active(u))

func at_tile(t: Vector2i) -> Dictionary:
	for u in units:
		if u["state"] != "dead" and int(u.get("in_vehicle", -1)) < 0 and not u.get("fled", false):
			if u["kind"] == "vehicle":
				if (u["pos"] - t).abs().x <= 1 and (u["pos"] - t).abs().y <= 1:
					return u
			elif u["pos"] == t:
				return u
	return {}

func is_free_tile(t: Vector2i, ignore := -1) -> bool:
	if is_blocked(t):
		return false
	var o := at_tile(t)
	return o.is_empty() or o["id"] == ignore

## Vehicle crew skills: the best of the men inside, or the nameless crew's number.
func crew_skill(v: Dictionary, skill: String) -> int:
	var best := -1
	for id in v["occupants"]:
		var m := unit(id)
		if not m.is_empty() and m["state"] == "ok":
			best = maxi(best, int(m["skills"].get(skill, 0.0)))
	return best if best >= 0 else int(v["crew_skill"])

# ---------------- turns ----------------
func start() -> void:
	_new_round()

func _new_round() -> void:
	var list := units.filter(func(u): return active(u))
	# initiative, then agility, then a die roll: ties do not always go to the same side
	for u in list:
		var ini := int(u["initiative"])
		if u["team"] == "squad" and bool(u.get("hungry", false)):
			ini = maxi(1, ini - 1)             # M9: hunger slows the squad down
		u["_ord"] = ini * 100 + (int(u["attrs"].get("AGILITY", 5)) if u["kind"] == "man" else 5) * 10 + rng.randi_range(0, 9)
	list.sort_custom(func(a, b): return int(a["_ord"]) > int(b["_ord"]))
	order = list.map(func(u): return u["id"])
	for u in units:
		u["reacted"] = false                # one reaction shot per round
		if u["team"] == "squad":
			u["plan"] = []                  # Jagged Alliance-style: replan every round
			u["plan_ap"] = int(u["ap"])
	turn_i = 0
	log.append("COMBAT ROUND %d BEGINS." % round_no)
	_begin_turn()

func current() -> Dictionary:
	while turn_i < order.size():
		var u := unit(order[turn_i])
		if not u.is_empty() and active(u):
			return u
		turn_i += 1
	return {}

func _begin_turn() -> void:
	var u := current()
	if u.is_empty():
		return
	if u["kind"] == "man" and float(u.get("morale", 100.0)) <= 0.0:
		_panic(u)                             # freeze or flee; morale recovers to 50
		u["ap"] = 0
		end_turn()                            # the panicked round is spent: next unit
		return
	u["ap"] = AP_MAX
	if u["kind"] == "vehicle":
		u["fired_main"] = false
		u["fired"] = {}
		u["moved"] = false
		if int(u["comp"]["engine"]) >= 100 or int(u["comp"]["susp"]) >= 100:
			u["ap"] = AP_MAX                  # immobile but can still shoot
	else:
		if u["knocked"]:
			u["knocked"] = false
			u["ap"] = AP_MAX / 2              # getting up from a knock-down
		_bleed(u)
		if not active(u):
			end_turn()

## Next unit; a new round when everybody has acted. Checks the end of the battle.
func end_turn() -> void:
	turn_i += 1
	_check_over()
	if over:
		return
	if current().is_empty():
		round_no += 1
		_new_round()
	else:
		_begin_turn()

func _check_over() -> void:
	var s := team_units("squad").size() + _occupied_vehicles("squad")
	var e := team_units("enemy").size() + _occupied_vehicles("enemy")
	if s == 0 or e == 0:
		over = true
		winner = "squad" if e == 0 and s > 0 else "enemy"
		log.append("THERE ARE NO MORE ENEMIES." if winner == "squad" else "THE SQUAD HAS FALLEN.")

func _occupied_vehicles(team: String) -> int:
	return units.filter(func(u): return u["kind"] == "vehicle" and u["team"] == team and u["state"] == "ok" and u["crew_left"] > 0).size() - team_units(team).filter(func(u): return u["kind"] == "vehicle").size()

# ---------------- movement ----------------
static func tracked(u: Dictionary) -> bool:
	return u["kind"] == "vehicle" and u["data"].get("kind", "") == "tracked"

## Tanks and other heavy tracked vehicles drive through trees and knock them down.
static func crushes_trees(u: Dictionary) -> bool:
	return tracked(u) and float(u["data"].get("weight_t", 0.0)) >= 20.0

## Can the unit enter this tile at all (walls never; a tree only under a heavy tracked vehicle;
## a big crater not on wheels)?
func passable(u: Dictionary, t: Vector2i) -> bool:
	if not inside(t):
		return false
	var i := idx(t)
	if blocked[i] == 1 and not (tree[i] == 1 and crushes_trees(u)):
		return false
	if crater[i] >= 2 and u["kind"] == "vehicle" and not tracked(u):
		return false                              # cars and trucks drive round the big ones
	return true

## Extra cost factor of entering a tile: pushing a tree over, climbing in and out of craters.
## Tracks cross any crater but slowly (x2 / x3), wheels only the small ones (x2.5); a man loses
## one AP climbing through.
func terrain_cost(u: Dictionary, t: Vector2i, k: float) -> float:
	var i := idx(t)
	if tree[i] == 1:
		k *= 2.0
	var cz := int(crater[i])
	if cz > 0:
		if u["kind"] == "man":
			k += 1.0
		elif tracked(u):
			k *= 1.0 + cz
		else:
			k *= 2.5
	return k

func move_cost(u: Dictionary) -> float:
	if u["kind"] == "vehicle":
		var d: Dictionary = u["data"]
		var tiles: float = float(d["com_move"][1]) / TILE        # rough-terrain combat move per turn
		return maxf(0.5, AP_MAX / maxf(tiles, 1.0))
	var k := tile / TILE                  # the AP are for 2 m: indoors a step costs half
	if _limb_out(u, "LEFT LEG") or _limb_out(u, "RIGHT LEG"):
		return 4.0 * k
	return float(COST["move_" + u["stance"]] if u["stance"] != "stand" else COST["move"]) * k

## Cheapest moves from the unit's tile within its AP (Dijkstra over the grid): {tile: [cost, parent]}.
func _flood(u: Dictionary) -> Dictionary:
	var occ := {}
	for o in units:
		if o["id"] != u["id"] and o["state"] != "dead" and int(o.get("in_vehicle", -1)) < 0 and not o.get("fled", false):
			if o["kind"] == "vehicle":
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						occ[o["pos"] + Vector2i(dx, dy)] = true
			else:
				occ[o["pos"]] = true
	var c := move_cost(u)
	var roadk := 1.0
	if u["kind"] == "vehicle":
		roadk = float(u["data"]["com_move"][1]) / float(u["data"]["com_move"][0])
	var best := {u["pos"]: [0.0, u["pos"]]}
	var open: Array = [u["pos"]]
	var ap: float = u["ap"]
	if u.get("reserve", false) and u["kind"] == "man":
		ap = maxf(0.0, float(ap) - COST["snap"])   # reserved for one snapshot, OpenXCom-style
	while not open.is_empty():
		# pop the cheapest (the sets are small: a few hundred tiles)
		var bi := 0
		for i in range(1, open.size()):
			if best[open[i]][0] < best[open[bi]][0]:
				bi = i
		var t: Vector2i = open[bi]
		open.remove_at(bi)
		var base: float = best[t][0]
		for d in DIRS8:
			var n: Vector2i = t + d
			if not passable(u, n) or occ.has(n):
				continue
			if d.x != 0 and d.y != 0 and (not passable(u, Vector2i(t.x + d.x, t.y)) or not passable(u, Vector2i(t.x, t.y + d.y))):
				continue                              # no cutting corners round trunks and walls
			var k := c * (1.4 if d.x != 0 and d.y != 0 else 1.0)
			if road[idx(n)] == 1:
				k *= roadk
			k = terrain_cost(u, n, k)
			var nc := base + k
			if nc > ap + 0.001:
				continue
			if not best.has(n) or nc < best[n][0]:
				best[n] = [nc, t]
				open.append(n)
	refresh_seen()
	return best

func path_to(u: Dictionary, to: Vector2i) -> Array:
	var f := _flood(u)
	if not f.has(to) or to == u["pos"]:
		return []
	var p: Array = [to]
	while p[0] != u["pos"]:
		p.push_front(f[p[0]][1])
	return p

## Tiles the unit can reach with its AP: {tile: ap_cost}.
func reachable(u: Dictionary) -> Dictionary:
	var out := {}
	var f := _flood(u)
	for t in f:
		if t != u["pos"]:
			out[t] = f[t][0]
	return out

## OpenXCom-style time-unit reserve: while on, the unit's moves stop with enough AP for
## one snap shot (blanked into _flood). Men only; the toggle costs nothing.
func set_reserve(u: Dictionary) -> bool:
	if u["kind"] != "man":
		return false
	u["reserve"] = not u.get("reserve", false)
	return bool(u["reserve"])

func move(u: Dictionary, to: Vector2i) -> bool:
	if u["kind"] == "vehicle" and (int(u["comp"]["engine"]) >= 100 or int(u["comp"]["susp"]) >= 100):
		log.append("THE %s CANNOT MOVE." % u["name"])
		return false
	var f := _flood(u)
	if not f.has(to) or to == u["pos"]:
		log.append("%s CANNOT REACH THAT TILE THIS ROUND." % u["name"])
		return false
	var p: Array = [to]
	while p[0] != u["pos"]:
		p.push_front(f[p[0]][1])
	var reached: Array = [u["pos"]]
	for i in range(1, p.size()):
		u["pos"] = p[i]                          # step by step: the watchers answer to every one
		u["facing"] = _dir_index(p[i] - p[i - 1])
		reached.append(p[i])
		if u["kind"] == "vehicle" and int(u["comp"]["susp"]) >= 100:
			break                                # the suspension gives out on the way
		refresh_seen()
		_reaction(u)                             # the watchers answer each step of the walk
		if u["state"] != "ok":
			break
	u["ap"] -= float(f[u["pos"]][0])             # only the ground actually crossed is paid
	if u["kind"] == "vehicle":
		u["moved"] = true
		for id in u["occupants"]:
			unit(id)["pos"] = u["pos"]
	refresh_seen()                               # crossing into someone's sight
	events.append({"type": "move", "id": u["id"], "path": reached})
	if crushes_trees(u):
		var n := 0
		for i in range(1, reached.size()):
			var dir: Vector2i = reached[i] - reached[i - 1]
			for dy in range(-1, 2):                   # the hull is three tiles wide
				for dx in range(-1, 2):
					if fell_tree(reached[i] + Vector2i(dx, dy), dir):
						n += 1
		if n > 0:
			log.append("THE %s FLATTENS %s." % [u["name"], "A TREE" if n == 1 else "%d TREES" % n])
	return true

## A tree goes down (driven over, or a big blast at its foot): the tile opens, the fallen crown
## still hides a man lying in it. dir: the way it falls.
func fell_tree(t: Vector2i, dir: Vector2i) -> bool:
	if not inside(t) or tree[idx(t)] == 0:
		return false
	var i := idx(t)
	tree[i] = 0
	blocked[i] = 0
	bush[i] = 1
	events.append({"type": "tree_down", "tile": t, "dir": dir})
	return true

static func _dir_index(d: Vector2i) -> int:
	var dd := Vector2i(signi(d.x), signi(d.y))
	for i in range(8):
		if DIRS8[i] == dd:
			return i
	return 4

func set_stance(u: Dictionary, s: String) -> bool:
	if u["kind"] != "man" or u["stance"] == s or u["ap"] < COST["stance"]:
		return false
	u["ap"] -= COST["stance"]
	u["stance"] = s
	return true

# ---------------- seeing and cover ----------------
## Tiles on the line between two tiles (Bresenham), endpoints excluded.
func line(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	var d := (b - a).abs()
	var s := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var err := d.x - d.y
	var p := a
	while p != b:
		var e2 := 2 * err
		if e2 > -d.y:
			err -= d.y
			p.x += s.x
		if e2 < d.x:
			err += d.x
			p.y += s.y
		if p != b:
			out.append(p)
	return out

func can_see(a: Vector2i, b: Vector2i) -> bool:
	for t in line(a, b):
		if is_blocked(t) and not (inside(t) and furniture[idx(t)] == 1):
			return false
	return true

# ---------------- UFO-style spotting (fog of war) ----------------
## A unit is seen by `by` when one of that team can draw a line of sight within the
## close-sight range (20 tiles = 40 m on the field, 20 m indoors: sighting, not firing
## range - distant tanks stay dark until they fire). Once spotted, remembered.
const SIGHT_TILES := 20.0

func is_seen(u: Dictionary, by: String) -> bool:
	if not options.get("fog", false):
		return true
	return bool(u.get("seen_by", {}).get(by, false))

## The enemy ids the squad has currently spotted: living enemies marked seen by "squad".
func _seen_enemies_squad() -> Array:
	var out: Array = []
	for u in units:
		if u["team"] == "enemy" and u["state"] != "dead" and is_seen(u, "squad"):
			out.append(u["id"])
	return out

## The firing muzzle reveals the shooter to the other side (and in both directions).
func _reveal(u: Dictionary) -> void:
	if not options.get("fog", false):
		return
	if not u.has("seen_by"):
		u["seen_by"] = {}
	for team in ["squad", "enemy"]:
		if team != u["team"]:
			u["seen_by"][team] = true

## A full two-way sight refresh after an action (cheap: few units against each other).
func refresh_seen() -> void:
	if not options.get("fog", false):
		return
	for t in units:
		if t["state"] == "dead" or not t.has("seen_by"):
			t["seen_by"] = {"squad": false, "enemy": false}
		for by in ["squad", "enemy"]:
			if t["team"] == by or bool(t["seen_by"][by]):
				continue
			for s in units:
				if s["team"] != by or s["state"] == "dead":
					continue
				# the eyes: men on foot, and every vehicle (the crew looks out through it)
				if s["kind"] != "vehicle" and int(s.get("in_vehicle", -1)) >= 0:
					continue
				if Vector2(s["pos"]).distance_to(Vector2(t["pos"])) > SIGHT_TILES:
					continue
				if can_see(s["pos"], t["pos"]):
					t["seen_by"][by] = true
					if by == "squad":
						log.append("%s IS SPOTTED." % String(t["name"]))
					break

## Cover of a target against a shooter: 2 heavy (wall / trunk right in front), 1 concealment
## (bushes on or next to the target), 0 none.
func cover(target: Vector2i, shooter: Vector2i) -> int:
	var l := line(target, shooter)
	if not l.is_empty() and is_blocked(l[0]):
		return 2
	if inside(target) and crater[idx(target)] > 0:     # down in a crater (lying or crouching)
		var m := at_tile(target)
		if not m.is_empty() and m["kind"] == "man" and m["stance"] != "stand":
			return 2 if m["stance"] == "prone" or crater[idx(target)] >= 2 else 1
	if inside(target) and bush[idx(target)] == 1:
		return 1
	if not l.is_empty() and inside(l[0]) and bush[idx(l[0])] == 1:
		return 1
	return 0

func dist_m(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b)) * tile

# ---------------- firing ----------------
const NOT_INDOORS := ["rocket launcher", "missile launcher", "grenade launcher", "heavy machinegun"]

## Indoors the launchers and the heavy machine guns stay silent.
func usable_here(wp: Dictionary) -> bool:
	return not (options["indoors"] and wp.get("category", "") in NOT_INDOORS)

func weapon_of(u: Dictionary, which := "") -> Dictionary:
	if u["kind"] == "vehicle":
		var g: String = which if which != "" else _main_gun(u)
		var gd: Dictionary = guns.get(g, {}).duplicate()
		gd["name"] = g
		gd["category"] = "vehicle gun"
		return gd
	var n: String = which if which != "" else u["weapon"]
	return items.get(n, {})

func _main_gun(v: Dictionary) -> String:
	var ws: Array = v["data"].get("weapons", [])
	return ws[0] if not ws.is_empty() else ""

static func skill_for(wp: Dictionary) -> String:
	match wp.get("category", ""):
		"revolver", "automatic pistol":
			return "PISTOL"
		"machinegun", "heavy machinegun", "grenade launcher", "rocket launcher", "missile launcher", "vehicle gun":
			return "HEAVY WEAPONS"
		"hand grenade":
			return "THROWN WEAPON"
	return "RIFLE"

## Range band of a distance for a weapon: 0 short, 1 medium, 2 long, 3 extreme, 4 out of range.
static func band(wp: Dictionary, m: float) -> int:
	var r := float(maxi(int(wp.get("range_m", 10)), 2))
	if m <= r:
		return 0
	if m <= 2 * r:
		return 1
	if m <= 4 * r:
		return 2
	if m <= 8 * r:
		return 3
	return 4

## Chance (0..1) that a shot hits. mode: snap / aimed / burst (per round).
func hit_chance(u: Dictionary, target: Dictionary, wp: Dictionary, mode: String) -> float:
	if wp.is_empty():
		return 0.0
	var m := dist_m(u["pos"], target["pos"])
	var b := band(wp, m)
	if b >= 4 or not can_see(u["pos"], target["pos"]):
		return 0.0
	var skill: int
	var agl := 5
	if u["kind"] == "vehicle":
		skill = crew_skill(u, "HEAVY WEAPONS")
	else:
		skill = int(u["skills"].get(skill_for(wp), 0.0))
		agl = int(u["attrs"].get("AGILITY", 5))
	var c := 20.0 + 7.0 * skill + 2.0 * agl
	c += [15.0, 0.0, -20.0, -40.0][b]
	match mode:
		"aimed":
			c += 30.0 if wp.get("category", "") == "sniper rifle" else 20.0
		"snap":
			c -= 10.0
		"burst":
			c -= 5.0
	if target["kind"] == "vehicle":
		c += 20.0
	else:
		c -= {"stand": 0.0, "crouch": 10.0, "prone": 20.0}[target["stance"]]
		c -= [0.0, 10.0, 35.0][cover(target["pos"], u["pos"])]
	if u["kind"] == "man":
		if _limb_out(u, "LEFT ARM") or _limb_out(u, "RIGHT ARM"):
			c -= 25.0
		if int(u["bleed"]) > 0:
			c -= 10.0
	elif u["moved"] and u["data"].get("stabilization", "") == "Fair":
		c -= 15.0
	if options["story"]:
		if u["team"] == "squad":
			c *= 1.2
		elif target["team"] == "squad":
			c *= 0.8
	return clampf(c / 100.0, 0.03, 0.95)

func ap_for(mode: String, u: Dictionary) -> int:
	if u["kind"] == "vehicle":
		return COST["gun"] if mode == "gun" else COST["burst"]
	return COST[mode]

## Fire at a target. mode: snap, aimed, burst; for vehicles which = the weapon ("" = main gun).
func fire(u: Dictionary, target: Dictionary, mode: String, which := "") -> bool:
	var wp := weapon_of(u, which)
	if wp.is_empty() or target.is_empty() or not active(u):
		return false
	if not usable_here(wp):
		log.append("YOU CAN'T USE THAT WEAPON INDOORS.")
		return false
	var cost := ap_for("gun" if (u["kind"] == "vehicle" and int(wp.get("rof", 0)) == 0) else mode, u)
	if u["ap"] < cost:
		return false
	if not is_seen(target, u["team"]):                # fog: no firing into the dark
		if u["team"] == "squad":
			log.append("THE TARGET IS NOT IN SIGHT.")
		return false
	var name: String = wp.get("name", "")
	if u["kind"] == "vehicle":
		if int(wp.get("rof", 0)) == 0:
			if u["fired_main"] or int(u["comp"]["gun"]) >= 100:
				return false
			u["fired_main"] = true
		if u["fired"].has(name):              # one gunner per weapon: each fires once a turn
			return false
		if int(u["ammo"].get(name, 0)) <= 0:
			log.append("THE %s IS OUT OF AMMUNITION FOR THE %s." % [u["name"], name])
			return false
	elif int(u["ammo"]) <= 0:
		log.append("%s MUST RELOAD THIS WEAPON BEFORE FIRING." % u["name"])
		return false
	u["ap"] -= cost
	if u["kind"] == "man":
		u["facing"] = _dir_index(target["pos"] - u["pos"])   # a vehicle's turret turns, not its hull
	_reveal(u)                                            # the muzzle flash carries the address
	var rounds := 1
	if mode == "burst" and int(wp.get("rof", 0)) > 0:
		rounds = int(wp["rof"])
	if u["kind"] == "vehicle":
		u["fired"][name] = true
		rounds = mini(rounds, int(u["ammo"][name]))
		u["ammo"][name] = int(u["ammo"][name]) - rounds
	else:
		rounds = mini(rounds, int(u["ammo"]))
		u["ammo"] = int(u["ammo"]) - rounds
	events.append({"type": "fire", "id": u["id"], "target": target["id"], "rounds": rounds, "weapon": name})
	var explosive: bool = wp.get("explosive", false) or wp.get("category", "") in ["rocket launcher", "missile launcher", "grenade launcher"]
	var hits := 0
	for r in range(rounds):
		var ch := hit_chance(u, target, wp, mode) - 0.05 * r * float(wp.get("recoil_burst", 2)) / 3.0
		if rng.randf() < ch:
			hits += 1
			if explosive and not (target["kind"] == "vehicle" and not wp.get("heat", true)):
				_explode(u, target["pos"], wp, target)
			else:
				_hit(u, target, wp)
		if not active(target):
			break
	if hits == 0:
		log.append("%s ATTACKS %s WITH THE %s AND MISSES." % [u["name"], target["name"], name])
		if explosive:
			var miss: Vector2i = target["pos"] + DIRS8[rng.randi_range(0, 7)] * rng.randi_range(1, 3)
			_explode(u, miss, wp, {})
	else:
		_xp(u, skill_for(wp), hits)
	_check_over()
	return true

## Melee attack: only at adjacent range. Uses UNARMED MELEE (or ARMED MELEE if a melee
## weapon is carried, but the remake has none, so UNARMED MELEE). Damage is 1D6 + STR/4.
func melee(u: Dictionary, target: Dictionary) -> bool:
	if target.is_empty() or not active(u) or not active(target):
		return false
	if target["kind"] == "vehicle":
		log.append("YOU CANNOT MELEE A VEHICLE.")
		return false
	var d := dist_m(u["pos"], target["pos"])
	if d > 1.5:
		log.append("%s IS TOO FAR AWAY TO STRIKE." % target["name"])
		return false
	var cost := 3
	if u["ap"] < cost:
		return false
	var skill_name := "UNARMED MELEE"
	var lvl := int(u["skills"].get(skill_name, 0.0))
	var str_val := int(u["attrs"].get("STRENGTH", 5))
	var dmg := rng.randi_range(1, 6) + int(str_val / 4) + lvl
	u["ap"] -= cost
	u["facing"] = _dir_index(target["pos"] - u["pos"])
	_reveal(u)
	events.append({"type": "fire", "id": u["id"], "target": target["id"], "rounds": 1, "weapon": "MELEE"})
	var loc := _location(target, false)
	var cap := int(target["hits"].get(loc, 10))
	var absorbed := 0
	var by_armor := ""
	for a in target["armor"]:
		if loc in ARMOR_COVERS.get(a, []):
			absorbed = mini(dmg, maxi(0, int(ARMOR_AV.get(a, 0)) - 0) * 2)
			by_armor = a
	if absorbed > 0:
		log.append("%s STRIKES %s IN %s FOR %d POINTS, %d ABSORBED BY %s." % [u["name"], target["name"], loc, dmg, absorbed, by_armor])
	else:
		log.append("%s STRIKES %s IN %s FOR %d POINTS OF DAMAGE." % [u["name"], target["name"], loc, dmg])
	_wound(target, loc, dmg - absorbed, u)
	_xp(u, skill_name, 1)
	_check_over()
	return true

## A bullet that hit: location, armour, damage and what it does to the body.
func _hit(u: Dictionary, target: Dictionary, wp: Dictionary) -> void:
	var b := band(wp, dist_m(u["pos"], target["pos"]))
	var pen: Array = wp.get("penetration", [0, 0, 0])
	var p := int(pen[mini(maxi(b - 1, 0), pen.size() - 1)]) if b > 0 else int(pen[0])
	if target["kind"] == "vehicle":
		_hit_vehicle(u, target, int(wp.get("damage", 1)), p, false, wp.get("name", ""))
		return
	var loc := _location(target, cover(target["pos"], u["pos"]) == 2)
	var dmg := _d6(maxi(1, int(wp.get("damage", 1))))
	var absorbed := 0
	var by := ""
	for a in target["armor"]:
		if loc in ARMOR_COVERS.get(a, []):
			absorbed = mini(dmg, maxi(0, int(ARMOR_AV.get(a, 0)) - p) * 2)
			by = a
	var txt := "%s ATTACKS %s WITH THE %s AND HITS %s, %d POINTS OF DAMAGE" % [u["name"], target["name"], wp.get("name", ""), loc, dmg]
	if absorbed > 0:
		txt += ", %d OF WHICH ARE ABSORBED BY THE %s" % [absorbed, by]
	log.append(txt + ".")
	_wound(target, loc, dmg - absorbed, u)

func _d6(n: int) -> int:
	var s := 0
	for i in range(n):
		s += rng.randi_range(1, 6)
	return s

## Hit location (d10): 1 head, 2-4 chest, 5-6 abdomen, 7-8 arms, 9-10 legs. Behind heavy cover
## or prone the legs and belly are hidden: those rolls hit the arms / head instead.
func _location(target: Dictionary, covered: bool) -> String:
	var r := rng.randi_range(1, 10)
	var loc: String = ["HEAD", "CHEST", "CHEST", "CHEST", "ABDOMEN", "ABDOMEN", "LEFT ARM", "RIGHT ARM", "LEFT LEG", "RIGHT LEG"][r - 1]
	if covered or target.get("stance", "") == "prone":
		if loc.ends_with("LEG"):
			loc = "LEFT ARM" if loc.begins_with("LEFT") else "RIGHT ARM"
		elif loc == "ABDOMEN":
			loc = "HEAD" if rng.randf() < 0.3 else "CHEST"
	return loc

func _limb_out(u: Dictionary, loc: String) -> bool:
	return int(u["dmg"].get(loc, 0)) >= int(u["hits"].get(loc, 99))

## Damage to a body location: slight / serious / critical, bleeding, death, knock-down.
func _wound(t: Dictionary, loc: String, dmg: int, by: Dictionary) -> void:
	if dmg <= 0:
		log.append("THE HIT CAUSED NO DAMAGE TO %s." % t["name"])
		return
	var cap := int(t["hits"].get(loc, 10))
	var before := int(t["dmg"].get(loc, 0))
	var now := before + dmg
	t["dmg"][loc] = now
	events.append({"type": "hit", "id": t["id"], "loc": loc, "dmg": dmg})
	if loc in ["HEAD", "CHEST"] and now >= cap:
		if _spared(t) and now < 2 * cap:
			log.append("THE HIT TO THE %s KNOCKS %s UNCONSCIOUS." % [loc, t["name"]])
			t["bleed"] = int(t["bleed"]) + 1
			_down(t)
			return
		_die(t, by, "THE HIT HAS KILLED %s." % t["name"])
		return
	var level := "SLIGHT"
	if now >= cap:
		level = "CRITICAL"
	elif now * 2 >= cap:
		level = "SERIOUS"
	log.append("THE HIT HAS CAUSED %s DAMAGE TO %s'S %s." % [level, t["name"], loc])
	if level != "SLIGHT" and before * 2 < cap:
		t["bleed"] = int(t["bleed"]) + (2 if level == "CRITICAL" else 1)
	if loc == "ABDOMEN" and now >= cap:
		_down(t)
	if dmg >= int(t["attrs"].get("CONSTITUTION", 5)) + 3 and t["state"] == "ok":
		t["knocked"] = true                          # knocked down: loses half the next turn
		t["stance"] = "prone"
		if current().get("id", -1) == t["id"]:
			t["ap"] = 0

## Blood loss at the start of a turn. Down at 3x CON, dead at 5x CON lost.
func _bleed(u: Dictionary) -> void:
	if int(u["bleed"]) <= 0:
		return
	u["blood"] = int(u["blood"]) + int(u["bleed"])
	var con := int(u["attrs"].get("CONSTITUTION", 5))
	if _spared(u):
		u["blood"] = mini(int(u["blood"]), 5 * con - 1)
	if int(u["blood"]) >= 5 * con:
		var worst := _worst_loc(u)
		_die(u, {}, "BECAUSE OF SEVERE BLOOD LOSS RESULTING FROM INJURIES TO THE %s, %s DIES." % [worst, u["name"]])
	elif int(u["blood"]) >= 3 * con and u["state"] == "ok":
		_down(u)

## Story mode: the squad's wounded fall unconscious instead of dying (except from a hit far over
## the location's capacity, or a vehicle blowing up around them).
func _spared(u: Dictionary) -> bool:
	return options["story"] and u["team"] == "squad" and u["kind"] == "man"

func _worst_loc(u: Dictionary) -> String:
	var best := "CHEST"
	var bv := -1.0
	for l in LOCS:
		var v := float(u["dmg"].get(l, 0)) / maxf(1.0, float(u["hits"].get(l, 10)))
		if v > bv:
			bv = v
			best = l
	return best

func _down(u: Dictionary) -> void:
	if u["state"] != "ok":
		return
	u["state"] = "down"
	u["stance"] = "prone"
	log.append("%s COLLAPSES." % u["name"])
	events.append({"type": "down", "id": u["id"]})
	_morale_witness(u, MO_DOWN)
	_check_over()

func _die(u: Dictionary, by: Dictionary, txt: String) -> void:
	if u["state"] == "dead":
		return
	u["state"] = "dead"
	u["bleed"] = 0
	log.append(txt)
	events.append({"type": "die", "id": u["id"]})
	if not by.is_empty():
		by["kills"] = int(by.get("kills", 0)) + 1
		_xp(by, "", 0, 2)
	_morale_witness(u, -MO_DEAD)
	if not by.is_empty() and by["kind"] == "man":
		_morale_killer(by)
	_check_over()

# ---------------- panic and morale (UFO-engine style, mapped to the tabletop's coolness) --
const MO_DOWN := 20.0                    # a man falls: the side loses heart
const MO_DEAD := 30.0
const MO_KILL := 15.0                    # and the killer's side takes heart
const PANIC_RECOVER := 50.0              # after the break he half-recovers

## Same-side witnesses lose `delta` heart (delta positive = loss); the other side gains
## half when someone falls. Vehicles have no heart.
func _morale_witness(victim: Dictionary, delta: float) -> void:
	var loss := -delta if delta < 0.0 else delta
	for s in units:
		if s["kind"] != "man" or s["state"] == "dead" or s["team"] != victim["team"]:
			continue
		s["morale"] = clampf(float(s.get("morale", 100.0)) - loss, 0.0, 150.0)

func _morale_killer(killer: Dictionary) -> void:
	for s in units:
		if s["kind"] == "man" and s["team"] == killer["team"] and s["state"] != "dead":
			s["morale"] = clampf(float(s.get("morale", 100.0)) + MO_KILL, 0.0, 150.0)

## Morale broken: freeze in place (lose the round) or run for the cover away from the
## enemy. The worst passes: morale recovers to half.
func _panic(u: Dictionary) -> void:
	if rng.randf() < 0.5:
		log.append("%s FREEZES IN FEAR." % u["name"])
		u["stance"] = "prone"
	else:
		log.append("%s PANICS AND RUNS FOR COVER." % u["name"])
		_flee(u)
	u["ap"] = 0
	u["morale"] = PANIC_RECOVER

## UFO-engine reaction fire: watchers of the other side that SEE the mover take one free
## snap shot (range <= 8 tiles), one reacting shooter per move, once per round each. The
## movement stops at a hit that drops the mover. Gated by options["reaction"].
func _reaction(mover: Dictionary) -> void:
	if not options.get("reaction", false) or mover["state"] != "ok":
		return
	var opp: String = "squad" if mover["team"] == "enemy" else "enemy"
	for s in units:
		if s["team"] != opp or s["state"] == "dead" or s["kind"] != "man" or s.get("reacted", false):
			continue
		if Vector2(s["pos"]).distance_to(Vector2(mover["pos"])) > 8.0:
			continue
		if not can_see(s["pos"], mover["pos"]) or not is_seen(mover, opp):
			continue
		log.append("%s REACTS TO %s'S MOVE." % [s["name"], mover["name"]])
		if fire(s, mover, "snap"):
			s["reacted"] = true
			if mover["state"] != "ok":
				return                        # the mover is down: the walk is over

# ---------------- explosions ----------------
## Grenade / shell / rocket bursting at a tile: concussion inside 3 m (knock-down and 2D6 to the
## chest), fragments to 2x the burst radius (each 1D6 to a random location; body armour stops
## a fragment whose damage is not above 3x its AV; prone or behind cover halves the chance).
func _explode(u: Dictionary, at: Vector2i, wp: Dictionary, direct: Dictionary) -> void:
	var big: bool = wp.get("category", "") in ["rocket launcher", "missile launcher"] or guns.has(wp.get("name", ""))
	events.append({"type": "explode", "tile": at, "size": 2 if big else 1})
	if not options["indoors"] and (direct.is_empty() or direct["kind"] != "vehicle"):   # a hit on a vehicle bursts on its armour
		_crater(at, 2 if big else 1, u["pos"] if not u.is_empty() else at)
	var burst := float(wp.get("burst", wp.get("damage_b", 6)))
	if not direct.is_empty() and direct["kind"] == "vehicle":
		var pen: Array = wp.get("penetration", [0, 0, 0])
		_hit_vehicle(u, direct, int(wp.get("damage", wp.get("damage_c", 6))), int(pen[0]), true, wp.get("name", ""))
	var anyone := false
	for t in units:
		if t["kind"] != "man" or t["state"] == "dead" or int(t.get("in_vehicle", -1)) >= 0 or t.get("fled", false):
			continue
		var m := dist_m(t["pos"], at)
		if m > burst * 2.0:
			continue
		anyone = true
		if m <= 3.0:
			var d := _d6(2 + int(wp.get("damage_c", 3)) / 3)
			log.append("%s IS %d METERS FROM THE BLAST SIGHT AND RECEIVES %d POINTS OF DAMAGE FROM THE CONCUSSION." % [t["name"], int(m), d])
			t["knocked"] = true
			t["stance"] = "prone"
			_wound(t, "CHEST", d, u)
			if t["state"] == "dead":
				continue
		var p := 0.6 if m <= burst else 0.2
		if t["stance"] == "prone" or cover(t["pos"], at) == 2:
			p *= 0.5
		var n := 0
		var tries := rng.randi_range(1, 3) if options["frag_limit"] else rng.randi_range(1, 6)
		for k in range(tries):
			if rng.randf() < p:
				n += 1
		if n == 0:
			log.append("%s HAS NOT BEEN HIT BY FRAGMENTS." % t["name"])
			continue
		for k in range(n):
			var loc := _location(t, false)
			var d := rng.randi_range(1, 6)
			var stopped := ""
			for a in t["armor"]:
				if loc in ARMOR_COVERS.get(a, []) and d <= int(ARMOR_AV.get(a, 0)) * 3:
					stopped = a
			if stopped != "":
				log.append("%s HAS BEEN PROTECTED BY THE %s." % [t["name"], stopped])
				continue
			log.append("%s IS HIT BY A FRAGMENT IN THE %s, %d POINTS OF DAMAGE." % [t["name"], loc, d])
			_wound(t, loc, d, u)
			if t["state"] == "dead":
				break
	if not anyone and (direct.is_empty() or direct["kind"] != "vehicle"):
		log.append("THE EXPLOSION WAS HARMLESS.")

## The hole a burst leaves: a shell hole (1) from grenades, a crater (2, with a ring of shell-hole
## ground round it) from shells, rockets and missiles. A big blast fells a tree at its centre.
func _crater(at: Vector2i, size: int, from: Vector2i) -> void:
	if not inside(at) or (blocked[idx(at)] == 1 and tree[idx(at)] == 0):
		return                                     # not on a wall
	if size >= 2:
		fell_tree(at, at - from)
	var tiles := [at]
	if size >= 2:
		tiles += [at + Vector2i(1, 0), at + Vector2i(-1, 0), at + Vector2i(0, 1), at + Vector2i(0, -1)]
	for t in tiles:
		if inside(t) and blocked[idx(t)] == 0:
			crater[idx(t)] = maxi(int(crater[idx(t)]), size if t == at else 1)
	events.append({"type": "crater", "tile": at, "size": size})

## Throw a grenade at a tile (Thrown Weapon skill; misses scatter 1-3 tiles).
func throw_grenade(u: Dictionary, at: Vector2i) -> bool:
	if u["kind"] != "man" or int(u["grenades"]) <= 0 or u["ap"] < COST["grenade"]:
		return false
	var occ := at_tile(at)
	if at == u["pos"] or (not occ.is_empty() and occ["team"] == u["team"] and occ["state"] != "dead"):
		log.append("YOU CANNOT DROP A GRENADE ON YOUR OWN MAN.")
		return false
	var rng_m := float(int(u["attrs"].get("STRENGTH", 5)) * 4 + 10)
	if dist_m(u["pos"], at) > rng_m:
		log.append("THERE ARE NO ENEMIES WITHIN THROWING RANGE.")
		return false
	u["ap"] -= COST["grenade"]
	u["grenades"] = int(u["grenades"]) - 1
	_reveal(u)
	var gr: Dictionary = items.get("FRAGMENTATION GRENADE", {"damage_c": 3, "damage_b": 12})
	var land := at
	var skill := int(u["skills"].get("THROWN WEAPON", 0.0))
	if rng.randf() >= clampf(0.35 + 0.08 * skill + 0.02 * int(u["attrs"].get("AGILITY", 5)), 0.1, 0.95):
		land = at + DIRS8[rng.randi_range(0, 7)] * rng.randi_range(1, 3)
		land = Vector2i(clampi(land.x, 0, w - 1), clampi(land.y, 0, h - 1))
	else:
		_xp(u, "THROWN WEAPON", 1)
	log.append("%s THROWS THE GRENADE. THE GRENADE LANDS %d METERS FROM THE TARGET." % [u["name"], int(dist_m(land, at))])
	events.append({"type": "throw", "id": u["id"], "tile": land})
	var g2 := {"name": "FRAGMENTATION GRENADE", "damage_c": int(gr.get("damage_c", 3)), "burst": float(gr.get("damage_b", 12)) / 2.0}
	_explode(u, land, g2, at_tile(land))
	_check_over()
	return true

# ---------------- vehicles hit ----------------
## Which armour a shot meets: hull or turret (turreted vehicles 50/50), and the facing the
## shot comes from relative to the vehicle's heading.
## Which side of a vehicle faces a point: F front, S side, R rear.
func arc(v: Dictionary, from: Vector2i) -> String:
	var heading := Vector2(DIRS8[int(v["facing"])])
	var to_shooter := Vector2(from - v["pos"]).normalized()
	var dot := heading.normalized().dot(to_shooter)
	return "F" if dot > 0.5 else ("R" if dot < -0.5 else "S")

func _facing_key(v: Dictionary, from: Vector2i) -> String:
	var side := arc(v, from)
	var turret: bool = v["data"]["config"] != "Stnd" and rng.randf() < 0.5
	return ("T" if turret else "H") + side

func _hit_vehicle(u: Dictionary, v: Dictionary, damage: int, pen: int, heat: bool, wname: String) -> void:
	var key := _facing_key(v, u["pos"])
	var arm: Dictionary = v["data"]["armor"]
	var av := int(arm.get(key, arm.get("H" + key.substr(1), 1)))
	if heat and key in v["data"].get("spaced", []):
		av *= 2
	if key in v["data"].get("compound", []):
		av = int(av * (2.0 if heat else 1.2))
	var where: String = {"HF": "HULL FRONT", "HS": "HULL SIDE", "HR": "HULL REAR", "TF": "TURRET FRONT", "TS": "TURRET SIDE", "TR": "TURRET REAR"}[key]
	# small arms can always chew at wheels and tracks
	if not heat and rng.randf() < 0.2:
		var sv: Array = v["data"]["susp"]
		if damage >= 4 or sv[0] == "W":
			v["comp"]["susp"] = mini(100, int(v["comp"]["susp"]) + int(100 / max(1, int(sv[1]))))
			log.append("%s HITS THE %s IN THE SUSPENSION." % [u["name"], v["name"]])
			if int(v["comp"]["susp"]) >= 100:
				log.append("THE %s CANNOT MOVE: THE SUSPENSION IS DESTROYED." % v["name"])
			return
	if pen < av:
		log.append("%s HITS THE %s ON THE %s. THE ROUND DOES NOT PENETRATE (%d VS %d)." % [u["name"], v["name"], where, pen, av])
		events.append({"type": "ricochet", "id": v["id"]})
		return
	var excess := pen - av
	var power := damage + excess / 10
	log.append("%s HITS THE %s ON THE %s AND PENETRATES." % [u["name"], v["name"], where])
	events.append({"type": "penetrate", "id": v["id"]})
	# what is behind the armour: crew, engine (hull), gun / turret drive (turret), ammunition.
	# A round with a lot of energy left goes through more than one thing (1 + excess / 40).
	var parts: Array = ["crew", "engine", "engine", "fuel", "ammo"] if key.begins_with("H") else ["crew", "gun", "turret", "ammo"]
	for k in range(1 + mini(3, excess / 40)):
		if v["state"] != "ok":
			return
		_component_hit(u, v, parts[rng.randi_range(0, parts.size() - 1)], power, heat)
	_xp(u, "HEAVY WEAPONS" if heat else "", 1)
	if int(v["crew_left"]) <= 0 and v["state"] == "ok":
		log.append("THE %s IS KNOCKED OUT." % v["name"])
		_vehicle_destroyed(v, u, false)

func _component_hit(u: Dictionary, v: Dictionary, part: String, power: int, heat: bool) -> void:
	var pct := mini(100, power * rng.randi_range(5, 15))
	match part:
		"crew":
			_crew_hit(v, power, u)
		"ammo":
			if rng.randi_range(1, 100) <= (pct + 20 if heat else pct / 2):
				log.append("THE AMMUNITION EXPLODES. THE HIT HAS DESTROYED THE VEHICLE.")
				_vehicle_destroyed(v, u, true)
			_crew_hit(v, power / 2, u)
		_:
			v["comp"][part] = mini(100, int(v["comp"][part]) + pct)
			log.append("THE HIT CAUSES %d%% DAMAGE TO THE %s'S %s." % [pct, v["name"], part.to_upper()])
			if part == "fuel" and heat and int(v["comp"]["fuel"]) >= 60:
				log.append("THE FUEL CATCHES FIRE. THE HIT HAS DESTROYED THE VEHICLE.")
				_vehicle_destroyed(v, u, false)

func _crew_hit(v: Dictionary, power: int, by: Dictionary) -> void:
	# men of the squad inside take the hit; a nameless crew loses a man
	var inside: Array = v["occupants"].map(func(id): return unit(id)).filter(func(m): return not m.is_empty() and m["state"] != "dead")
	if not inside.is_empty():
		var m: Dictionary = inside[rng.randi_range(0, inside.size() - 1)]
		_wound(m, _location(m, false), _d6(maxi(1, power / 2)), by)
		if m["state"] != "ok":
			v["crew_left"] = maxi(0, int(v["crew_left"]) - 1)
	else:
		v["crew_left"] = maxi(0, int(v["crew_left"]) - 1)
		log.append("A CREWMAN OF THE %s IS HIT." % v["name"])

## Knocked out: men of the squad inside get out (survivors), a nameless crew bails out as men
## with pistols (the tabletop's bail-out) unless the vehicle blew up.
func _vehicle_destroyed(v: Dictionary, by: Dictionary, blown: bool) -> void:
	v["state"] = "dead"
	events.append({"type": "wreck", "id": v["id"]})
	if not by.is_empty():
		by["kills"] = int(by.get("kills", 0)) + 1
	for id in v["occupants"]:
		var m := unit(id)
		if m.is_empty():
			continue
		m["in_vehicle"] = -1
		if blown:
			_die(m, by, "%s DIES IN THE EXPLOSION." % m["name"])
		else:
			m["pos"] = _free_near(v["pos"])
	v["occupants"] = []
	if not blown and v["team"] == "enemy":
		for k in range(int(v["crew_left"])):
			var t := {"name": "CREWMAN", "skills": {"PISTOL": 2}, "attrs": {"STRENGTH": 5, "CONSTITUTION": 5, "AGILITY": 5},
				"hits": {"HEAD": 10, "CHEST": 30, "ABDOMEN": 20, "LEFT ARM": 20, "RIGHT ARM": 20, "LEFT LEG": 20, "RIGHT LEG": 20},
				"gear": {"weapon": "PM MAKAROV", "mags": 2}, "initiative": 2}
			var c := add_man("enemy", t, _free_near(v["pos"]))
			log.append("A CREWMAN BAILS OUT OF THE %s." % v["name"])
	v["crew_left"] = 0
	_check_over()

func _free_near(t: Vector2i) -> Vector2i:
	for r in range(2, 6):
		for d in DIRS8:
			var c: Vector2i = t + d * r
			if is_free_tile(c):
				return c
	return t

# ---------------- reloading, first aid ----------------
func reload(u: Dictionary) -> bool:
	if u["kind"] != "man" or u["ap"] < COST["reload"]:
		return false
	var wp := weapon_of(u)
	if int(u["mags"]) <= 0:
		log.append("THAT WEAPON HAS NO EXTRA CLIPS.")
		return false
	if int(u["ammo"]) >= int(wp.get("magazine", 1)):
		log.append("THAT WEAPON IS FULLY LOADED.")
		return false
	u["ap"] -= COST["reload"]
	u["mags"] = int(u["mags"]) - 1
	u["ammo"] = maxi(1, int(wp.get("magazine", 1)))
	if u["team"] == "squad":
		log.append("YOU SPEND A COMBAT ROUND RELOADING YOUR %s." % String(wp.get("name", "WEAPON")))
	else:
		log.append("THE ENEMY SPENDS A ROUND RELOADING.")
	return true

## First aid on a man next to the medic (or himself): stops bleeding, may bring a fallen man
## round. Medical skill; a personal medical kit adds to the chance.
func first_aid(medic: Dictionary, patient: Dictionary) -> bool:
	if medic["kind"] != "man" or medic["ap"] < COST["aid"] or patient["state"] == "dead":
		return false
	if (medic["pos"] - patient["pos"]).abs().x > 1 or (medic["pos"] - patient["pos"]).abs().y > 1:
		return false
	if int(patient["bleed"]) <= 0 and patient["state"] == "ok":
		log.append("%s DOES NOT NEED FIRST AID." % patient["name"])
		return false
	medic["ap"] -= COST["aid"]
	var skill := int(medic["skills"].get("MEDICAL", 0.0))
	var kit := int(medic["medkits"]) > 0
	var ch := clampf(0.3 + 0.08 * skill + (0.2 if kit else 0.0), 0.05, 0.95)
	if kit:
		medic["medkits"] = int(medic["medkits"]) - 1
	if rng.randf() < ch:
		patient["bleed"] = 0
		var l := _worst_loc(patient)
		patient["dmg"][l] = maxi(0, int(patient["dmg"].get(l, 0)) - rng.randi_range(1, 3))
		log.append("%s GIVES %s FIRST AID. THE BLEEDING STOPS." % [medic["name"], patient["name"]])
		_xp(medic, "MEDICAL", 1)
		if patient["state"] == "down" and int(patient["blood"]) < 3 * int(patient["attrs"].get("CONSTITUTION", 5)) and int(patient["dmg"].get("ABDOMEN", 0)) < int(patient["hits"].get("ABDOMEN", 99)):
			patient["state"] = "ok"
			log.append("%s IS BACK ON %s FEET." % [patient["name"], "HER" if patient.get("gender", "M") == "F" else "HIS"])
		return true
	patient["bleed"] = maxi(0, int(patient["bleed"]) - 1)
	log.append("%s'S FIRST AID ONLY SLOWS THE BLEEDING." % medic["name"])
	return true

# ---------------- experience ----------------
## Skill experience (the tabletop's learning by doing): a point per success, kills count double.
func _xp(u: Dictionary, skill: String, n: int, kill := 0) -> void:
	if skill == "" and kill > 0 and u["kind"] == "man":
		skill = skill_for(weapon_of(u))
	if skill == "":
		return
	var who := u
	if u["kind"] == "vehicle":
		var ins: Array = u["occupants"]
		if ins.is_empty():
			return
		who = unit(ins[0])
	who["xp"][skill] = int(who["xp"].get(skill, 0)) + n + kill

# ---------------- AI ----------------
## One step of a computer-controlled unit (enemies, and the squad in auto-tests). Returns false
## when it has nothing more to do this turn.
func ai_step(u: Dictionary) -> bool:
	if not active(u) or over:
		return false
	var foes := units.filter(func(x): return x["team"] != u["team"] and active(x) and is_seen(x, u["team"]))
	if foes.is_empty():
		# nothing in sight: the squad hunts the objective, and every tank hunts the other
		# side's engine noise (an idle armour duel would never make contact in the fog)
		var hunt: bool = bool(options.get("fog", false)) and seek.x >= 0 and (u["team"] == "squad" or u["kind"] == "vehicle")
		var target := Vector2(seek)
		if hunt and u["team"] != "squad":
			var near_sq := units.filter(func(x): return x["team"] == "squad" and active(x))
			if near_sq.is_empty():
				return false
			var best_sq: Dictionary = near_sq[0]
			for x in near_sq:
				if Vector2(x["pos"]).distance_to(Vector2(u["pos"])) < Vector2(best_sq["pos"]).distance_to(Vector2(u["pos"])):
					best_sq = x
			target = Vector2(best_sq["pos"])
		if hunt:
			# move toward the target (the route draws the reaction fire as it goes)
			var reach := reachable(u)
			var best_t: Vector2i = u["pos"]
			var best_d := target.distance_to(Vector2(u["pos"]))
			for t in reach:
				var d := target.distance_to(Vector2(t))
				if d < best_d - 0.01:
					best_d = d
					best_t = t
			if best_t != u["pos"] and move(u, best_t):
				return true
			return false
		return false
	if u["kind"] == "man":
		# a wounded friend next to us bleeds: first aid (if no enemy is right on top of us)
		for f in units:
			if f["team"] == u["team"] and f["id"] != u["id"] and f["kind"] == "man" and f["state"] != "dead" and int(f["bleed"]) > 0:
				if (f["pos"] - u["pos"]).abs().x <= 1 and (f["pos"] - u["pos"]).abs().y <= 1 and u["ap"] >= COST["aid"]:
					return first_aid(u, f)
		if int(u["ammo"]) <= 0:
			if reload(u):
				return true
			return false
		# morale: half the side down and the rest may run (coolness ~ initiative)
		var mine := units.filter(func(x): return x["team"] == u["team"] and x["kind"] == "man")
		var lost := mine.filter(func(x): return x["state"] != "ok").size()
		if lost * 2 >= mine.size() and mine.size() > 1 and u["team"] == "enemy" and rng.randi_range(1, 10) > int(u["initiative"]) + 4:
			return _flee(u)
	# best target and way of firing
	var best_t: Dictionary = {}
	var best_s := 0.0
	var best_m := "snap"
	var best_w := ""
	var options_w: Array = [""]
	var armour_present := foes.any(func(f): return f["kind"] == "vehicle" and int(f["data"]["armor"].get("HF", 0)) >= 20)
	if u["kind"] == "vehicle":
		options_w = u["data"].get("weapons", [])
	elif u["launcher"] != "" and int(u["rockets"]) > 0:
		options_w = ["", u["launcher"]]
	for f in foes:
		for wn in options_w:
			var wp := weapon_of(u, wn)
			if wp.is_empty() or not usable_here(wp) or (u["kind"] == "vehicle" and (u["fired"].has(wn) or (int(wp.get("rof", 0)) == 0 and u["fired_main"]))):
				continue
			var vs_vehicle: bool = f["kind"] == "vehicle"
			var at: bool = wp.get("category", "") in ["rocket launcher", "missile launcher"] or (u["kind"] == "vehicle" and int(wp.get("rof", 0)) == 0)
			if u["kind"] == "man" and at and not vs_vehicle and armour_present:
				continue                          # the rockets are for the tank
			if vs_vehicle and not at and int(wp.get("penetration", [0])[0]) < 5:
				continue
			for m in (["gun"] if u["kind"] == "vehicle" and int(wp.get("rof", 0)) == 0 else ["snap", "aimed", "burst"]):
				if m == "burst" and int(wp.get("rof", 0)) == 0:
					continue
				var mode: String = "snap" if m == "gun" else m
				if u["ap"] < ap_for(m, u):
					continue
				var ch := hit_chance(u, f, wp, mode)
				# launchers have damage 0 in ITEMS.DAT: their warhead is damage_c (contact)
				var dmg := float(maxi(int(wp.get("damage", 0)), int(wp.get("damage_c", 1)))) * (float(wp.get("rof", 1)) * 0.5 if m == "burst" else 1.0)
				var score := ch * dmg * (3.0 if vs_vehicle and at else 1.0)
				if score > best_s:
					best_s = score
					best_t = f
					best_m = m
					best_w = wn
	# a grenade into a group of two or more
	if u["kind"] == "man" and int(u["grenades"]) > 0 and u["ap"] >= COST["grenade"]:
		for f in foes:
			if f["kind"] != "man":
				continue
			var near := foes.filter(func(x): return x["kind"] == "man" and dist_m(x["pos"], f["pos"]) <= 6.0).size()
			var mates := units.filter(func(x): return x["team"] == u["team"] and active(x) and dist_m(x["pos"], f["pos"]) <= 10.0).size()
			if near >= 2 and mates == 0 and dist_m(u["pos"], f["pos"]) <= float(int(u["attrs"].get("STRENGTH", 5)) * 4 + 10) and dist_m(u["pos"], f["pos"]) > 10.0:
				return throw_grenade(u, f["pos"])
	# a man with a launcher in front of a tank works round to its side first (16 mm there, not 100)
	if u["kind"] == "man" and u["launcher"] != "" and int(u["rockets"]) > 0 and _flank(u, foes):
		return true
	if not best_t.is_empty() and (best_s > 0.6 or u["ap"] < 4 or u["kind"] == "vehicle" and best_s > 0.1):
		if u["kind"] == "man" and best_w != "":
			var keep: String = u["weapon"]
			var ka := int(u["ammo"])
			u["weapon"] = best_w
			u["ammo"] = 1
			var ok := fire(u, best_t, "snap")
			u["weapon"] = keep
			u["ammo"] = ka
			if ok:
				u["rockets"] = int(u["rockets"]) - 1
				if int(u["rockets"]) <= 0:
					u["launcher"] = ""
			return ok
		return fire(u, best_t, "snap" if best_m == "gun" else best_m, best_w)
	# nobody worth shooting from here: move to a better spot (closer, in cover)
	if u["ap"] >= move_cost(u) * 2:
		var tgt: Dictionary = foes[0]
		for f in foes:
			if dist_m(u["pos"], f["pos"]) < dist_m(u["pos"], tgt["pos"]):
				tgt = f
		var reach := reachable(u)
		var bt: Vector2i = u["pos"]
		var bs := -1e9
		var wp := weapon_of(u)
		var want := float(wp.get("range_m", 30)) * 1.5
		for t in reach:
			var d := dist_m(t, tgt["pos"])
			var s := -absf(d - want) - float(reach[t]) * 0.5
			if can_see(t, tgt["pos"]):
				s += 25.0
			s += cover(t, tgt["pos"]) * 12.0
			if s > bs:
				bs = s
				bt = t
		if bt != u["pos"] and move(u, bt):
			return true
	if not best_t.is_empty() and u["ap"] >= 3:
		return fire(u, best_t, "snap" if best_m == "gun" else best_m, best_w)
	if u["kind"] == "man" and u["stance"] == "stand" and u["ap"] >= 1:
		return set_stance(u, "crouch")
	return false

## Move a launcher man to the side or rear of the nearest armoured vehicle that faces him: a tile
## in launcher range he can see it from, as covered as can be, keeping 3 AP to fire. False when
## he is already on its flank, or no such tile is in reach this turn (then he fires from here).
func _flank(u: Dictionary, foes: Array) -> bool:
	var veh: Dictionary = {}
	for f in foes:
		if f["kind"] == "vehicle" and int(f["data"]["armor"].get("HF", 0)) >= 20 and (veh.is_empty() or dist_m(u["pos"], f["pos"]) < dist_m(u["pos"], veh["pos"])):
			veh = f
	if veh.is_empty() or arc(veh, u["pos"]) != "F" or u["ap"] < move_cost(u) * 2 + COST["snap"]:
		return false
	var rng_m := float(items.get(u["launcher"], {}).get("range_m", 100))
	var reach := reachable(u)
	var bt := Vector2i(-1, -1)
	var bs := -1e9
	for t in reach:
		if float(reach[t]) > u["ap"] - COST["snap"] or arc(veh, t) == "F":
			continue
		var d := dist_m(t, veh["pos"])
		if d > rng_m or d < 8.0 or not can_see(t, veh["pos"]):
			continue
		var sc := -float(reach[t]) + (8.0 if arc(veh, t) == "R" else 0.0)
		for o in foes:                            # cover from the others too
			if o["kind"] == "man":
				sc += cover(t, o["pos"]) * 3.0
		if sc > bs:
			bs = sc
			bt = t
	if bt.x >= 0:
		return move(u, bt)
	# no flank tile this turn: work towards one (12 tiles off the tank's side nearer to him),
	# from cover to cover, if that gets him clearly closer
	var hd := Vector2(DIRS8[int(veh["facing"])])
	var side := Vector2(-hd.y, hd.x).normalized()
	if side.dot(Vector2(u["pos"] - veh["pos"])) < 0.0:
		side = -side
	var goal := Vector2(veh["pos"]) + side * 12.0
	var now := Vector2(u["pos"]).distance_to(goal)
	bs = -1e9
	for t in reach:
		var d := Vector2(t).distance_to(goal)
		if d > now - 3.0:
			continue
		var sc := -d * 2.0 + cover(t, veh["pos"]) * 6.0
		if sc > bs:
			bs = sc
			bt = t
	return bt.x >= 0 and move(u, bt)

func _flee(u: Dictionary) -> bool:
	var edge := Vector2i(0 if u["pos"].x < w / 2 else w - 1, u["pos"].y)
	if u["pos"].x == edge.x or u["pos"].x <= 0 or u["pos"].x >= w - 1:
		u["fled"] = true
		log.append("%s RUNS AWAY." % u["name"])
		_check_over()
		return false
	var reach := reachable(u)
	var bt: Vector2i = u["pos"]
	for t in reach:
		if absi(t.x - edge.x) < absi(bt.x - edge.x):
			bt = t
	if bt == u["pos"]:
		return false
	return move(u, bt)

## Let the computer play the current unit's whole turn.
func ai_turn() -> void:
	var u := current()
	if u["team"] == "enemy":
		log.append("THE ENEMY TURN BEGINS.")
	var guard := 0
	while not u.is_empty() and active(u) and guard < 12 and not over:
		guard += 1
		if not ai_step(u):
			break
	if not over:
		end_turn()

## Auto-resolve the whole battle (tests, and "quick combat").
func auto_play(max_rounds := 40) -> void:
	start()
	var guard := 0
	while not over and round_no <= max_rounds and guard < 2000:
		guard += 1
		ai_turn()
	if not over:
		over = true
		winner = "none"

# ---------------- after the battle ----------------
## After the fighting: the squad's best medic sees to whoever still bleeds (5 minutes each).
## Story mode: whoever lies unconscious comes to at half strength.
func aftermath() -> Array:
	var lines: Array = []
	var sq := units.filter(func(u): return u["team"] == "squad" and u["kind"] == "man")
	var medics := sq.filter(func(u): return u["state"] == "ok")
	medics.sort_custom(func(a, b): return int(a["skills"].get("MEDICAL", 0.0)) > int(b["skills"].get("MEDICAL", 0.0)))
	for p in sq:
		if p["state"] == "dead" or (int(p["bleed"]) <= 0 and p["state"] == "ok"):
			continue
		if _spared(p) and p["state"] == "down":
			_half_strength(p)
			lines.append("%s COMES TO, BANDAGED. HALF FIT TO FIGHT." % p["name"])
			continue
		if _spared(p):
			p["bleed"] = 0
			lines.append("%s'S WOUNDS ARE BANDAGED." % p["name"])
			continue
		if medics.is_empty():
			_die(p, {}, "BECAUSE OF SEVERE BLOOD LOSS RESULTING FROM INJURIES TO THE %s, %s DIES." % [_worst_loc(p), p["name"]])
			lines.append(log[-1])
			continue
		var m: Dictionary = medics[0]
		m["ap"] = AP_MAX
		var tries := 3
		while tries > 0 and (int(p["bleed"]) > 0 or p["state"] == "down"):
			tries -= 1
			m["ap"] = AP_MAX
			m["pos"] = p["pos"] + Vector2i(1, 0)
			first_aid(m, p)
		if int(p["bleed"]) > 0:
			_die(p, {}, "BECAUSE OF SEVERE BLOOD LOSS RESULTING FROM INJURIES TO THE %s, %s DIES." % [_worst_loc(p), p["name"]])
		lines.append(log[-1])
	return lines

## Story mode: an unconscious man comes to at 50% condition. No location is worse than half
## its capacity, the blood loss is at most half the deadly amount, and the bleeding is stopped.
func _half_strength(u: Dictionary) -> void:
	for l in LOCS:
		var cap := int(u["hits"].get(l, 10))
		if int(u["dmg"].get(l, 0)) > cap / 2:
			u["dmg"][l] = cap / 2
	u["blood"] = mini(int(u["blood"]), 5 * int(u["attrs"].get("CONSTITUTION", 5)) / 2)
	u["bleed"] = 0
	u["state"] = "ok"
	u["stance"] = "stand"

## Jagged Alliance-style planning: queue actions for a unit without spending its AP yet;
## the queue is played out all at once in execute_plan(). plan_ap is the budget left.
func plan_move(u: Dictionary, to: Vector2i) -> bool:
	if u["kind"] != "man" or u["state"] != "ok":
		return false
	var f := _flood(u)
	if not f.has(to) or to == u["pos"]:
		return false
	var cost := float(f[to][0])
	if cost > float(u.get("plan_ap", 0)) + 0.001:
		return false
	var p := path_to(u, to)
	if p.is_empty():
		return false
	u["plan"].append({"type": "move", "to": to, "path": p})
	u["plan_ap"] = int(u["plan_ap"]) - int(round(cost))
	return true

func plan_fire(u: Dictionary, target: Dictionary, mode: String) -> bool:
	if u["kind"] != "man" or target.is_empty() or target["state"] == "dead":
		return false
	var cost := ap_for(mode, u)
	if cost > int(u.get("plan_ap", 0)):
		return false
	u["plan"].append({"type": "fire", "target": target["id"], "mode": mode})
	u["plan_ap"] = int(u["plan_ap"]) - cost
	return true

func plan_grenade(u: Dictionary, at: Vector2i) -> bool:
	if u["kind"] != "man" or int(u["grenades"]) <= 0 or COST["grenade"] > int(u.get("plan_ap", 0)):
		return false
	var occ := at_tile(at)
	if at == u["pos"] or (not occ.is_empty() and occ["team"] == u["team"] and occ["state"] != "dead"):
		log.append("YOU CANNOT DROP A GRENADE ON YOUR OWN MAN.")
		return false
	u["plan"].append({"type": "grenade", "to": at})
	u["plan_ap"] = int(u["plan_ap"]) - COST["grenade"]
	return true

func clear_plan(u: Dictionary) -> void:
	u["plan"] = []
	u["plan_ap"] = int(u["ap"])

## Play every planned action of the squad in one pass, then hand the turn to the enemy.
## If a previously unseen enemy shows up mid-execution, the plan aborts (REPLAN): the
## remaining plans stay queued, plan_ap and end_turn() are left alone, and the view is
## expected to drop back to the planning phase.
func execute_plan() -> void:
	var seen_before := _seen_enemies_squad()
	for u in units:
		if u["team"] != "squad" or u["kind"] != "man" or not active(u):
			continue
		if u["plan"].is_empty():
			continue
		for a in u["plan"]:
			if not active(u):
				break
			match a["type"]:
				"move":
					move(u, a["to"])
				"fire":
					var t := unit(a["target"])
					if not t.is_empty():
						fire(u, t, a.get("mode", "snap"))
				"grenade":
					throw_grenade(u, a["to"])
			var seen_now := _seen_enemies_squad()
			var newly: Array = []
			for e in seen_now:
				if not seen_before.has(e):
					newly.append(e)
			if not newly.is_empty():
				interrupted = true
				interrupt_enemies = newly
				return
		u["plan"] = []
		u["plan_ap"] = 0
	end_turn()
## Returns the improvement lines.
func write_back(squad: Array, cr: ChargenRules) -> Array:
	var lines: Array = []
	for u in units:
		if u["team"] != "squad" or u["kind"] != "man" or int(u["ref"]) < 0 or int(u["ref"]) >= squad.size():
			continue
		var r: Dictionary = squad[int(u["ref"])]
		r["damage"] = u["dmg"]
		if u["state"] != "dead":
			_survivor(r["damage"], u["hits"])
		r["bleed"] = u["bleed"]
		r["blood"] = u["blood"]
		r["dead"] = u["state"] == "dead"
		var g: Dictionary = r.get("gear", {})
		g["mags"] = u["mags"] + (1 if int(u["ammo"]) > 0 else 0)
		g["grenades"] = u["grenades"]
		g["medkits"] = u["medkits"]
		g["rockets"] = u["rockets"]
		if u["launcher"] == "":
			g["launcher"] = ""
		r["gear"] = g
		r["kills"] = int(r.get("kills", 0)) + int(u["kills"])
		if r["dead"]:
			continue
		var xp: Dictionary = r.get("xp", {})
		for s in u["xp"]:
			xp[s] = int(xp.get(s, 0)) + int(u["xp"][s])
			var lvl := cr.level(r, s)
			var need := 3 + lvl
			while int(xp[s]) >= need:
				xp[s] = int(xp[s]) - need
				cr.add_skill(r, s, 1)
				if cr.level(r, s) > lvl:             # half levels (see ChargenRules) improve silently
					lines.append("%s IMPROVES: %s %d -> %d" % [r["name"], s, lvl, cr.level(r, s)])
				lvl = cr.level(r, s)
				need = 3 + lvl
		r["xp"] = xp
	return lines
