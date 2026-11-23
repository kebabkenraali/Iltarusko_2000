## Conversation / message box at the bottom of the field view: pages of text, typed out;
## a click (or Space / Enter) finishes the page, the next click goes on. While open the field
## view waits. The one speaking is shown as a talking head (Portraits): the mouth moves while
## the text is typed out.
extends Panel

var pages: Array = []              # [speaker, text]
var shown := 0.0
var speaker: Label
var body: RichTextLabel
var on_close: Callable
var face: Array = []               # the person spoken to (Portraits frames); set by the field view
var squad: Array = []              # recruits: a page spoken by one of them shows their portrait
var portrait: TextureRect
var talking: Array = []            # frames of the head on the current page
var text_x := 176.0                # the text starts right of the head

func _ready() -> void:
	position = Vector2(40, 520)
	size = Vector2(1200, 250)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.02, 0.92)
	sb.border_color = Color(0.6, 0.12, 0.08)
	sb.set_border_width_all(3)
	add_theme_stylebox_override("panel", sb)
	portrait = TextureRect.new()
	portrait.position = Vector2(16, 44)
	portrait.size = Vector2(144, 129)
	_style_portrait(portrait)
	add_child(portrait)
	speaker = Label.new()
	speaker.position = Vector2(20, 10)
	speaker.add_theme_font_size_override("font_size", 22)
	speaker.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	add_child(speaker)
	body = RichTextLabel.new()
	body.position = Vector2(text_x, 44)
	body.size = Vector2(1200 - text_x - 20, 190)
	body.add_theme_font_size_override("normal_font_size", 19)
	body.add_theme_color_override("default_color", Color(1, 0.4, 0.33))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	visible = false

## Text, then choices: [[label, Callable], ...]. A label names who does it and with which skill,
## e.g. "[ERIKA JONES - MEDICAL 6] Treat the wounded (20 min)". Conversation and action in one.
func choose(lines: Array, who: String, options: Array) -> void:
	choices = options
	say(lines, who)

var choices: Array = []
var choice_box: VBoxContainer

func _show_choices() -> void:
	if choice_box == null:
		choice_box = VBoxContainer.new()
		choice_box.add_theme_constant_override("separation", 4)
		add_child(choice_box)
	for c in choice_box.get_children():
		c.queue_free()
	choice_box.position = Vector2(text_x, 44 + 24 * mini(4, body.get_line_count()) + 6)
	for i in range(choices.size()):
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, choices[i][0]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 17)
		var cb: Callable = choices[i][1]
		b.pressed.connect(func(): pick(cb))
		choice_box.add_child(b)
	choice_box.visible = true

## Choose an option (button, number key or a test).
func pick(cb: Callable) -> void:
	choices = []
	if choice_box:
		choice_box.visible = false
	pages.clear()
	visible = false
	cb.call()

func pick_index(i: int) -> void:
	if i >= 0 and i < choices.size():
		pick(choices[i][1])

func say(lines: Array, who := "", done := Callable()) -> void:
	for l in lines:
		if String(l).strip_edges() != "":
			pages.append([who, String(l)])
	if done.is_valid():
		on_close = done
	if not visible and not pages.is_empty():
		_next()

func _style_portrait(r: TextureRect) -> void:
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE

## The head for a page: Exor 1 on the radio, a recruit by name, or the person spoken to.
func _head_for(who: String) -> Array:
	if who.begins_with("EXOR"):
		return Portraits.exor()
	for r in squad:
		if String(r.get("name", "")) == who:
			return Portraits.recruit(r)
	return face

func _next() -> void:
	if pages.is_empty() and not choices.is_empty():
		_show_choices()
		return
	if choice_box:
		choice_box.visible = false
	if pages.is_empty():
		visible = false
		if on_close.is_valid():
			var c := on_close
			on_close = Callable()
			c.call()
		return
	var p: Array = pages.pop_front()
	talking = _head_for(String(p[0]))
	portrait.visible = not talking.is_empty()
	if not talking.is_empty():
		portrait.texture = talking[0]
	speaker.text = p[0]
	body.text = p[1]
	body.visible_characters = 0
	shown = 0.0
	visible = true
	if pages.is_empty() and not choices.is_empty():
		_show_choices()                    # the choices come with the last line

func _process(delta: float) -> void:
	if visible:
		shown += delta * 90.0
		body.visible_characters = int(shown)
		if talking.size() > 1:            # the mouth moves while the words come
			var typing := body.visible_characters >= 0 and body.visible_characters < body.get_total_character_count()
			portrait.texture = talking[1 + (int(shown / 11.0) % (talking.size() - 1))] if typing and int(shown / 11.0) % 2 == 0 else talking[0]

func advance() -> void:
	if body.visible_characters < body.get_total_character_count() and body.visible_characters >= 0:
		shown = body.get_total_character_count()
		body.visible_characters = -1
	else:
		_next()

## Finish everything at once (tests). Open choices are closed without picking.
func flush() -> void:
	pages.clear()
	choices = []
	_next()

func waiting_choice() -> bool:
	return visible and choice_box != null and choice_box.visible

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.device != 4242 and Array(OS.get_cmdline_user_args()).any(func(a): return String(a).begins_with("--test=")):
		return
	if ev is InputEventMouseButton and ev.pressed:
		advance()
		accept_event()
