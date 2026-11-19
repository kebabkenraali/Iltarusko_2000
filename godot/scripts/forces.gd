## Who fights with what: the squad's kit (the manual's basic load plus a weapon by nationality
## and skill), the groups met on the road and in the towns, the vehicles, and how a battle is
## set up on the ground of a place (terrain props, town walls) and how the squad deploys.
class_name Forces
extends RefCounted

const NATO := ["BRITAIN", "CANADA", "GERMANY", "DENMARK", "UNITED STATES"]
const NATO_RIFLE := {"BRITAIN": "L85", "CANADA": "M16A2", "GERMANY": "G3", "DENMARK": "G3", "UNITED STATES": "M16A2"}
const PACT_RIFLE := {"POLAND": "AKM", "HUNGARY": "AKM", "CZECHOSLOVAKIA": "AKM", "U.S.S.R": "AK-74"}
const MAX_DEPLOY := 10                 # tiles from the nearest squad mate when placing by hand
const ENEMY_KEEP := 6                  # deploy no closer to the enemy than this (tiles)

## The basic load (manual p.31): kevlar vest and helmet, six fragmentation grenades, a personal
## medical kit; the weapon by nationality and what the recruit is best at.
static func equip(r: Dictionary) -> void:
	if r.has("gear"):
		return
	var nato: bool = r.get("country", "") in NATO
	var weapon: String = NATO_RIFLE.get(r.get("country", ""), "") if nato else PACT_RIFLE.get(r.get("country", ""), "AK-74")
	var sk: Dictionary = r.get("skills", {})
	var hw := int(sk.get("HEAVY WEAPONS", 0.0))
	var rf := int(sk.get("RIFLE", 0.0))
	var launcher := ""
	if hw >= 4 and hw > rf:
		weapon = "M60" if nato else "PK"
	elif hw >= 2:
		launcher = "LAW 80 ROCKET LAUNCHER" if nato else "RPG-16 ROCKET LAUNCHER"
	if int(sk.get("PISTOL", 0.0)) > rf + 2 and hw < 2:
		weapon = "M9" if nato else "PM MAKAROV"
	r["gear"] = {"weapon": weapon, "mags": 5, "grenades": 6, "medkits": 1, "armor": ["KEVLAR VEST", "KEVLAR HELMET"],
		"launcher": launcher, "rockets": 2 if launcher != "" else 0}

## Enemy soldiers for a group met on the road (World.GROUPS) or a town's Black Legion.
## Returns {"men": [templates], "vehicles": [names]}.
## For the "tank" mission Krakow's armoury hands everyone without a launcher a LAW 80 (one shot,
## used up in the fight). men: battle units.
static func issue_at_weapons(men: Array) -> void:
	for u in men:
		if u["kind"] == "man" and (u["launcher"] == "" or int(u["rockets"]) <= 0):
			u["launcher"] = "LAW 80 ROCKET LAUNCHER"
			u["rockets"] = 1

static func group(name: String, count: int, rng: RandomNumberGenerator) -> Dictionary:
	var men: Array = []
	var vehicles: Array = []
	for i in range(count):
		var t := _man(rng)
		match name:
			"BLACK LEGION PATROL", "BLACK LEGION":
				t["name"] = "BLACK LEGION SOLDIER"
				t["gear"]["weapon"] = ["AK-74", "AKM", "AK-74"][i % 3]
				if i == 1:
					t["gear"]["weapon"] = "PK"
				if i == 2:
					t["gear"]["launcher"] = "RPG-16 ROCKET LAUNCHER"
					t["gear"]["rockets"] = 2
				t["gear"]["armor"] = ["KEVLAR HELMET"] if rng.randf() < 0.6 else []
				t["gear"]["grenades"] = 2
				t["skills"]["RIFLE"] = rng.randi_range(3, 5)
				t["skills"]["HEAVY WEAPONS"] = rng.randi_range(2, 4)
				t["body"] = "EM"
			"MARAUDERS":
				t["name"] = "MARAUDER"
				t["gear"]["weapon"] = ["AKM", "PUMP-ACTION SHOTGUN", "M16A2", "PM MAKAROV", "AK-74"][rng.randi_range(0, 4)]
				t["gear"]["grenades"] = 1 if rng.randf() < 0.3 else 0
				t["skills"]["RIFLE"] = rng.randi_range(2, 4)
			"STRAGGLERS":
				t["name"] = "STRAGGLER"
				t["gear"]["weapon"] = "AK-74"
				t["gear"]["mags"] = 1
				t["gear"]["armor"] = ["KEVLAR VEST"]
				t["skills"]["RIFLE"] = rng.randi_range(3, 5)
				t["body"] = "EM"
			"HUNTERS":
				t["name"] = "HUNTER"
				t["gear"]["weapon"] = ["M40", "PUMP-ACTION SHOTGUN"][i % 2]
				t["skills"]["RIFLE"] = rng.randi_range(3, 6)
			"MERCHANTS":
				t["name"] = "MERCHANT GUARD"
				t["gear"]["weapon"] = ["AKM", "UZI"][i % 2]
			_:
				t["name"] = "REFUGEE"
				t["gear"]["weapon"] = "PM MAKAROV"
				t["skills"]["PISTOL"] = 1
		men.append(t)
	if name == "BLACK LEGION PATROL" and rng.randf() < 0.35:
		vehicles.append("T-72" if rng.randf() < 0.4 else "HMMWV")
	return {"men": men, "vehicles": vehicles}

