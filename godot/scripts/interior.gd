## Inside a building: the room composed from the interior kit (tools/compose_rooms.py,
## data/rooms.json). Room coordinates: a = east, b = south in metres from the NW corner, the same
## projection and scale as outside. The squad walks in through the door, furniture blocks the way
## (flat rugs do not), and walking back to the doorway leaves. The camera fits the room to the
## screen (rooms are small: a house is 8 x 6 m). People of the town are inside; clicking one
## walks the leader over and opens the conversation scene (talk_scene.gd).
extends Node2D

var main: Node
var tactical: Node                 # the field view, frozen while we are inside
var building: Dictionary
var description := ""
var room: Dictionary
var party := Vector2.ZERO
var dest := Vector2.ZERO
var moving := false
var leaving := false
var squad: Array = []
var world: Node2D
var cam: Camera2D
var hud: Label
var ui: CanvasLayer
var bg: Sprite2D
var folk: Array = []               # {kind, city, pos, body, head, sprite}
var furniture: Array = []          # standing pieces (fade when the squad is behind one)
var talk_to: Dictionary = {}       # walking over to this person
var talk: Node = null              # the open conversation scene
var actionbar: Node                # the original's bottom icon bar (manual p.55)
var bmsg: Label                    # the bar's one-line answer

# people inside, by building type (the town's people are met indoors)
const FOLK := {"HOUSE": 2, "TAVERN": 3, "MARKET": 2, "CHURCH": 1, "HOSPITAL": 1, "BANK": 1, "JAIL": 1, "FACTORY": 1, "BARN": 0}

const SC := 3.0
const K := 12.0 * SC
const OFFS := [Vector2(0, 0), Vector2(-0.9, 0.7), Vector2(0.9, 0.7), Vector2(0, 1.4)]

func iso(w: Vector2) -> Vector2:
	return Vector2((w.x + w.y) * K, (w.y - w.x) * K * 0.5)

func uniso(s: Vector2) -> Vector2:
	var sum := s.x / K
	var dif := s.y * 2.0 / K
	return Vector2((sum - dif) * 0.5, (sum + dif) * 0.5)

func _ready() -> void:
	var rooms = GameData._json("res://data/rooms.json")
	room = rooms[building["key"]]
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	var dark := Polygon2D.new()             # the night around the room
	dark.polygon = PackedVector2Array([Vector2(-5000, -5000), Vector2(5000, -5000), Vector2(5000, 5000), Vector2(-5000, 5000)])
	dark.color = Color(0.05, 0.05, 0.06)
	dark.z_index = -3
	add_child(dark)
	bg = Sprite2D.new()
	bg.texture = load("res://original/graphics/BUILDING/rooms/%s.png" % building["key"])
	bg.centered = false
	bg.scale = Vector2.ONE * SC
	bg.position = -Vector2(room["nw"][0], room["nw"][1]) * SC       # its NW floor corner at iso(0, 0)
	bg.z_index = -2
	add_child(bg)
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	for f in room["furniture"]:
		var sp := Sprite2D.new()
		sp.texture = load("res://original/graphics/BUILDING/rooms/%s.png" % f["pic"])
		sp.centered = false
		sp.scale = Vector2.ONE * SC
		sp.position = iso(Vector2(f["centre"][0], f["centre"][1]))
		sp.offset = Vector2(-sp.texture.get_width() / 2.0, float(f["r"]) * 12.0 - sp.texture.get_height())
		if f["flat"]:
			sp.z_index = -1
			add_child(sp)
		else:
			world.add_child(sp)
			furniture.append(sp)     # fade when the squad walks behind it
	# indoors, as everywhere outside a fight, the leader stands for the squad
	for m in [main.squad[clampi(main.leader_index, 0, main.squad.size() - 1)]]:
		var s := Soldier.new()
		s.body = "AF" if m["gender"] == "F" else "AM"
		s.head = int(m.get("head", m["face"]))
		world.add_child(s)
		squad.append(s)
	var door := Vector2(room["door"][0], room["door"][1])
	party = door + _inward() * 1.6
	_add_folk()
	# the whole room on the screen, as large as it goes
	var px: Vector2 = bg.texture.get_size() * SC
	cam.zoom = Vector2.ONE * clampf(minf(1180.0 / px.x, 620.0 / px.y), 1.0, 2.6)
	cam.position = bg.position + px / 2.0 + Vector2(0, 30)
	ui = CanvasLayer.new()
	add_child(ui)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 22)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	hud.text = "%s - %s.   Click to move, click a person to talk, the doorway (or Esc) to leave.\n%s" % [building["city"], building["type"], description]
	ui.add_child(hud)
	actionbar = preload("res://scripts/action_bar.gd").new()
	ui.add_child(actionbar)
	actionbar.setup(_bar_def())
	bmsg = Label.new()
	bmsg.position = Vector2(16, 660)
	bmsg.size = Vector2(1248, 46)
	bmsg.add_theme_font_size_override("font_size", 16)
	bmsg.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	bmsg.add_theme_color_override("font_outline_color", Color.BLACK)
	bmsg.add_theme_constant_override("outline_size", 6)
	ui.add_child(bmsg)
	_place()

