## Headless check of the bottom icon bar (action_bar.gd): ten buttons, the number hotkeys
## 1-9/0, and the options window on top of the bar (its own numbers and ESC/backing out).
## godot --headless --path . --script tests/test_action_bar.gd
extends SceneTree

func _init() -> void:
	var calls := {}                  # lambdas capture locals by value: use a Dictionary (reference)
	var bar := preload("res://scripts/action_bar.gd").new()
	root.add_child(bar)
	var defs: Array = []
	for i in range(10):
		var idx := i
		defs.append({"key": str((i + 1) % 10), "label": "ICON %d" % i, "cb": func(): calls[i] = true})
	bar.setup(defs)
	var btns: Array = bar.bar.get_children()
	assert(btns.size() == 10, "ten buttons")
	assert(String(btns[0].text).begins_with("1\nICON 0"))
	assert(String(btns[9].text).begins_with("0\nICON 9"))
	# the numbers pick straight from the keyboard
	bar.hotkey(KEY_1)
	bar.hotkey(KEY_5)
	bar.hotkey(KEY_0)
	assert(calls.get(0) == true and calls.get(4) == true and calls.get(9) == true, "numbers 1, 5 and 0 ran their callbacks: %s" % [calls.keys()])
	# blank key: not one of the bar's
	assert(bar.hotkey(KEY_X) == false)
	# an options window opens over the bar, its own numbers pick, and it closes
	var got := {}
	bar.choose("TEST", [["First", func(): got["a"] = 1], ["Second", func(): got["b"] = 1]])
	assert(bar.choice_open(), "window open")
	bar.hotkey(KEY_2)
	assert(got.get("b") == 1 and not got.has("a"), "the window's number 2 ran its choice")
	assert(not bar.choice_open(), "the window closed after a choice")
	bar.hotkey(KEY_2)                                    # back to the bar: number 2 = the second icon
	assert(calls.get(1) == true, "bar keys work again after the window")
	# a too-high number does nothing while the window is open
	bar.choose("TEST2", [["Only", func(): got["only"] = 2]])
	bar.hotkey(KEY_4)
	bar.hotkey(KEY_9)
	assert(not got.has("only") and bar.choice_open(), "wrong numbers are not choices")
	bar.close_choices()
	bar.choose("TEST3", [["A", func(): got["x"] = 0], ["B", func(): got["x"] = 0], ["C", func(): got["x"] = 0]])
	assert(bar.win.get_child_count() == 4, "title label + three buttons")
	bar.close_choices()
	assert(not bar.choice_open(), "closed")
	print("ACTIONBAR TEST PASS")
	quit(0)