static func _man(rng: RandomNumberGenerator) -> Dictionary:
	var s := rng.randi_range(4, 7)
	var c := rng.randi_range(4, 7)
	return {"name": "ENEMY", "attrs": {"STRENGTH": s, "CONSTITUTION": c, "AGILITY": rng.randi_range(4, 7)},
		"skills": {"RIFLE": 3, "PISTOL": 2, "HEAVY WEAPONS": 1, "THROWN WEAPON": 2, "MEDICAL": rng.randi_range(0, 2)},
		"hits": {"HEAD": 2 * c, "CHEST": 3 * (s + c), "ABDOMEN": 2 * (s + c), "LEFT ARM": 2 * (s + c), "RIGHT ARM": 2 * (s + c), "LEFT LEG": 2 * (s + c), "RIGHT LEG": 2 * (s + c)},
		"gear": {"weapon": "AKM", "mags": 3, "grenades": 0, "armor": [], "medkits": 0}, "initiative": rng.randi_range(2, 4),
		"head": rng.randi_range(0, 14), "body": "AM"}

static func vehicle_data(name: String) -> Dictionary:
	var d = GameData._json("res://data/vehicles.json")
	for v in d["vehicles"]:
		if v["name"] == name:
			return v
	return {}

static func vehicle_guns() -> Dictionary:
	return GameData._json("res://data/vehicles.json")["guns"]

## A battle on the ground of a place: size in tiles, tree trunks and town walls block, bushes
## conceal, roads speed vehicles. origin: metres of tile (0, 0).
static func make_battle(lm: LocalMap, town: Town, origin: Vector2, size: Vector2i, items: Array, seed_value: int) -> Battle:
	var b := Battle.new(size.x, size.y, items, vehicle_guns(), seed_value)
	b.options["fog"] = true                               # the UFO-style spotting
	b.options["reaction"] = true                          # watchers answer every step
	b.refresh_seen()
	if lm != null:
		for pr in lm.props:
			var t := Vector2i(((pr["pos"] - origin) / Battle.TILE).floor())
			if not b.inside(t):
				continue
			if pr["kind"] == "bush":
				b.bush[b.idx(t)] = 1
			else:
				b.set_blocked(t)
				b.tree[b.idx(t)] = 1
		for y in range(size.y):
			for x in range(size.x):
				var m := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * Battle.TILE
				if lm.on_road(m):
					b.road[y * size.x + x] = 1
				if lm.in_river(m):
					b.set_blocked(Vector2i(x, y))
	if town != null:
		for bd in town.near(origin + Vector2(size) * Battle.TILE * 0.5, 120.0):
			var half: Vector2 = bd["size"] / 2.0
			var c: Vector2 = bd["centre"]
			for y in range(size.y):
				for x in range(size.x):
					var m := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * Battle.TILE
					if absf(m.x - c.x) < half.x and absf(m.y - c.y) < half.y:
						b.set_blocked(Vector2i(x, y))
	return b

## A fight inside a building (data/rooms.json): 1 m tiles over the room's floor, the standing
## furniture in the way (cover; flat rugs are not).
static func make_room_battle(room: Dictionary, items: Array, seed_value: int) -> Battle:
	var size := Vector2i(int(room["size"][0]), int(room["size"][1]))
	var b := Battle.new(size.x, size.y, items, vehicle_guns(), seed_value)
	b.tile = 1.0
	b.options["indoors"] = true
	b.options["fog"] = true
	b.options["reaction"] = true
	b.refresh_seen()
	var door := Vector2(room["door"][0], room["door"][1])
	for f in room["furniture"]:
		if f["flat"]:
			continue
		var c := Vector2(f["centre"][0], f["centre"][1])
		for y in range(size.y):
			for x in range(size.x):
				var m := Vector2(x, y) + Vector2(0.5, 0.5)
				if m.distance_to(c) < float(f["r"]) + 0.15 and m.distance_to(door) > 1.2:
					b.set_blocked(Vector2i(x, y))
					b.furniture[b.idx(Vector2i(x, y))] = 1
	return b

## Indoors: everyone on the free tile nearest his side's spot (rooms are a few metres across).
static func deploy_near(b: Battle, list: Array, at: Vector2i, toward: Vector2, stance := "stand") -> void:
	for u in list:
		var best := at
		var bd := 1e9
		for y in range(b.h):
			for x in range(b.w):
				var t := Vector2i(x, y)
				var d := Vector2(t).distance_to(Vector2(at))
				if d < bd and b.is_free_tile(t, u["id"]):
					bd = d
					best = t
		u["pos"] = best
		u["stance"] = stance
		u["facing"] = Battle._dir_index(Vector2i(toward.normalized().round()))

