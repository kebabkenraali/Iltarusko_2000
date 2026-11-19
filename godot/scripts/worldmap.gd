## World map: the original terrain (WORLD/worldmap.png, drawn from DW_GFY.UYB with the LCD
## mapper's own road and river shapes) at 16 px per km. Click a place to see the route and the
## walking time; click again to go. Time runs as the squad marches; trouble can come on the
## way (the original "AFTER %s OF %s, YOU RUN INTO TROUBLE FROM THE %s."), and towns are entered
## from the map. Wheel zooms, right-drag pans, C centres on the squad. With a vehicle the squad
## drives (World.DRIVE: roads and bridges for wheels, anywhere but rivers for tracks), burning
## fuel by the hour; V parks it and goes on foot, or boards it again where it stands.
extends Node2D

var main: Node
var world: World
const CELL := 16.0

var map_sprite: Sprite2D
var fog_sprite: Sprite2D
var fog_img: Image
var cam: Camera2D
var hover := Vector2i(-1, -1)
var hover_path: Array = []
var path: Array = []                  # route being walked (cells)
var walk_i := 0
var walk_t := 0.0
var walked_min := 0.0                 # minutes since the march began (for the trouble text)
var dragging := false
var hud: Label
var place_lbl: Label
var obj_lbl: Label
var panel: Panel
var panel_text: Label
var panel_buttons: HBoxContainer
var panel_pic: TextureRect
var test_risk := ""                   # tests: "none", "trap" or "ambush" instead of the dice
var czarny := Vector2.ZERO
var squad_lbl: Label
const MARCH_SPEED := 7.0              # cells (km) per real second while marching
const DRIVE_SPEED := 14.0             # ... and while driving

func _ready() -> void:
	world = main.world
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	cam.zoom = Vector2.ONE * 0.9
	map_sprite = Sprite2D.new()
	map_sprite.texture = load("res://original/graphics/WORLD/worldmap.png")
	map_sprite.centered = false
	map_sprite.z_index = -2
	add_child(map_sprite)
	fog_img = Image.create(world.w, world.h, false, Image.FORMAT_RGBA8)
	fog_sprite = Sprite2D.new()
	fog_sprite.centered = false
	fog_sprite.scale = Vector2.ONE * CELL
	fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fog_sprite.z_index = -1
	add_child(fog_sprite)
	_update_fog()
	var cz: Dictionary = main.data.city("CHECINY")
	czarny = world.city_cell(cz) if not cz.is_empty() else Vector2(-999, -999)
	_build_ui()
	cam.position = world.pos * CELL
	_refresh_hud()

# ---------------- UI ----------------
func _label(parent: Node, at: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var top := ColorRect.new()
	top.color = Color(0.05, 0.04, 0.03, 0.75)
	top.size = Vector2(1280, 92)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top)
	hud = _label(ui, Vector2(16, 8), 22, Color(1, 0.85, 0.45))
	place_lbl = _label(ui, Vector2(16, 38), 18, Color(0.9, 0.9, 0.8))
	obj_lbl = _label(ui, Vector2(16, 62), 17, Color(1, 0.6, 0.4))
	var help := _label(ui, Vector2(860, 12), 14, Color(0.75, 0.75, 0.7))
	help.text = "Click: plan route / go   Wheel: zoom   V: drive / park\nRight-drag: pan   C: centre   Esc: stop   R: rest 8 h"
	var sqbg := ColorRect.new()
	sqbg.color = Color(0.05, 0.04, 0.03, 0.7)
	sqbg.position = Vector2(0, 92)
	sqbg.size = Vector2(470, 130)
	sqbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(sqbg)
	squad_lbl = _label(ui, Vector2(16, 96), 15, Color(0.95, 0.95, 0.85))
	panel = Panel.new()
	panel.position = Vector2(290, 470)
	panel.size = Vector2(700, 300)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.02, 0.94)
	sb.border_color = Color(0.6, 0.12, 0.08)
	sb.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	ui.add_child(panel)
	panel_text = _label(panel, Vector2(20, 16), 19, Color(1, 0.45, 0.35))
	panel_text.size = Vector2(660, 210)
	panel_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_pic = TextureRect.new()                 # a picture beside the text (a wreck)
	panel_pic.position = Vector2(470, 20)
	panel_pic.size = Vector2(210, 200)
	panel_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	panel_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_child(panel_pic)
	panel_buttons = HBoxContainer.new()
	panel_buttons.position = Vector2(20, 240)
	panel_buttons.add_theme_constant_override("separation", 12)
	panel.add_child(panel_buttons)

