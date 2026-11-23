## Field view of one place: a town, or the spot of an encounter on the world map (main.local
## says which). World coordinates are the original's (metres): a = east, b = south.
## Same 2:1 isometric projection as the 1991 game: north towards the top-left.
## Modern additions: click-to-move for the whole squad, travel-to-city with time compression,
## day/night lighting, an LCD map drawn in the ground view's orientation (M), pause (Space).
## Cities are built from the original templates (Town); walls block, a click on a building
## walks to its door and goes in. Missions (Campaign) put people in the towns (Townsfolk): a click
## on a person walks up to them and talks, interrogates, treats or fights depending on who it is.
extends Node2D

var main: Node
const SC := 3.0                              # sprites (soldiers, buildings) at 3x the original pixels
const K := 12.0 * SC                         # screen px per metre: the kits are drawn at 12 px/m
# The party position in 64-bit floats: Vector2 is 32-bit, which at 260 000 m resolves only
# 3 cm - less than a walking step per frame. Everything is drawn relative to (pa, pb).
var pa := 159500.0                           # east, metres (Krakow)
var pb := 257500.0                           # south, metres
var party: Vector2:
	get:
		return Vector2(pa, pb)
	set(v):
		pa = v.x
		pb = v.y
var dest := Vector2.ZERO
var moving := false
var fast := false
var paused := false
var hour := 21.0                             # the original starts in the evening/night
var squad: Array = []
var hud: Label
var msg: Label
var lcd: Control
var tint: CanvasModulate
var cam: Camera2D
var target_city := ""
var arrived := {}
var world: Node2D                            # y-sorted: soldiers and buildings
var town: Town
var bsprites: Array = []                     # [building, Sprite2D]
var enter_target: Dictionary = {}            # building whose door we are walking to
var ui_layer: CanvasLayer
var overlay: Node2D                           # drawn over the houses
var here := ""                               # city the party is in
var folk: Townsfolk
var dialog: Panel
var objective: Label
var person_target: Dictionary = {}           # the person we are walking up to
var local: LocalMap                          # the ground, trees and the edge of this place
var mode := "town"                           # "town" or "encounter"
var group: Dictionary = {}                   # who the squad ran into (encounters)
var prop_sprites: Array = []                 # [prop, Sprite2D]
var rush := 0.0                              # 0 = the leader alone, 1 = the squad at the leader's side
var actionbar: Node                          # the original's bottom icon bar (manual p.55)
const NO_MOVE := "YOU CAN'T USE THE MOVE FEATURE BECAUSE THERE ARE ENEMIES TOO CLOSE TO YOU."
const LEADER_LANGS := ["POLISH", "RUSSIAN", "ENGLISH"]
const TOWN_LANGS := ["POLISH"]

func iso(w: Vector2) -> Vector2:
	var dx: float = w.x - pa
	var dy: float = w.y - pb
	return Vector2((dx + dy) * K, (dy - dx) * K * 0.5)

## Screen offset of a small world vector (no party subtraction).
func iso_vec(o: Vector2) -> Vector2:
	return Vector2((o.x + o.y) * K, (o.y - o.x) * K * 0.5)

## Move the party by a small vector, in 64-bit.
func _move(d: Vector2) -> void:
	pa += d.x
	pb += d.y

func uniso(s: Vector2) -> Vector2:
	# inverse of iso(): s = ((a+b)K, (b-a)K/2) relative to the party
	var sum := s.x / K
	var dif := s.y * 2.0 / K
	return Vector2(pa + (sum - dif) * 0.5, pb + (sum + dif) * 0.5)

func _ready() -> void:
	var L: Dictionary = main.local
	mode = L.get("mode", "town")
	group = L.get("group", {})
	var start: Vector2 = L.get("start", Vector2(pa, pb))
	pa = start.x
	pb = start.y
	hour = main.world.hour()
	local = LocalMap.new(main.world, L.get("centre", start), 130.0 if mode == "town" else 60.0, mode == "town")
	tint = CanvasModulate.new()
	add_child(tint)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	cam.zoom = Vector2.ONE * 0.6
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	overlay = Node2D.new()                  # marks drawn over the houses (the hideout)
	overlay.z_index = 50
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	town = Town.new(main.data.cities)
	for b in town.buildings:
		var sp := Sprite2D.new()
		sp.centered = false
		sp.visible = false
		world.add_child(sp)
		bsprites.append([b, sp])
	refresh_art()
	for pr in local.props:
		var sp := Sprite2D.new()
		sp.texture = local.tex[pr["kind"]]
		sp.centered = false
		sp.scale = Vector2.ONE * SC
		sp.offset = Vector2(-sp.texture.get_width() / 2.0, -sp.texture.get_height() + 3)
		world.add_child(sp)
		prop_sprites.append([pr, sp])
	# the recruits from chargen: gender picks the body, the recruit's field head sprite the head
	main.default_squad()
	for m in main.squad:
		var s := Soldier.new()
		s.body = "AF" if m["gender"] == "F" else "AM"
		s.head = int(m.get("head", m["face"]))
		world.add_child(s)
		squad.append(s)
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	ui.add_child(hud)
	msg = Label.new()
	msg.position = Vector2(16, 682)
	msg.add_theme_font_size_override("font_size", 22)
	msg.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	msg.add_theme_color_override("font_outline_color", Color.BLACK)
	msg.add_theme_constant_override("outline_size", 6)
	ui.add_child(msg)
	lcd = preload("res://scripts/lcd_map.gd").new()
	lcd.view = self
	lcd.visible = false
	ui.add_child(lcd)
	ui_layer = ui
	objective = Label.new()
	objective.position = Vector2(16, 40)
	objective.add_theme_font_size_override("font_size", 19)
	objective.add_theme_color_override("font_color", Color(1, 0.7, 0.4))
	objective.add_theme_color_override("font_outline_color", Color.BLACK)
	objective.add_theme_constant_override("outline_size", 6)
	ui.add_child(objective)
	actionbar = preload("res://scripts/action_bar.gd").new()
	ui.add_child(actionbar)
	actionbar.setup(_bar_def())
	dialog = preload("res://scripts/dialog.gd").new()
	ui.add_child(dialog)
	folk = Townsfolk.new(self)
	if mode == "encounter":
		folk.spawn_group(group, local)
	refresh_target()
	if mode == "encounter":
		msg.text = ("THE %s ARE HERE. Click them to fight, M = back to the map." % group.get("name", "")) if group.get("hostile", false) else ("A GROUP OF %s. Click to talk, M or the map edge = move on." % group.get("name", ""))
	else:
		msg.text = "Click to move, click a person to talk, M or the edge of town = world map, Space = pause."

