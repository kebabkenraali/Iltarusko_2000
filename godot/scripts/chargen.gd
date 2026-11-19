## Character generation (the original CGEN): squad roster on the left, a step-by-step recruit
## builder in the middle, the recruit's portrait and service record on the right.
## The 1991 look is kept (red text: light = selectable, dark = not), over the chargen tank photo.
## Modern touches: every unavailable career says why (tooltip and text), a live preview of the
## skill levels a term gives, random recruits in one click, squads saved to disk.
extends Control

var main: Node
var cr: ChargenRules
var squad: Array = []                    # finished recruits (Dictionaries)
var leader := 0
var r: Dictionary = {}                   # recruit being built
var step := ""
var term: Dictionary = {}                # current term record
var pending: Dictionary = {}             # skill picks this term: skill -> levels
var pending_lang := ""
var secondary: Array = []                # chosen secondary activity skills
var bg_picks: Array = []
var bg_lang := ""
var group := "ARMY"
var viewing := -1                        # roster index shown in the profile view
var used_random_attrs := false
var snapshot: Dictionary = {}            # recruit before the current term (for BACK)

var roster_box: VBoxContainer
var work: VBoxContainer                  # wizard area
var info: VBoxContainer                  # portrait + record
var face_tex := {}
var bg: TextureRect

const RED := Color(1.0, 0.36, 0.3)
const DARK := Color(0.42, 0.13, 0.11)
const HI := Color(1.0, 0.85, 0.45)
const SQUAD_FILE := "user://squad.json"
const MAX_SQUAD := 4

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	cr = ChargenRules.new(GameData._json("res://data/careers.json"), main.data.chargen, main.rng_seed)
	theme = _theme()
	bg = TextureRect.new()
	bg.texture = load(main.art("CGEN", "TANK"))
	bg.size = Vector2(1280, 800)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.modulate = Color(0.55, 0.55, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_panel(Rect2(16, 16, 288, 768))
	_panel(Rect2(320, 16, 600, 768))
	_panel(Rect2(936, 16, 328, 768))
	roster_box = _vbox(Rect2(28, 28, 264, 744))
	work = _vbox(Rect2(334, 28, 572, 744))
	info = _vbox(Rect2(948, 28, 304, 744))
	_load_faces()
	squad = main.squad.duplicate(true)
	leader = main.leader_index
	_refresh_roster()
	_show_menu()

## F2: swap the pictures in place (the recruit being built and the roster stay as they are).
func refresh_art() -> void:
	bg.texture = load(main.art("CGEN", "TANK"))
	_load_faces()
	_refresh_roster()
	match step:
		"identity": _step_identity()
		"attributes": _step_attributes()
		"background": _step_background()
		"career": _step_career()
		"allocate": _step_allocate()
		"profile": _step_profile()
		"view": view_recruit(viewing)
		_: _show_menu()

## Portraits cut from the FACES sheets (remastered or original).
func _load_faces() -> void:
	for g in ["M", "F"]:
		var sheet: Texture2D = load(main.art("FACES", "men" if g == "M" else "women"))
		var div := float(sheet.get_width()) / 320.0
		var list: Array = []
		for i in range(15):
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2((i % 5) * 48 * div, (i / 5) * 43 * div, 48 * div, 43 * div)
			list.append(at)
		face_tex[g] = list

# ---------------- look ----------------
func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	for c in ["Button", "Label", "CheckBox", "OptionButton", "LineEdit"]:
		t.set_color("font_color", c, RED)
		t.set_color("font_disabled_color", c, DARK)
		t.set_color("font_hover_color", c, HI)
		t.set_color("font_pressed_color", c, HI)
		t.set_color("font_focus_color", c, RED)
		t.set_color("font_hover_pressed_color", c, HI)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.12, 0.02, 0.02, 0.85)
	flat.border_color = Color(0.5, 0.1, 0.08)
	flat.set_border_width_all(1)
	flat.set_content_margin_all(4)
	var hover := flat.duplicate()
	hover.border_color = HI
	var pressed := flat.duplicate()
	pressed.bg_color = Color(0.35, 0.05, 0.04, 0.95)
	pressed.border_color = HI
	var dis := flat.duplicate()
	dis.bg_color = Color(0.06, 0.01, 0.01, 0.7)
	dis.border_color = Color(0.25, 0.06, 0.05)
	for c in ["Button", "OptionButton"]:
		t.set_stylebox("normal", c, flat)
		t.set_stylebox("hover", c, hover)
		t.set_stylebox("pressed", c, pressed)
		t.set_stylebox("hover_pressed", c, pressed)
		t.set_stylebox("disabled", c, dis)
		t.set_stylebox("focus", c, StyleBoxEmpty.new())
	t.set_stylebox("normal", "LineEdit", flat)
	t.set_stylebox("focus", "LineEdit", hover)
	return t