func _ask(text: String, buttons: Array, picture := "") -> void:
	panel_text.text = text
	panel_pic.texture = load(picture) if picture != "" and ResourceLoader.exists(picture) else null
	panel_text.size.x = 440.0 if panel_pic.texture else 660.0
	for c in panel_buttons.get_children():
		c.queue_free()
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(150, 40)
		btn.pressed.connect(func(): panel.visible = false; b[1].call())
		panel_buttons.add_child(btn)
	panel.visible = true

func _refresh_hud() -> void:
	hud.text = world.date_text() + "     SEASON: " + {"F": "AUTUMN", "W": "WINTER", "P": "SPRING", "S": "SUMMER"}[world.season()]
	place_lbl.text = describe(world.pos)
	obj_lbl.text = main.campaign.objective_text()
	var lines: Array = []
	for r in main.squad:
		lines.append("%s%s  %s" % ["* " if r == main.squad[main.leader_index] else "  ", r["name"], Healing.condition(r)])
	if main.fuel_cans > 0.0:
		lines.append("JERRYCANS: %d L" % int(main.fuel_cans))
	if main.squad_vehicle != "":
		lines.append("%s  FUEL %d/%d L  %s" % [main.squad_vehicle, int(ceil(main.vehicle_fuel)), int(main.fuel_cap()),
			"DRIVING" if main.driving() else "PARKED: " + describe(main.vehicle_at)])
	squad_lbl.text = "\n".join(lines)

## "FOREST, 3 KM SOUTHWEST OF SKAWINA" / "IN KRAKOW".
func describe(p: Vector2) -> String:
	var best: Dictionary = {}
	var bd := 1e9
	for c in main.data.cities:
		if int(c["size"]) > 4:
			continue
		var d: float = world.city_cell(c).distance_to(p)
		if d < bd:
			bd = d
			best = c
	var names := {"G": "OPEN COUNTRY", "F": "FOREST", "R": "ROAD", "B": "BRIDGE", "T": "TOWN", "V": "RIVER", "W": "WATER", "X": "COUNTRY"}
	var t: String = names.get(world.at(Vector2i(int(p.x), int(p.y))), "COUNTRY")
	if bd < 1.5:
		return "IN " + String(best["name"])
	var dv: Vector2 = p - world.city_cell(best)
	var dirs := ["EAST", "SOUTHEAST", "SOUTH", "SOUTHWEST", "WEST", "NORTHWEST", "NORTH", "NORTHEAST"]
	var k := int(round(atan2(dv.y, dv.x) / (PI / 4.0))) % 8
	if k < 0:
		k += 8
	return "%s, %d KM %s OF %s" % [t, int(round(bd)), dirs[k], best["name"]]

func _update_fog() -> void:
	for y in range(world.h):
		for x in range(world.w):
			fog_img.set_pixel(x, y, Color(0.02, 0.02, 0.02, 0.0 if world.explored[y * world.w + x] == 1 else 0.5))
	fog_sprite.texture = ImageTexture.create_from_image(fog_img)

