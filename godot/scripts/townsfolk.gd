## People in the cities: the leader in the centre of town, residents walking about, and what a
## mission puts there (suspects, wounded or sick, Black Legion soldiers). Spawned when the squad
## comes near a city and removed when it leaves; the mission state decides who is there.
class_name Townsfolk
extends RefCounted

var view: Node                    # the field view (iso(), world, town, main)
var people: Array = []            # {kind, city, pos, home, sprite, index, mark}
var spawned := {}                 # city -> true

func _init(field_view: Node) -> void:
	view = field_view

func _free_spot(rng: RandomNumberGenerator, centre: Vector2, rmin: float, rmax: float) -> Vector2:
	for i in range(40):
		var a := rng.randf() * TAU
		var p := centre + Vector2(cos(a), sin(a)) * rng.randf_range(rmin, rmax)
		if view.town.blocking(p, 1.0).is_empty():
			return p
	return centre

## (Re)create the people of a city from the mission state.
func spawn(city: Dictionary) -> void:
	var name: String = city["name"]
	despawn(name)
	spawned[name] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) + view.main.campaign.done_count * 7919
	var centre := Vector2(city["a"], city["b"])
	var cp: Campaign = view.main.campaign
	_add("leader", name, _free_spot(rng, centre, 0.0, 3.0), rng, 0)
	var st := cp.step()
	var here := cp.place(st) == name if st != "" else false
	var suspects := 5 if here and st.begins_with("spy:") else 0
	for i in range(maxi(4, suspects)):
		_add("suspect" if i < suspects else "resident", name, _free_spot(rng, centre, 6.0, 30.0), rng, i)
	if here and st.begins_with("treat:"):
		for i in range(int(cp.mission["patients"])):
			_add("patient", name, _free_spot(rng, centre, 4.0, 25.0), rng, i)
	var tank_here: bool = here and st.begins_with("clear:") and cp.mission["type"] == "tank"
	var wreck_here: bool = here and st.begins_with("repair:")
	if tank_here and cp.enemies_in(name) > 0:
		var v := Forces.vehicle_data(cp.mission["tank"])
		_add_vehicle("tank", name, _free_spot(rng, centre, 20.0, 45.0), String(v.get("enemy_sprite", "V3")))
	elif not cp.hideout_in(name):              # hideouts: they are inside, not in the street
		for i in range(cp.enemies_in(name)):
			_add("enemy", name, _free_spot(rng, centre, 12.0, 45.0), rng, i, "AM" if wreck_here else "")
	if wreck_here:
		var v := Forces.vehicle_data(cp.vehicle_model())
		_add_vehicle("wreck", name, _free_spot(rng, centre, 50.0, 70.0), String(v.get("enemy_wreck", "DV3")))

## The group met on the road: hostile ones as enemies 15-35 m off, the others as travellers.
func spawn_group(g: Dictionary, lm: LocalMap) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(lm.centre)
	var legion: bool = String(g.get("name", "")).begins_with("BLACK LEGION")
	for i in range(int(g.get("count", 3))):
		var pos := lm.free_spot(rng, 15.0, 35.0)
		_add("enemy" if g.get("hostile", false) else "traveller", "ENCOUNTER", pos, rng, i, "EM" if legion else "")
	spawned["ENCOUNTER"] = true

func _add(kind: String, city: String, pos: Vector2, rng: RandomNumberGenerator, index: int, body := "") -> void:
	var s := Soldier.new()
	if body != "":
		s.body = body
		s.head = rng.randi_range(0, 14) if body != "EM" else 0
	elif kind == "enemy":
		s.body = "EM"
		s.head = 0
	else:
		s.body = "AF" if rng.randf() < 0.4 else "AM"
		s.head = rng.randi_range(0, 14)
	s.dir = rng.randi_range(0, 7)
	view.world.add_child(s)
	# base: a whole-metre point (exact in 32-bit floats); off: small offset that walking changes
	var base := pos.floor()
	people.append({"kind": kind, "city": city, "pos": pos, "base": base, "off": pos - base, "home": pos - base,
		"sprite": s, "index": index, "wander": pos - base, "t": rng.randf() * 4.0})

## A vehicle in town: the Black Legion's tank, or the downed vehicle of a "vehicle" mission.
func _add_vehicle(kind: String, city: String, pos: Vector2, sprite: String) -> void:
	var s := Sprite2D.new()
	s.texture = load("res://original/graphics/BUILDING/%s_rgba.png" % sprite)
	s.scale = Vector2.ONE * 3.0
	s.offset = Vector2(0, -7)
	view.world.add_child(s)
	var base := pos.floor()
	people.append({"kind": kind, "city": city, "pos": pos, "base": base, "off": pos - base, "home": pos - base,
		"sprite": s, "index": 0, "wander": pos - base, "t": 0.0})

func despawn(city: String) -> void:
	for p in people.duplicate():
		if p["city"] == city:
			p["sprite"].queue_free()
			people.erase(p)
	spawned.erase(city)

func remove(p: Dictionary) -> void:
	p["sprite"].queue_free()
	people.erase(p)

## Nearest person to a world point within `reach` metres, or {}.
func at(w: Vector2, reach := 1.6) -> Dictionary:
	var best: Dictionary = {}
	var bd := reach
	for p in people:
		var d: float = p["pos"].distance_to(w)
		if d < bd:
			bd = d
			best = p
	return best

func of_kind(kind: String, city: String) -> Array:
	return people.filter(func(p): return p["kind"] == kind and p["city"] == city)

func update(delta: float, party: Vector2) -> void:
	# spawn / despawn by distance
	for c in view.main.data.cities:
		var d: float = Vector2(c["a"], c["b"]).distance_to(party)
		if d < 250.0 and not spawned.has(c["name"]):
			spawn(c)
		elif d > 400.0 and spawned.has(c["name"]):
			despawn(c["name"])
	for p in people:
		# residents stroll near their spot; the leader, the sick and soldiers stay put
		if p["kind"] in ["resident", "suspect"]:
			p["t"] -= delta
			if p["t"] <= 0.0:
				p["t"] = randf_range(3.0, 7.0)
				var a := randf() * TAU
				p["wander"] = p["home"] + Vector2(cos(a), sin(a)) * randf_range(0.0, 4.0)
			var to: Vector2 = p["wander"] - p["off"]
			var s: Soldier = p["sprite"]
			if to.length() > 0.1:
				var nxt: Vector2 = p["off"] + to.normalized() * minf(0.9 * delta, to.length())
				if view.town.blocking(p["base"] + nxt, 0.6).is_empty():
					p["off"] = nxt
					p["pos"] = p["base"] + nxt
				s.set_heading(to)
				s.walking = true
			else:
				s.walking = false
		p["sprite"].position = view.iso(p["base"]) + view.iso_vec(p["off"])
		p["sprite"].visible = p["pos"].distance_to(party) < 160.0
