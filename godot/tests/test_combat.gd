## Headless check of the legacy combat module (M5): godot --headless --path . --script tests/test_combat.gd
## The game fights through battle.gd; this covers combat.gd's pure functions - hit chance, hit
## location, damage, cover, turn order and the queued-action loop.
extends SceneTree

func _init() -> void:
	var data := GameData.new()
	data.load_all()
	var fails := 0
	var CombatClass = preload("res://scripts/combat.gd")
	var combat = CombatClass.new(4242)
	combat.set_item_data(data.items)

	var p = CombatClass.Participant.new()
	p.name = "TEST RECRUIT"
	p.team = "squad"
	p.pos = Vector2(159500, 257500)
	p.skills = {"RIFLE": 4, "PISTOL": 3, "SMG": 2, "HEAVY WEAPONS": 1, "GRENADE": 2, "MEDICAL": 2, "initiative": 4}
	p.attrs = {"STRENGTH": 6, "CONSTITUTION": 6, "AGILITY": 6, "INTELLIGENCE": 6, "EDUCATION": 6, "CHARISMA": 6}
	p.hits = {"HEAD": 12, "CHEST": 36, "ABDOMEN": 24, "LEFT ARM": 24, "RIGHT ARM": 24, "LEFT LEG": 24, "RIGHT LEG": 24}
	p.weapon = data.items.filter(func(i): return i["name"] == "M16A2")[0]
	p.ammo = 30
	if not p.is_alive():
		fails += 1
		print("FAIL: participant not alive after creation")

	var e = CombatClass.Participant.new()
	e.name = "TEST ENEMY"
	e.team = "enemy"
	e.pos = Vector2(159510, 257510)
	e.skills = {"RIFLE": 3, "initiative": 3}
	e.attrs = {"CONSTITUTION": 5}
	e.hits = {"HEAD": 12, "CHEST": 36, "ABDOMEN": 24, "LEFT ARM": 24, "RIGHT ARM": 24, "LEFT LEG": 24, "RIGHT LEG": 24}
	e.weapon = p.weapon.duplicate()
	e.ammo = 30
	combat.participants.append(p)
	combat.participants.append(e)
	combat.player_team.append(p)
	combat.enemy_team.append(e)

	# Hit chance calculation
	combat.init_turn_order()
	var action = CombatClass.Action.new()
	action.type = CombatClass.ActionType.ATTACK
	action.actor = p
	action.target_participant = e
	action.weapon = p.weapon
	var chance = combat.calculate_hit_chance(p, e, action)
	if chance < 0.01 or chance > 0.99:
		fails += 1
		print("FAIL: hit chance out of range: ", chance)

	# Hit location determination
	var loc = combat.determine_hit_location("")
	if loc not in ["HEAD", "CHEST", "ABDOMEN", "LEFT ARM", "RIGHT ARM", "LEFT LEG", "RIGHT LEG"]:
		fails += 1
		print("FAIL: invalid hit location: ", loc)

	# Damage calculation, and the head multiplier
	var weapon = {"damage": 4, "penetration": [2, 3, 0], "category": "rifle", "range_m": 65}
	var dmg = combat.calculate_damage(weapon, "CHEST", e)
	if dmg < 1:
		fails += 1
		print("FAIL: damage too low: ", dmg)
	var head_dmg = combat.calculate_damage(weapon, "HEAD", e)
	if head_dmg <= dmg:
		fails += 1
		print("FAIL: head damage not higher: ", head_dmg, " vs ", dmg)

	# Cover system
	combat.build_cover_map([{"centre": Vector2(159505, 257505), "size": Vector2(20, 20)}])
	var cover = combat.get_cover(Vector2(159505, 257505))
	if cover < 0.0 or cover > 1.0:
		fails += 1
		print("FAIL: cover out of range: ", cover)

	# Queued actions run in real time
	combat.queue_action(p, CombatClass.ActionType.ATTACK, Vector2.ZERO, e)
	var results = combat.process_actions(0.1)
	if results.is_empty():
		fails += 1
		print("FAIL: combat process returned no results")
	if combat.is_combat_over():
		fails += 1
		print("FAIL: combat over immediately")

	print("COMBAT TEST ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)