# ---------------- input ----------------
func _unhandled_input(ev: InputEvent) -> void:
	if not main.input_ok(ev):
		return
	if ev is InputEventMouseMotion:
		if dragging:
			cam.position -= ev.relative / cam.zoom
		var c := _cell_at(get_global_mouse_position())
		if c != hover and path.is_empty():
			hover = c
			hover_path = world.route(c, mode())
			queue_redraw()
	elif ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			dragging = ev.pressed
		elif ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var z := cam.zoom.x * (1.15 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
			cam.zoom = Vector2.ONE * clampf(z, 0.45, 3.0)
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not panel.visible:
			go_to(_cell_at(get_global_mouse_position()))
	elif ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_C: cam.position = world.pos * CELL
			KEY_ESCAPE: path = []
			KEY_R: rest()
			KEY_V: toggle_vehicle()

func _cell_at(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))

## "foot", or the vehicle's kind while the squad drives.
func mode() -> String:
	return main.vehicle_kind() if main.driving() else "foot"

## V: park the vehicle and go on foot, or board it again (the squad must stand by it).
func toggle_vehicle() -> void:
	if not path.is_empty() or panel.visible:
		return
	if main.squad_vehicle == "":
		main.toast("THE SQUAD HAS NO VEHICLE.")
	elif main.driving():
		main.vehicle_at = world.pos
		main.toast("THE %s IS PARKED. THE SQUAD GOES ON FOOT." % main.squad_vehicle)
	elif world.pos.distance_to(main.vehicle_at) > 1.0:
		main.toast("THE %s IS PARKED: %s." % [main.squad_vehicle, describe(main.vehicle_at)])
	else:
		var poured: float = main.pour_cans()
		if main.vehicle_fuel <= 0.0:
			main.toast("YOUR VEHICLE IS OUT OF FUEL.")
		else:
			main.vehicle_at = Vector2(-1, -1)
			main.toast(("THE SQUAD POURS %d L INTO THE TANK AND BOARDS THE %s." % [int(poured), main.squad_vehicle]) if poured > 0.0
				else "THE SQUAD BOARDS THE %s." % main.squad_vehicle)
	hover_path = []
	hover = Vector2i(-1, -1)
	_refresh_hud()
	queue_redraw()

## Start marching (or driving) to a cell (click, or a test).
func go_to(c: Vector2i) -> void:
	var r := world.route(c, mode())
	if r.is_empty():
		var town := _town_at(world.pos)
		if not town.is_empty() and world.cell() == c:
			_offer_town(town)
		return
	path = r
	walk_i = 1
	walk_t = 0.0
	walked_min = 0.0
	queue_redraw()

func go_to_city(name: String) -> void:
	var c: Dictionary = main.data.city(name)
	if not c.is_empty():
		var p := world.city_cell(c)
		go_to(Vector2i(int(p.x), int(p.y)))

func _town_at(p: Vector2) -> Dictionary:
	for c in main.data.cities:
		if int(c["size"]) <= 4 and world.city_cell(c).distance_to(p) < 1.6:
			return c
	return {}

func _offer_town(c: Dictionary) -> void:
	var buttons: Array = [["ENTER " + String(c["name"]), func(): main.enter_town(c["name"])]]
	if c["name"] == "KRAKOW":
		buttons.append(["REPORT TO HQ", func(): main.show_office()])
	buttons.append(["STAY ON THE MAP", func(): pass])
	_ask("YOU REACH %s.  %s" % [c["name"], main.campaign.objective_text() if main.campaign.objective_city() == c["name"] else ""], buttons)

