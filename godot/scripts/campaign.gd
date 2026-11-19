## The mission campaign run by Exor 1 (data/missions.json, built from the original texts).
## One mission at a time: the radio briefing names the cities, the city leaders give the job
## (with a reward), remind while it is not done and thank at the end. Every few missions Exor's
## story messages move the war along. Pure logic: the field view asks it what is where and tells
## it what the squad did.
class_name Campaign
extends RefCounted

var data: Dictionary                 # missions.json
var cities: Array
var items: Array
var rng := RandomNumberGenerator.new()
var mission: Dictionary = {}         # current mission (empty = none)
var done_count := 0
var story_index := 0                 # next story message
var pending_story := ""              # shown before the next briefing
var icon_index := 0                  # next ICON news message (after story is exhausted)
var final_mission := false           # true when the story is exhausted: the next mission is the assault on Krakow
var victory := false                 # true when the squad won the final battle
var stores: Array = []               # Krakow's stores (rewards, crates brought home)
var funds := 0                       # Krakow's cash box (the squad's pay) - M9: computer & motor pool
const PAY_PER_MISSION := 2000        # MK the HQ pays for each finished mission (remake's number)
var food := 0                        # M9 economy round 2: field rations in the squad's larder
const RATION_PRICE := 10             # one field ration costs 10 MK at the HQ store
const RATION_PER_MEAL := 1           # one ration feeds one soldier for one 8-hour sleep
var carried: Array = []              # items the squad carries for the mission
var motor_pool: Array = []           # vehicles brought to Krakow (vehicles.json names)
var friends: Array = []              # towns the squad has finished a mission for (they refuel it)
var lost_cities: Array = []          # towns that fell to Czarny (defend mission failed)
var clock: Callable = func(): return 0.0      # game minutes (main sets it to the world clock)
var is_story: Callable = func(): return false # story mode: the sick hold out longer
var squad_size: Callable = func(): return 4    # how many the squad has now (M9: garrisons scale with it)
var squad_vehicle: Callable = func(): return ""  # M9 economy: vehicle the squad rides (set by main.gd)

## M9 balance formulas (test_balance.gd measures with the same numbers):
## the Black Legion's garrison turns out one or two stronger than the raiding squad;
## inside a building there is room for fewer (and the close quarters favour the defenders,
## so the squad keeps its edge): two fewer, at least two. The tank comes with three escorts.
const ROOM_MIN := 2
const ROOM_MAX := 5
const TANK_ESCORTS := 3

static func field_count(squad: int, rng: RandomNumberGenerator) -> int:
	return squad + rng.randi_range(1, 2)

static func room_count(squad: int) -> int:
	return clampi(squad - 2, ROOM_MIN, ROOM_MAX)

## M9 economy round 2: food. One ration feeds one soldier for one 8-hour sleep.
## feed() is called whenever the squad sleeps (world map R, tactical NECESSITY).
## Returns {"fed": int, "hungry": int} - how many ate and how many went hungry.
## The hungry soldiers are marked on the squad (recruit "hungry" flag) so battle
## can apply the initiative/aim penalty.
func feed(squad_size: int) -> Dictionary:
	var fed := mini(squad_size, int(food))
	food = food - fed
	var hungry := squad_size - fed
	return {"fed": fed, "hungry": hungry}

## Add rations (from fish/forage/hunt scrounging or HQ purchase).
func add_food(n: int) -> void:
	food = int(food) + maxi(0, n)

## Buy rations at the HQ store. Returns how many were bought (0 if unaffordable).
func buy_food(n: int) -> int:
	var cost := n * RATION_PRICE
	if int(funds) < cost:
		return 0
	funds = int(funds) - cost
	food = int(food) + n
	return n


# The wounded and the sick do not wait (the original's "TOO MANY OF THE CITIZENS OF THIS
# COMMUNITY HAVE DIED"): after a grace time (the march there plus some hours) one untreated
# patient dies every few hours. When more than half have died, the leader gives no reward.
# The 1991 timings are not known; these are the remake's. Story mode: half again the grace,
# twice the interval.
const SICK_TYPES := ["wounded", "epidemic"]
# the hostage-takers and the assassins hide in a building of their town: the fight is indoors
const HIDEOUT_TYPES := ["hostage", "assassins"]
const GRACE_HOURS := 8.0              # on top of the march from Krakow (20 min a km)
const DEATH_EVERY := {"wounded": 6.0, "epidemic": 8.0}   # hours
var log: Array = []

