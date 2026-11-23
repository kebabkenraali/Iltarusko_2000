## Combat system for Twilight: 2000 (M5)
## Real-time with pause (Space), queued commands, group selection.
## Uses weapon stats from items.json, hit locations, cover, grenades, tabletop rules as options.
class_name Combat
extends RefCounted

## Combat participant (squad member or enemy)
class Participant:
	var name: String
	var pos: Vector2
	var team: String
	var skills: Dictionary
	var attrs: Dictionary
	var hits: Dictionary
	var wounds: Dictionary = {}
	var stance: String = "standing"
	var weapon: Dictionary = {}
	var ammo: int = 0
	var ap: float = 0
	var suppressed: bool = false
	var pinned: bool = false
	var target: Participant = null
	var orders: Array = []
	var id: int = 0

	func is_alive() -> bool:
		for loc in wounds:
			if wounds[loc] >= hits.get(loc, 999):
				return false
		return true

	func hit_capacity(loc: String) -> int:
		return int(hits.get(loc, 0))

	func wound_at(loc: String) -> int:
		return int(wounds.get(loc, 0))

	func take_damage(loc: String, amount: int) -> void:
		wounds[loc] = wound_at(loc) + amount

	func location_disabled(loc: String) -> bool:
		return wound_at(loc) >= hit_capacity(loc)

	func weapon_skill(cat: String) -> float:
		var skill_map = {
			"pistol": "PISTOL", "revolver": "PISTOL", "automatic pistol": "PISTOL",
			"submachinegun": "SMG", "rifle": "RIFLE", "assault rifle": "RIFLE",
			"battle rifle": "RIFLE", "light machinegun": "HEAVY WEAPONS",
			"machinegun": "HEAVY WEAPONS", "grenade launcher": "HEAVY WEAPONS",
			"shotgun": "RIFLE", "hunting bow": "HUNTING BOW",
		}
		var skill_name = skill_map.get(cat, "RIFLE")
		return float(skills.get(skill_name, 0))

	func get_initiative() -> int:
		return int(skills.get("initiative", 1))


## Combat action types
enum ActionType {
	MOVE, ATTACK, AIMED_ATTACK, BURST, GRENADE, RELOAD,
	STANCE, USE_ITEM, OBSERVE, WAIT
}

## Combat action (queued command)
class Action:
	var type: ActionType
	var actor: Participant
	var target_pos: Vector2 = Vector2.ZERO
	var target_participant: Participant = null
	var weapon: Dictionary = {}
	var param: Variant = null
	var time_issued: float = 0
	var executed: bool = false


## Combat state
var participants: Array[Participant] = []
var player_team: Array[Participant] = []
var enemy_team: Array[Participant] = []
var turn_order: Array[Participant] = []
var current_turn: int = 0
var round_time: float = 0
const ROUND_DURATION := 5.0
var paused: bool = false
var rng := RandomNumberGenerator.new()
var cover_map: Dictionary = {}
var options := {
	"tabletop_rules": true, "aimed_fire": true, "coolness_under_fire": true,
	"knockdown": true, "xp_system": true, "fragmentation": true, "real_time": true,
}
var item_data: Array = []

func _init(seed: int = 0) -> void:
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
## Set item data reference (from GameData)
func set_item_data(items: Array) -> void:
	item_data = items


## Calculate hit chance for an attack
func calculate_hit_chance(attacker: Participant, defender: Participant, action: Action) -> float:
	var weapon = action.weapon
	if weapon.is_empty():
		weapon = attacker.weapon
	if weapon.is_empty():
		return 0.0

	var base_chance: float = 0.3
	var skill = attacker.weapon_skill(weapon.get("category", ""))
	base_chance += skill * 0.06
	base_chance = clampf(base_chance, 0.05, 0.95)

	var dist = attacker.pos.distance_to(defender.pos)
	var range_m = float(weapon.get("range_m", 30))
	if dist > range_m:
		base_chance *= range_m / dist

	match defender.stance:
		"crouching": base_chance *= 0.7
		"prone": base_chance *= 0.4
		"standing": pass

	var cover = get_cover(defender.pos)
	base_chance *= (1.0 - cover * 0.6)

	if action.type == ActionType.AIMED_ATTACK and options["aimed_fire"]:
		base_chance *= 1.3

	if action.type == ActionType.BURST:
		base_chance *= 0.8

	if attacker.suppressed:
		base_chance *= 0.5

	if options["coolness_under_fire"] and defender.team == "player":
		var coolness = attacker.attrs.get("COOLNESS", 5)
		base_chance *= (0.8 + coolness * 0.04)

	return clampf(base_chance, 0.01, 0.99)