## The city the current mission step happens in (Krakow when there is no mission).
func refresh_target() -> void:
	var c: String = main.campaign.objective_city()
	target_city = c if c != "" else "KRAKOW"
	objective.text = main.campaign.objective_text()

## Building sprites: the remastered or original composition (F2), sorted at the ground centre.
func refresh_art() -> void:
	for pair in bsprites:
		var b: Dictionary = pair[0]
		var sp: Sprite2D = pair[1]
		var path: String = main.art("BUILDING/composed", b["key"])
		sp.texture = load(path)
		var div: float = main.art_div(path)
		var m: Dictionary = town.meta[b["key"]]
		var sz: Vector2 = b["size"]
		var c := Vector2(m["nw"][0], m["nw"][1]) + Vector2((sz.x + sz.y) * 6.0, (sz.y - sz.x) * 3.0)
		sp.scale = Vector2.ONE * SC / div
		sp.offset = -c * div

## A building the squad stands behind fades (its art would cover a soldier): the same trick
## the battle's trees use. The sort point is the base centre, so a soldier whose feet are
## above it and whose body is inside the art's rectangle would be hidden - fade instead.
func _fade_over(sp: Sprite2D) -> void:
	if sp.texture == null:
		return
	var r := Rect2(sp.position + sp.offset * sp.scale, sp.texture.get_size() * sp.scale)
	var behind := false
	for s in squad:
		if s.visible and r.has_point(s.position + Vector2(0, -34)) and s.position.y < sp.position.y:
			behind = true
			break
	sp.modulate = Color(1, 1, 1, 0.45 if behind else 1.0)

## Fast travel to a city: stop on the road 40 m short of the centre (the houses stand there).
func travel_to(city: String) -> void:
	var c: Dictionary = main.data.city(city)
	if c.is_empty():
		return
	var centre := Vector2(c["a"], c["b"])
	dest = centre - (centre - party).normalized() * 40.0
	moving = true
	fast = true
	enter_target = {}

## Walk to a building's door and go inside (also used by the tests).
func walk_to_door(b: Dictionary) -> void:
	var out: Vector2 = [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)][int(b["facing"])]
	dest = b["door"] + out * 1.2
	moving = true
	fast = false
	enter_target = b

func test_enter_nearest() -> void:
	var near := town.near(party, 200.0)
	if not near.is_empty():
		near.sort_custom(func(x, y): return x["door"].distance_to(party) < y["door"].distance_to(party))
		walk_to_door(near[0])

## Go into a building: the field view freezes (hidden, not processing) and the room takes over.
func _enter(b: Dictionary) -> void:
	if main:
		main.play_sfx("DOOR")
	if main.campaign.is_hideout(here, _index_of(b)):
		main.battle_indoors(here, b, party)    # they are waiting inside
		return
	var room := preload("res://scripts/interior.gd").new()
	room.main = main
	room.tactical = self
	room.building = b
	room.description = INSIDE.get(b["type"], "")
	var found := _search(b)
	if found != "":
		room.description = found
		refresh_target()
	visible = false
	tint.visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	ui_layer.visible = false
	main.add_child(room)
	main.room = room

