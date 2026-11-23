## Headless check that the screens actually receive real GUI clicks:
## godot --headless --path . --script tests/test_gui_input.gd
## The screens hang under a plain Node, so a FULL_RECT screen would stay 0x0 and swallow
## every click (the office bug): this boots the game, sizes the screens and sends real
## InputEventMouseButton events through Input.parse_input_event.
extends SceneTree

var fails := 0

func _init() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _click(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	var up: InputEventMouseButton = ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	root.size = Vector2(1280, 800)            # headless default is 64x64: the stretch
	await process_frame                        # transform would eat the click positions
	await process_frame
	var chargen = main.screen
	_check(chargen.get_script().resource_path.contains("chargen"), "game opens in chargen")
	_check(chargen is Control and chargen.size == Vector2(1280, 800), "chargen screen sized 1280x800 (got %s)" % [chargen.size])
	var btn: Button = null
	for c in chargen.roster_box.get_children():
		if c is Button and c.text == "RANDOMLY RECRUIT":
			btn = c
	if btn == null:
		print("FAIL RANDOMLY RECRUIT button not found in the roster")
		quit(1)
		return
	var br := btn.get_global_rect()
	print("RANDOMLY RECRUIT global rect: ", br)
	_click(br.position + br.size / 2.0)                 # the real click, on the measured rect
	for i in range(6):
		await process_frame
	_check(chargen.squad.size() == 1, "a real click recruits a soldier (squad %d)" % chargen.squad.size())
	# deploy: the office must be sized and its radio hotspot must react to a real click
	var cr := ChargenRules.new(GameData._json("res://data/careers.json"), main.data.chargen, 77)
	var sq: Array = []
	for i in range(4):
		var r := cr.random_recruit()
		Forces.equip(r)
		sq.append(r)
	main.deploy(sq, 0)
	await process_frame
	await process_frame
	var office = main.screen
	_check(office.get_script().resource_path.contains("office"), "deploy opens the office")
	_check(office is Control and office.size == Vector2(1280, 800), "office screen sized 1280x800 (got %s)" % [office.size])
	_click(Vector2(544, 740))                 # the radio hotspot (105,172 62x26, x4)
	for i in range(6):
		await process_frame
	_check(main.screen.get_script().resource_path.contains("briefing"), "a real click on the radio opens the briefing")
	print("GUI INPUT TEST ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)