## The people in the room: residents of the town, standing on free floor away from the door.
func _add_folk() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(building.get("key", "")) + hash(building.get("city", "")) + int(building.get("centre", Vector2.ZERO).x)
	var sz := Vector2(room["size"][0], room["size"][1])
	var door := Vector2(room["door"][0], room["door"][1])
	for i in range(int(FOLK.get(building.get("type", ""), 0))):
		for tries in range(40):
			var p := Vector2(rng.randf_range(1.0, sz.x - 1.0), rng.randf_range(1.0, sz.y - 1.0))
			if not is_free(p) or p.distance_to(door) < 2.5 or folk.any(func(f): return f["pos"].distance_to(p) < 1.4):
				continue
			var s := Soldier.new()
			s.body = "AF" if rng.randf() < 0.45 else "AM"
			s.head = rng.randi_range(0, 14)
			s.set_heading(door - p)
			world.add_child(s)
			s.position = iso(p)
			folk.append({"kind": "resident", "city": building.get("city", ""), "pos": p, "body": s.body, "head": s.head, "sprite": s})
			break

func _person_at(w: Vector2) -> Dictionary:
	for f in folk:
		if f["pos"].distance_to(w) < 0.8 or f["pos"].distance_to(w + Vector2(0.6, 0.6)) < 0.8:   # the click lands on the body, above the feet
			return f
	return {}

## Open the conversation scene with a person: the field view's talk runs through it.
func open_talk(p: Dictionary) -> void:
	talk_to = {}
	if tactical == null or (talk != null and is_instance_valid(talk)):
		return
	moving = false
	talk = self                                  # busy: no second scene while the picture is taken
	# the background: the room as it looks now (furniture), without the people and the text
	var people: Array = squad + folk.map(func(f): return f["sprite"])
	hud.visible = false
	for n in people:
		n.visible = false
	await RenderingServer.frame_post_draw
	var shot := ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	hud.visible = true
	for n in people:
		n.visible = true
	var sc := preload("res://scripts/talk_scene.gd").new()
	sc.main = main
	sc.room_tex = shot
	sc.leader = main.squad[clampi(main.leader_index, 0, main.squad.size() - 1)]
	sc.other = {"body": p["body"], "head": p["head"]}
	ui.add_child(sc)
	talk = sc
	var old: Node = tactical.dialog
	tactical.dialog = sc
	sc.closed.connect(func():
		if is_instance_valid(tactical):
			tactical.dialog = old
		talk = null)
	tactical.interact(p)

func _inward() -> Vector2:
	return [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][int(room["facing"])]

## Free floor: inside the walls and not on standing furniture.
func is_free(p: Vector2) -> bool:
	var sz := Vector2(room["size"][0], room["size"][1])
	var door := Vector2(room["door"][0], room["door"][1])
	if p.distance_to(door) > 0.9 and (p.x < 0.4 or p.y < 0.4 or p.x > sz.x - 0.4 or p.y > sz.y - 0.4):
		return false
	for f in room["furniture"]:
		if not f["flat"] and p.distance_to(Vector2(f["centre"][0], f["centre"][1])) < float(f["r"]) + 0.35:
			return false
	for f in folk:
		if f["pos"].distance_to(p) < 0.5:
			return false
	return true

