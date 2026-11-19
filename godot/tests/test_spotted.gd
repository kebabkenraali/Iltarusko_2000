## Headless check of the UFO-style spotting (battle.gd fog): enemies stay dark beyond
## the close sight, a muzzle flash reveals the shooter, spotting is sticky, and the
## defensive AI holds its ground while nothing is seen.
## godot --headless --path . --script tests/test_spotted.gd
extends SceneTree

var cr: ChargenRules
var data: GameData

func _init() -> void:
	cr = ChargenRules.new(GameData._json("res://data/careers.json"), GameData._json("res://data/chargen.json"), 13)
	data = GameData.new()
	data.load_all()
	var b := Battle.new(40, 30, data.items, Forces.vehicle_guns(), 4242)
	b.options["fog"] = true
	b.refresh_seen()
	var rec := cr.random_recruit()
	Forces.equip(rec)
	var s := b.add_man("squad", rec, Vector2i(2, 15), 0)
	var g := Forces.group("BLACK LEGION", 1, rng_of(5))
	var e := b.add_man("enemy", g["men"][0], Vector2i(35, 15))
	# 33 tiles (~66 m) apart: over the close sight, walls absent -> out of sight
	b.refresh_seen()
	assert(not b.is_seen(s, "enemy"), "the enemy does not see the squad at 66 m")
	assert(not b.is_seen(e, "squad"), "the squad does not see the enemy at 66 m")
	# the enemy holds its ground while nothing is seen (no action this turn)
	assert(not b.ai_step(e), "nothing in sight: the defender waits")
	# within the sight with a clear line: spotted, and sticky
	e["pos"] = Vector2i(18, 15)
	b.refresh_seen()
	assert(b.is_seen(e, "squad"), "spotted at 36 m with a clear line")
	e["pos"] = Vector2i(35, 15)
	b.refresh_seen()
	assert(b.is_seen(e, "squad"), "sticky: once spotted, remembered")
	# a shot from the dark reveals the shooter to both sides
	e["pos"] = Vector2i(35, 15)
	b.fire(e, s, "snap")                                  # 66 m: out of squad sight, muzzle reveals
	assert(b.is_seen(e, "squad"), "the muzzle flash reveals the shooter")
	# and a blind shot is refused: the squad cannot fire at an unseen target
	e["seen_by"]["squad"] = false                         # forget again: beyond sight, no flash
	b.refresh_seen()
	assert(not b.fire(s, e, "snap"), "no firing at an unseen target (spotted gate)")
	print("SPOTTED TEST PASS")
	quit(0)

func rng_of(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r