func _panel(rect: Rect2) -> void:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.0, 0.0, 0.72)
	sb.border_color = Color(0.55, 0.1, 0.08)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)

func _vbox(rect: Rect2) -> VBoxContainer:
	var s := ScrollContainer.new()
	s.position = rect.position
	s.size = rect.size
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(s)
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = rect.size.x - 12
	v.add_theme_constant_override("separation", 6)
	s.add_child(v)
	return v

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _label(box: Node, text: String, size := 18, color := RED) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# wrapping labels have no minimum width: inside a row they would wrap letter by letter
	if box is VBoxContainer:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l

## A wrapping label that takes the rest of a row.
func _note(box: Node, text: String, size := 14, color := RED) -> Label:
	var l := _label(box, text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _button(box: Node, text: String, cb: Callable, enabled := true, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.tooltip_text = tip
	b.pressed.connect(cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(b)
	return b

func _row(box: Node) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	return h

# ---------------- roster (left) ----------------
func _refresh_roster() -> void:
	_clear(roster_box)
	_label(roster_box, "SQUAD %d / %d" % [squad.size(), MAX_SQUAD], 22, HI)
	for i in range(squad.size()):
		var m: Dictionary = squad[i]
		var h := _row(roster_box)
		var tr := TextureRect.new()
		tr.texture = face_tex[m["gender"]][int(m["face"])]
		tr.custom_minimum_size = Vector2(72, 64)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(tr)
		var b := Button.new()
		b.text = "%s%s\n%s" % ["* " if i == leader else "", m["name"], m["rank"]]
		b.tooltip_text = "View recruit (* = squad leader)"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(view_recruit.bind(i))
		h.add_child(b)
	_label(roster_box, "")
	var full := squad.size() >= MAX_SQUAD
	_button(roster_box, "MANUALLY RECRUIT", begin_manual, not full, "Build a recruit step by step")
	_button(roster_box, "RANDOMLY RECRUIT", random_recruit, not full, "The computer builds a recruit")
	_button(roster_box, "SAVE SQUAD", save_squad, not squad.is_empty())
	_button(roster_box, "LOAD SQUAD", load_squad, FileAccess.file_exists(SQUAD_FILE))
	_button(roster_box, "MODE: " + ("STORY" if main.difficulty == "story" else "NORMAL"), toggle_mode, true,
		"NORMAL: the war as it is. STORY: the squad shoots better, is hit less, the wounded fall unconscious instead of dying and heal faster.")
	_button(roster_box, "DEPLOY SQUAD", deploy, not squad.is_empty(), "Report to Krakow HQ with this squad")
	_label(roster_box, "")
	_button(roster_box, "CONTINUE (AUTOSAVE)", func(): main.load_game(main.AUTOSAVE), FileAccess.file_exists(main.AUTOSAVE),
		"The game as it was when the squad last came back to the map")
	_button(roster_box, "LOAD QUICKSAVE (F9)", func(): main.load_game(main.QUICKSAVE), FileAccess.file_exists(main.QUICKSAVE),
		"The game saved with F5")

func _show_menu() -> void:
	step = "menu"
	_clear(work)
	_clear(info)
	_label(work, "TWILIGHT: 2000 - RECRUITMENT", 26, HI)
	_label(work, "Build a squad of up to four soldiers. Recruit them by hand or let the computer do it, "
		+ "then deploy to the Krakow headquarters. Click a recruit on the left to view the service record, "
		+ "choose the squad leader or discharge.")

# ---------------- recruit builder ----------------
func begin_manual() -> void:
	r = cr.new_recruit()
	r["name"] = ""
	cr.set_origin(r, main.data.chargen["countries"][0])
	bg_picks = []
	bg_lang = ""
	used_random_attrs = false
	_step_identity()

func random_recruit() -> void:
	if squad.size() >= MAX_SQUAD:
		return
	var m := cr.random_recruit()
	squad.append(m)
	_refresh_roster()
	view_recruit(squad.size() - 1)

func next_step() -> void:
	match step:
		"identity": _step_attributes()
		"attributes": _step_background()
		"background":
			cr.apply_background(r, bg_picks, bg_lang)
			_step_career()

func _step_identity() -> void:
	step = "identity"
	_clear(work)
	_label(work, "1. RECRUIT", 24, HI)
	var g := _row(work)
	for x in [["M", "MALE"], ["F", "FEMALE"]]:
		var b := Button.new()
		b.text = x[1]
		b.toggle_mode = true
		b.button_pressed = r["gender"] == x[0]
		b.pressed.connect(func(): r["gender"] = x[0]; r["head"] = cr.head_for(x[0], int(r["face"])); _step_identity())
		g.add_child(b)
	var nm := LineEdit.new()
	nm.placeholder_text = "Name (up to 19 letters)"
	nm.max_length = 19
	nm.text = r["name"]
	nm.text_changed.connect(func(t): r["name"] = t.to_upper(); _refresh_info(); _update_next())
	work.add_child(nm)
	var grid := GridContainer.new()
	grid.columns = 5
	for i in range(15):
		var tb := TextureButton.new()
		tb.texture_normal = face_tex[r["gender"]][i]
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.custom_minimum_size = Vector2(106, 94)
		tb.modulate = Color.WHITE if i == int(r["face"]) else Color(0.55, 0.55, 0.55)
		tb.pressed.connect(func(): r["face"] = i; r["head"] = cr.head_for(r["gender"], i); _step_identity())
		grid.add_child(tb)
	work.add_child(grid)
	# how the recruit looks in the field: suggested from the portrait, changeable
	var fh := _row(work)
	_label(fh, "IN THE FIELD")
	_button(fh, " < ", func(): r["head"] = (int(r["head"]) + 14) % 15; _step_identity())
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(70, 150)
	var sol := Soldier.new()
	sol.body = "AF" if r["gender"] == "F" else "AM"
	sol.head = int(r["head"])
	sol.position = Vector2(35, 146)
	holder.add_child(sol)
	fh.add_child(holder)
	_button(fh, " > ", func(): r["head"] = (int(r["head"]) + 1) % 15; _step_identity())
	var co := _row(work)
	_label(co, "COUNTRY")
	var ob := OptionButton.new()
	var countries: Array = main.data.chargen["countries"]
	for c in countries:
		ob.add_item(c)
	ob.selected = countries.find(r["country"])
	ob.item_selected.connect(func(i): cr.set_origin(r, countries[i]); _step_identity())
	co.add_child(ob)
	var nats := cr.nationalities(r["country"])
	if not nats.is_empty():
		var nr := _row(work)
		_label(nr, "NATIONALITY")
		var on := OptionButton.new()
		for n in nats:
			on.add_item(n)
		on.selected = nats.find(r["nationality"])
		on.item_selected.connect(func(i): cr.set_origin(r, r["country"], nats[i]); _step_identity())
		nr.add_child(on)
	var langs: Array = []
	for l in r["languages"]:
		langs.append("%s %d" % [l, int(r["languages"][l])])
	_label(work, "Languages: " + ", ".join(langs), 16)
	_nav()
	_refresh_info()

func _nav() -> void:
	var h := _row(work)
	_button(h, "CANCEL", _cancel)
	var b := _button(h, "NEXT >", next_step)
	b.name = "Next"
	_update_next()

func _update_next() -> void:
	var b := work.find_child("Next", true, false) as Button
	if b == null:
		return
	match step:
		"identity": b.disabled = r["name"].strip_edges() == ""
		"attributes": b.disabled = cr.points_left(r) != 0 and not used_random_attrs
		"background": b.disabled = bg_picks.size() != int(cr.rules["background_picks"]) or (bg_picks.has("LANGUAGE") and bg_lang == "")

func _cancel() -> void:
	r = {}
	_show_menu()

func _step_attributes() -> void:
	step = "attributes"
	_clear(work)
	_label(work, "2. ATTRIBUTES", 24, HI)
	_label(work, "Distribute %d points (1-10 each), or roll them at random." % int(cr.rules["attribute_points"]), 16)
	for a in main.data.chargen["attributes"]:
		var h := _row(work)
		var l := _label(h, a)
		l.custom_minimum_size.x = 200
		_button(h, " - ", func(): _attr(a, -1), int(r["attrs"][a]) > 1 and not used_random_attrs)
		var v := _label(h, str(r["attrs"][a]), 22, HI)
		v.custom_minimum_size.x = 36
		_button(h, " + ", func(): _attr(a, 1), int(r["attrs"][a]) < 10 and cr.points_left(r) > 0 and not used_random_attrs)
	_label(work, "Points left: %d" % cr.points_left(r) if not used_random_attrs else "Random set", 20, HI)
	var h2 := _row(work)
	_button(h2, "RANDOM", func(): cr.random_attrs(r); used_random_attrs = true; _step_attributes())
	_button(h2, "ALLOCATE", func(): _reset_attrs(); _step_attributes())
	_nav()
	_refresh_info()

func _attr(a: String, d: int) -> void:
	cr.change_attr(r, a, d)
	_step_attributes()

func _reset_attrs() -> void:
	used_random_attrs = false
	for a in r["attrs"]:
		r["attrs"][a] = 1

func _step_background() -> void:
	step = "background"
	_clear(work)
	_label(work, "3. BACKGROUND SKILLS", 24, HI)
	_label(work, "What the recruit learned by age 17: choose %d, each at +%d." % [int(cr.rules["background_picks"]), int(cr.rules["background_level"])], 16)
	var grid := GridContainer.new()
	grid.columns = 2
	for s in cr.rules["background_skills"]:
		var b := Button.new()
		b.text = s
		b.toggle_mode = true
		b.button_pressed = bg_picks.has(s)
		b.custom_minimum_size.x = 270
		b.disabled = not bg_picks.has(s) and bg_picks.size() >= int(cr.rules["background_picks"])
		b.pressed.connect(func(): _toggle_bg(s))
		grid.add_child(b)
	work.add_child(grid)
	if bg_picks.has("LANGUAGE"):
		var h := _row(work)
		_label(h, "LANGUAGE")
		var ob := OptionButton.new()
		ob.add_item("- choose -")
		var avail: Array = []
		for l in main.data.chargen["languages"]:
			if not r["languages"].has(l) or r["languages"][l] < cr.rules["native_language_level"]:
				avail.append(l)
				ob.add_item(l)
		ob.selected = avail.find(bg_lang) + 1
		ob.item_selected.connect(func(i): bg_lang = "" if i == 0 else avail[i - 1]; _update_next())
		h.add_child(ob)
	_nav()
	_refresh_info()

func _toggle_bg(s: String) -> void:
	if bg_picks.has(s):
		bg_picks.erase(s)
	elif bg_picks.size() < int(cr.rules["background_picks"]):
		bg_picks.append(s)
	_step_background()

func _step_career() -> void:
	step = "career"
	_clear(work)
	var n: int = r["terms"].size()
	_label(work, "4. TERM %d (AGE %d-%d)" % [n + 1, 17 + 4 * n, 21 + 4 * n], 24, HI)
	var forced := cr.forced_career(r)
	if forced != "":
		_label(work, ("In prison for this term." if forced == "PRISON" else "War: this term is served under fire as " + forced + "."), 18)
		_button(work, "SERVE: " + forced, func(): choose_career(cr.begin_forced(r)))
		_refresh_info()
		return
	if r["war"]:
		_label(work, "WAR! Choose a branch of the armed forces for one term under fire.", 18, HI)
	var g := _row(work)
	for gr in cr.rules["groups"]:
		var b := Button.new()
		b.text = gr
		b.toggle_mode = true
		b.button_pressed = gr == group
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): group = gr; _step_career())
		g.add_child(b)
	for c in cr.rules["careers"]:
		if c["group"] != group or c["req"].get("never", false):
			continue
		var why := cr.entry_problem(r, c)
		var h := _row(work)
		var b := _button(h, c["name"], choose_career.bind(c["name"]), why == "", c.get("note", ""))
		b.custom_minimum_size.x = 300
		if why != "":
			_note(h, why, 14, DARK.lightened(0.35))
		else:
			_note(h, "%d skills, %d secondary" % [int(c["picks"]), int(c["secondary"])], 14)
	_refresh_info()

func choose_career(cname: String) -> void:
	snapshot = r.duplicate(true)
	term = cr.start_term(r, cname)
	pending = {}
	pending_lang = ""
	secondary = []
	for i in range(int(term["secondary"])):
		secondary.append("")
	_step_allocate()

func _picks_left() -> int:
	var used := 0
	for s in pending:
		used += int(pending[s])
	return int(term["picks"]) - used

## Preview of the recruit after this term's picks (half-level rule included).
func _preview() -> Dictionary:
	var p := r.duplicate(true)
	for s in pending:
		cr.add_skill(p, s, int(pending[s]), pending_lang if s == "LANGUAGE" else "")
	for s in secondary:
		if s != "":
			cr.add_skill(p, s, 1)
	return p

func _step_allocate() -> void:
	step = "allocate"
	_clear(work)
	var c := cr.career(term["career"])
	_label(work, "%s - TERM %d" % [term["career"], r["terms"].size() + 1], 24, HI)
	if c.has("note"):
		_label(work, c["note"], 15)
	_label(work, "Skill levels to assign: %d" % _picks_left(), 20, HI)
	var p := _preview()
	for s in c["skills"]:
		var h := _row(work)
		var l := _label(h, "%s (%s)" % [s, cr.controlling(s).substr(0, 3)])
		l.custom_minimum_size.x = 290
		_button(h, " - ", func(): _pick(s, -1), int(pending.get(s, 0)) > 0)
		var now := cr.level(r, s)
		var after := cr.level(p, s, pending_lang) if s == "LANGUAGE" and pending_lang != "" else cr.level(p, s)
		var v := _label(h, ("%d" % now) if after == now else ("%d > %d" % [now, after]), 18, HI if after != now else RED)
		v.custom_minimum_size.x = 70
		_button(h, " + ", func(): _pick(s, 1), _picks_left() > 0)
	if c["skills"].has("LANGUAGE") and int(pending.get("LANGUAGE", 0)) > 0:
		var h := _row(work)
		_label(h, "LANGUAGE")
		var ob := OptionButton.new()
		var all: Array = main.data.chargen["languages"]
		for l in all:
			ob.add_item(l)
		if pending_lang == "":
			pending_lang = cr._default_language(r)
		ob.selected = all.find(pending_lang)
		ob.item_selected.connect(func(i): pending_lang = all[i]; _step_allocate())
		h.add_child(ob)
	for i in range(secondary.size()):
		var h := _row(work)
		_label(h, "SECONDARY ACTIVITY")
		var ob := OptionButton.new()
		ob.add_item("- choose -")
		var sec: Array = cr.rules["secondary_skills"]
		for s in sec:
			ob.add_item(s)
		ob.selected = sec.find(secondary[i]) + 1
		ob.item_selected.connect(func(k): secondary[i] = "" if k == 0 else sec[k - 1]; _step_allocate())
		h.add_child(ob)
	var ready := _picks_left() == 0 and not secondary.has("")
	var h2 := _row(work)
	_button(h2, "< BACK", _undo_term, cr.forced_career(snapshot) == "", "Choose another career")
	_button(h2, "AUTO", auto_allocate)
	var b := _button(h2, "SERVE TERM", serve_term, ready)
	b.name = "Serve"
	_refresh_info(p)

func _pick(s: String, d: int) -> void:
	var v: int = int(pending.get(s, 0)) + d
	if v <= 0:
		pending.erase(s)
	else:
		pending[s] = v
	_step_allocate()

## Fill the remaining picks and secondary activities the way the random recruiter does.
func auto_allocate() -> void:
	var c := cr.career(term["career"])
	var list: Array = c["skills"]
	while _picks_left() > 0:
		var k := mini(cr.rng.randi_range(0, list.size() - 1), cr.rng.randi_range(0, list.size() - 1))
		pending[list[k]] = int(pending.get(list[k], 0)) + 1
	var sec: Array = cr.rules["secondary_skills"]
	for i in range(secondary.size()):
		if secondary[i] == "":
			secondary[i] = sec[cr.rng.randi_range(0, sec.size() - 1)]
	_step_allocate()

## Back to the career choice: start_term may have given basic training and a rank, so the
## recruit is restored from the snapshot taken before the term began.
func _undo_term() -> void:
	if not snapshot.is_empty():
		r = snapshot
		snapshot = {}
	_step_career()

func serve_term() -> void:
	if _picks_left() != 0 or secondary.has(""):
		return
	for s in pending:
		cr.add_skill(r, s, int(pending[s]), pending_lang if s == "LANGUAGE" else "")
		term["gained"][s] = int(pending[s])
	for s in secondary:
		cr.add_skill(r, s, 1)
		term["gained"][s] = int(term["gained"].get(s, 0)) + 1
	var ev := cr.end_term(r, term)
	if r["done"]:
		cr.finish(r)
		_step_profile(ev)
	else:
		_step_career()
		for e in ev:
			_label(work, e, 16, HI)

func _step_profile(ev: Array = []) -> void:
	step = "profile"
	_clear(work)
	for e in ev:
		_label(work, e, 16, HI)
	_sheet(work, r)
	var h := _row(work)
	_button(h, "ENLIST", enlist, squad.size() < MAX_SQUAD)
	_button(h, "DISCARD", _cancel)
	_refresh_info()

func enlist() -> void:
	if r.is_empty() or squad.size() >= MAX_SQUAD:
		return
	squad.append(r)
	r = {}
	_refresh_roster()
	_show_menu()

# ---------------- viewing ----------------
func view_recruit(i: int) -> void:
	viewing = i
	step = "view"
	r = {}
	_clear(work)
	var m: Dictionary = squad[i]
	_sheet(work, m)
	var h := _row(work)
	_button(h, "MAKE LEADER", func(): _set_leader(i), leader != i, "The leader is the one Exor 1 calls on the radio")
	_button(h, "DISCHARGE", func(): discharge(i))
	_button(h, "CLOSE", _show_menu)
	_refresh_info(m)

func _set_leader(i: int) -> void:
	leader = i
	_refresh_roster()
	view_recruit(i)

func discharge(i: int) -> void:
	squad.remove_at(i)
	if leader >= squad.size():
		leader = 0
	elif i < leader:
		leader -= 1
	_refresh_roster()
	_show_menu()

## Profile sheet (the original "View Recruit" / printable record).
func _sheet(box: Node, m: Dictionary) -> void:
	_label(box, "%s  -  %s" % [m["name"], m["rank"]], 24, HI)
	var origin: String = m["country"] + (" / " + m["nationality"] if m["nationality"] != "" else "")
	_label(box, "%s, age %d. %s" % ["Male" if m["gender"] == "M" else "Female", int(m["age"]), origin], 16)
	var at: Array = []
	for a in m["attrs"]:
		at.append("%s %d" % [a.substr(0, 3), int(m["attrs"][a])])
	_label(box, "  ".join(at), 18, HI)
	var sk: Array = []
	for s in m["skills"]:
		if int(m["skills"][s]) > 0:
			sk.append([s, m["skills"][s]])
	sk.sort_custom(func(x, y): return x[1] > y[1])
	_label(box, "SKILLS: " + ", ".join(sk.map(func(x): return "%s %s" % [x[0], _lv(x[1])])), 15)
	var ln: Array = []
	for l in m["languages"]:
		ln.append("%s %s" % [l, _lv(m["languages"][l])])
	_label(box, "LANGUAGES: " + ", ".join(ln), 15)
	_label(box, "SERVICE: " + " > ".join(m["terms"].map(func(t): return t["career"])), 15)
	var hits: Dictionary = m["hits"]
	_label(box, "HIT CAPACITY: head %d, chest %d, abdomen/limbs %d" % [hits["HEAD"], hits["CHEST"], hits["ABDOMEN"]], 15)
	_label(box, "LOAD %d kg   THROW %d m   INITIATIVE %d   RADS %d   MONEY $%d" % [m["load"], m["throw"], m["initiative"], m["rads"], m["money"]], 15)
	var hn: Dictionary = m["hit_numbers"]
	_label(box, "HIT NUMBERS (close/med/long/ext): " + "  ".join(hn.keys().map(func(k): return "%s %s" % [k.substr(0, 5), "/".join(hn[k].map(func(v): return str(v)))])), 14)

static func _lv(v: float) -> String:
	return ("%d" % int(v)) + (" 1/2" if v - floorf(v) >= 0.5 else "")

## Right panel: portrait, name and the service log so far.
func _refresh_info(m: Dictionary = {}) -> void:
	if m.is_empty():
		m = r
	_clear(info)
	if m.is_empty():
		return
	var tr := TextureRect.new()
	tr.texture = face_tex[m["gender"]][int(m["face"])]
	tr.custom_minimum_size = Vector2(288, 258)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	info.add_child(tr)
	_label(info, m["name"] if m["name"] != "" else "(no name)", 22, HI)
	if step in ["attributes", "background", "career", "allocate"] or m.has("terms"):
		var at: Array = []
		for a in m["attrs"]:
			at.append("%s %d" % [a.substr(0, 3), int(m["attrs"][a])])
		_label(info, "  ".join(at), 15)
	if m.get("rank", "") != "":
		_label(info, m["rank"], 16)
	for e in m.get("log", []).slice(-12):
		_label(info, "- " + e, 14)

# ---------------- squad file and deploy ----------------
func save_squad() -> void:
	var f := FileAccess.open(SQUAD_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"squad": squad, "leader": leader, "mode": main.difficulty}, " "))
	f.close()
	_refresh_roster()