func _unhandled_input(ev: InputEvent) -> void:
	if not main.input_ok(ev):
		return
	if ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_ESCAPE and actionbar.choice_open():
			actionbar.close_choices()       # ESC backs out of the icon's options window first
			return
		if actionbar.hotkey(ev.keycode):
			return
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		leave()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var w := uniso(get_global_mouse_position())
		var door := Vector2(room["door"][0], room["door"][1])
		var p := _person_at(w)
		if not p.is_empty():
			talk_to = p                          # walk up to them, then talk
			dest = p["pos"] + (party - p["pos"]).normalized() * 0.9
			moving = true
			leaving = false
		elif w.distance_to(door) < 1.5:
			walk_out()
		else:
			dest = w
			moving = true
			leaving = false

# ---------------- the bottom icon bar, room version (the original's icons, manual p.55) ----------------
func _bar_def() -> Array:
	return [
		{"key": "1", "label": "NECESSITY", "cb": _room_sleep},
		{"key": "2", "label": "OPTIONS", "cb": _room_options},
		{"key": "3", "label": "RADIO", "cb": _room_radio},
		{"key": "4", "label": "INVENTORY", "cb": _room_inventory},
		{"key": "5", "label": "COMBAT", "cb": _room_nothing.bind("Combat happens on the ground outside; the people of this house are no Black Legion.")},
		{"key": "6", "label": "TALK", "cb": _room_talk},
		{"key": "7", "label": "TAKE", "cb": _room_nothing.bind("Nothing loose in this room to take.")},
		{"key": "8", "label": "USE", "cb": _room_nothing.bind("Nothing here to use out of a hand yet.")},
		{"key": "9", "label": "MAP", "cb": _room_nothing.bind("The LCD map is used outside, on the ground.")},
		{"key": "0", "label": "LOOK", "cb": _room_look},
	]

func _room_sleep() -> void:
	var lines := Healing.rest(main.squad, 8.0, true, false, main.difficulty == "story")
	main.world.minutes += 480.0
	bmsg.text = "HOURS PASS. " + "\n".join(lines)

func _room_options() -> void:
	actionbar.choose("GAME OPTIONS", [
		["Save game", func():
			actionbar.close_choices()
			bmsg.text = "GAME SAVED." if main.save_game(main.QUICKSAVE) else "COULD NOT SAVE."],
		["Load game", func():
			actionbar.close_choices()
			if not main.load_game(main.QUICKSAVE):
				bmsg.text = "NO SAVED GAME."],
		["Sound on / off", func():
			actionbar.close_choices()
			bmsg.text = "SOUND %s." % ("ON" if main.toggle_sound() else "OFF")],
		["Quit", func():
			actionbar.close_choices()
			get_tree().quit()],
	])

func _room_radio() -> void:
	var st: String = main.campaign.step()
	bmsg.text = main.campaign.objective_text() if st != "" else "NO MISSION GOES ON AT THE MOMENT."

func _room_inventory() -> void:
	var lines: Array = []
	var gear_names: Array = []
	for r in main.squad:
		if r.get("dead", false):
			lines.append("%s - KILLED IN ACTION" % String(r["name"]))
			continue
		var g: Dictionary = r.get("gear", {})
		var wn := String(g.get("weapon", "(unarmed)"))
		lines.append("%s - %s // %s // MEDKITS %d" % [
			String(r["name"]), wn.to_lower(), Healing.condition(r), int(g.get("medkits", 0))])
		if wn.strip_edges() != "" and not gear_names.has(wn):
			gear_names.append(wn)
	bmsg.text = "\n".join(lines)
	# The original Inventory icon has INFO/DESCRIPTION choices: read the long text of a
	# carried item (the game's own EQUIP.TXT, extracted to data/EQUIP.json).
	var opts: Array = []
	for nm in gear_names:
		opts.append(["DESCRIPTION - %s" % nm, _room_item_description.bind(String(nm))])
	opts.append(["CLOSE", func(): bmsg.text = "\n".join(lines)])
	actionbar.choose("INVENTORY", opts)

## Show the original long description of a gear item in the room's message line.
func _room_item_description(item_name: String) -> void:
	var desc: String = main.data.item_description(item_name)
	bmsg.text = desc if desc != "" else "NO DESCRIPTION IS AVAILABLE FOR %s." % item_name.to_upper()

