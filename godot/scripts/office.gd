## Krakow HQ office: original background, every object is a one-click hotspot with a tooltip.
extends Control

var main: Node
var hover_name := ""
var tip: Label
var bg: TextureRect
var notice := ""                         # e.g. replacements HQ assigned; shown until the mouse moves

# hotspots in original 320x200 coordinates (from the 1991 office screen)
const HOTSPOTS := [
	{"name": "radio", "rect": Rect2(105, 172, 62, 26), "tip": "Radio: receive orders from Exor 1"},
	{"name": "cabinet", "rect": Rect2(168, 22, 34, 78), "tip": "Filing cabinet: choose up to four soldiers"},
	{"name": "map", "rect": Rect2(24, 2, 126, 84), "tip": "Wall map: Krakow and Czarny's territory"},
	{"name": "computer", "rect": Rect2(232, 80, 88, 120), "tip": "Computer: food, ammunition, medicine, fuel, morale"},
	{"name": "lamp", "rect": Rect2(0, 78, 46, 104), "tip": "Lamp: leave the office - out to the map of the region"},
	{"name": "motorpool", "rect": Rect2(168, 110, 40, 60), "tip": "Motor Pool: buy, repair or refuel vehicles"},
]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	bg = TextureRect.new()
	refresh_art()
	bg.size = Vector2(1280, 800)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.show_behind_parent = true             # keep the hover frame (drawn in _draw) on top
	add_child(bg)
	tip = Label.new()
	tip.add_theme_font_size_override("font_size", 22)
	tip.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	tip.add_theme_color_override("font_outline_color", Color.BLACK)
	tip.add_theme_constant_override("outline_size", 6)
	tip.position = Vector2(16, 760)
	tip.text = notice
	add_child(tip)

func refresh_art() -> void:
	bg.texture = load(main.art("OFFICE", "OFFICE"))

func _hit(p: Vector2) -> Dictionary:
	var q: Vector2 = p / float(main.SCALE)
	for h in HOTSPOTS:
		if h["rect"].has_point(q):
			return h
	return {}

func test_hover(p: Vector2) -> void:
	_update_hover(p)

func _update_hover(p: Vector2) -> void:
	var h := _hit(p)
	hover_name = h.get("name", "")
	tip.text = h.get("tip", "")
	queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_update_hover(ev.position)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		match _hit(ev.position).get("name", ""):
			"radio": main.show_briefing()
			"lamp": main.show_world()
			"motorpool": main.show_motor_pool()
			"computer": main.show_computer()

func _draw() -> void:
	for h in HOTSPOTS:
		if h["name"] == hover_name:
			var r: Rect2 = h["rect"]
			draw_rect(Rect2(r.position * main.SCALE, r.size * main.SCALE), Color(1, 0.85, 0.3, 0.9), false, 3.0)
