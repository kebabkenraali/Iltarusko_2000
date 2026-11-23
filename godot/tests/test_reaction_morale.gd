## Headless check of the UFO-engine slices: reaction fire (watchers answer each step,
## once per round each, one shooter per move, the walk stops when the mover falls) and
## the panic/morale system (casualties drain the side's heart, a broken soldier freezes
## or flees and half-recovers).
## godot --headless --path . --script tests/test_reaction_morale.gd
extends SceneTree

func _init() -> void:
	var cr := ChargenRules.new(GameData._json("res://data/careers.json"), GameData._json("res://data/chargen.json"), 21)
	var data := GameData.new()
	data.load_all()
	var items: Array = data.items
	# ---- reaction fire ----
	var b := Battle.new(40, 30, items, Forces.vehicle_guns(), 900)
	b.options["fog"] = true
	b.options["reaction"] = true
	b.refresh_seen()
	var sq: Array = []
	for i in range(2):
		var r := cr.random_recruit()
		Forces.equip(r)
		sq.append(b.add_man("squad", r, Vector2i(2 + i, 15), i))
	var g := Forces.group("BLACK LEGION", 1, RandomNumberGenerator.new())
	var e := b.add_man("enemy", g["men"][0], Vector2i(30, 15))
	b.refresh_seen()
	# all dark: nobody spots anybody: a move should draw no reaction
	b.move(sq[0], Vector2i(10, 15))
	assert(not b.log.any(func(l): return "REACTS" in String(l)), "no reaction while everything is dark")
	# bring the watcher into sight: the mover crossing in front of him gets answered
	e["seen_by"]["squad"] = true                        # the squad has spotted him
	sq[0]["pos"] = Vector2i(10, 15)
	sq[0]["ap"] = 10.0
	sq[1]["pos"] = Vector2i(2, 16)
	# the enemy now moves: the squad watcher is 4-8 tiles away with a clear line
	e["pos"] = Vector2i(18, 15)
	e["ap"] = 10.0
	e["reacted"] = false
	var before: int = sq[0]["ammo"]
	b.move(e, Vector2i(14, 15))
	var reacts: Array = b.log.filter(func(l): return "REACTS" in String(l))
	assert(not reacts.is_empty(), "the watcher reacted to the crossing move")
	assert(int(sq[0]["ammo"]) <= before - 1, "the reaction shot spent ammunition")
	# once per round: a second crossing draws no further shot from the same watcher
	assert(sq[0]["reacted"], "the watcher is marked used this round")
	# ---- panic and morale ----
	var b2 := Battle.new(20, 20, items, Forces.vehicle_guns(), 901)
	b2.options = {}
	b2.refresh_seen()
	var s1 := b2.add_man("squad", cr.random_recruit(), Vector2i(3, 10), 0)
	var s2 := b2.add_man("squad", cr.random_recruit(), Vector2i(3, 12), 1)
	Forces.equip(cr.random_recruit())
	var e2 := b2.add_man("enemy", Forces.group("BLACK LEGION", 1, RandomNumberGenerator.new())["men"][0], Vector2i(10, 11))
	var m_before: float = float(s2["morale"])
	b2._die(s1, e2, "THE HIT HAS KILLED %s." % s1["name"])
	assert(float(s2["morale"]) <= m_before - Battle.MO_DEAD + 0.01, "a death drains the mate's heart")
	assert(float(e2["morale"]) >= 100.0 + Battle.MO_KILL - 0.01, "the killer's side takes heart")
	# a broken soldier: on his turn he either freezes (0 AP) or flees, and half-recovers
	s2["morale"] = 0.0
	b2.add_man("enemy", Forces.group("BLACK LEGION", 1, RandomNumberGenerator.new())["men"][0], Vector2i(11, 11))
	b2._new_round()
	b2.turn_i = b2.order.find(s2["id"])
	b2._begin_turn()
	assert(float(s2["morale"]) == Battle.PANIC_RECOVER, "the worst passes: morale half")
	assert(int(s2["ap"]) == 0 and (b2.log.any(func(l): return "FREEZES" in String(l) or "PANICS AND RUNS" in String(l)) or s2.get("fled", false)), "freeze or flee")
	print("REACTION + MORALE TEST PASS")
	quit(0)