# ---------------- marching ----------------
func _process(delta: float) -> void:
	if path.is_empty() or panel.visible:
		return
	var drive: bool = main.driving()
	walk_t += delta * (DRIVE_SPEED if drive else MARCH_SPEED)
	while walk_t >= 1.0 and walk_i < path.size():
		walk_t -= 1.0
		var prev: Vector2i = path[walk_i - 1]
		var c: Vector2i = path[walk_i]
		var mins: float = world.step_minutes(prev, c, mode())
		world.minutes += mins
		walked_min += mins
		world.pos = Vector2(c) + Vector2(0.5, 0.5)
		world.reveal(c, 4 if drive else 3)
		walk_i += 1
		if drive:
			main.vehicle_fuel -= main.fuel_per_hour() * mins / 60.0
			if main.vehicle_fuel <= 0.0:
				_out_of_fuel()
				break
		var wr: Dictionary = world.check_wreck(func(v): return Forces.vehicle_data(v).get("fuel_cap", 0)) if wrecks_on() else {}
		if not wr.is_empty():
			path = []
			_update_fog()
			_wreck(wr)
			break
		var g := world.check_trouble(main.data.cities, czarny, 0.5 if drive else 1.0)
		if not g.is_empty():
			path = []
			_update_fog()
			_trouble(g)
			break
		if walk_i >= path.size():
			path = []
			_update_fog()
			var town := _town_at(world.pos)
			if not town.is_empty():
				_offer_town(town)
	if not path.is_empty():
		# smooth marker between cells
		var a: Vector2 = Vector2(path[walk_i - 1]) + Vector2(0.5, 0.5)
		var b: Vector2 = Vector2(path[mini(walk_i, path.size() - 1)]) + Vector2(0.5, 0.5)
		world.pos = a.lerp(b, walk_t)
	cam.position = cam.position.lerp(world.pos * CELL, 0.12)
	_refresh_hud()
	queue_redraw()

## Wrecks by the way are a story mode find only.
func wrecks_on() -> bool:
	return main.difficulty == "story"

## A wrecked vehicle by the way: drain what fuel is left in it (half an hour), or move on.
## A wreck is never safe: it may be bait for an ambush, or wired with a booby trap.
func _wreck(wr: Dictionary) -> void:
	var v := Forces.vehicle_data(wr["vehicle"])
	var doing := "DRIVING" if main.driving() else "MARCHING AND RESTING"
	var txt := "AFTER %s OF %s, YOU COME ACROSS A WRECKED %s (%s)." % [World.span_text(walked_min), doing, wr["vehicle"], describe(world.pos)]
	_ask(txt, [["DRAIN THE FUEL", _siphon.bind(wr)], ["MOVE ON", func(): pass]],
		"res://original/graphics/BUILDING/%s_rgba.png" % String(v.get("enemy_wreck" if randf() < 0.5 else "wreck", "DV1")))

## The best at spotting traps goes first: COMBAT ENGINEER or OBSERVATION.
func _searcher() -> Dictionary:
	var best: Dictionary = {}
	var bl := -1
	for r in main.squad:
		var l := maxi(int(r["skills"].get("COMBAT ENGINEER", 0.0)), int(r["skills"].get("OBSERVATION", 0.0)))
		if l > bl:
			bl = l
			best = r
	return best

func _siphon(wr: Dictionary) -> void:
	world.minutes += 30.0
	var lines: Array = []
	var who := _searcher()
	var lvl := maxi(int(who["skills"].get("COMBAT ENGINEER", 0.0)), int(who["skills"].get("OBSERVATION", 0.0)))
	# the risks: an ambush (15%), else a trap (35%) that the searcher may find first
	var ambush := randf() < 0.15
	var trapped := not ambush and randf() < 0.35
	var spotted := trapped and randf() < minf(0.85, 0.3 + 0.1 * lvl)
	if test_risk != "":
		ambush = test_risk == "ambush"
		trapped = test_risk == "trap"
		spotted = false
	if ambush:
		var g: Dictionary = World.GROUPS[0].duplicate() if world.pos.distance_to(czarny) < 25.0 else World.GROUPS[1].duplicate()
		g["count"] = randi_range(int(g["min"]), int(g["max"]))
		g["terrain"] = world.at(world.cell())
		g["cell"] = world.cell()
		_ask("AS %s REACHES THE %s, SHOTS RING OUT FROM COVER. THE WRECK WAS BAIT: AN AMBUSH BY THE %s." % [who["name"], wr["vehicle"], g["name"]],
			[["FIGHT", func(): main.battle_from_encounter(g)]])
		return
	if spotted:
		lines.append("%s FINDS A GRENADE WIRED TO THE FUEL CAP AND DISARMS IT." % who["name"])
	elif trapped:
		lines.append_array(_booby_trap(who, wr))
		_refresh_hud()
		_ask("  ".join(lines), [["CONTINUE", func(): pass]])
		return
	if wr["burnt"]:
		lines.append("THE %s HAS BURNT OUT. THERE IS NO FUEL LEFT IN IT." % wr["vehicle"])
	elif float(wr["fuel"]) <= 0.0:
		lines.append("THE TANKS OF THE %s ARE DRY." % wr["vehicle"])
	else:
		var got: Array = main.take_fuel(float(wr["fuel"]))
		lines.append("THE SQUAD DRAINS %d L OF FUEL FROM THE %s." % [int(wr["fuel"]), wr["vehicle"]])
		if got[0] > 0.0:
			lines.append("%d L GO INTO THE %s." % [int(got[0]), main.squad_vehicle])
		if got[1] > 0.0:
			lines.append("%d L GO INTO THE JERRYCANS (%d L CARRIED)." % [int(got[1]), int(main.fuel_cans)])
		var lost := float(wr["fuel"]) - float(got[0]) - float(got[1])
		if lost >= 1.0:
			lines.append("THERE IS NOTHING TO CARRY THE LAST %d L IN." % int(lost))
	_refresh_hud()
	_ask("  ".join(lines), [["CONTINUE", func(): pass]])