const PLAYABLE := ["supplies", "spy", "hostage", "assassins", "wounded", "epidemic", "exile", "dump", "defend", "liberate", "tank", "vehicle"]
const TANKS := ["T-72", "T-72", "T-80"]   # the Black Legion's tank forces
const DOWNED := {"T-90 TANK": "T-90", "A HUMVEE": "HMMWV"}   # the briefing's vehicle -> vehicles.json
const HOME := "KRAKOW"
const CZARNY := "CHECINY"            # the Baron's fortress: never a mission city

func _init(missions: Dictionary, city_list: Array, item_list: Array, seed_value := 0) -> void:
	data = missions
	cities = city_list
	items = item_list
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

func city(name: String) -> Dictionary:
	for c in cities:
		if c["name"] == name:
			return c
	return {}

func _dist(a: String, b: String) -> float:
	var ca := city(a)
	var cb := city(b)
	return Vector2(ca["a"], ca["b"]).distance_to(Vector2(cb["a"], cb["b"]))

## Cities that can be part of a mission, nearest to `from` first.
func _near(from: String, exclude: Array, limit: int) -> Array:
	var out: Array = []
	for c in cities:
		var n: String = c["name"]
		if n == HOME or n == CZARNY or exclude.has(n) or int(c["size"]) > 4:
			continue
		out.append(n)
	out.sort_custom(func(x, y): return _dist(from, x) < _dist(from, y))
	return out.slice(0, limit)

func _pick(arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)]

## Reward a leader promises: something useful from the item list (weapons, medicine, kit).
func _reward() -> String:
	var good: Array = []
	for it in items:
		var c: String = it.get("category", "")
		if c in ["assault rifle", "rifle", "light machinegun", "machinegun", "grenade launcher", "medical", "equipment", "submachinegun", "automatic pistol"] or String(it["name"]).ends_with("KIT"):
			good.append(it["name"])
	if good.is_empty():
		return "SUPPLIES"
	return _pick(good)

## Start the next mission (the first ones close to Krakow, later ones further out).
## When the story and the ICON news are exhausted, the next mission is the final one:
## the Black Legion's assault on Krakow ("ATTACK ON KRAKOW").
func new_mission(force_type := "") -> Dictionary:
	if not final_mission and story_index >= data["story"].size() and icon_index >= data.get("icon_news", []).size():
		final_mission = true
		pending_story = data["endings"]["jammed"]
	if final_mission:
		force_type = "defend"
	var t: String = force_type if force_type != "" else _pick(PLAYABLE)
	var reach := 6 + done_count * 3
	var target: String
	if final_mission:
		target = HOME
	else:
		target = _pick(_near(HOME, [], reach))
	var m := {"type": t, "target": target, "step": 0, "nag": 0, "brief": rng.randi_range(0, data["types"][t]["brief"].size() - 1),
		"intro": rng.randi_range(0, data["types"][t]["intro"].size() - 1), "talked": {},
		"goods": _pick(data["lists"]["goods"]), "disease": _pick(data["lists"]["diseases"]),
		"area": _pick(data["lists"]["areas"]), "vehicle": _pick(data["lists"]["vehicles"]), "reward": _reward()}
	m["source"] = _pick(_near(target, [target], 4))
	m["home"] = _pick(_near(target, [target, m["source"]], 4))
	m["hostage"] = _pick(_near(target, [target, m["source"], m["home"]], 4))
	if t == "exile":
		# the exiles sit in "source"; their occupied home city is "home"
		pass
	m["tank"] = _pick(TANKS)
	m["enemies"] = {}
	m["patients"] = 0
	m["spy"] = -1
	if t in SICK_TYPES:                   # the sick are there from the start, and the clock runs
		m["patients"] = rng.randi_range(3, 5)
		m["sick_total"] = m["patients"]
		m["died"] = 0
		m["started"] = float(clock.call())
	mission = m
	log.append("New mission: %s (%s)" % [t, target])
	_prepare_step()
	return m

