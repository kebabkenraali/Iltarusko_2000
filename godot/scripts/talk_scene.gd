## A conversation indoors, as a scene: the room's picture behind, the squad leader and the person
## spoken to standing large in front of it, what they say in one box and the squad's choices in
## another. It is the field view's dialog box with a different layout: the field view's talk
## (interact, interrogate, treat ...) runs through it unchanged while it stands in for the dialog.
extends "res://scripts/dialog.gd"

signal closed

var main: Node
var room_tex: Texture2D               # the room as the interior view showed it
var leader: Dictionary                # recruit dictionary
var other: Dictionary                 # {body, head} of the person spoken to
var answer: Panel
var question: Panel

const RED := Color(1, 0.4, 0.33)

func _box(rect: Rect2, border: Color) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.02, 0.9)
	sb.border_color = border
	sb.set_border_width_all(3)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p

func _figure(body: String, head: int, dir: int, at: Vector2) -> void:
	var s := Soldier.new()
	s.body = body
	s.head = head
	s.dir = dir
	s.scale = Vector2.ONE * 2.6           # Soldier draws at 3x: about 8x the original pixels
	s.position = at
	add_child(s)

func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(1280, 800)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04)
	add_theme_stylebox_override("panel", sb)
	# the room, filling the upper part of the screen
	var bg := TextureRect.new()
	bg.texture = room_tex
	bg.position = Vector2(0, 0)
	bg.size = Vector2(1280, 560)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.modulate = Color(0.45, 0.45, 0.5)             # dimmed: the two in front stand out
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# the two of them, turned to each other
	_figure("AF" if leader.get("gender", "M") == "F" else "AM", int(leader.get("head", leader.get("face", 0))), 3, Vector2(300, 540))
	_figure(String(other.get("body", "AM")), int(other.get("head", 0)), 5, Vector2(980, 540))
	# what is said (the other person, or what happens) and what the squad can do
	answer = _box(Rect2(470, 40, 770, 230), Color(0.6, 0.12, 0.08))
	speaker = Label.new()
	speaker.position = Vector2(18, 10)
	speaker.add_theme_font_size_override("font_size", 22)
	speaker.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	answer.add_child(speaker)
	portrait = TextureRect.new()                       # the talking head, in the answer box
	portrait.position = Vector2(14, 44)
	portrait.size = Vector2(160, 144)
	_style_portrait(portrait)
	answer.add_child(portrait)
	body = RichTextLabel.new()
	body.position = Vector2(188, 44)
	body.size = Vector2(564, 176)
	body.add_theme_font_size_override("normal_font_size", 19)
	body.add_theme_color_override("default_color", RED)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	answer.add_child(body)
	question = _box(Rect2(40, 575, 1200, 205), Color(0.75, 0.6, 0.2))
	var qh := Label.new()
	qh.text = "%s (click the text to go on, 1-9 to choose)" % leader.get("name", "")
	qh.position = Vector2(18, 8)
	qh.add_theme_font_size_override("font_size", 16)
	qh.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	question.add_child(qh)
	choice_box = VBoxContainer.new()
	choice_box.position = Vector2(18, 38)
	choice_box.add_theme_constant_override("separation", 4)
	question.add_child(choice_box)
	choice_box.visible = false
	visible = false

## The choices go into the question box (the base class puts them under the text).
func _show_choices() -> void:
	for c in choice_box.get_children():
		c.queue_free()
	for i in range(choices.size()):
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, choices[i][0]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		var cb: Callable = choices[i][1]
		b.pressed.connect(func(): pick(cb))
		choice_box.add_child(b)
	choice_box.visible = true

## The base class hides the box when a choice is made or the last page is read; here that ends
## the scene, unless the choice or the closing callback said something more.
func pick(cb: Callable) -> void:
	super.pick(cb)
	if not visible:
		_close()

func _next() -> void:
	super._next()
	if not visible:
		_close()

func _close() -> void:
	if is_queued_for_deletion():
		return
	visible = false
	closed.emit()
	queue_free()

func _unhandled_input(ev: InputEvent) -> void:
	if main != null and not main.input_ok(ev):
		return
	if ev is InputEventKey and ev.pressed:
		if ev.keycode >= KEY_1 and ev.keycode <= KEY_9 and waiting_choice():
			pick_index(ev.keycode - KEY_1)
		elif ev.keycode == KEY_ESCAPE and waiting_choice():
			pick_index(choices.size() - 1)
		elif ev.keycode in [KEY_SPACE, KEY_ENTER]:
			advance()
		get_viewport().set_input_as_handled()