## The trap goes off: the fuel burns, the searcher is hurt (never killed) and some of his gear is
## lost in the blast.
func _booby_trap(who: Dictionary, wr: Dictionary) -> Array:
	var lines: Array = ["A BOOBY TRAP GOES OFF AS %s OPENS THE FUEL CAP OF THE %s. THE FUEL GOES UP IN FLAMES." % [who["name"], wr["vehicle"]]]
	var loc: String = ["LEFT ARM", "RIGHT ARM", "LEFT LEG", "RIGHT LEG", "ABDOMEN"][randi_range(0, 4)]
	var cap := int(who["hits"].get(loc, 10))
	var dmg: Dictionary = who.get("damage", {})
	dmg[loc] = clampi(int(dmg.get(loc, 0)) + randi_range(maxi(1, cap / 3), cap - 1), 0, cap - 1)
	who["damage"] = dmg
	who["bleed"] = 0
	lines.append("%s IS %s IN THE %s." % [who["name"], "BADLY HURT" if int(dmg[loc]) * 2 >= cap else "WOUNDED", loc])
	Forces.equip(who)
	var g: Dictionary = who["gear"]
	var lost: Array = []
	if randf() < 0.6 or test_risk == "trap":
		var m := mini(int(g.get("mags", 0)), randi_range(1, 3))
		if m > 0:
			g["mags"] = int(g["mags"]) - m
			lost.append("%d MAGAZINE%s" % [m, "S" if m > 1 else ""])
		var gr := int(g.get("grenades", 0)) / 2
		if gr > 0:
			g["grenades"] = int(g["grenades"]) - gr
			lost.append("%d GRENADE%s" % [gr, "S" if gr > 1 else ""])
		if int(g.get("medkits", 0)) > 0 and randf() < 0.5:
			g["medkits"] = int(g["medkits"]) - 1
			lost.append("A MEDKIT")
	if not lost.is_empty():
		lines.append("LOST IN THE BLAST: %s." % ", ".join(lost))
	return lines

## The tank runs dry on the way: the vehicle stays where it stopped, the squad goes on foot.
## (The motor pool at Krakow sends a recovery team for it; a friendly town nearby has fuel.)
func _out_of_fuel() -> void:
	main.vehicle_fuel = 0.0
	main.vehicle_at = world.pos
	path = []
	_update_fog()
	_ask("YOU RUN OUT OF FUEL ON YOUR WAY THERE.  THE %s IS LEFT BEHIND (%s).  THE SQUAD GOES ON FOOT." % [main.squad_vehicle, describe(world.pos)],
		[["CONTINUE", func(): pass]])