## The game-state a step needs: enemies in the city to clear, patients to treat, the spy.
func _prepare_step() -> void:
	var st := step()
	if st.begins_with("clear:"):
		var c := place(st)
		if not mission["enemies"].has(c):
			if mission["type"] == "tank":
				mission["enemies"][c] = 1
			elif mission["type"] in HIDEOUT_TYPES:
				mission["enemies"][c] = room_count(int(squad_size.call()))    # the fight is in a room
			else:
				mission["enemies"][c] = field_count(int(squad_size.call()), rng)
		if mission["type"] in HIDEOUT_TYPES and not mission.has("hideout"):
			mission["hideout"] = rng.randi_range(0, 2)      # which of the town's buildings
	elif st.begins_with("repair:"):
		var c := place(st)
		if not mission["enemies"].has(c):
			mission["enemies"][c] = field_count(int(squad_size.call()), rng)   # "I'M SURE YOU WON'T BE THE ONLY ONE LOOKING FOR IT"
	elif st.begins_with("treat:"):
		if mission["patients"] == 0 and not mission.has("sick_total"):
			mission["patients"] = rng.randi_range(3, 5)
	elif st.begins_with("spy:"):
		if mission["spy"] < 0:
			mission["spy"] = rng.randi_range(0, 4)        # which of the five suspects

func steps() -> Array:
	return data["types"][mission["type"]]["steps"] if not mission.is_empty() else []

func step() -> String:
	var s := steps()
	return s[mission["step"]] if not mission.is_empty() and mission["step"] < s.size() else ""

## City a step happens in ("talk:source" -> the source city's name).
func place(st: String) -> String:
	var w: String = st.split(":")[1]
	if w == "KRAKOW":
		return HOME
	return mission.get(w, w)

func objective_city() -> String:
	return place(step()) if step() != "" else ""

## Hours before the first untreated patient dies, and between deaths after that.
func sick_times() -> Array:
	var km: float = _city_pos(HOME).distance_to(_city_pos(mission["target"])) / 1000.0
	var grace := km * 20.0 / 60.0 + GRACE_HOURS
	var every: float = DEATH_EVERY.get(mission["type"], 6.0)
	if is_story.call():
		grace *= 1.5
		every *= 2.0
	return [grace, every]

func _city_pos(n: String) -> Vector2:
	for c in cities:
		if c["name"] == n:
			return Vector2(c["a"], c["b"])
	return Vector2.ZERO

## The enemies of this town's step hide indoors (hostage-takers, assassins).
func hideout_in(c: String) -> bool:
	return not mission.is_empty() and mission["type"] in HIDEOUT_TYPES and step().begins_with("clear:") \
		and place(step()) == c and enemies_in(c) > 0

## Building number i (of the town's buildings) is their hideout.
func is_hideout(c: String, i: int) -> bool:
	return hideout_in(c) and i == int(mission.get("hideout", -1))

## Untreated patients die as time goes by. Returns how many died now.
func tick() -> int:
	if mission.is_empty() or not mission.has("sick_total") or int(mission["patients"]) <= 0:
		return 0
	var t := sick_times()
	var hours: float = (float(clock.call()) - float(mission["started"])) / 60.0 - float(t[0])
	if hours < 0.0:
		return 0
	var due := int(hours / float(t[1])) + 1
	var n := mini(due - int(mission["died"]), int(mission["patients"]))
	if n <= 0:
		return 0
	mission["patients"] = int(mission["patients"]) - n
	mission["died"] = int(mission["died"]) + n
	if int(mission["patients"]) == 0 and step().begins_with("treat:"):
		_advance()                          # no one left to treat: back to the leader
	return n

## More than half of the patients died: the leader will not reward the squad.
func too_many_died() -> bool:
	return mission.has("sick_total") and int(mission["died"]) * 2 > int(mission["sick_total"])