## Determine hit location (tabletop uses d10 table)
func determine_hit_location(aimed_loc: String = "") -> String:
	if aimed_loc != "" and options["aimed_fire"]:
		if rng.randf() < 0.6:
			return aimed_loc

	var roll = rng.randi_range(1, 10)
	match roll:
		1: return "HEAD"
		2, 3, 4, 5: return "CHEST"
		6: return "ABDOMEN"
		7: return "LEFT ARM"
		8: return "RIGHT ARM"
		9: return "LEFT LEG"
		10: return "RIGHT LEG"
	return "CHEST"


## Calculate damage after penetration and armor
func calculate_damage(weapon: Dictionary, hit_loc: String, defender: Participant) -> int:
	var base_damage = int(weapon.get("damage", 1))
	var penetration = weapon.get("penetration", [0, 0, 0])
	var armor_value = 0
	var effective_damage = base_damage
	if armor_value > 0:
		var pen = penetration[0]
		if pen >= armor_value:
			effective_damage = base_damage
		else:
			effective_damage = maxi(1, base_damage - (armor_value - pen))

	match hit_loc:
		"HEAD": effective_damage = float(effective_damage) * 2.0
		"CHEST": effective_damage = float(effective_damage) * 1.0
		"ABDOMEN": effective_damage = float(effective_damage) * 1.2
		"LEFT ARM", "RIGHT ARM": effective_damage = float(effective_damage) * 0.7
		"LEFT LEG", "RIGHT LEG": effective_damage = float(effective_damage) * 0.8

	if options["knockdown"] and effective_damage >= defender.hit_capacity(hit_loc) * 0.5:
		defender.pinned = true

	return int(effective_damage)
## Resolve a single attack
func resolve_attack(action: Action) -> Dictionary:
	var attacker = action.actor
	var defender = action.target_participant
	if defender == null or not defender.is_alive():
		return {"hit": false, "damage": 0, "location": "", "killed": false, "actor": attacker.name, "target": "NONE"}

	var chance = calculate_hit_chance(attacker, defender, action)
	var hit = rng.randf() < chance

	var result = {"hit": hit, "damage": 0, "location": "", "killed": false, "suppressed": false, "actor": attacker.name, "target": defender.name}

	if hit:
		var loc = determine_hit_location(action.param if action.type == ActionType.AIMED_ATTACK else "")
		var dmg = calculate_damage(action.weapon, loc, defender)
		defender.take_damage(loc, dmg)
		result.damage = dmg
		result.location = loc
		result.killed = not defender.is_alive()
		result.actor = attacker.name
		result.target = defender.name

		if rng.randf() < 0.3:
			defender.suppressed = true

		if options["xp_system"] and attacker.team == "player":
			var xp_gain = 1
			if action.type == ActionType.AIMED_ATTACK:
				xp_gain = 2

	var rof = int(action.weapon.get("rof", 0))
	var shots = 1
	if action.type == ActionType.BURST and rof > 0:
		shots = mini(rof, attacker.ammo)
	attacker.ammo = maxi(0, attacker.ammo - shots)

	return result


## Grenade attack with fragmentation
func resolve_grenade(action: Action) -> Array[Dictionary]:
	var thrower = action.actor
	var target_pos = action.target_pos
	var grenade = action.weapon
	var results: Array[Dictionary] = []

	var scatter_dist = maxf(1.0, 10.0 - thrower.weapon_skill("GRENADE") * 2.0)
	var angle = rng.randf() * 2 * PI
	var actual_pos = target_pos + Vector2(cos(angle), sin(angle)) * scatter_dist * rng.randf()

	var blast_radius = float(grenade.get("blast_radius", 5.0))
	var frag_radius = float(grenade.get("frag_radius", 15.0))
	var base_damage = int(grenade.get("damage", 10))

	for p in participants:
		if not p.is_alive():
			continue
		var dist = p.pos.distance_to(actual_pos)
		if dist <= blast_radius:
			var dmg = int(base_damage * (1.0 - dist / blast_radius))
			var loc = determine_hit_location()
			p.take_damage(loc, dmg)
			results.append({"actor": thrower.name, "target": p.name, "hit": true, "damage": dmg, "location": loc, "type": "blast"})
		elif options["fragmentation"] and dist <= frag_radius:
			var frag_chance = (1.0 - dist / frag_radius) * 0.4
			if rng.randf() < frag_chance:
				var frag_dmg = rng.randi_range(1, 4)
				var loc = determine_hit_location()
				p.take_damage(loc, frag_dmg)
				results.append({"actor": thrower.name, "target": p.name, "hit": true, "damage": frag_dmg, "location": loc, "type": "fragment"})

	thrower.ammo = maxi(0, thrower.ammo - 1)
	return results


