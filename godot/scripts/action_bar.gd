## The bottom icon bar of the 2-D views: the original's "2-D Ground Icons" (manual p.55), ten
## icons left to right in the original order. An icon is picked by a mouse click or straight
## from the keyboard with its number (1-9, 0); icons with sub-choices open a small options
## window above the bar, whose own choices get numbers of their own and ESC closes it.
## The views feed setup() their actions (key, label, callback) in the original order and route
## key events through hotkey() from their _unhandled_input.
extends Panel

const BAR_TOP := 708.0

var bar: HBoxContainer
var defs: Array = []                  # [{"key", "label", "cb"}] in the original order
var win: Panel = null
var win_defs: Array = []              # the callbacks of the open options window

func setup(d: Array) -> void:
	defs = d
	position = Vector2(0, BAR_TOP)
	size = Vector2(1280, 92)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.02, 0.92)
	sb.border_color = Color(0.6, 0.12, 0.08)
	sb.set_border_width_all(3)
	add_theme_stylebox_override("panel", sb)
	bar = HBoxContainer.new()
	bar.position = Vector2(4, 4)
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	for i in range(defs.size()):
		var b := Button.new()
		b.text = "%s\n%s" % [String(defs[i]["key"]), String(defs[i]["label"])]
		b.custom_minimum_size = Vector2(126, 78)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		var cb: Callable = defs[i]["cb"]
		b.pressed.connect(cb)
		bar.add_child(b)

## A key from the view's _unhandled_input: true when this bar used it.
## While the options window is open the numbers pick its choices instead.
func hotkey(kc: int) -> bool:
	if choice_open():
		if kc >= KEY_1 and kc <= KEY_9:
			run_choice(kc - KEY_1)
			return true
		return false
	if kc == KEY_0:
		run(defs.size() - 1)
		return true
	if kc >= KEY_1 and kc <= KEY_9 and kc - KEY_1 < defs.size():
		run(kc - KEY_1)
		return true
	return false

func run(i: int) -> void:
	if i >= 0 and i < defs.size():
		var cb: Callable = defs[i]["cb"]
		cb.call()

# ---------------- the options window ----------------
## buttons: [[label, Callable], ...]; each choice gets its number in the window.
func choose(title: String, buttons: Array) -> void:
	close_choices()
	win = Panel.new()
	win.position = Vector2(420, 480)
	win.size = Vector2(440, 42 + buttons.size() * 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.06, 0.04, 0.97)
	sb.border_color = Color(0.75, 0.5, 0.25)
	sb.set_border_width_all(2)
	win.add_theme_stylebox_override("panel", sb)
	add_child(win)
	var t := Label.new()
	t.text = title
	t.position = Vector2(16, 8)
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	win.add_child(t)
	win_defs = []
	for i in range(buttons.size()):
		win_defs.append(buttons[i][1])
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, String(buttons[i][0])]
		b.position = Vector2(16, 38 + i * 40)
		b.size = Vector2(408, 36)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		var cb: Callable = buttons[i][1]
		b.pressed.connect(func():
			close_choices()
			cb.call())
		win.add_child(b)

func run_choice(i: int) -> void:
	if i < 0 or i >= win_defs.size():
		return
	var cb: Callable = win_defs[i]
	close_choices()
	cb.call()

func close_choices() -> void:
	if win != null:
		win.queue_free()
		win = null
		win_defs = []

func choice_open() -> bool:
	return win != null