## Keep the view on the map.
func _clamp_cam() -> void:
	var half := Vector2(640, 400) / cam.zoom
	var size := Vector2(world.w, world.h) * CELL
	cam.position.x = clampf(cam.position.x, half.x, maxf(half.x, size.x - half.x))
	cam.position.y = clampf(cam.position.y, half.y - 92.0 / cam.zoom.y, maxf(half.y, size.y - half.y))

func _physics_process(_d: float) -> void:
	_clamp_cam()

## Trouble on the way: the original line, then engage or try to slip away.
func _trouble(g: Dictionary) -> void:
	var doing := "DRIVING" if main.driving() else "MARCHING AND RESTING"
	var txt := "AFTER %s OF %s, YOU RUN INTO TROUBLE FROM THE %s." % [World.span_text(walked_min), doing, g["name"]]
	if not g["hostile"]:
		txt = "AFTER %s OF %s, YOU MEET A GROUP OF %s." % [World.span_text(walked_min), doing, g["name"]]
	var buttons: Array = [["ENGAGE" if g["hostile"] else "APPROACH", func(): main.battle_from_encounter(g) if g["hostile"] else main.enter_encounter(g)]]
	buttons.append(["TRY TO EVADE" if g["hostile"] else "MOVE ON", func(): _evade(g)])
	_ask(txt + "  (%d PEOPLE, %s)" % [g["count"], describe(world.pos)], buttons)

func _evade(g: Dictionary) -> void:
	if not g["hostile"]:
		return
	# the squad's best at Stealth leads them round the danger
	var lvl := 0
	var who := ""
	for m in main.squad:
		var v := int(m["skills"].get("STEALTH", 0.0))
		if who == "" or v > lvl:
			lvl = v
			who = m["name"]
	if main.driving() and randf() < 0.5:
		_ask("THE %s LEAVES THEM BEHIND." % main.squad_vehicle, [["CONTINUE", func(): pass]])
	elif randf() < 0.35 + 0.08 * lvl:
		_ask("%s LEADS THE SQUAD AROUND THEM UNSEEN." % who, [["CONTINUE", func(): pass]])
	else:
		_ask("THE %s HAVE SEEN YOU." % g["name"], [["FIGHT", func(): main.battle_from_encounter(g)]])