## Cover system - calculate cover value at position (0.0 to 1.0)
func get_cover(pos: Vector2) -> float:
	var key = "%d_%d" % [int(pos.x / 10), int(pos.y / 10)]
	if cover_map.has(key):
		return cover_map[key]
	return 0.0


## Build cover map from town buildings
func build_cover_map(town_buildings: Array) -> void:
	cover_map.clear()
	for b in town_buildings:
		var centre = b["centre"]
		var size = b["size"]
		for dx in range(-int(size.x/2)-5, int(size.x/2)+5):
			for dy in range(-int(size.y/2)-5, int(size.y/2)+5):
				var wp = centre + Vector2(dx, dy)
				var key = "%d_%d" % [int(wp.x / 10), int(wp.y / 10)]
				if not cover_map.has(key):
					cover_map[key] = 0.5
## Initialize turn order by initiative
func init_turn_order() -> void:
	turn_order = participants.duplicate()
	turn_order.sort_custom(func(a, b): return a.get_initiative() > b.get_initiative())
	current_turn = 0


## Get current actor in turn order
func current_actor() -> Participant:
	if turn_order.is_empty():
		return null
	return turn_order[current_turn % turn_order.size()]


## Advance to next turn
func next_turn() -> void:
	current_turn += 1
	if current_turn % turn_order.size() == 0:
		for p in participants:
			p.ap = float(p.get_initiative()) * 2.0
			p.suppressed = false
			p.pinned = false


## Execute queued actions for current actor (real-time mode)
func process_actions(delta: float) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if not options["real_time"]:
		return results

	round_time += delta
	if round_time >= ROUND_DURATION:
		round_time = 0
		next_turn()

	for p in participants:
		if not p.is_alive():
			continue
		while not p.orders.is_empty():
			var action = p.orders[0]
			if action.executed:
				p.orders.pop_front()
				continue

			var ap_cost = get_ap_cost(action)
			if options["real_time"] or p.ap >= ap_cost:
				action.executed = true
				p.ap -= ap_cost

				match action.type:
					ActionType.ATTACK, ActionType.AIMED_ATTACK, ActionType.BURST:
						results.append(resolve_attack(action))
					ActionType.GRENADE:
						results.append_array(resolve_grenade(action))
					ActionType.MOVE:
						pass
					ActionType.RELOAD:
						p.ammo = int(p.weapon.get("magazine", 0))
					ActionType.STANCE:
						p.stance = action.param

				p.orders.pop_front()
			else:
				break

	return results


## AP cost for action types
func get_ap_cost(action: Action) -> float:
	match action.type:
		ActionType.MOVE: return 2.0
		ActionType.ATTACK: return 3.0
		ActionType.AIMED_ATTACK: return 5.0
		ActionType.BURST: return 4.0
		ActionType.GRENADE: return 4.0
		ActionType.RELOAD: return 3.0
		ActionType.STANCE: return 1.0
		ActionType.USE_ITEM: return 2.0
		ActionType.OBSERVE: return 1.0
		ActionType.WAIT: return 0.5
	return 3.0


## Queue action for participant
func queue_action(actor: Participant, action_type: ActionType, target_pos: Vector2 = Vector2.ZERO, target: Participant = null, param: Variant = null) -> void:
	var action := Action.new()
	action.type = action_type
	action.actor = actor
	action.target_pos = target_pos
	action.target_participant = target
	action.weapon = actor.weapon.duplicate()
	action.param = param
	action.time_issued = Time.get_ticks_msec() / 1000.0
	actor.orders.append(action)


## Clear all orders for a participant
func clear_orders(actor: Participant) -> void:
	actor.orders.clear()


## Get all alive player characters
func get_alive_players() -> Array[Participant]:
	var out: Array[Participant] = []
	for p in player_team:
		if p.is_alive():
			out.append(p)
	return out


## Get all alive enemies
func get_alive_enemies() -> Array[Participant]:
	var out: Array[Participant] = []
	for p in enemy_team:
		if p.is_alive():
			out.append(p)
	return out


## Check if combat is over
func is_combat_over() -> bool:
	return get_alive_players().is_empty() or get_alive_enemies().is_empty()


## Get combat result text
func get_result_text() -> String:
	if get_alive_players().is_empty():
		return "SQUAD ELIMINATED"
	if get_alive_enemies().is_empty():
		return "ENEMIES DEFEATED"
	return "COMBAT CONTINUES"