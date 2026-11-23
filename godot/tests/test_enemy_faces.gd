## Headless check of the enemies' own portraits (FACES/enemies.png): every enemy unit gets
## a face index from Battle.add_man, the sheet loads, and the units get distinct faces.
## godot --headless --path . --script tests/test_enemy_faces.gd
extends SceneTree

func _init() -> void:
	var data := GameData.new()
	data.load_all()
	var b := Battle.new(40, 30, data.items, Forces.vehicle_guns(), 4242)
	var g := Forces.group("BLACK LEGION", 6, rng_of(5))
	var g2 := Forces.group("MARAUDERS", 2, rng_of(6))
	var faces := []
	for t in g["men"] + g2["men"]:
		var u := b.add_man("enemy", t, Vector2i(20, 15))
		assert(u.has("face") and int(u["face"]) >= 0 and int(u["face"]) < 15, "enemy unit has a face index 0-14")
		faces.append(int(u["face"]))
	assert(faces.size() == 8, "six BLACK LEGION + two MARAUDER men")
	assert(faces[0] != faces[1] and faces[0] != faces[2] and faces[1] != faces[2], "the BLACK LEGION soldiers have different faces")
	assert(faces[6] != faces[7], "the two marauders have different faces")
	assert(ResourceLoader.exists("res://original/graphics/FACES/enemies.png"), "the enemies sheet is in the project")
	var sheet := load("res://original/graphics/FACES/enemies.png")
	assert(sheet != null, "the enemies sheet loads")
	assert(int(sheet.get_size().x) == 240 and int(sheet.get_size().y) == 129, "the sheet is 240x129")
	print("ENEMY FACES TEST PASS")
	quit(0)

func rng_of(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r