func objective_text() -> String:
	tick()
	var st := step()
	if st == "":
		return "No mission. Report to the radio at Krakow HQ."
	var c := place(st)
	match st.split(":")[0]:
		"talk":
			return "Talk to the leader of %s (centre of town)." % c
		"clear":
			if mission["type"] in HIDEOUT_TYPES:
				return "Find the %s hiding in a building of %s and eliminate them (%d left)." % [
					"hostage-takers" if mission["type"] == "hostage" else "assassins", c, int(mission["enemies"].get(c, 0))]
			if mission["type"] == "tank":
				return "Destroy the Black Legion %s in %s." % [mission["tank"], c]
			return "Eliminate the Black Legion in %s (%d left)." % [c, int(mission["enemies"].get(c, 0))]
		"repair":
			var n := int(mission["enemies"].get(c, 0))
			return "Find the downed %s outside %s and repair it%s." % [vehicle_model(), c, (" (%d scavengers around it)" % n) if n > 0 else ""]
		"treat":
			var dead := int(mission.get("died", 0))
			return "Treat the %s in %s (%d left%s)." % ["sick" if mission["type"] == "epidemic" else "wounded", c, int(mission["patients"]),
				(", %d died" % dead) if dead > 0 else ""]
		"spy":
			return "Find the spy in %s: interrogate the townspeople." % c
		"search":
			return "Find the %s in one of the buildings of %s." % [data["types"][mission["type"]]["item"], c]
		"reach":
			return "Bring the supplies back to %s." % c
	return st

func _advance() -> void:
	mission["step"] += 1
	mission["nag"] = 0
	_prepare_step()

# ---------------- texts ----------------
func _fill(parts: Array, leader: String, extra := "") -> String:
	var out := ""
	for p in parts:
		var s: String = p
		if s.begins_with("{") and s.ends_with("}"):
			var key := s.substr(1, s.length() - 2)
			s = leader if key == "leader" else String(mission.get(key, ""))
			if out != "" and not out.ends_with(" "):
				out += " "
			out += s
			continue
		if out != "" and not out.ends_with(" ") and s != "" and (s[0].is_valid_identifier() or s[0].is_valid_int()):
			out += " "
		out += s
	if extra != "" and out.contains("%s"):
		out = out.replace("%s", extra)
	return out.strip_edges()

## Radio message at the office: a pending story message, then the current briefing.
func briefing(leader: String) -> String:
	if mission.is_empty():
		new_mission()
	var t: Dictionary = data["types"][mission["type"]]
	var text := _fill(t["brief"][int(mission["brief"])], leader)
	if pending_story != "":
		text = pending_story + "\n\n" + text
		pending_story = ""
	return text

func _pct() -> String:
	var t: Dictionary = data["types"][mission["type"]]
	return String(mission.get(String(t.get("pct", "{target}")).trim_prefix("{").trim_suffix("}"), mission["target"]))

func _intro(leader: String) -> String:
	var t: Dictionary = data["types"][mission["type"]]
	var s := _fill(t["intro"][int(mission["intro"])], leader, _pct())
	if s.contains("{reward}") or t["intro"][int(mission["intro"])].has("{reward}"):
		pass
	if not s.ends_with("."):
		s += "."
	return s

func _nag(leader: String) -> String:
	var t: Dictionary = data["types"][mission["type"]]
	if t.get("nag", []).is_empty():
		return data["lines"]["leader_hello"]
	var n: Array = t["nag"]
	var s := _fill(n[int(mission["nag"]) % n.size()], leader, _pct())
	mission["nag"] += 1
	return s

# ---------------- what the squad does ----------------
## Talking to the leader of a city. Returns the lines to show.
## The town in trouble (for exiles: where they wait) gives the job on the first visit and
## reminders after that; a "talk" step in this town moves the mission on.
func talk_leader(c: String, leader: String) -> Array:
	tick()
	if mission.is_empty():
		return [data["lines"]["leader_hello"], data["lines"]["slow"]]
	var st := step()
	var t: Dictionary = data["types"][mission["type"]]
	var asker: String = mission["source"] if mission["type"] == "exile" else mission["target"]
	if st.begins_with("talk:") and place(st) == c:
		if mission["step"] == steps().size() - 1:
			return _complete(leader)
		_advance()
		var lines: Array = []
		if c == asker:
			mission["talked"][c] = true
			lines.append(_intro(leader))
		if mission["type"] == "supplies" and c == mission["source"]:
			carried.append(t["item"])
			lines.append("THE LEADER HANDS OVER THE %s FOR %s." % [t["item"], mission["target"]])
		return lines
	if c == asker:
		if not mission["talked"].has(c):
			mission["talked"][c] = true
			return [_intro(leader)]
		return [_nag(leader)]
	return [data["lines"]["leader_hello"]]

