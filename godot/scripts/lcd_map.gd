## Hand-held LCD map, drawn in the same isometric orientation as the ground view
## (north to the top-left), so a direction on the map is the same direction on the ground.
extends Control

var view: Node                   # the tactical scene (party position, data)
const KM := 18.0                 # map pixels per kilometre

func _ready() -> void:
	position = Vector2(240, 120)
	size = Vector2(800, 560)

func _process(_d: float) -> void:
	if visible:
		queue_redraw()

func _iso(w: Vector2) -> Vector2:
	var d: Vector2 = (w - view.party) / 1000.0 * KM
	return size / 2 + Vector2(d.x + d.y, (d.y - d.x) * 0.5)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.22, 0.18, 0.96))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.75, 0.7), false, 6.0)
	var font := ThemeDB.fallback_font
	for c in view.main.data.cities:
		var p := _iso(Vector2(c["a"], c["b"]))
		if Rect2(Vector2.ZERO, size).has_point(p):
			var is_target: bool = c["name"] == view.target_city
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color(1, 0.8, 0.2) if is_target else Color(0.8, 0.8, 0.8))
			draw_string(font, p + Vector2(8, -6), c["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	var me := _iso(view.party)
	draw_line(me + Vector2(-8, -8), me + Vector2(8, 8), Color.RED, 3.0)
	draw_line(me + Vector2(-8, 8), me + Vector2(8, -8), Color.RED, 3.0)
	# north arrow (top-left, as in the ground view's compass)
	var o := Vector2(60, 60)
	draw_line(o, o + Vector2(-30, -15), Color(1, 0.9, 0.3), 3.0)
	draw_string(font, o + Vector2(-52, -22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.9, 0.3))
	draw_string(font, Vector2(16, size.y - 16), "LIQUID CRYSTAL DISPLAY  -  M closes", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.3, 0.3))
