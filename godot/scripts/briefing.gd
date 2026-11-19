## Radio briefing from Exor 1. Original art: the officer (ICON/MOUTH0) with his talking mouth
## (MOUTH1-6 at 96,60) and the flickering terminal (SCREEN1-6 at 24,90), positions matched
## against the base picture. Modern touch: the message types out; click to skip, then return.
extends Control

var main: Node
var text := ""
var label: RichTextLabel
var officer: TextureRect
var div := 1.0                        # 4 when the art is the 4x AI remaster
var mouth: TextureRect
var screen_anim: TextureRect
var mouth_tex: Array = []
var screen_tex: Array = []
var t := 0.0
var shown := 0.0
const S := 3.0
const ORIGIN := Vector2(740, 100)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04)
	bg.size = Vector2(1280, 800)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	officer = _sprite("", Vector2.ZERO)
	mouth = _sprite("", Vector2(96, 60))
	screen_anim = _sprite("", Vector2(24, 90))
	label = RichTextLabel.new()
	label.position = Vector2(48, 80)
	label.size = Vector2(640, 640)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 22)
	label.add_theme_color_override("default_color", Color(0.85, 0.95, 0.85))
	label.text = text
	label.visible_characters = 0
	add_child(label)
	var hint := Label.new()
	hint.text = "Click to skip / return to the office"
	hint.position = Vector2(48, 740)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(hint)
	refresh_art()

func refresh_art() -> void:
	var p: String = main.art("ICON", "MOUTH0")
	officer.texture = load(p)
	div = main.art_div(p)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if div > 1.0 else CanvasItem.TEXTURE_FILTER_NEAREST
	mouth_tex.clear()
	screen_tex.clear()
	for i in range(1, 7):
		mouth_tex.append(load(main.art("ICON", "MOUTH%d" % i)))
		screen_tex.append(load(main.art("ICON", "SCREEN%d" % i)))

func _sprite(path: String, at: Vector2) -> TextureRect:
	var r := TextureRect.new()
	if path != "":
		r.texture = load(path)
	r.position = ORIGIN + at * S
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

func _process(delta: float) -> void:
	t += delta
	shown = minf(shown + delta * 45.0, float(text.length()))
	label.visible_characters = int(shown)
	var talking := shown < text.length()
	mouth.texture = mouth_tex[int(t * 10.0) % mouth_tex.size()] if talking else null
	screen_anim.texture = screen_tex[int(t * 4.0) % screen_tex.size()]
	for r in [officer, mouth, screen_anim]:
		if r.texture:
			r.size = r.texture.get_size() * S / div

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if shown < text.length():
			shown = text.length()
		else:
			main.show_office()