func _complete(leader: String) -> Array:
	if too_many_died():
		return _failed()
	if final_mission:
		victory = true
		var lines: Array = [data["endings"]["victory"][0]]
		lines.append(data["endings"]["victory"][1])
		mission = {}
		log.append("Victory: the Black Legion defeated at Krakow")
		return lines
	var t: Dictionary = data["types"][mission["type"]]
	var lines: Array = [_fill(t["done"][0], leader, _pct())]
	if t.has("item") and carried.has(t["item"]):
		carried.erase(t["item"])
	stores.append(mission["reward"])
	lines.append("REWARD: %s (sent to the stores at Krakow)." % mission["reward"])
	if mission.has("reward2"):
		stores.append(mission["reward2"])
		lines.append("AS AGREED, ALSO: %s." % mission["reward2"])
	lines.append(data["lines"]["loyalty"] + ".")
	if not friends.has(mission.get("target", "")):
		friends.append(mission.get("target", ""))
	done_count += 1
	funds += PAY_PER_MISSION
	lines.append("HQ PAYS THE SQUAD %d MK FOR THE JOB." % PAY_PER_MISSION)
	log.append("Mission complete: %s" % mission["type"])
	if done_count % 2 == 1 and story_index < data["story"].size():
		pending_story = data["story"][story_index]
		story_index += 1
	elif done_count % 2 == 1 and icon_index < data.get("icon_news", []).size():
		pending_story = data["icon_news"][icon_index]
		icon_index += 1
	mission = {}
	return lines

## The mission ends without a reward (too many of the sick died before the squad came).
func _failed() -> Array:
	if final_mission:
		# the final assault was lost: the squad is captured/killed
		final_mission = false
		log.append("Defeat: the Black Legion took Krakow")
		mission = {}
		return [data["endings"]["city_lost"]]
	var lines: Array = [data["lines"]["too_many_died"]]
	lines.append("%d OF %d DIED BEFORE THEY COULD BE TREATED." % [int(mission["died"]), int(mission["sick_total"])])
	log.append("Mission failed: %s" % mission["type"])
	mission = {}
	return lines

## The downed vehicle of a "vehicle" mission, as a vehicles.json name.
func vehicle_model() -> String:
	return DOWNED.get(mission.get("vehicle", ""), "HMMWV")

## The downed vehicle repaired: it goes to the motor pool at Krakow and the mission is done.
func repaired(leader: String) -> Array:
	var v := vehicle_model()
	motor_pool.append(v)
	var lines := _complete(leader)
	lines[0] = "THE %s %s" % [v, lines[0]]
	return lines

## Purchase a vehicle for the motor pool at Krakow.
# Returns true if purchased, false if not enough money or invalid vehicle.
func purchase_vehicle(vehicle_name: String, funds: int) -> bool:
	var VehicleClass = preload("res://scripts/vehicle.gd")
	var vehicle = VehicleClass.new()
	var vdata = vehicle.get_vehicle(vehicle_name)
	if vdata.is_empty():
		return false
	var price = int(vdata.get("price", 0))
	if funds < price:
		return false
	motor_pool.append(vehicle_name)
	return true

## Get the price of a vehicle.
func get_vehicle_price(vehicle_name: String) -> int:
	var VehicleClass = preload("res://scripts/vehicle.gd")
	var vehicle = VehicleClass.new()
	var vdata = vehicle.get_vehicle(vehicle_name)
	if vdata.is_empty():
		return 0
	return int(vdata.get("price", 0))

## List available vehicles for purchase.
func get_purchasable_vehicles() -> Array:
	var VehicleClass = preload("res://scripts/vehicle.gd")
	var vehicle = VehicleClass.new()
	var result: Array = []
	for v in vehicle.get_all_vehicles():
		result.append({
			"name": v["name"],
			"price": int(v.get("price", 0)),
			"fuel_type": v.get("fuel_type", "D"),
			"kind": v.get("kind", "wheeled")
		})
	return result