## Over the houses: the hideout's door (the townspeople point it out).
func _draw_overlay() -> void:
	var hd := hideout()
	if not hd.is_empty() and hd["door"].distance_to(party) < 120.0:
		var at := iso(hd["door"])
		overlay.draw_string(ThemeDB.fallback_font, at + Vector2(-52, -118), "HIDEOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.BLACK)
		overlay.draw_string(ThemeDB.fallback_font, at + Vector2(-54, -120), "HIDEOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.55, 0.35))
		overlay.draw_line(at + Vector2(0, -105), at + Vector2(0, -20), Color(1, 0.55, 0.35), 4.0)

## The building's number among this town's buildings (missions name buildings by it).
func _index_of(b: Dictionary) -> int:
	return town.buildings.filter(func(x): return x["city"] == here).find(b)

## The hideout of a hostage / assassins mission in this town, or {}.
func hideout() -> Dictionary:
	if not main.campaign.hideout_in(here):
		return {}
	var mine := town.buildings.filter(func(x): return x["city"] == here)
	var i := int(main.campaign.mission.get("hideout", -1))
	return mine[i] if i >= 0 and i < mine.size() else {}

## Searching a building of this town for a mission's crates: a line when they are found.
func _search(b: Dictionary) -> String:
	var mine := town.buildings.filter(func(x): return x["city"] == here)
	return main.campaign.searched(here, mine.find(b))

## Back from a room: outside the door, the way we came in.
func leave_building(b: Dictionary) -> void:
	var out: Vector2 = [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)][int(b["facing"])]
	party = b["door"] + out * 1.6
	dest = party
	moving = false
	enter_target = {}
	visible = true
	tint.visible = true
	ui_layer.visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	cam.make_current()
	main.room = null
	msg.text = "Left the %s." % String(b["type"]).to_lower()

const INSIDE := {
	"HOUSE": "A family home. The people here watch you warily from the back room.",
	"TAVERN": "Smoke, home-brewed vodka and rumours. A good place to hear what goes on in the region.",
	"MARKET": "Stalls of potatoes, cabbage, boots and the odd box of cartridges, traded for food or gold.",
	"JAIL": "The town lock-up, guarded by the militia.",
	"HOSPITAL": "A doctor with too few supplies and too many patients.",
	"BANK": "The vault holds what the town still trusts: gold.",
	"FACTORY": "Silent machines; a few workers keep one line running.",
	"CHURCH": "Candles and a priest who knows everyone in town.",
	"BARN": "Hay, tools and a tired horse.",
}

func _unhandled_input(ev: InputEvent) -> void:
	if not main.input_ok(ev):
		return
	if dialog.visible:
		if ev is InputEventKey and ev.pressed and ev.keycode >= KEY_1 and ev.keycode <= KEY_9 and dialog.waiting_choice():
			dialog.pick_index(ev.keycode - KEY_1)
		elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and dialog.waiting_choice():
			dialog.pick_index(dialog.choices.size() - 1)
		elif (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventKey and ev.pressed and ev.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]):
			dialog.advance()
		return
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and actionbar.choice_open():
		actionbar.close_choices()               # ESC backs out of the icon's options window first
		return
	if ev is InputEventKey and ev.pressed and actionbar.hotkey(ev.keycode):
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var w := uniso(get_global_mouse_position())
		var who := folk.at(w, 1.8)
		if not who.is_empty():
			walk_to_person(who)
			return
		var b := town.door_at(w, 3.0)
		if b.is_empty():
			b = town.blocking(w, 0.0)          # a click on a building walks to its door
		if not b.is_empty():
			walk_to_door(b)
		else:
			dest = w
			moving = true
			fast = false
			enter_target = {}
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# zoom: the original scale (1.0) shows ~35 m; zoom out to see a whole town
		var z := cam.zoom.x * (1.15 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
		cam.zoom = Vector2.ONE * clampf(z, 0.35, 1.5)
	elif ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_M: try_leave()
			KEY_L: lcd.visible = not lcd.visible
			KEY_SPACE: paused = not paused

func _process(delta: float) -> void:
	if dialog.visible:
		folk.update(0.0, party)
		return
	if paused:
		hud.text = "PAUSED"
		return
	var speed := 1.6                                   # walking pace, m/s (8 m per 5 s combat round)
	var scale_t := 1.0
	if fast and moving and party.distance_to(dest) > 5.0:
		scale_t = 300.0                                 # time compression on open road (5 game min per second)
	if moving:
		var to := Vector2(dest.x - pa, dest.y - pb)       # 64-bit difference, then small
		var step := speed * delta * scale_t
		if not town.near(party, 40.0).is_empty():
			step = minf(step, 0.8)                      # among houses: never jump through a wall
		var mv := to if to.length() <= step else to.normalized() * step
		var wall := town.blocking(party + mv)
		if wall.is_empty() and local.blocking(party + mv) and not local.blocking(party):
			wall = {"type": "TREE"}
		if not wall.is_empty() and town.blocking(party).is_empty():
			# steer along the wall: the first free direction turning away from the straight line
			var found := false
			for deg in [30, -30, 60, -60, 90, -90, 120, -120]:
				var cand: Vector2 = to.normalized().rotated(deg_to_rad(deg)) * minf(step, 0.8)
				if town.blocking(party + cand).is_empty() and not local.blocking(party + cand):
					_move(cand)
					found = true
					break
			if not found:
				moving = false
				fast = false
				msg.text = "A %s wall is in the way. Click the building to walk to its door." % String(wall["type"]).to_lower()
		elif to.length() <= step:
			party = dest
			moving = false
			fast = false
			if not enter_target.is_empty():
				_enter(enter_target)
			elif not person_target.is_empty():
				var p := person_target
				person_target = {}
				interact(p)
		else:
			_move(mv)
		for s in squad:
			s.set_heading(to)
	for s in squad:
		s.walking = moving
	main.world.minutes += delta * scale_t / 60.0                 # the world clock runs in real time here
	hour = main.world.hour()
	var light := clampf(0.5 - 0.5 * cos((hour - 2.0) / 24.0 * TAU), 0.0, 1.0)
	tint.color = Color(0.35, 0.35, 0.5).lerp(Color(1, 1, 1), light)
	# one figure - the leader - stands for the squad; when enemies come close the others rush to
	# the leader's side (the original manual: "the other three team members rush to their
	# leader's side") and leave again when the fight is over
	var fighting := _hostiles_near(35.0)
	rush = clampf(rush + (delta * 1.6 if fighting else -delta * 1.2), 0.0, 1.0)
	var offs := [Vector2(-2.5, 2.0), Vector2(2.5, 2.0), Vector2(0, 4.2)]   # metres, room for 3x sprites
	var k := 0
	for i in range(squad.size()):
		if i == main.leader_index:
			squad[i].position = Vector2.ZERO
			squad[i].visible = true
			continue
		var o: Vector2 = offs[k % offs.size()]
		k += 1
		squad[i].position = iso_vec(o * (1.0 + 7.0 * (1.0 - rush)))
		squad[i].visible = rush > 0.0
		squad[i].walking = moving or (rush > 0.0 and rush < 1.0)
	cam.position = Vector2.ZERO
	for pair in prop_sprites:
		var sp: Sprite2D = pair[1]
		sp.position = iso(pair[0]["pos"])
		sp.visible = pair[0]["pos"].distance_to(party) < 90.0
	if party.distance_to(local.centre) > local.radius:
		try_leave()
	for pair in bsprites:
		var b: Dictionary = pair[0]
		var sp: Sprite2D = pair[1]
		sp.visible = b["centre"].distance_to(party) < 160.0
		if sp.visible:
			sp.position = iso(b["centre"])
			_fade_over(sp)
	var was := here
	here = ""
	for c in main.data.cities:
		if Vector2(c["a"], c["b"]).distance_to(party) < 130.0:
			here = c["name"]
	if here != was and here != "":
		_arrived_in(here)
	folk.update(delta, party)
	queue_redraw()
	overlay.queue_redraw()
	var c: Dictionary = main.data.city(target_city)
	var dist := party.distance_to(Vector2(c["a"], c["b"]))
	hud.text = "%s   %s   OBJECTIVE: %s %.1f km" % [main.world.date_text(), ("IN " + here) if here != "" else ("ENCOUNTER: " + String(group.get("name", ""))), target_city, dist / 1000.0]
	if dist < 150.0 and not arrived.has(target_city):
		arrived[target_city] = true
		msg.text = "Arrived at %s. The leader waits in the centre of town; click people to talk." % target_city

func _draw() -> void:
	# ground: the season's 2 m tiles (left vertex of a tile = its north-west corner)
	# as far as the camera sees (zoomed out to see a whole town, the area grows)
	var tx0 := int(floor(pa / 2.0))
	var ty0 := int(floor(pb / 2.0))
	var zinv := 1.0 / cam.zoom.x
	var n := int(ceil(18.0 * zinv))
	var lim := Vector2(820.0, 520.0) * zinv
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var tx := tx0 + i
			var ty := ty0 + j
			var p := iso(Vector2(tx * 2.0, ty * 2.0))
			if absf(p.x) > lim.x or absf(p.y) > lim.y:
				continue
			var outside := Vector2(tx * 2 + 1, ty * 2 + 1).distance_to(local.centre) > local.radius
			draw_texture_rect(local.tiles[local.tile_at(tx, ty)], Rect2(p.x, p.y - 36.0, 144.0, 72.0), false,
				Color(0.55, 0.55, 0.55) if outside else Color.WHITE)
	# the town's name
	for c in main.data.cities:
		var cw := Vector2(c["a"], c["b"])
		if cw.distance_to(party) < 400.0:
			draw_string(ThemeDB.fallback_font, iso(cw) + Vector2(-60, -20), c["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1, 0.8))
	# who is who: the leader, and the people a mission is about
	for p in folk.people:
		if not p["sprite"].visible:
			continue
		var at: Vector2 = iso(p["pos"]) + Vector2(-10, -150)
		match p["kind"]:
			"leader":
				draw_string(ThemeDB.fallback_font, at + Vector2(-30, 0), "LEADER", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.85, 0.3))
			"patient":
				draw_string(ThemeDB.fallback_font, at, "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1, 0.2, 0.2))

# ---------------- back to the world map ----------------
func _hostiles_near(r: float) -> bool:
	for p in folk.people:
		if p["kind"] == "enemy" and p["pos"].distance_to(party) < r:
			return true
	return false

## Walk off the edge or press M: back to the world map, unless enemies are close (the original's
## own rule for its map MOVE feature).
func try_leave() -> void:
	if _hostiles_near(30.0):
		msg.text = NO_MOVE
		var back: Vector2 = (local.centre - party).normalized() * 1.5
		_move(back)
		moving = false
		return
	main.leave_local()

# ---------------- people and missions ----------------
func walk_to_person(p: Dictionary) -> void:
	var away: Vector2 = (party - p["pos"]).normalized() if party.distance_to(p["pos"]) > 0.1 else Vector2(0, 1)
	dest = p["pos"] + away * 1.6
	moving = true
	fast = false
	enter_target = {}
	person_target = p

func _alive() -> Array:
	return main.squad.filter(func(m): return int(m.get("wounds", 0)) < int(m["hits"]["CHEST"]))

## Best squad member at a skill (among those still standing): [recruit, level] or [].
func best(skill: String) -> Array:
	var top: Array = []
	for m in _alive():
		var lv := int(m["skills"].get(skill, 0.0))
		if top.is_empty() or lv > top[1]:
			top = [m, lv]
	return top

## Who can talk to someone speaking one of `langs`: [recruit, language] or [].
func speaker(langs: Array) -> Array:
	var top: Array = []
	for m in _alive():
		for l in langs:
			var lv := int(m["languages"].get(l, 0.0))
			if lv > 0 and (top.is_empty() or lv > top[2]):
				top = [m, l, lv]
	return top

func _spend(minutes: int) -> void:
	hour = fmod(hour + minutes / 60.0, 24.0)

func _line(key: String) -> String:
	return String(main.data.missions["lines"][key])

## Click on a person, now that the squad is standing next to them. The talk is a choice of
## things to do, each done by the squad member best at it ("[ERIKA JONES - MEDICAL 6] ...").
func interact(p: Dictionary) -> void:
	dialog.face = Portraits.person(p)
	dialog.squad = main.squad
	match p["kind"]:
		"leader":
			var sp := speaker(LEADER_LANGS)
			if sp.is_empty():
				_no_language(p, "POLISH")
				return
			var opts: Array = [["Ask about the mission", _leader_talk.bind(p, sp)]]
			var pe := best("PERSUASION")
			var m: Dictionary = main.campaign.mission
			if not m.is_empty() and m.get("target", "") == p["city"] and not m.has("haggled"):
				opts.append(["%s Ask for more in return (%d%%)" % [_tag(pe, "PERSUASION"), _pct(_chance(pe, 0.25, 0.08))], _haggle.bind(p, pe)])
			if main.vehicle_near(p["city"]) and main.vehicle_fuel < main.fuel_cap() and main.campaign.friends.has(p["city"]):
				opts.append(["Ask for fuel", func():
					main.refuel()
					dialog.say(["I'VE TAKEN THE LIBERTY OF REFUELING YOUR %s." % main.squad_vehicle], "LEADER OF " + p["city"])])
			opts.append(["Goodbye", func(): pass])
			dialog.choose(["%s %s." % [sp[0]["name"], _line("initiates")]], "LEADER OF " + p["city"], opts)
		"resident", "traveller":
			var langs: Array = TOWN_LANGS if p["kind"] == "resident" else TOWN_LANGS + ["RUSSIAN", "GERMAN", "ENGLISH"]
			var sp := speaker(langs)
			if sp.is_empty():
				_no_language(p, "POLISH")
				return
			var ob := best("OBSERVATION")
			var sc := best("SCROUNGING")
			var who: String = ("RESIDENT OF " + p["city"]) if p["kind"] == "resident" else String(group.get("name", "TRAVELLER"))
			var opts: Array = [
				["%s Ask what has been going on (%d%%)" % [_tag(ob, "OBSERVATION"), _pct(_chance(ob, 0.35, 0.07))], _rumour.bind(p, ob)],
				["%s Ask for anything they can spare (%d%%)" % [_tag(sc, "SCROUNGING"), _pct(_chance(sc, 0.2, 0.07))], _scrounge.bind(p, sc)],
				["Goodbye", func(): pass]]
			dialog.choose(["%s %s." % [sp[0]["name"], _line("initiates")]], who, opts)
		"suspect":
			var iq := best("INTERROGATION")
			var pe := best("PERSUASION")
			if p.get("cleared", false):
				dialog.say([_line("spy_denies")], "SUSPECT")
				return
			dialog.choose(["A NERVOUS-LOOKING CITIZEN OF %s." % p["city"]], "SUSPECT", [
				["%s Interrogate (%d%%, 15 min)" % [_tag(iq, "INTERROGATION"), _pct(_chance(iq, 0.3, 0.08))], interrogate.bind(p, iq)],
				["%s Talk round to the subject (%d%%, 15 min)" % [_tag(pe, "PERSUASION"), _pct(_chance(pe, 0.2, 0.08))], interrogate.bind(p, pe, 0.2)],
				["Leave", func(): pass]])
		"patient":
			var md := best("MEDICAL")
			dialog.choose(["%s" % ("A FEVERISH CITIZEN SHAKES ON THE GROUND." if main.campaign.mission.get("type", "") == "epidemic" else "A WOUNDED CITIZEN LIES BLEEDING.")], "PATIENT", [
				["%s Treat (%d%%, 20 min)" % [_tag(md, "MEDICAL"), _pct(_chance(md, 0.35, 0.07))], treat.bind(p, md)],
				["Leave", func(): pass]])
		"enemy":
			fight(p, "BLACK LEGION SOLDIER")
		"tank":
			fight(p, "TANK")
		"wreck":
			var cp: Campaign = main.campaign
			var v := cp.vehicle_model()
			if cp.enemies_in(here) > 0:
				dialog.say(["SCAVENGERS ARE STRIPPING THE %s. THEY WILL NOT LET ANYONE NEAR IT." % v], "THE DOWNED " + v)
				return
			var mc := best("MECHANIC")
			dialog.choose(["THE %s SITS IN THE MUD, ONE TRACK OFF AND THE ENGINE COLD." % v if v == "T-90" else "THE %s LIES ON ITS SIDE IN THE DITCH, THE ENGINE COLD." % v], "THE DOWNED " + v, [
				["%s Repair it (%d%%, 2 hours)" % [_tag(mc, "MECHANIC"), _pct(_chance(mc, 0.25, 0.08))], _repair.bind(p, mc)],
				["Leave it", func(): pass]])

## Mechanic: get the downed vehicle going; it is taken to the motor pool at Krakow.
func _repair(p: Dictionary, b: Array) -> void:
	_spend(120)
	if b.is_empty() or randf() >= _chance(b, 0.25, 0.08):
		dialog.say(["TWO HOURS OF WORK, AND THE ENGINE STILL WILL NOT TURN OVER. %s KEEPS AT IT." % (b[0]["name"] if not b.is_empty() else "THE SQUAD")], "MECHANIC")
		return
	folk.remove(p)
	dialog.say(["%s GETS THE ENGINE RUNNING." % b[0]["name"]] + main.campaign.repaired(main.leader), "EXOR 1", _mission_changed.bind(here))

## "[NAME - SKILL n]" for a choice label.
func _tag(b: Array, skill: String) -> String:
	if b.is_empty():
		return "[NOBODY]"
	return "[%s - %s %d]" % [b[0]["name"], skill, int(b[1])]

func _chance(b: Array, base: float, per: float) -> float:
	return clampf(base + per * (int(b[1]) if not b.is_empty() else 0), 0.05, 0.95)

func _pct(c: float) -> int:
	return int(round(c * 100.0))

func _leader_talk(p: Dictionary, sp: Array) -> void:
	_spend(randi_range(5, 15))
	dialog.say(main.campaign.talk_leader(p["city"], main.leader), "LEADER OF " + p["city"], _mission_changed.bind(p["city"]))

## Persuasion: the leader adds something to the reward (once per mission).
func _haggle(p: Dictionary, b: Array) -> void:
	_spend(10)
	main.campaign.mission["haggled"] = true
	if not b.is_empty() and randf() < _chance(b, 0.25, 0.08):
		var extra: String = main.campaign._reward()
		main.campaign.mission["reward2"] = extra
		dialog.say(["%s MAKES THE CASE WELL. THE LEADER WILL ADD %s TO THE REWARD." % [b[0]["name"], extra]], "LEADER OF " + p["city"])
	else:
		dialog.say(["THE LEADER WILL NOT GIVE MORE THAN WAS PROMISED."], "LEADER OF " + p["city"])

## Observation: what the people have seen - a pointer for the mission.
func _rumour(p: Dictionary, b: Array) -> void:
	_spend(10)
	var cp: Campaign = main.campaign
	if b.is_empty() or randf() >= _chance(b, 0.35, 0.07):
		dialog.say([_line("not_interested")], "RESIDENT")
		return
	var st := cp.step()
	var line := "NOTHING MUCH HAPPENS HERE. PEOPLE TRY TO GET THROUGH THE WINTER."
	if st != "":
		var c := cp.place(st)
		if st.begins_with("clear:"):
			line = "THE BLACK LEGION? %d OF THEM WERE SEEN IN %s." % [cp.enemies_in(c), c]
		elif st.begins_with("spy:"):
			line = "ONE OF THE PEOPLE WALKING ABOUT %s KEEPS MEETING STRANGERS AFTER DARK." % c
		elif st.begins_with("treat:"):
			line = "THERE ARE STILL %d WHO NEED A DOCTOR IN %s." % [int(cp.mission["patients"]), c]
		elif st.begins_with("search:"):
			line = "THE CRATES WERE CARRIED INTO ONE OF THE BUILDINGS OF %s." % c
		elif st.begins_with("talk:"):
			line = "THE LEADER OF %s IS EXPECTING SOMEONE FROM KRAKOW." % c
	dialog.say(["%s LISTENS CAREFULLY: \"%s\"" % [b[0]["name"], line]], "RESIDENT")

## Scrounging: a small find for Krakow's stores, once per person.
func _scrounge(p: Dictionary, b: Array) -> void:
	_spend(15)
	if p.get("asked", false) or b.is_empty() or randf() >= _chance(b, 0.2, 0.07):
		p["asked"] = true
		dialog.say([_line("nothing_to_say")], "RESIDENT")
		return
	p["asked"] = true
	var finds := ["BASIC TOOLS", "FLASHLIGHT", "PERSONAL MEDICAL KIT", "PAIN RELIEVER", "ANTIBIOTIC", "7.62MM S", "5.56MM N"]
	var it: String = finds[randi_range(0, finds.size() - 1)]
	main.campaign.stores.append(it)
	dialog.say(["%s TRADES A FEW CIGARETTES FOR %s (TO THE STORES AT KRAKOW)." % [b[0]["name"], it]], "RESIDENT")

func _no_language(p: Dictionary, lang: String) -> void:
	var m: Dictionary = _alive()[0] if not _alive().is_empty() else main.squad[0]
	dialog.say(["%s %s %s %s." % [m["name"], _line("speaking"), lang, _line("no_translator")]], p["city"])

## The mission moved on: people of the city change (soldiers appear, the sick are cured...).
func _mission_changed(city: String) -> void:
	if main.campaign.victory:
		main.set_music("VICT2")
	for c in main.data.cities:
		if folk.spawned.has(c["name"]):
			folk.spawn(c)
	refresh_target()

func _arrived_in(city: String) -> void:
	if city == "KRAKOW":
		for m in main.squad:
			m["wounds"] = 0                       # the medics at HQ patch everybody up
	var lines: Array = main.campaign.arrived(city, main.leader)
	dialog.squad = main.squad
	if not lines.is_empty():
		dialog.say(lines, "EXOR 1", _mission_changed.bind(city))

## Interrogation of a suspect (spy missions), with the original lines.
func interrogate(p: Dictionary, b: Array = [], base := 0.3) -> void:
	if b.is_empty():
		b = best("INTERROGATION")
	if b.is_empty():
		return
	var name: String = b[0]["name"]
	_spend(15)
	if p.get("cleared", false):
		dialog.say([_line("spy_denies")], "SUSPECT")
		return
	var ok := randf() < _chance(b, base, 0.08)
	if main.campaign.is_spy(int(p["index"])):
		if ok:
			dialog.say([_line("spy_found"), _line("spy_fight")], name, fight.bind(p, "SPY"))
		else:
			dialog.say([_line("spy_unsure") % name + "  " + _line("spy_not_good") + _line("spy_best")], name)
	else:
		if ok:
			p["cleared"] = true
			dialog.say([_line("spy_denies"), _line("spy_innocent") % ["", name]], "SUSPECT")
		else:
			dialog.say([_line("spy_unsure") % name + "  " + _line("spy_not_good") + _line("spy_best")], name)

## Treating a wounded or sick citizen with the squad's best Medical skill.
func treat(p: Dictionary, b: Array = []) -> void:
	if b.is_empty():
		b = best("MEDICAL")
	if b.is_empty():
		return
	# the time it took to get here: the town may have fewer patients left alive than lie about
	main.campaign.tick()
	var lying := folk.people.filter(func(x): return x["kind"] == "patient" and x["city"] == here)
	if lying.size() > int(main.campaign.mission.get("patients", 0)):
		folk.remove(p)
		dialog.say(["THE PATIENT DIED BEFORE %s COULD HELP." % b[0]["name"]], b[0]["name"], refresh_target)
		return
	_spend(20)
	if randf() < _chance(b, 0.35, 0.07):
		p["kind"] = "resident"
		var finished: bool = main.campaign.patient_treated()
		dialog.say(["%s TREATS THE PATIENT, WHO WILL LIVE." % b[0]["name"]] + (["ALL THE PATIENTS ARE CARED FOR. REPORT TO THE LEADER."] if finished else []), b[0]["name"], refresh_target)
	else:
		dialog.say(["20 MINUTES OF TREATMENT DOESN'T HELP. %s TRIES AGAIN LATER." % b[0]["name"]], b[0]["name"])

## A fight starts the turn-based battle on this ground (the battle screen).
func fight(p: Dictionary, what: String) -> void:
	if what == "SPY":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var t: Dictionary = Forces.group("MARAUDERS", 1, rng)["men"][0]
		t["name"] = "THE SPY"
		t["gear"]["weapon"] = "PM MAKAROV"
		main.start_battle({"local": local, "town": town, "centre": p["pos"], "from": party - p["pos"], "men": [t],
			"back": "town", "city": here, "spy": true, "title": "THE SPY IN " + here})
	elif mode == "encounter":
		main.battle_from_encounter(group)
	else:
		main.battle_in_town(here, party)

# ---------------- the bottom icon bar (the original's "2-D Ground Icons", manual p.55) ----------------
## The ten icons in the original order; the numbers pick them straight from the keyboard.
func _bar_def() -> Array:
	return [
		{"key": "1", "label": "NECESSITY", "cb": _icon_necessity},
		{"key": "2", "label": "OPTIONS", "cb": _icon_options},
		{"key": "3", "label": "RADIO", "cb": _icon_radio},
		{"key": "4", "label": "INVENTORY", "cb": _icon_inventory},
		{"key": "5", "label": "COMBAT", "cb": _icon_combat},
		{"key": "6", "label": "TALK", "cb": _icon_talk},
		{"key": "7", "label": "TAKE", "cb": _icon_take},
		{"key": "8", "label": "USE", "cb": _icon_use},
		{"key": "9", "label": "MAP", "cb": _icon_map},
		{"key": "0", "label": "LOOK", "cb": _icon_look},
	]

func _icon_necessity() -> void:
	actionbar.choose("NECESSITY", [
		["Fish (1 h)", _survive.bind("FISHING", 0.30, 60, "FISH", "WITH SOME FISH", 2)],
		["Forage (1 h)", _survive.bind("FORAGING", 0.35, 60, "FORAGE", "WITH BERRIES AND ROOTS", 3)],
		["Hunt (2 h)", _survive.bind("RIFLE", 0.25, 120, "HUNT", "WITH HIS KILL", 4)],
		["Sleep 8 hours", _sleep],
	])

## FISH / FORAGE / HUNT on the original's own lines (TWI2D): "YOU SPEND A FEW HOURS
## %sING." + "AFTER ... , %s COMES BACK %s." / "... EMPTY HANDED." The hour word is a
## small splice of the original's fixed "AFTER FOUR HOURS" (fishing takes an hour here).
func _survive(skill: String, base: float, minutes: int, activity: String, found: String, rations: int) -> void:
	actionbar.close_choices()
	_spend(minutes)
	var hour := "FOUR HOURS" if minutes >= 240 else "%d HOURS" % (minutes / 60)
	if minutes == 60:
		hour = "AN HOUR"
	var b := best(skill)
	var who: String = b[0]["name"] if not b.is_empty() else "SOMEBODY"
	var ok := not b.is_empty() and randf() < _chance(b, base, 0.06)
	if ok:
		main.campaign.add_food(rations)
		dialog.say(["YOU SPEND A FEW HOURS %sING.\nAFTER %s, %s COMES BACK %s (%d RATIONS)." % [activity, hour, who, found, rations]], who)
	else:
		dialog.say(["YOU SPEND A FEW HOURS %sING.\nAFTER %s, %s COMES BACK EMPTY HANDED." % [activity, hour, who]], who)

## SLEEP: 8 hours pass for the whole campaign clock, the squad heals per the tabletop's rule.
## M9 economy round 2: every soldier needs one field ration per 8-hour sleep; hungry
## soldiers pay an initiative/aim penalty in the next battle.
func _sleep() -> void:
	actionbar.close_choices()
	var res: Dictionary = main.campaign.feed(main.squad.size())
	var hungry_i := 0
	for r in main.squad:
		if r.get("dead", false):
			continue
		if hungry_i < int(res["hungry"]):
			r["hungry"] = true
			hungry_i += 1
		else:
			r["hungry"] = false
	var food_line := ""
	if int(res["fed"]) > 0:
		food_line = "THE SQUAD EATS %d RATION(S)." % int(res["fed"])
	if int(res["hungry"]) > 0:
		food_line = (food_line + "  " if food_line != "" else "") + "%d MAN(S) GO HUNGRY." % int(res["hungry"])
	var lines := Healing.rest(main.squad, 8.0, mode == "town", false, main.difficulty == "story")
	if food_line != "":
		lines.insert(0, food_line)
	dialog.face = []
	dialog.squad = main.squad
	main.world.minutes += 480.0
	dialog.say(lines, "THE SQUAD")

func _icon_options() -> void:
	actionbar.choose("GAME OPTIONS", [
		["Save game", func():
			actionbar.close_choices()
			msg.text = "GAME SAVED." if main.save_game(main.QUICKSAVE) else "COULD NOT SAVE."],
		["Load game", func():
			actionbar.close_choices()
			if not main.load_game(main.QUICKSAVE):
				msg.text = "NO SAVED GAME."],
		["Sound on / off", func():
			actionbar.close_choices()
			msg.text = "SOUND %s." % ("ON" if main.toggle_sound() else "OFF")],
		["Quit", func():
			actionbar.close_choices()
			get_tree().quit()],
	])

## The walkie-talkie in the field: the mission's next step straight from Exor 1.
func _icon_radio() -> void:
	dialog.face = Portraits.exor()
	dialog.squad = main.squad
	var st: String = main.campaign.step()
	if st == "":
		dialog.say(["NO MISSION GOES ON AT THE MOMENT. THE NEXT ONE COMES FROM THE OFFICE AT KRAKOW."], "EXOR 1")
	else:
		dialog.say(["%s" % main.campaign.objective_text()], "EXOR 1")

## The character sheets, read-only: wounds, health and what each member carries.
func _icon_inventory() -> void:
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
	# The original Inventory icon has INFO/DESCRIPTION choices: read the long text of a
	# carried item (the game's own EQUIP.TXT, extracted to data/EQUIP.json).
	var opts: Array = []
	for nm in gear_names:
		opts.append(["DESCRIPTION - %s" % nm, _show_item_description.bind(String(nm))])
	opts.append(["CLOSE", func(): pass])
	dialog.face = []
	dialog.squad = main.squad
	dialog.choose(lines, "THE SQUAD", opts)

## Show the original long description of a gear item, or a plain refusal if none exists.
func _show_item_description(item_name: String) -> void:
	var desc: String = main.data.item_description(item_name)
	if desc == "":
		desc = "NO DESCRIPTION IS AVAILABLE FOR %s." % item_name.to_upper()
	dialog.face = []
	dialog.squad = main.squad
	dialog.say([desc], item_name.to_upper())

func _icon_combat() -> void:
	var en := {}
	var dist := 40.0
	for p in folk.people:
		var d: float = p["pos"].distance_to(party)
		if d < dist and p["kind"] in ["enemy", "tank"]:
			en = p
			dist = d
	if en.is_empty():
		msg.text = "No enemy in sight."
		return
	var what: String = "TANK" if en["kind"] == "tank" else "BLACK LEGION SOLDIER"
	actionbar.choose("COMBAT", [
		["Aggressive", func():
			fight(en, what)],
		["Tactical", func():
			fight(en, what)],
		["Retreat", func():
			actionbar.close_choices()
			try_leave()],
	])

func _icon_talk() -> void:
	var near := {}
	var best_d := 5.0
	for p in folk.people:
		var d: float = p["pos"].distance_to(party)
		if d < best_d and p["kind"] not in ["enemy", "tank"]:
			near = p
			best_d = d
	if near.is_empty():
		msg.text = "Nobody within earshot."
		return
	walk_to_person(near)

## TAKE: on a search mission, search the building the leader faces for the mission's crates.
## Otherwise pick up anything at the leader's feet (dropped gear, crates).
func _icon_take() -> void:
	var st: String = main.campaign.step()
	if st.begins_with("search:"):
		var front: Vector2 = party + DIRS[clampi(squad[clampi(main.leader_index, 0, squad.size() - 1)].dir, 0, 7)] * 2.5
		var b := town.door_at(front, 5.0)
		if b.is_empty():
			b = town.blocking(front, 0.0)
		if not b.is_empty():
			var line := _search(b)
			if line != "":
				msg.text = line
			else:
				msg.text = "The building is empty here."
		else:
			msg.text = "No building within reach."
		return
	# not a search mission: nothing lie around to pick up in the field view
	msg.text = "Nothing here can be picked up."

## USE: use a medical kit on the most wounded awake squad member, or treat a wounded
## person the leader faces. No gear is consumed from the recruit's inventory here -
## the battle's first-aid path handles medkits during combat; this is the between-mission
## patch-up: the squad medic stops bleeding and bandages wounds at the cost of time.
func _icon_use() -> void:
	var st: String = main.campaign.step()
	if st.begins_with("treat:"):
		msg.text = "Use SLEEP (icon 1) to rest and heal, or go to the wounded in the town buildings."
		return
	var best: Dictionary = {}
	var worst: float = 0.0
	for r in main.squad:
		if r.get("dead", false) or bool(r.get("hungry", false)) and int(r.get("bleed", 0)) <= 0:
			continue
		var dmg: Dictionary = r.get("dmg", {})
		var hits: Dictionary = r.get("hits", {})
		var loc_worst := 0.0
		for l in ["HEAD", "CHEST", "ABDOMEN", "LEFT ARM", "RIGHT ARM", "LEFT LEG", "RIGHT LEG"]:
			var v := float(dmg.get(l, 0)) / maxf(1.0, float(hits.get(l, 10)))
			if v > loc_worst:
				loc_worst = v
		var bleed := float(r.get("bleed", 0))
		var sev := loc_worst + (0.5 if bleed > 0 else 0.0)
		if sev > worst and sev > 0.0:
			worst = sev
			best = r
	if not best.is_empty():
		var meds := int(best.get("medkits", 0))
		if meds > 0:
			best["medkits"] = meds - 1
			best["bleed"] = 0
			for l in best.get("dmg", {}).keys():
				best["dmg"][l] = maxi(0, int(best["dmg"][l]) - int(best["attrs"].get("CONSTITUTION", 5) / 3))
			msg.text = "%s PATCHES UP %s WITH A MEDICAL KIT." % [best["name"], best["name"]]
		else:
			msg.text = "%S HAS NO MEDICAL KITS." % [best["name"]]
	else:
		msg.text = "No wounded to treat."

func _icon_map() -> void:
	lcd.visible = not lcd.visible

## What stands in front of the leader: a person, a building, a tree, or open ground.
func _icon_look() -> void:
	var dir: Vector2 = DIRS[clampi(squad[clampi(main.leader_index, 0, squad.size() - 1)].dir, 0, 7)]
	var front: Vector2 = party + dir * 2.5
	var who := folk.at(front, 2.5)
	if not who.is_empty():
		var t: String = {
			"leader": "A LEADER OF THE RESISTANCE STANDS IN FRONT OF THE SQUAD.",
			"resident": "A RESIDENT OF THE TOWN, GOING ABOUT THE DAY.",
			"traveller": "A TRAVELLER, ROPED TOGETHER WITH OTHERS ON THE ROAD.",
			"patient": "A SICK PERSON SHAKES ON THE GROUND HERE.",
			"suspect": "A NERVOUS-LOOKING CITIZEN, EYEING THE CORNERS.",
			"enemy": "A BLACK LEGION SOLDIER, ARMED AND WATCHING.",
			"tank": "A TANK OF THE BLACK LEGION, ENGINE IDLING.",
			"wreck": "THE SQUAD'S LOST VEHICLE, COLD IN THE MUD.",
		}.get(String(who["kind"]), "SOMEBODY STANDS HERE.")
		msg.text = t
		return
	var b := town.door_at(front, 5.0)
	if b.is_empty():
		b = town.blocking(front, 0.0)
	if not b.is_empty():
		msg.text = "A %s. %s" % [String(b["type"]).to_lower(), INSIDE.get(b["type"], "")]
		return
	if local.blocking(front):
		msg.text = "Trees and brush; the way is blocked."
		return
	if local.in_river(front):
		msg.text = "A river runs through."
	elif local.on_road(front):
		msg.text = "The road passes here."
	else:
		msg.text = "Open ground."

# in DIRS order (the Soldier's compass): the world direction each index stands for
const DIRS := [Vector2(0, -1), Vector2(0.7, -0.7), Vector2(1, 0), Vector2(0.7, 0.7), Vector2(0, 1), Vector2(-0.7, 0.7), Vector2(-1, 0), Vector2(-0.7, -0.7)]

# ---------------- test hooks ----------------
## Tests: go straight into another town (as if the squad had marched there on the map).
## Tests: the camera over the town centre at a zoom (the party stands there for the picture).
func test_overview(z: float) -> void:
	var c: Vector2 = main.local.get("centre", party)
	pa = c.x
	pb = c.y
	cam.zoom = Vector2.ONE * z
	queue_redraw()

func test_teleport(city: String) -> void:
	main.enter_town(city)

func test_talk_leader() -> void:
	for p in folk.people:
		if p["kind"] == "leader" and p["city"] == here:
			_test_step_next_to(p)
			return

## Tests skip the walk: stand two metres away, then the usual walk-up and interaction.
func _test_step_next_to(p: Dictionary) -> void:
	party = p["pos"] + Vector2(0, 2.0)
	walk_to_person(p)

## Do whatever the current step needs in this city, one person at a time.
func test_work() -> void:
	if main.campaign.step().begins_with("search:"):
		for b in town.buildings.filter(func(x): return x["city"] == here):
			var line := _search(b)
			if line != "":
				print("[test] search: ", line)
				refresh_target()
				return
		return
	var hd := hideout()
	if not hd.is_empty():
		walk_to_door(hd)
		return
	for kind in ["enemy", "tank", "patient", "suspect", "wreck"]:
		for p in folk.people:
			if p["kind"] == kind and p["city"] == here and not p.get("cleared", false):
				_test_step_next_to(p)
				return

## Tests: walk up to the first person of a kind in this place (no choice taken yet).
func test_meet(kind: String) -> void:
	for p in folk.people:
		if p["kind"] == kind:
			_test_step_next_to(p)
			return

func test_pick(i: int) -> void:
	dialog.pages.clear()
	if dialog.waiting_choice() or not dialog.choices.is_empty():
		dialog.pick_index(i)

## Tests: read through, take the first choice (the main thing to do) and read its result.
func test_close_dialog() -> void:
	for i in range(4):
		if dialog.waiting_choice() or (not dialog.pages.is_empty() and not dialog.choices.is_empty()):
			dialog.pages.clear()
			dialog.pick_index(0)
		dialog.pages.clear()
		if not dialog.choices.is_empty():
			continue
		dialog.flush()
		break

## One move of a scripted mission run: go to the objective city, then do what the step needs.
func test_auto() -> void:
	var cp: Campaign = main.campaign
	if cp.mission.is_empty():
		print("[test] mission done; stores: ", cp.stores)
		return
	# a player would not send a badly hurt squad back in: rest first (as at Krakow's hospital)
	for r in main.squad:
		if Healing.condition(r).begins_with("CRITICAL") or Healing.condition(r).begins_with("SERIOUSLY"):
			Healing.rest(main.squad, 24.0, true, true, main.difficulty == "story")
			print("[test] the squad rests and heals")
			return
	var st := cp.step()
	var c := cp.place(st)
	if here != c:
		test_teleport(c)
		print("[test] -> ", c, " for ", st)
		return
	if st.begins_with("talk:"):
		test_talk_leader()
	else:
		test_work()
	print("[test] ", st, " in ", c, " : ", cp.objective_text())