func _room_nothing(why: String) -> void:
	bmsg.text = why

func _room_talk() -> void:
	var near := {}
	var best_d := 2.5
	for f in folk:
		var d: float = f["pos"].distance_to(party)
		if d < best_d:
			near = f
			best_d = d
	if near.is_empty():
		bmsg.text = "Nobody is standing close enough to talk across the room."
		return
	open_talk(near)

func _room_look() -> void:
	for f in folk:
		if f["pos"].distance_to(party) < 2.0:
			bmsg.text = "A citizen of %s stands close by." % building["city"]
			return
	for f in room["furniture"]:
		if Vector2(f["centre"][0], f["centre"][1]).distance_to(party) < float(f["r"]) + 1.0:
			bmsg.text = "%s of the room's furniture is at arm's reach." % String(f["pic"]).to_lower()
			return
	bmsg.text = "The room holds what it holds: furniture and people, nothing out of the ordinary."

func walk_out() -> void:
	dest = Vector2(room["door"][0], room["door"][1])
	moving = true
	leaving = true

## Walk to the point of the room nearest to a piece of furniture (used by the test).
## Tests: talk to the i-th person in the room (straight away), then pick a choice.
func test_talk(i: int) -> void:
	for m in main.squad:                         # the test squad may have no Polish speaker
		m["languages"]["POLISH"] = maxf(float(m["languages"].get("POLISH", 0.0)), 3.0)
	if i < folk.size():
		open_talk(folk[i])

func test_pick(i: int) -> void:
	if talk != null and is_instance_valid(talk) and talk != self:   # not while the scene is still being made
		talk.pages.clear()
		if talk.waiting_choice() or not talk.choices.is_empty():
			talk.pick_index(i)
		else:
			talk.advance()

func test_walk_to_furniture(i: int) -> void:
	var f: Dictionary = room["furniture"][i % room["furniture"].size()]
	dest = Vector2(f["centre"][0], f["centre"][1]) + Vector2(0, float(f["r"]) + 0.6)
	moving = true

func _process(delta: float) -> void:
	if moving:
		var to := dest - party
		var step := 1.6 * delta
		if to.length() <= step:
			party = dest
			moving = false
			if leaving:
				leave()
				return
			if not talk_to.is_empty():
				for s in squad:
					s.set_heading(talk_to["pos"] - party)
				open_talk(talk_to)
		else:
			var next := party + to.normalized() * step
			if not is_free(next) and not leaving:
				next = Vector2.INF
				for deg in [30, -30, 60, -60, 90, -90]:
					var c: Vector2 = party + to.normalized().rotated(deg_to_rad(deg)) * step
					if is_free(c):
						next = c
						break
				if next == Vector2.INF:
					moving = false
					next = party
					if not talk_to.is_empty() and party.distance_to(talk_to["pos"]) < 1.8:
						open_talk(talk_to)           # close enough: talk across the furniture
			party = next
		for s in squad:
			s.set_heading(to)
	for s in squad:
		s.walking = moving
	_place()

func _place() -> void:
	for i in range(squad.size()):
		var p: Vector2 = party + OFFS[i]
		squad[i].position = iso(p)
	# nobody disappears behind the furniture: the piece fades when a soldier is behind it
	for f in furniture:
		var r := Rect2(f.position + f.offset * f.scale, f.texture.get_size() * f.scale)
		var behind := false
		for s in squad:
			if s.visible and r.has_point(s.position + Vector2(0, -34)) and s.position.y < f.position.y:
				behind = true
				break
		f.modulate = Color(1, 1, 1, 0.45 if behind else 1.0)
	queue_redraw()

func _draw() -> void:
	# the doorway, so the way out is easy to see
	var d := Vector2(room["door"][0], room["door"][1])
	var pts := PackedVector2Array([iso(d + Vector2(-0.6, -0.6)), iso(d + Vector2(0.6, -0.6)), iso(d + Vector2(0.6, 0.6)), iso(d + Vector2(-0.6, 0.6))])
	draw_colored_polygon(pts, Color(1, 0.85, 0.3, 0.35))

func leave() -> void:
	if tactical == null:                    # a room shown on its own (tests)
		return
	tactical.leave_building(building)
	queue_free()