## Field repair: repair a damaged vehicle instance.
# Requires a crew member with COMBAT ENGINEER skill.
# Repairs engine and hull damage up to a limit based on skill.
func field_repair(vehicle_inst: Dictionary, engineer_skill: int) -> Dictionary:
	var repaired = vehicle_inst.duplicate()
	var damage = repaired.get("damage", {})
	var max_repair = 20 + engineer_skill * 5  # percent per repair attempt
	for loc in damage:
		var dmg = damage[loc]
		if dmg > 0:
			var repair_amt = min(max_repair, dmg)
			damage[loc] = dmg - repair_amt
			if damage[loc] <= 0:
				damage.erase(loc)
	repaired["damage"] = damage
	# Engine repair restores engine_running if engine damage < 100
	if damage.get("engine", 0) < 100:
		repaired["engine_running"] = true
	return repaired

## Check if a vehicle can be refueled with a specific fuel type.
func can_refuel_with(vehicle_name: String, fuel_type: String) -> bool:
	var VehicleClass = preload("res://scripts/vehicle.gd")
	var vehicle = VehicleClass.new()
	var vdata = vehicle.get_vehicle(vehicle_name)
	if vdata.is_empty():
		return false
	var vtype = vdata.get("fuel_type", "D")
	if vtype == "M":  # multi-fuel
		return true
	return vtype == fuel_type

## An enemy in city c is down.
func enemy_down(c: String) -> void:
	if mission.is_empty() or not mission["enemies"].has(c):
		return
	mission["enemies"][c] = maxi(0, int(mission["enemies"][c]) - 1)
	if mission["enemies"][c] == 0 and step().begins_with("clear:") and place(step()) == c:
		_advance()

func enemies_in(c: String) -> int:
	if mission.is_empty():
		return 0
	return int(mission["enemies"].get(c, 0))

## A patient treated (wounded / epidemic). Returns true when the step is finished.
func patient_treated() -> bool:
	tick()
	if int(mission.get("patients", 0)) <= 0:
		return false                        # died while the squad was on its way to him
	mission["patients"] = maxi(0, int(mission["patients"]) - 1)
	if mission["patients"] == 0 and step().begins_with("treat:"):
		_advance()
		return true
	return false

func is_spy(suspect: int) -> bool:
	return not mission.is_empty() and step().begins_with("spy:") and suspect == int(mission["spy"])

func spy_dead() -> void:
	if step().begins_with("spy:"):
		_advance()

## Squad went into a building of city c; returns a line if the crate was found there.
func searched(c: String, building_index: int) -> String:
	if not step().begins_with("search:") or place(step()) != c:
		return ""
	if not mission.has("crate_at"):
		mission["crate_at"] = rng.randi_range(0, 2)
	if building_index % 3 == int(mission["crate_at"]):
		var item: String = data["types"][mission["type"]]["item"]
		carried.append(item)
		_advance()
		return "YOU FIND THE %s. %s" % [item, data["lines"]["crate_loaded"]]
	return ""

## The squad arrived in a city (for "reach" steps).
func arrived(c: String, leader: String) -> Array:
	if step().begins_with("reach:") and place(step()) == c:
		# M9 economy round 2: dump mission requires a 2 1/2 TON TRUCK to load the crates.
		if mission.get("type") == "dump":
			var veh := String(squad_vehicle.call())
			if veh != "2 1/2 TON TRUCK":
				return [data["lines"]["need_truck"]]
		return _complete(leader)
	return []

# ---------------- save ----------------
func to_dict() -> Dictionary:
	return {"mission": mission, "done": done_count, "story": story_index, "pending": pending_story,
		"stores": stores, "carried": carried, "motor_pool": motor_pool, "friends": friends, "funds": funds,
		"food": int(food), "icon_index": int(icon_index), "final_mission": final_mission, "victory": victory,
		"lost_cities": lost_cities}

func from_dict(d: Dictionary) -> void:
	mission = d.get("mission", {})
	done_count = int(d.get("done", 0))
	story_index = int(d.get("story", 0))
	pending_story = d.get("pending", "")
	stores = d.get("stores", [])
	carried = d.get("carried", [])
	motor_pool = d.get("motor_pool", [])
	friends = d.get("friends", [])
	funds = int(d.get("funds", 0))
	food = int(d.get("food", 0))
	icon_index = int(d.get("icon_index", 0))
	final_mission = bool(d.get("final_mission", false))
	victory = bool(d.get("victory", false))
	lost_cities = d.get("lost_cities", [])