## Indoors, the ones waiting for the squad: spread over the far part of the room (at least 3 m
## apart, so one grenade does not get them all), each behind furniture if he can be, crouched.
static func deploy_defenders(b: Battle, list: Array, door: Vector2i, rng: RandomNumberGenerator) -> void:
	var taken: Array = []
	for u in list:
		var best := Vector2i(-1, -1)
		var bs := -1e9
		for y in range(b.h):
			for x in range(b.w):
				var t := Vector2i(x, y)
				if not b.is_free_tile(t, u["id"]) or taken.has(t):
					continue
				var s := Vector2(t).distance_to(Vector2(door))              # far from the door
				if b.cover(t, door) == 2:
					s += 4.0                                                  # furniture between
				for o in taken:
					var d := Vector2(t).distance_to(Vector2(o))
					if d < 3.0:
						s -= (3.0 - d) * 4.0
				s += rng.randf() * 1.5
				if s > bs:
					bs = s
					best = t
		if best.x >= 0:
			u["pos"] = best
			taken.append(best)
		u["stance"] = "crouch"
		u["facing"] = Battle._dir_index(Vector2i((Vector2(door - u["pos"])).normalized().round()))

## Where the squad stands when the shooting starts: a line abreast facing the enemy, 3 tiles
## apart, each man on the free tile next to his slot that gives the best cover, crouched.
static func deploy_squad(b: Battle, squad_units: Array, at: Vector2i, toward: Vector2) -> void:
	var fwd := toward.normalized() if toward.length() > 0.01 else Vector2(1, 0)
	var side := Vector2(-fwd.y, fwd.x)
	var n := squad_units.size()
	for i in range(n):
		var u: Dictionary = squad_units[i]
		var slot := Vector2(at) + side * (i - (n - 1) / 2.0) * 3.0 - fwd * (1.0 if i % 2 == 1 else 0.0)
		var best := Vector2i(-1, -1)
		var bs := -1e9
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var t := Vector2i(slot.round()) + Vector2i(dx, dy)
				if not b.inside(t) or not b.is_free_tile(t, u["id"]):
					continue
				var ahead := Vector2i((Vector2(t) + fwd * 1.5).round())
				var s := -Vector2(t).distance_to(slot)
				if b.inside(ahead) and b.is_blocked(ahead):
					s += 4.0                       # a trunk or wall between him and the enemy
				if b.bush[b.idx(t)] == 1:
					s += 1.5
				if s > bs:
					bs = s
					best = t
		if best.x >= 0:
			u["pos"] = best
		u["stance"] = "crouch"
		u["facing"] = Battle._dir_index(Vector2i(fwd.round()))

## Hand placement during deployment: a free tile no more than MAX_DEPLOY tiles from the nearest
## other squad member, and not right next to the enemy. Returns "" or the reason.
static func placement_problem(b: Battle, u: Dictionary, t: Vector2i) -> String:
	if not b.inside(t) or not b.is_free_tile(t, u["id"]):
		return "THAT PLACE IS TAKEN OR BLOCKED."
	var mates := b.units.filter(func(x): return x["team"] == u["team"] and x["id"] != u["id"] and x["kind"] == "man" and b.active(x))
	if not mates.is_empty():
		var nearest := 999
		for m in mates:
			var d: Vector2i = (m["pos"] - t).abs()
			nearest = mini(nearest, maxi(d.x, d.y))
		if nearest > MAX_DEPLOY:
			return "NO MORE THAN %d TILES FROM THE NEAREST SQUAD MEMBER." % MAX_DEPLOY
	var keep := 3 if b.options.get("indoors", false) else ENEMY_KEEP
	for e in b.units:
		if e["team"] != u["team"] and b.active(e):
			var d: Vector2i = (e["pos"] - t).abs()
			if maxi(d.x, d.y) < keep:
				return "TOO CLOSE TO THE ENEMY."
	return ""

## Enemies spread out on the far side, facing the squad.
static func deploy_enemies(b: Battle, list: Array, centre: Vector2i, toward: Vector2, rng: RandomNumberGenerator) -> void:
	var fwd := toward.normalized() if toward.length() > 0.01 else Vector2(-1, 0)
	var side := Vector2(-fwd.y, fwd.x)
	for i in range(list.size()):
		var u: Dictionary = list[i]
		for k in range(30):
			var t := Vector2i((Vector2(centre) + side * rng.randf_range(-6, 6) + fwd * rng.randf_range(-3, 3)).round())
			t = Vector2i(clampi(t.x, 1, b.w - 2), clampi(t.y, 1, b.h - 2))
			if b.is_free_tile(t, u["id"]):
				u["pos"] = t
				break
		u["facing"] = Battle._dir_index(Vector2i(fwd.round()))
