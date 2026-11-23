## Game flow: recruitment (chargen) -> HQ office -> radio briefing -> world map -> a town or an
## encounter (field view) -> back to the world map.
## Also runs scripted test sessions:
##   godot --path remake/godot -- --test=<name>   (writes screenshots to user://tests/<name>/)
extends Node

const SCALE := 4                      # original 320x200 art shown at 4x on a 1280x800 window

var data := GameData.new()
var screen: Node = null
var leader := "NICK"
var test_name := ""
var test_steps: Array = []
var test_t := 0.0
var shot_dir := ""
var remastered := false               # original 1991 art; the AI art is set aside
const ALLOW_AI_ART := false           # true brings back F2 (AI art <-> original); off at the user's request
var squad: Array = []                 # recruits from chargen (Dictionaries, see chargen_rules.gd)
var leader_index := 0
var rng_seed := 0                     # 0 = random; tests use a fixed seed
var room: Node = null                 # interior scene while the squad is inside a building
var campaign: Campaign
var world: World
var local: Dictionary = {}            # what the field view shows: {mode, centre, start, group}
var fallen: Array = []                # recruits killed in action
var squad_vehicle := ""               # vehicle the squad rides in (battles start with it)
var vehicle_fuel := 0.0               # litres in its tank
var vehicle_at := Vector2(-1, -1)     # world cell where it is parked; (-1, -1) = with the squad
var fuel_cans := 0.0                  # litres the squad carries in jerrycans (20 L a man)
const CAN_LITRES := 20.0
var difficulty := "normal"            # "normal" or "story" (chosen at recruitment)
var music: AudioStreamPlayer          # soundtrack (a track per screen: office, map, battle)
var music_track := ""
var sfx_players: Array[AudioStreamPlayer] = []   # a small pool so effects can overlap
const SQUAD_MAX := 4

func _ready() -> void:
	data.load_all()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			test_name = a.substr(7)
	if test_name != "":
		rng_seed = 2000
		seed(2000)                         # tests repeat exactly
	campaign = Campaign.new(data.missions, data.cities, data.items, rng_seed)
	campaign.clock = func(): return world.minutes
	campaign.is_story = func(): return difficulty == "story"
	campaign.squad_size = func(): return maxi(1, squad.size())   # M9: garrisons scale with the squad
	campaign.squad_vehicle = func(): return squad_vehicle        # M9 economy: truck needed for dump missions
	world = World.new(rng_seed)
	if test_name != "":
		_setup_test()
	else:
		show_chargen()

const TEST_DEVICE := 4242               # input events made by the test runner carry this device id

## Real mouse / keyboard input is ignored while a test runs (the window is on someone's desktop).
func input_ok(ev: InputEvent) -> bool:
	return test_name == "" or ev.device == TEST_DEVICE

## Picture path: the AI remaster when it exists and is enabled, otherwise the original.
func art(lib: String, name: String) -> String:
	var r := "res://remastered/%s/%s.png" % [lib, name]
	if remastered and ResourceLoader.exists(r):
		return r
	return "res://original/graphics/%s/%s.png" % [lib, name]

## Remastered pictures are stored at 4x the original size; divide by this when sizing.
func art_div(path: String) -> float:
	return 4.0 if path.begins_with("res://remastered/") else 1.0

func _unhandled_key_input(ev: InputEvent) -> void:
	if input_ok(ev) and ev.pressed and not ev.echo and not squad.is_empty():
		if ev.keycode == KEY_F5 and can_save():
			save_game(QUICKSAVE)
			toast("GAME SAVED.")
		elif ev.keycode == KEY_F9 and FileAccess.file_exists(QUICKSAVE):
			load_game(QUICKSAVE)
			toast("GAME LOADED.")
	if ALLOW_AI_ART and input_ok(ev) and ev.pressed and ev.keycode == KEY_F2:
		remastered = not remastered
		Soldier.remastered = remastered
		if screen and screen.has_method("refresh_art"):
			screen.refresh_art()

# ---------------- saving ----------------
## The game is saved between scenes: on the world map, at the office or walking in a town (a
## save made in a town goes on at its edge). Not during a battle or inside a building.
var QUICKSAVE := "user://quicksave.sav"    # tests point these into user://tests/
var AUTOSAVE := "user://autosave.sav"
const SAVE_VERSION := 1

func can_save() -> bool:
	return screen != null and room == null and screen.get_script() in [
		preload("res://scripts/worldmap.gd"), preload("res://scripts/office.gd"), preload("res://scripts/tactical.gd")]

func game_state() -> Dictionary:
	return {"version": SAVE_VERSION, "squad": squad, "leader": leader_index, "fallen": fallen,
		"mode": difficulty, "vehicle": squad_vehicle, "world": world.to_dict(), "campaign": campaign.to_dict(),
		"fuel": vehicle_fuel, "vehicle_at": [vehicle_at.x, vehicle_at.y], "cans": fuel_cans,
		"town": String(screen.here) if screen != null and screen.get_script() == preload("res://scripts/tactical.gd") else "",
		"saved": Time.get_datetime_string_from_system()}

func apply_state(d: Dictionary) -> void:
	squad = d["squad"]
	leader_index = clampi(int(d.get("leader", 0)), 0, maxi(0, squad.size() - 1))
	leader = String(squad[leader_index]["name"]).split(" ")[0] if not squad.is_empty() else "NICK"
	fallen = d.get("fallen", [])
	difficulty = String(d.get("mode", "normal"))
	squad_vehicle = String(d.get("vehicle", ""))
	vehicle_fuel = float(d.get("fuel", fuel_cap()))
	var va: Array = d.get("vehicle_at", [-1, -1])
	vehicle_at = Vector2(va[0], va[1])
	fuel_cans = float(d.get("cans", 0.0))
	world.from_dict(d["world"])
	campaign.from_dict(d["campaign"])
	local = {}

