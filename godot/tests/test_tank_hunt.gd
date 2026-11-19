## Headless check of the fogged armour duel: a squad tank and an enemy tank start far
## apart (beyond the 20-tile sight). The enemy tank must drive toward the squad's engine
## noise (it would otherwise sit invisible in the fog for the whole battle), and as it
## closes in it must be spotted and drawn by the squad's side.
## godot --headless --path . --script tests/test_tank_hunt.gd
extends SceneTree

var cr: ChargenRules
var data: GameData

func _init() -> void:
	cr = ChargenRules.new(GameData._json("res://data/careers.json"), GameData._json("res://data/chargen.json"), 13)
	data = GameData.new()
	data.load_all()
	var b := Battle.new(44, 30, data.items, Forces.vehicle_guns(), 4242)
	b.options["fog"] = true
	b.refresh_seen()
	# the squad's tank on the west edge, the enemy tank on the east edge: 27 tiles apart
	var rec := cr.random_recruit()
	Forces.equip(rec)
	var m := b.add_man("squad", rec, Vector2i(3, 15), 0)
	var sv := b.add_vehicle("squad", Forces.vehicle_data("M1A1"), Vector2i(3, 15), 2)
	b.board(m, sv)
	var ev := b.add_vehicle("enemy", Forces.vehicle_data("T-72"), Vector2i(40, 15), 6)
	b.seek = Vector2i(40, 15)
	b.refresh_seen()
	assert(not b.is_seen(ev, "squad"), "the enemy tank starts unseen in the fog")
	# the enemy tank hunts the squad's engine noise: it closes in turn after turn
	var steps := 0
	var rounds := 0
	while not b.is_seen(ev, "squad") and rounds < 60:
		if not b.ai_step(ev):
			b.end_turn()                       # a new round: the tank drives on
			rounds += 1
		steps += 1
		if steps > 400:
			break
	assert(rounds < 60, "the enemy tank closed the distance")
	assert(b.is_seen(ev, "squad"), "the advancing tank is spotted (and drawn)")
	var start := Vector2i(40, 15)
	assert(Vector2(ev["pos"]).distance_to(Vector2(start)) > 2.0, "the tank actually moved")
	print("TANK HUNT TEST PASS (rounds=", rounds, ", steps=", steps, ")")
	quit(0)
