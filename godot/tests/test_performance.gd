## Headless performance test: auto_play must resolve 200 battle rounds in under 1 second.
## godot --headless --path . --script tests/test_performance.gd
extends SceneTree

var cr: ChargenRules
var data: GameData

func _init() -> void:
	cr = ChargenRules.new(GameData._json("res://data/careers.json"), GameData._json("res://data/chargen.json"), 13)
	data = GameData.new()
	data.load_all()
	# a full-strength town battle: squad + 2 enemies on each side
	var b := Battle.new(40, 30, data.items, Forces.vehicle_guns(), 4242)
	b.options["fog"] = true
	b.options["reaction"] = true
	b.refresh_seen()
	for i in range(4):
		var rec := cr.random_recruit()
		Forces.equip(rec)
		b.add_man("squad", rec, Vector2i(5, 15 + i * 2), i)
	for i in range(6):
		var g := Forces.group("BLACK LEGION", 1, RandomNumberGenerator.new())
		var e := b.add_man("enemy", g["men"][0], Vector2i(30, 15 + i * 2))
	var t0: float = Time.get_ticks_msec() / 1000.0
	b.auto_play(200)
	var t1: float = Time.get_ticks_msec() / 1000.0
	var elapsed := t1 - t0
	print("PERFORMANCE: 200 rounds in %.3f s" % elapsed)
	assert(elapsed < 1.0, "200 rounds must take < 1 s, took %.3f" % elapsed)
	print("PERFORMANCE TEST PASS")
	quit(0)