func load_squad() -> void:
	var d = GameData._json(SQUAD_FILE)
	if d == null:
		return
	squad = d["squad"]
	leader = int(d["leader"])
	main.difficulty = String(d.get("mode", main.difficulty))
	_refresh_roster()
	_show_menu()

func toggle_mode() -> void:
	main.difficulty = "normal" if main.difficulty == "story" else "story"
	_refresh_roster()

func deploy() -> void:
	if squad.is_empty():
		return
	main.deploy(squad, leader)

# ---------------- scripted test hooks ----------------
func test_identity(nm: String, gender: String, face: int, country: String) -> void:
	r["gender"] = gender
	r["face"] = face
	r["head"] = cr.head_for(gender, face)
	r["name"] = nm
	cr.set_origin(r, country)
	_step_identity()

func test_attrs(values: Array) -> void:
	var attrs: Array = main.data.chargen["attributes"]
	_reset_attrs()
	for i in range(attrs.size()):
		r["attrs"][attrs[i]] = int(values[i])
	_step_attributes()

func test_background(picks: Array, lang: String) -> void:
	bg_picks = picks.duplicate()
	bg_lang = lang
	_step_background()

func test_group(g: String) -> void:
	group = g
	_step_career()

## Serve terms (forced ones as required, otherwise the given career) until the recruit is done.
func test_finish(cname: String) -> void:
	var guard := 0
	while step != "profile" and guard < 14:
		guard += 1
		if step == "career":
			var f := cr.forced_career(r)
			choose_career(cr.begin_forced(r) if f != "" else cname)
		auto_allocate()
		serve_term()