# ---------------- drawing ----------------
func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Czarny's fortress and the 12 km Exor warned about
	if czarny.x > -900:
		draw_arc(czarny * CELL, 12.0 * CELL, 0, TAU, 96, Color(0.9, 0.1, 0.1, 0.8), 3.0)
	var obj: String = main.campaign.objective_city()
	for c in main.data.cities:
		if int(c["size"]) > 4 and c["name"] != "CHECINY":
			continue
		var p: Vector2 = world.city_cell(c) * CELL
		var col := Color(0.45, 1.0, 0.45)
		if c["name"] == "CHECINY":
			col = Color(1, 0.15, 0.15)
		elif c["name"] == "KRAKOW":
			col = Color(0.4, 0.7, 1.0)
		draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.05, 0.05, 0.05))
		draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col)
		if c["name"] == obj:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
			draw_arc(p, 14 + 4 * pulse, 0, TAU, 32, Color(1, 0.85, 0.2), 3.0)
		if cam.zoom.x >= 0.7 or c["name"] in [obj, "KRAKOW", "CHECINY"]:
			var nm: String = c["name"] + (" (HQ)" if c["name"] == "KRAKOW" else "")
			draw_string(font, p + Vector2(9, -7), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.BLACK)
			draw_string(font, p + Vector2(8, -8), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 0.9))
	# the planned route and its walking time
	var show: Array = path if not path.is_empty() else hover_path
	if show.size() > 1:
		var pts := PackedVector2Array()
		for c in show:
			pts.append((Vector2(c) + Vector2(0.5, 0.5)) * CELL)
		draw_polyline(pts, Color(1, 0.9, 0.3, 0.9), 3.0)
		if path.is_empty():
			var end: Vector2 = pts[pts.size() - 1]
			var t := World.span_text(world.route_minutes(show, mode()))
			if main.driving():
				var litres: float = world.route_minutes(show, mode()) / 60.0 * main.fuel_per_hour()
				t += "  %d L%s" % [int(ceil(litres)), "  (NOT ENOUGH FUEL)" if litres > main.vehicle_fuel else ""]
			draw_string(font, end + Vector2(12, 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.BLACK)
			draw_string(font, end + Vector2(11, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.9, 0.4))
	# a parked vehicle: a small hull with its name
	if main.squad_vehicle != "" and not main.driving():
		var vp: Vector2 = main.vehicle_at * CELL
		draw_rect(Rect2(vp - Vector2(8, 5), Vector2(16, 10)), Color.BLACK)
		draw_rect(Rect2(vp - Vector2(6, 3), Vector2(12, 6)), Color(0.55, 0.62, 0.35))
		draw_string(font, vp + Vector2(10, 14), main.squad_vehicle, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.BLACK)
		draw_string(font, vp + Vector2(9, 13), main.squad_vehicle, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.95, 0.6))
	# the squad: a red X, as on the original LCD map (in a box while driving)
	var me := world.pos * CELL
	if main.driving():
		draw_rect(Rect2(me - Vector2(10, 10), Vector2(20, 20)), Color.BLACK, false, 4.0)
		draw_rect(Rect2(me - Vector2(10, 10), Vector2(20, 20)), Color(0.85, 0.95, 0.6), false, 2.0)
	draw_line(me + Vector2(-7, -7), me + Vector2(7, 7), Color.BLACK, 5.0)
	draw_line(me + Vector2(-7, 7), me + Vector2(7, -7), Color.BLACK, 5.0)
	draw_line(me + Vector2(-7, -7), me + Vector2(7, 7), Color(1, 0.15, 0.1), 3.0)
	draw_line(me + Vector2(-7, 7), me + Vector2(7, -7), Color(1, 0.15, 0.1), 3.0)

## Eight hours of rest where the squad stands (the original's sleep: in a town a real bed).
## M9 economy round 2: every soldier needs one field ration per 8-hour sleep.
func rest() -> void:
	if not path.is_empty() or panel.visible:
		return
	var town := _town_at(world.pos)
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
	var lines := Healing.rest(main.squad, 8.0, not town.is_empty(), String(town.get("name", "")) == "KRAKOW", main.difficulty == "story")
	if food_line != "":
		lines.insert(0, food_line)
	world.minutes += 8 * 60
	_refresh_hud()
	_ask("\n".join(lines), [["CONTINUE", func(): pass]])

# ---------------- test hooks ----------------
func test_force_trouble(name: String) -> void:
	for g in World.GROUPS:
		if g["name"] == name:
			var gg: Dictionary = g.duplicate()
			gg["count"] = int(g["min"]) + 1
			gg["terrain"] = world.at(world.cell())
			gg["cell"] = world.cell()
			walked_min = 95.0
			_trouble(gg)
			return

## Put the squad on the nearest cell of a terrain type (tests).
func test_place(kind: String) -> void:
	var c0 := world.cell()
	for r in range(1, 30):
		for y in range(c0.y - r, c0.y + r + 1):
			for x in range(c0.x - r, c0.x + r + 1):
				if world.at(Vector2i(x, y)) == kind and _town_at(Vector2(x, y)).is_empty():
					world.pos = Vector2(x, y) + Vector2(0.5, 0.5)
					cam.position = world.pos * CELL
					return

func test_force_wreck(v: String, litres: float, burnt := false, risk := "none") -> void:
	test_risk = risk
	walked_min = 40.0
	_wreck({"vehicle": v, "burnt": burnt, "fuel": litres})

func test_winter() -> void:
	world.minutes += 100.0 * 1440.0         # early January

func test_press(i: int) -> void:
	var b := panel_buttons.get_child(i) as Button
	if b:
		b.pressed.emit()