func save_game(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(game_state())
	f.close()
	return true

## Load a save and continue on the world map. False if the file is missing or not a save.
func load_game(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var d = f.get_var()
	f.close()
	if not d is Dictionary or int(d.get("version", 0)) != SAVE_VERSION:
		return false
	apply_state(d)
	if String(d.get("town", "")) != "":
		enter_town(d["town"])
	else:
		show_world()
	return true

## Short line over everything for two seconds.
func toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, 380)
	l.size = Vector2(1280, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	var layer := CanvasLayer.new()          # over the screen, whatever its camera does
	layer.layer = 100
	layer.add_child(l)
	add_child(layer)
	get_tree().create_timer(2.0).timeout.connect(layer.queue_free)

# ---------------- sound ----------------
## Background music for a screen: a track name from original/audio/music (looped).
func set_music(track: String) -> void:
	if music_track == track:
		return
	music_track = track
	if music == null:
		music = AudioStreamPlayer.new()
		music.volume_db = -14.0
		music.finished.connect(_music_again)
		add_child(music)
	if track == "":
		music.stop()
		return
	var path := "res://original/audio/music/%s.wav" % track
	if not ResourceLoader.exists(path):
		music_track = ""
		return
	music.stream = load(path)
	if sound_on:
		music.play()

func _music_again() -> void:
	if music != null and music.stream != null and music_track != "":
		music.play()

## Stop the sound cleanly when the game closes (no leaked stream players at exit).
func _exit_tree() -> void:
	stop_audio()

func stop_audio() -> void:
	if music != null:
		music.stop()
		music.stream = null
	for s in sfx_players:
		s.stop()
		s.stream = null

## The Game Options' SOUND (icon 2 on the bottom bar): all music and effects at once.
var sound_on := true

func toggle_sound() -> bool:
	sound_on = not sound_on
	if not sound_on:
		if music != null:
			music.stop()
		for s in sfx_players:
			s.stop()
	elif music_track != "":
		var t := music_track
		music_track = ""
		set_music(t)                     # bring the screen's track back
	return sound_on

## A sound effect from original/audio/sfx, from a small pool so they can overlap.
func play_sfx(name: String, db := -6.0) -> void:
	var path := "res://original/audio/sfx/%s.wav" % name
	if not sound_on:
		return
	if not ResourceLoader.exists(path):
		return
	var pl: AudioStreamPlayer = null
	for s in sfx_players:
		if not s.playing:
			pl = s
			break
	if pl == null:
		if sfx_players.size() >= 6:
			pl = sfx_players[0]
		else:
			pl = AudioStreamPlayer.new()
			sfx_players.append(pl)
			add_child(pl)
	pl.stream = load(path)
	pl.volume_db = db
	pl.play()

func _swap(node: Node) -> void:
	if room:
		room.queue_free()
		room = null
	if screen:
		screen.queue_free()
	screen = node
	add_child(node)
	if node is Control:
		# the screens hang under a plain Node: anchors have no parent rect, so a
		# FULL_RECT screen would stay 0x0 and never receive mouse clicks - pin to
		# the top-left corner and size it explicitly
		node.set_anchors_preset(Control.PRESET_TOP_LEFT)
		node.size = Vector2(1280, 800)

func show_chargen() -> void:
	set_music("TWICHAR3")
	var c := preload("res://scripts/chargen.gd").new()
	c.main = self
	_swap(c)

## Chargen is done: the squad reports to the office; the leader's name goes on the radio.
func deploy(recruits: Array, leader_i: int) -> void:
	squad = recruits.duplicate(true)
	leader_index = clampi(leader_i, 0, squad.size() - 1)
	leader = String(squad[leader_index]["name"]).split(" ")[0]
	var purse := 0
	for r in squad:
		purse += int(r.get("money", 0))
	campaign.funds = purse                       # the squad's savings go to Krakow's cash box
	show_office()

## A squad for screens reached without chargen (tests that start at the office).
func default_squad() -> void:
	if not squad.is_empty():
		return
	var cr := ChargenRules.new(GameData._json("res://data/careers.json"), data.chargen, 77)
	for i in range(4):
		squad.append(cr.random_recruit())
	if campaign.funds == 0:                      # tests that start at the office still get a purse
		for r in squad:
			campaign.funds += int(r.get("money", 0))

func show_office() -> void:
	set_music("TWICHAR3")
	var o := preload("res://scripts/office.gd").new()
	o.main = self
	o.notice = replacements()
	var notes: Array = [] if o.notice == "" else [o.notice]
	if squad_vehicle != "" and vehicle_at.x >= 0 and vehicle_fuel <= 0.0:
		notes.append("A RECOVERY TEAM BRINGS THE %s BACK FROM WHERE IT RAN DRY." % squad_vehicle)
		vehicle_at = Vector2(-1, -1)
	if squad_vehicle == "" and not campaign.motor_pool.is_empty():
		squad_vehicle = campaign.motor_pool[0]
		vehicle_at = Vector2(-1, -1)
		vehicle_fuel = fuel_cap()
		notes.append("THE %s FROM THE MOTOR POOL GOES WITH THE SQUAD." % squad_vehicle)
	elif driving() and vehicle_fuel < fuel_cap():
		vehicle_fuel = fuel_cap()
		notes.append("THE MOTOR POOL REFUELS THE %s." % squad_vehicle)
	o.notice = "  ".join(notes)
	_swap(o)

# ---------------- the squad's vehicle ----------------
## The squad rides in its vehicle (it is not parked somewhere).
func driving() -> bool:
	return squad_vehicle != "" and vehicle_at.x < 0

func vehicle_kind() -> String:
	return String(Forces.vehicle_data(squad_vehicle).get("kind", "wheeled")) if squad_vehicle != "" else ""

func fuel_cap() -> float:
	return float(Forces.vehicle_data(squad_vehicle).get("fuel_cap", 0)) if squad_vehicle != "" else 0.0

## Litres an hour on the move (vehicles.json fuel_cons, read as litres per hour of driving).
func fuel_per_hour() -> float:
	return float(Forces.vehicle_data(squad_vehicle).get("fuel_cons", 0)) if squad_vehicle != "" else 0.0

## The vehicle is with the squad or parked within reach of a town (for its leader's fuel).
func vehicle_near(city: String) -> bool:
	if squad_vehicle == "":
		return false
	return driving() or vehicle_at.distance_to(world.city_cell(data.city(city))) < 3.0

## Litres the jerrycans can still take.
func cans_space() -> float:
	return maxf(0.0, CAN_LITRES * squad.size() - fuel_cans)

## Pour the jerrycans into the vehicle's tank. Returns the litres poured.
func pour_cans() -> float:
	var n := minf(fuel_cans, fuel_cap() - vehicle_fuel) if squad_vehicle != "" else 0.0
	vehicle_fuel += n
	fuel_cans -= n
	return n

## Drain fuel from a wreck: into the tank while the squad drives, the rest into the jerrycans.
## Returns [into the tank, into the cans].
func take_fuel(litres: float) -> Array:
	var tank := minf(litres, fuel_cap() - vehicle_fuel) if driving() else 0.0
	vehicle_fuel += tank
	var cans := minf(litres - tank, cans_space())
	fuel_cans += cans
	return [tank, cans]

## Fill the tank (a friendly town's leader, or the motor pool).
func refuel() -> void:
	vehicle_fuel = fuel_cap()

## The vehicle is gone (knocked out in a battle).
func lose_vehicle() -> void:
	campaign.motor_pool.erase(squad_vehicle)
	squad_vehicle = ""
	vehicle_fuel = 0.0
	vehicle_at = Vector2(-1, -1)

## Krakow fills the gaps the fallen left: new random recruits, ordinary soldiers without the
## veterans' experience. Returns the line for the office.
func replacements() -> String:
	if fallen.is_empty() or squad.size() >= SQUAD_MAX:
		return ""
	var cr := ChargenRules.new(GameData._json("res://data/careers.json"), data.chargen, rng_seed + int(world.minutes))
	var names: Array = []
	while squad.size() < SQUAD_MAX:
		var r := cr.random_recruit()
		squad.append(r)
		names.append(r["name"])
	return "HQ ASSIGNS REPLACEMENTS TO THE SQUAD: " + ", ".join(names) + "."

func show_briefing() -> void:
	set_music("TWICHAR3")
	var b := preload("res://scripts/briefing.gd").new()
	b.main = self
	b.text = campaign.briefing(leader)
	_swap(b)

func show_tactical() -> void:
	set_music("XPLORE1")
	if local.is_empty():
		var c: Dictionary = data.city("KRAKOW")
		local = {"mode": "town", "centre": Vector2(c["a"], c["b"]), "start": Vector2(c["a"], c["b"])}
	var t := preload("res://scripts/tactical.gd").new()
	t.main = self
	_swap(t)

func show_world() -> void:
	set_music("XPLORE1")
	default_squad()
	var w := preload("res://scripts/worldmap.gd").new()
	w.main = self
	_swap(w)
	if test_name == "":
		save_game(AUTOSAVE)                 # every return to the map

## Motor Pool: buy, repair, refuel vehicles at Krakow.
func show_motor_pool() -> void:
	var mp := preload("res://scripts/motor_pool.gd").new()
	mp.main = self
	_swap(mp)

## Krakow HQ computer: funds, stores, motor pool and the squad's state (M4's resource screen).
func show_computer() -> void:
	var c := preload("res://scripts/computer.gd").new()
	c.main = self
	_swap(c)

## From the world map into a town: the squad walks in from the side it came from.
func enter_town(name: String) -> void:
	var c: Dictionary = data.city(name)
	var centre := Vector2(c["a"], c["b"])
	var from: Vector2 = world.to_metres(world.pos) - centre
	if from.length() < 1.0:
		from = Vector2(-1, 1)
	local = {"mode": "town", "centre": centre, "start": centre + from.normalized() * 55.0, "city": name}
	world.pos = world.city_cell(c)
	show_tactical()

## Trouble on the way: a field view of the spot, with the group in it.
func enter_encounter(g: Dictionary) -> void:
	var at: Vector2 = world.to_metres(world.pos)
	local = {"mode": "encounter", "centre": at, "start": at, "group": g}
	show_tactical()

## A battle (the turn-based battle screen). setup: see battle_view.gd.
func start_battle(setup: Dictionary) -> void:
	set_music("BATTLE1")
	default_squad()
	var v := preload("res://scripts/battle_view.gd").new()
	v.main = self
	v.setup = setup
	if not setup.has("squad_vehicle"):
		setup["squad_vehicle"] = squad_vehicle if driving() else ""   # a parked vehicle stays out of it
	_swap(v)

## Trouble on the road: the group's men (and vehicle) on the ground of the spot.
func battle_from_encounter(g: Dictionary) -> void:
	var at: Vector2 = world.to_metres(world.pos)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed + int(world.minutes)
	var f: Dictionary = Forces.group(g["name"], int(g.get("count", 3)), rng)
	var lm := LocalMap.new(world, at, 60.0)
	start_battle({"local": lm, "centre": at, "from": Vector2(-1, 0.3), "men": f["men"], "vehicles": f["vehicles"],
		"back": "world", "title": g["name"]})

## The Black Legion in a town (a mission's "eliminate" step).
func battle_in_town(city: String, from_pos: Vector2) -> void:
	var c: Dictionary = data.city(city)
	var centre := Vector2(c["a"], c["b"])
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed + int(world.minutes) + 5
	var n := maxi(1, campaign.enemies_in(city))
	var st := campaign.step()
	var here := campaign.place(st) == city if st != "" else false
	var tank: bool = here and st.begins_with("clear:") and campaign.mission["type"] == "tank"
	var scavengers: bool = here and st.begins_with("repair:")
	# the tank comes with its crew's comrades on foot (Campaign.TANK_ESCORTS); scavengers are marauders
	var f: Dictionary = Forces.group("MARAUDERS" if scavengers else "BLACK LEGION", Campaign.TANK_ESCORTS if tank else n, rng)
	var town := Town.new(data.cities)
	var lm := LocalMap.new(world, centre, 130.0, true)
	start_battle({"local": lm, "town": town, "centre": centre, "from": from_pos - centre, "men": f["men"],
		"vehicles": [campaign.mission["tank"]] if tank else [], "tank": tank,
		"back": "town", "city": city, "title": ("BLACK LEGION %s IN " % campaign.mission["tank"] if tank else ("SCAVENGERS AT " if scavengers else "BLACK LEGION IN ")) + city})

## The hostage-takers / assassins inside their hideout: the fight is in the room. outside: where
## the squad stood at the door (back there afterwards).
func battle_indoors(city: String, bld: Dictionary, outside: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed + int(world.minutes) + 31
	var f: Dictionary = Forces.group("BLACK LEGION", maxi(1, campaign.enemies_in(city)), rng)
	start_battle({"room": bld, "men": f["men"], "squad_vehicle": "", "back": "town", "city": city, "return_at": outside,
		"title": "INSIDE THE %s, %s" % [bld["type"], city]})

## After a battle: the dead leave the squad, the town's mission counts the enemies down, and
## the squad goes back where it came from. No one left: the game is lost.
func battle_over(setup: Dictionary, winner: String, enemy_killed: int) -> void:
	for r in squad.duplicate():
		if r.get("dead", false):
			squad.erase(r)
			fallen.append(r)
	if squad.is_empty():
		if campaign.final_mission:
			campaign.final_mission = false
			campaign.log.append("Defeat: the Black Legion took Krakow")
		elif not campaign.mission.is_empty() and campaign.mission.get("type", "") in ["defend", "tank", "liberate"]:
			# the squad was wiped in a defend/clear mission: the city falls to Czarny
			var city: String = campaign.mission.get("target", "")
			if city != "" and not campaign.lost_cities.has(city):
				campaign.lost_cities.append(city)
				if campaign.friends.has(city):
					campaign.friends.erase(city)
				campaign.pending_story = data.missions["endings"]["city_lost"]
				campaign.log.append("City lost to Czarny: %s" % city)
		_game_over()
		return
	leader_index = clampi(leader_index, 0, squad.size() - 1)
	leader = String(squad[leader_index]["name"]).split(" ")[0]
	if setup.get("back", "") == "town":
		var city: String = setup.get("city", "")
		if setup.get("spy", false):
			if winner == "squad":
				campaign.spy_dead()
		elif setup.get("tank", false):
			if winner == "squad":                    # the tank is knocked out: the step is done
				while campaign.enemies_in(city) > 0:
					campaign.enemy_down(city)
		else:
			for i in range(enemy_killed):
				campaign.enemy_down(city)
		if setup.has("return_at"):              # out of the building, at its door
			var c: Dictionary = data.city(city)
			local = {"mode": "town", "centre": Vector2(c["a"], c["b"]), "start": setup["return_at"], "city": city}
			show_tactical()
		else:
			enter_town(city)
	else:
		show_world()

func _game_over() -> void:
	set_music("LOSE1")
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(1280, 800)
	c.add_child(bg)
	var l := Label.new()
	l.position = Vector2(140, 300)
	l.size = Vector2(1000, 200)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	l.text = "%s\n\n(Click to recruit a new squad.)" % String(data.missions["lines"].get("captured", "YOU HAVE BEEN KILLED BY ENEMY GUNFIRE."))
	c.add_child(l)
	c.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: show_chargen())
	_swap(c)

## Back from a town or an encounter.
func leave_local() -> void:
	local = {}
	show_world()

# ---------------- scripted tests ----------------
func start_mission(t: String) -> void:
	campaign.new_mission(t)

func test_tank_battle() -> void:
	squad_vehicle = "M1A1"
	var at: Vector2 = world.to_metres(world.pos)
	start_battle({"local": LocalMap.new(world, at, 60.0), "centre": at, "from": Vector2(-1, 0), "men": [],
		"vehicles": ["T-72", "T-72"], "back": "world", "title": "TANKS"})
	squad_vehicle = ""

func enter_town_of_mission() -> void:
	enter_town(campaign.mission["target"])

## One room on its own (rooms test): building type and facing as in data/rooms.json.
func show_room(key: String) -> void:
	default_squad()
	var r := preload("res://scripts/interior.gd").new()
	r.main = self
	var parts := key.split("_")
	r.building = {"key": key, "city": "TEST", "type": parts[0], "facing": int(parts[1])}
	_swap(r)
	room = r

func show_soldier_lineup() -> void:
	var root := Node2D.new()
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.36, 0.24)
	bg.size = Vector2(1280, 800)
	root.add_child(bg)
	var bodies := ["AM", "AF", "EM"]
	for row in range(3):
		for d in range(8):
			var s := Soldier.new()
			s.body = bodies[row]
			s.head = row * 4 + 2
			s.dir = d
			s.position = Vector2(110 + d * 150, 220 + row * 250)
			root.add_child(s)
	_swap(root)

func _setup_test() -> void:
	shot_dir = OS.get_user_data_dir() + "/tests/" + test_name
	DirAccess.make_dir_recursive_absolute(shot_dir)
	QUICKSAVE = "user://tests/quicksave.sav"     # the player's own saves are left alone
	AUTOSAVE = "user://tests/autosave.sav"
	match test_name:
		"drive":
			# the motor pool's HMMWV: drive to a town, park and walk, board again, run dry, towed home
			campaign.motor_pool = ["HMMWV"]
			show_office()
			test_steps = [
				[0.5, "shot", "office_vehicle"],
				[0.2, "call", "test_drive_times"],
				[0.2, "call", "show_world"],
				[0.1, "call", "test_drain"],
				[0.1, "call", "refuel"],
				[0.3, "screen", ["go_to_city", "SLOMNIKI"]],
				[0.3, "shot", "route_driving"],
				[3.0, "call1", ["test_drive_check", "arrived"]],
				[0.2, "shot", "arrived_slomniki"],
				[0.2, "screen", ["test_press", 1]],
				[0.2, "key", KEY_V],
				[0.4, "shot", "parked"],
				[0.2, "call1", ["test_drive_check", "parked"]],
				[0.2, "call1", ["test_walk_cells", Vector2i(3, 0)]],
				[2.0, "key", KEY_V],
				[0.3, "call1", ["test_drive_check", "away"]],
				[0.2, "call1", ["test_walk_cells", Vector2i(0, 0)]],
				[2.0, "screen", ["test_press", 1]],
				[0.2, "key", KEY_V],
				[0.3, "call1", ["test_drive_check", "boarded"]],
				[0.2, "call", "test_drain"],
				[0.2, "screen", ["go_to_city", "PROSZOWICE"]],
				[3.0, "shot", "out_of_fuel"],
				[0.2, "call1", ["test_drive_check", "dry"]],
				[0.2, "screen", ["test_press", 0]],
				[0.2, "key", KEY_V],
				[0.5, "shot", "dry_map"],
				# a wrecked T-72 by the road: its fuel into the jerrycans, then into the HMMWV
				[0.2, "screen", ["test_force_wreck", "T-72", 60.0]],
				[0.5, "shot", "wreck_found"],
				[0.2, "screen", ["test_press", 0]],
				[0.5, "shot", "wreck_drained"],
				[0.2, "call1", ["test_drive_check", "cans"]],
				[0.2, "screen", ["test_press", 0]],
				[0.2, "key", KEY_V],
				[0.5, "shot", "poured"],
				[0.2, "call1", ["test_drive_check", "poured"]],
				[0.2, "screen", ["test_force_wreck", "HMMWV", 0.0, true]],
				[0.2, "screen", ["test_press", 0]],
				[0.4, "shot", "wreck_burnt"],
				[0.2, "call1", ["test_drive_check", "burnt"]],
				[0.2, "screen", ["test_press", 0]],
				[0.2, "screen", ["test_force_wreck", "M1A1", 50.0]],
				[0.2, "screen", ["test_press", 0]],
				[0.4, "shot", "wreck_split"],
				[0.2, "call1", ["test_drive_check", "split"]],
				[0.2, "screen", ["test_press", 0]],
				[0.2, "screen", ["test_force_wreck", "T-80", 100.0, false, "trap"]],
				[0.2, "screen", ["test_press", 0]],
				[0.4, "shot", "wreck_trap"],
				[0.2, "call1", ["test_drive_check", "trap"]],
				[0.2, "screen", ["test_press", 0]],
				[0.2, "call", "show_office"],
				[0.5, "shot", "office_recovered"],
				[0.2, "call1", ["test_drive_check", "recovered"]],
				[0.2, "call1", ["test_drive_check", "gate"]],
				[0.2, "call", "show_world"],
				[0.3, "screen", ["test_force_wreck", "2 1/2 TON TRUCK", 40.0, false, "ambush"]],
				[0.2, "screen", ["test_press", 0]],
				[0.4, "shot", "wreck_ambush"],
				[0.2, "screen", ["test_press", 0]],
				[1.5, "shot", "ambush_battle"],
				[0.2, "call1", ["test_drive_check", "ambush"]],
				[0.3, "call", "test_drive_done"],
				[0.3, "quit", 0],
			]
		"save":
			# a mission under way, saved in a town (F5), the game changed, then loaded (F9)
			show_office()
			if FileAccess.file_exists(QUICKSAVE):
				DirAccess.remove_absolute(QUICKSAVE)
			test_steps = [
				[0.2, "call1", ["start_mission", "supplies"]],
				[0.2, "call", "show_world"],
				[0.2, "screen", ["go_to_city", "SKAWINA"]],
				[4.0, "screen", ["test_press", 0]],
				[1.5, "shot", "town_before"],
				[0.2, "call", "test_save_before"],
				[0.2, "key", KEY_F5],
				[0.5, "shot", "saved_toast"],
				[0.2, "call", "test_save_mess"],
				[0.2, "key", KEY_F9],
				[1.0, "shot", "loaded"],
				[0.2, "call", "test_save_after"],
				[0.3, "quit", 0],
			]
		"save_errors":
			# save/load error handling: missing, corrupt, wrong version, valid round-trip
			show_office()
			test_steps = [
				[0.2, "call", "test_save_errors_missing"],
				[0.2, "call", "test_save_errors_corrupt"],
				[0.2, "call", "test_save_errors_wrong_version"],
				[0.2, "call", "test_save_errors_valid"],
				[0.3, "quit", 0],
			]
		"slice":
			# office -> radio -> world map -> march to Skawina -> into town
			show_office()
			test_steps = [
				[1.0, "shot", "office"],
				[0.2, "hover", Vector2(135, 187)],
				[0.5, "shot", "office_hover_radio"],
				[0.2, "call", "show_briefing"],
				[1.0, "shot", "briefing"],
				[0.2, "call", "show_world"],
				[1.0, "shot", "world"],
				[0.2, "screen", ["go_to_city", "SKAWINA"]],
				[4.0, "shot", "arrived"],
				[0.2, "screen", ["test_press", 0]],
				[1.5, "shot", "skawina"],
				[0.2, "key", KEY_L],
				[0.8, "shot", "lcd_map"],
				[0.5, "quit", 0],
			]
		"chargen":
			# recruit two at random and one by hand, deploy, and follow the leader to the radio
			show_chargen()
			test_steps = [
				[0.8, "shot", "roster_empty"],
				[0.2, "screen", ["random_recruit"]],
				[0.2, "screen", ["random_recruit"]],
				[0.6, "shot", "random_recruit_view"],
				[0.2, "screen", ["begin_manual"]],
				[0.2, "screen", ["test_identity", "ANNA KOWALSKA", "F", 6, "POLAND"]],
				[0.6, "shot", "identity"],
				[0.2, "screen", ["next_step"]],
				[0.2, "screen", ["test_attrs", [6, 6, 7, 5, 4, 4]]],
				[0.6, "shot", "attributes"],
				[0.2, "screen", ["next_step"]],
				[0.2, "screen", ["test_background", ["LANGUAGE", "SWIMMING", "WHEELED VEHICLE", "TRACKING"], "ENGLISH"]],
				[0.6, "shot", "background"],
				[0.2, "screen", ["next_step"]],
				[0.2, "screen", ["test_group", "ARMY"]],
				[0.6, "shot", "careers_army"],
				[0.2, "screen", ["choose_career", "ENLISTED INFANTRY"]],
				[0.2, "screen", ["auto_allocate"]],
				[0.6, "shot", "allocate"],
				[0.2, "screen", ["test_finish", "ENLISTED INFANTRY"]],
				[0.6, "shot", "profile"],
				[0.2, "screen", ["enlist"]],
				[0.2, "screen", ["view_recruit", 2]],
				[0.2, "screen", ["_set_leader", 2]],
				[0.6, "shot", "roster_three"],
				[0.2, "key", KEY_F2],
				[0.8, "shot", "roster_classic"],
				[0.2, "key", KEY_F2],
				[0.5, "screen", ["deploy"]],
				[0.8, "shot", "office"],
				[0.2, "call", "show_briefing"],
				[1.5, "shot", "briefing_leader"],
				[0.2, "call", "show_tactical"],
				[1.0, "shot", "tactical_squad"],
				[0.5, "quit", 0],
			]
		"computer":
			# the HQ computer: funds, stores, motor pool (M9 economy), then back to the office
			default_squad()
			show_office()
			test_steps = [
				[0.6, "call", "show_computer"],
				[1.0, "shot", "computer"],
				[0.3, "quit", 0],
			]
		"city":
			# Krakow built from its template, walk to the nearest door and go in, then Skawina
			show_tactical()
			test_steps = [
				[1.2, "shot", "krakow"],
				[0.2, "key", KEY_F2],
				[0.6, "shot", "krakow_classic"],
				[0.2, "key", KEY_F2],
				[0.2, "screen", ["test_enter_nearest"]],
				[26.0, "shot", "room"],
				[0.2, "room", ["test_walk_to_furniture", 0]],
				[6.0, "shot", "room_walked"],
				[0.2, "room", ["test_talk", 0]],
				[1.5, "shot", "talk"],
				[0.2, "room", ["test_pick", 0]],
				[2.5, "shot", "talk_answer"],
				[0.2, "room", ["test_pick", 0]],
				[0.5, "shot", "talk_closed"],
				[0.2, "room", ["walk_out"]],
				[8.0, "shot", "outside"],
				[0.2, "travel", "SKAWINA"],
				[22.0, "shot", "skawina"],
				[0.5, "quit", 0],
			]
		"towns":
			# one town of every template size, seen from above (zoomed out) and close up
			show_office()
			test_steps = []
			for c in ["WOSNIKI", "SLOMNIKI", "ZATOR", "KRAKOW", "ZINDER", "CHECINY"]:
				test_steps.append([0.2, "call1", ["enter_town", c]])
				test_steps.append([0.6, "screen", ["test_overview", 0.16]])
				test_steps.append([1.5, "shot", c.to_lower() + "_far"])
				test_steps.append([0.2, "screen", ["test_overview", 0.8]])
				test_steps.append([1.0, "shot", c.to_lower() + "_near"])
			test_steps.append([0.3, "quit", 0])
		"mission":
			# four mission types played through in the field: briefing, travel, the leader,
			# the work (fights, treatment, interrogation) and the reward
			show_office()
			test_steps = []
			difficulty = "story"                     # the squad must live through all twelve
			var types: Array = Campaign.PLAYABLE
			if OS.get_cmdline_user_args().has("--only-vehicles"):
				types = ["tank", "vehicle"]
			if OS.get_cmdline_user_args().has("--only-tank"):
				types = ["tank"]
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--types="):       # e.g. --types=wounded,epidemic
					types = Array(arg.trim_prefix("--types=").split(","))
			for t in types:
				test_steps.append([0.2, "call1", ["start_mission", t]])
				test_steps.append([0.2, "call", "show_briefing"])
				test_steps.append([1.0, "shot", "brief_" + t])
				test_steps.append([0.2, "call", "show_tactical"])
				for k in range({"spy": 50, "tank": 140, "vehicle": 50, "hostage": 40, "assassins": 40}.get(t, 26)):
					test_steps.append([0.3, "screen", ["test_auto"]])
					test_steps.append([2.5, "shot", "%s_%02d" % [t, k]])
					test_steps.append([0.1, "screen", ["test_close_dialog"]])
			test_steps.append([0.3, "quit", 0])
		"world":
			# world map: route to Skawina and the town, then trouble in a forest and on a road
			show_office()
			test_steps = [
				[0.3, "call", "show_world"],
				[1.0, "shot", "world_krakow"],
				[0.2, "screen", ["go_to_city", "SKAWINA"]],
				[0.4, "shot", "world_marching"],
				[4.0, "shot", "world_arrived"],
				[0.2, "screen", ["test_press", 0]],
				[1.5, "shot", "town_skawina"],
				[0.2, "call", "show_world"],
				[0.3, "screen", ["test_place", "F"]],
				[0.3, "screen", ["test_force_trouble", "MARAUDERS"]],
				[0.8, "shot", "trouble_forest"],
				[0.2, "screen", ["test_press", 0]],
				[1.5, "shot", "encounter_forest"],      # hostile: straight into the battle
				[0.2, "screen", ["test_auto"]],
				[6.0, "shot", "encounter_fight"],
				[20.0, "shot", "after_fight"],          # the battle over, back on the map
				[0.2, "call", "show_world"],
				[0.3, "screen", ["test_place", "R"]],
				[0.3, "screen", ["test_force_trouble", "REFUGEES"]],
				[0.2, "screen", ["test_press", 0]],
				[1.5, "shot", "encounter_road"],
				[0.2, "call", "show_world"],
				[0.2, "screen", ["test_winter"]],
				[0.3, "screen", ["test_place", "G"]],
				[0.3, "screen", ["test_force_trouble", "BLACK LEGION PATROL"]],
				[0.2, "screen", ["test_press", 0]],
				[1.5, "shot", "encounter_winter"],
				[0.2, "call", "show_world"],
				[1.0, "shot", "world_after"],
				[0.3, "quit", 0],
			]
		"talk":
			# one figure for the squad; talks as choices done with the squad's skills
			show_office()
			test_steps = [
				[0.2, "call1", ["start_mission", "assassins"]],
				[0.2, "call1", ["enter_town", "KRAKOW"]],
				[1.2, "shot", "one_figure"],
				[0.2, "screen", ["test_meet", "resident"]],
				[3.0, "shot", "resident_choices"],
				[0.2, "screen", ["test_pick", 0]],
				[1.5, "shot", "resident_rumour"],
				[0.2, "screen", ["test_close_dialog"]],
				[0.2, "call1", ["enter_town_of_mission"]],
				[0.2, "screen", ["test_meet", "leader"]],
				[3.0, "shot", "leader_choices"],
				[0.2, "screen", ["test_pick", 1]],
				[1.5, "shot", "leader_haggle"],
				[0.2, "screen", ["test_close_dialog"]],
				[0.2, "screen", ["test_meet", "leader"]],
				[3.0, "screen", ["test_pick", 0]],
				[1.5, "shot", "leader_job"],
				[0.2, "screen", ["test_close_dialog"]],
				[0.5, "screen", ["test_meet", "enemy"]],
				[2.5, "shot", "squad_rushes_in"],
				[0.5, "quit", 0],
			]
		"battle":
			# a Black Legion patrol in a forest: deployment by hand, then the battle, the
			# aftermath, rest on the map; then tanks: the squad's M1A1 against two T-72s
			show_office()
			test_steps = [
				[0.3, "call", "show_world"],
				[0.3, "screen", ["test_place", "F"]],
				[0.3, "screen", ["test_force_trouble", "BLACK LEGION PATROL"]],
				[0.6, "shot", "trouble"],
				[0.2, "screen", ["test_press", 0]],
				[1.5, "shot", "deploy_auto"],
				[0.2, "screen", ["test_place", 0, 2, -3]],
				[0.2, "screen", ["test_place", 1, 25, 0]],
				[0.8, "shot", "deploy_moved"],
				[0.2, "screen", ["begin"]],
				[1.2, "shot", "first_turn"],
				[0.2, "screen", ["test_auto"]],
				[1.4, "shot", "fire_closeup"],
				[8.0, "shot", "battle_a"],
				[12.0, "shot", "battle_b"],
				[25.0, "shot", "battle_end"],
				[1.0, "shot", "world_after_battle"],
				[0.3, "screen", ["rest"]],
				[0.8, "shot", "rest"],
				[0.3, "call1", ["test_tank_battle"]],
				[1.5, "shot", "tanks_deploy"],
				[0.2, "screen", ["test_auto"]],
				[10.0, "shot", "tanks_a"],
				[20.0, "shot", "tanks_end"],
				[0.3, "quit", 0],
			]
		"boom":
			# a tank in a forest drives through the trees, then shells and a grenade burst
			# beside it: the fireball, the smoke and the craters left behind
			show_office()
			test_steps = [
				[0.3, "call", "show_world"],
				[0.3, "screen", ["test_place", "F"]],
				[0.3, "call1", ["test_tank_battle"]],
				[1.5, "shot", "start"],
				[0.2, "screen", ["test_drive_through_trees"]],
				[0.35, "shot", "tree_falling"],
				[1.2, "shot", "trees_down"],
				[0.2, "screen", ["test_blast", 5, -3, true]],
				[0.12, "shot", "fireball"],
				[0.5, "shot", "smoke"],
				[0.2, "screen", ["test_blast", 2, 4, false]],
				[0.1, "shot", "grenade"],
				[2.5, "shot", "craters"],
				[0.3, "quit", 0],
			]
		"rooms":
			# every building type's room, two door sides each
			test_steps = []
			for t in ["HOUSE", "TAVERN", "MARKET", "JAIL", "HOSPITAL", "BANK", "FACTORY", "BARN", "CHURCH"]:
				for f in [0, 3]:
					test_steps.append([0.1, "call1", ["show_room", "%s_%d" % [t, f]]])
					test_steps.append([0.6, "shot", "%s_%d" % [t, f]])
			test_steps.append([0.3, "quit", 0])
		"soldiers":
			# every direction for each body type, remastered and classic
			test_steps = [
				[0.2, "call", "show_soldier_lineup"],
				[0.8, "shot", "lineup"],
				[0.2, "key", KEY_F2],
				[0.8, "shot", "lineup_classic"],
				[0.5, "quit", 0],
			]
		"fullgame":
			# Complete game playthrough
			show_chargen()
			test_steps = [
				# Chargen: 3 random recruits + deploy
				[0.5, "screen", ["random_recruit"]],
				[0.3, "screen", ["random_recruit"]],
				[0.3, "screen", ["random_recruit"]],
				[0.5, "screen", ["deploy"]],
				[1.0, "shot", "office_after_chargen"],
				# Mission 1: supplies (simple)
				[0.2, "call1", ["start_mission", "supplies"]],
				[0.2, "call", "show_briefing"],
				[1.0, "shot", "brief_supplies"],
				[0.2, "call", "show_world"],
				[0.3, "screen", ["go_to_city", "SLOMNIKI"]],
				[5.0, "screen", ["test_press", 0]],
				[2.0, "screen", ["test_auto"]],
				[8.0, "screen", ["test_auto"]],
				[8.0, "screen", ["test_auto"]],
				[5.0, "screen", ["test_auto"]],
				[0.5, "shot", "mission1_done"],
				# Mission 2: hostage (indoor combat)
				[0.2, "call1", ["start_mission", "hostage"]],
				[0.2, "call", "show_briefing"],
				[1.0, "shot", "brief_hostage"],
				[0.2, "call", "show_world"],
				[0.3, "screen", ["go_to_city", "OLKUSZ"]],
				[5.0, "screen", ["test_press", 0]],
				[3.0, "screen", ["test_auto"]],
				[8.0, "screen", ["test_auto"]],
				[10.0, "screen", ["test_auto"]],
				[5.0, "screen", ["test_auto"]],
				[0.5, "shot", "mission2_done"],
				# Mission 3: tank (vehicle combat)
				[0.2, "call1", ["start_mission", "tank"]],
				[0.2, "call", "show_briefing"],
				[1.0, "shot", "brief_tank"],
				[0.2, "call", "show_world"],
				[0.3, "screen", ["go_to_city", "SZCZEKOINY"]],
				[5.0, "screen", ["test_press", 0]],
				[3.0, "screen", ["test_auto"]],
				[12.0, "screen", ["test_auto"]],
				[15.0, "screen", ["test_auto"]],
				[5.0, "screen", ["test_auto"]],
				[0.5, "shot", "mission3_done"],
				# Return to office and verify
				[0.2, "call", "show_office"],
				[1.0, "shot", "office_final"],
				[0.3, "quit", 0],
			]
		_:
			test_steps = [[1.0, "shot", "office"], [0.5, "quit", 0]]

# ---------------- drive test ----------------
var _drive_ok := true

func test_drive_times() -> void:
	for c in ["SLOMNIKI", "PROSZOWICE", "ZATOR", "CHECINY"]:
		var p := world.city_cell(data.city(c))
		var to := Vector2i(int(p.x), int(p.y))
		var t: Array = []
		for m in ["foot", "wheeled", "tracked"]:
			var r := world.route(to, m)
			t.append("%s %s" % [m, World.span_text(world.route_minutes(r, m)) if not r.is_empty() else "NO ROUTE"])
		print("[test] drive to %s: %s" % [c, ", ".join(t)])
	print("[test] drive: HMMWV %d L, %d L/h; M1A1 %d L, %d L/h" % [Forces.vehicle_data("HMMWV")["fuel_cap"], Forces.vehicle_data("HMMWV")["fuel_cons"],
		Forces.vehicle_data("M1A1")["fuel_cap"], Forces.vehicle_data("M1A1")["fuel_cons"]])

func _drive_expect(ok: bool, what: String) -> void:
	print("[test] drive %s: %s" % ["ok  " if ok else "FAIL", what])
	_drive_ok = _drive_ok and ok

func test_drive_check(stage: String) -> void:
	var line := "%s fuel %.1f at %s, squad %s" % [squad_vehicle, vehicle_fuel, vehicle_at, world.pos]
	match stage:
		"arrived":
			_drive_expect(driving() and vehicle_fuel < fuel_cap() and world.pos.distance_to(world.city_cell(data.city("SLOMNIKI"))) < 1.6, "drove to SLOMNIKI and used fuel: " + line)
		"parked":
			_drive_expect(not driving() and vehicle_at.distance_to(world.pos) < 0.01, "parked: " + line)
		"away":
			_drive_expect(not driving(), "away from it, V does not board: " + line)
		"boarded":
			_drive_expect(driving(), "back at it, V boards: " + line)
		"dry":
			_drive_expect(not driving() and vehicle_fuel == 0.0 and vehicle_at.x >= 0, "ran dry and left on the road: " + line)
		"cans":
			_drive_expect(fuel_cans == 60.0 and vehicle_fuel == 0.0, "60 L from the T-72 into the jerrycans: " + line + " cans %d" % fuel_cans)
		"poured":
			_drive_expect(driving() and vehicle_fuel == 60.0 and fuel_cans == 0.0, "jerrycans poured in, the squad drives again: " + line)
		"burnt":
			_drive_expect(vehicle_fuel == 60.0 and fuel_cans == 0.0, "nothing from a burnt-out wreck: " + line)
		"split":
			_drive_expect(vehicle_fuel == 90.0 and fuel_cans == 20.0, "50 L: 30 L fill the tank, 20 L into the cans: " + line + " cans %d" % fuel_cans)
		"trap":
			var hurt := squad.filter(func(r): return Healing.condition(r) != "UNHURT")
			var poorer := squad.filter(func(r): return r.has("gear") and int(r["gear"]["mags"]) < 5)
			_drive_expect(vehicle_fuel == 90.0 and fuel_cans == 20.0 and hurt.size() == 1 and poorer.size() == 1
				and squad.all(func(r): return not r.get("dead", false)),
				"booby trap: no fuel, %s hurt (%s), gear lost, nobody dead" % [hurt[0]["name"] if hurt else "NOBODY", Healing.condition(hurt[0]) if hurt else ""])
		"gate":
			var sv := difficulty
			var wm = preload("res://scripts/worldmap.gd").new()
			wm.main = self
			difficulty = "normal"
			var on_normal: bool = wm.wrecks_on()
			difficulty = "story"
			var on_story: bool = wm.wrecks_on()
			difficulty = sv
			wm.free()
			_drive_expect(not on_normal and on_story, "wrecks only in story mode")
			var n := 0
			var w2 := World.new(5)
			for i in range(100000):
				if not w2.check_wreck(func(v): return 100).is_empty():
					n += 1
			_drive_expect(n > 400 and n < 800, "wrecks: %d in 100000 km (one in %d km)" % [n, 100000 / maxi(1, n)])
		"ambush":
			_drive_expect(screen.get_script() == preload("res://scripts/battle_view.gd"), "the wreck was bait: a battle")
		"recovered":
			_drive_expect(driving() and vehicle_fuel == fuel_cap(), "towed back and refuelled at Krakow: " + line)

## Walk (on foot) to a cell relative to the parked vehicle.
func test_walk_cells(d: Vector2i) -> void:
	var v := Vector2i(int(vehicle_at.x), int(vehicle_at.y))
	screen.go_to(v + d)
	if v + d == world.cell():
		pass

func test_drain() -> void:
	vehicle_fuel = 8.0
	world.since_trouble = -1000.0          # nothing random on the way: the test wants the tank dry

func test_drive_done() -> void:
	print("DRIVE TEST ", "PASS" if _drive_ok else "FAIL")

# ---------------- save test ----------------
var _saved_state := ""

func _comparable() -> String:
	var d := game_state()
	d.erase("saved")
	d["world"]["minutes"] = snappedf(d["world"]["minutes"], 30.0)   # the town clock runs on
	return var_to_str(d)

func test_save_before() -> void:
	_saved_state = _comparable()
	print("[test] save: can_save=", can_save(), " in ", screen.get_script().resource_path.get_file())

## Everything the save holds is changed, so the load has something to undo.
func test_save_mess() -> void:
	print("[test] save: file written=", FileAccess.file_exists(QUICKSAVE))
	world.pos += Vector2(7, 3)
	world.minutes += 600.0
	campaign.done_count += 3
	campaign.mission = {}
	campaign.stores.append("RUBBISH")
	squad[0]["name"] = "SOMEONE ELSE"
	fallen.append(squad[0].duplicate())
	difficulty = "normal" if difficulty == "story" else "story"
	squad_vehicle = "T-80"

func test_save_after() -> void:
	var ok := _comparable() == _saved_state
	print("[test] save: on ", screen.get_script().resource_path.get_file(), " state restored=", ok)
	if not ok:
		var a := _saved_state.split(String.chr(10))
		var b := _comparable().split(String.chr(10))
		for i in range(mini(a.size(), b.size())):
			if a[i] != b[i]:
				print("[test] save differs: ", a[i], "  ->  ", b[i])
				break
	print("SAVE TEST ", "PASS" if ok else "FAIL")

## Save/load error handling: missing file, corrupt file, wrong version, valid round-trip.
## The game must not crash on any of these.
func test_save_errors_missing() -> void:
	var ok := load_game("user://does_not_exist.sav")
	assert(not ok, "missing file must return false")
	print("[save_errors] missing file: ok")

func test_save_errors_corrupt() -> void:
	var f := FileAccess.open("user://test_corrupt.sav", FileAccess.WRITE)
	f.store_string("this is not a save file at all")
	f.close()
	var ok := load_game("user://test_corrupt.sav")
	assert(not ok, "corrupt file must return false")
	print("[save_errors] corrupt file: ok")

func test_save_errors_wrong_version() -> void:
	var f := FileAccess.open("user://test_wrong_version.sav", FileAccess.WRITE)
	f.store_var({"version": 999, "squad": [], "leader": 0, "fallen": [], "mode": "normal",
		"vehicle": "", "world": {}, "campaign": {}, "fuel": 0.0, "vehicle_at": [-1, -1],
		"cans": 0.0, "town": "", "saved": "now"})
	f.close()
	var ok := load_game("user://test_wrong_version.sav")
	assert(not ok, "wrong version must return false")
	print("[save_errors] wrong version: ok")

func test_save_errors_valid() -> void:
	var d := game_state()
	d.erase("saved")
	var f := FileAccess.open("user://test_valid.sav", FileAccess.WRITE)
	f.store_var(d)
	f.close()
	var ok := load_game("user://test_valid.sav")
	assert(ok, "valid save must return true")
	print("[save_errors] valid roundtrip: ok")
	print("SAVE ERRORS TEST PASS")

func _process(delta: float) -> void:
	if test_steps.is_empty():
		return
	test_t += delta
	var s: Array = test_steps[0]
	if test_t < s[0]:
		return
	test_t = 0.0
	test_steps.pop_front()
	match s[1]:
		"shot":
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_dir + "/" + s[2] + ".png")
			print("[test] shot ", s[2])
		"hover":
			if screen.has_method("test_hover"):
				screen.test_hover(s[2] * SCALE)
		"call":
			call(s[2])
		"call1":
			var a1: Array = s[2]
			callv(a1[0], a1.slice(1))
		"screen":
			# [method, args...] on the current screen
			var a: Array = s[2]
			screen.callv(a[0], a.slice(1))
		"room":
			# [method, args...] on the room the squad is in
			var a: Array = s[2]
			if room:
				room.callv(a[0], a.slice(1))
			else:
				print("[test] FAIL not inside a room for ", a[0])
		"travel":
			if screen.has_method("travel_to"):
				screen.travel_to(s[2])
		"key":
			var ev := InputEventKey.new()
			ev.keycode = s[2]
			ev.pressed = true
			ev.device = TEST_DEVICE
			Input.parse_input_event(ev)
		"quit":
			print("[test] done ", test_name)
			stop_audio()                         # let the mixer release the streams before exit
			await get_tree().create_timer(0.3).timeout
			get_tree().quit(s[2])
