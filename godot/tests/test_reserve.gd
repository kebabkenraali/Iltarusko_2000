## Headless check of the reserve-for-snapshot mechanic (OpenXCom's reserved time units,
## battle.gd set_reserve + _flood clamp): while reserved, moves stop leaving AP for one
## snap shot; firing and the reserve toggle itself ignore the limit.
## godot --headless --path . --script tests/test_reserve.gd
extends SceneTree

var data: GameData

func _init() -> void:
	var cr := ChargenRules.new(GameData._json("res://data/careers.json"), GameData._json("res://data/chargen.json"), 11)
	data = GameData.new()
	data.load_all()
	var b := Battle.new(40, 30, data.items, Forces.vehicle_guns(), 77)
	b.options = {}
	var rec := cr.random_recruit()
	Forces.equip(rec)
	var u := b.add_man("squad", rec, Vector2i(2, 15), 0)
	# a straight open road to the east: tile (10,15) is 8 steps away
	var reach := b.reachable(u)
	assert(reach.has(Vector2i(11, 15)), "9 steps away is reachable with 10 AP")
	assert(not reach.has(Vector2i(13, 15)), "11 steps away is not")
	# reserved: only tiles that still leave AP >= snapshot cost (3)
	b.set_reserve(u)
	var r2 := b.reachable(u)
	assert(r2.has(Vector2i(9, 15)), "cost 7 leaves exactly 3: reachable")
	assert(not r2.has(Vector2i(10, 15)) and not r2.has(Vector2i(12, 15)), "cost 8 and 10 would leave < 3")
	# the battle move accepts a reserved-but-in-range tile and rejects one beyond it
	assert(b.move(u, Vector2i(8, 15)), "reserved move into range works")
	assert(not b.move(u, Vector2i(12, 15)), "reserved move past the reserve stops")
	# a vehicle cannot reserve
	var veh := b.add_vehicle("squad", Forces.vehicle_data("HMMWV"), Vector2i(30, 15), 6, 3)
	assert(not b.set_reserve(veh), "vehicles have no reserve")
	# the toggle is free and persistent
	assert(b.set_reserve(u) == false and b.set_reserve(u) == true, "toggle back on")
	b.set_reserve(u)                                  # back off
	assert(not u["reserve"], "toggle off works")
	print("RESERVE TEST PASS")
	quit(0)
