## The battle screen: the place's ground (season kit, trees, town houses) under a 2 m grid, the
## units drawn with the original sprites (standing, kneeling, lying, vehicles and wrecks), and a
## turn-based interface. First the deployment: the squad stands where soldiers would, and any
## man can be moved (no further than 10 tiles from his nearest mate, not next to the enemy).
## Then turns: click a tile to move, click an enemy to fire (mode from the bar or keys 1-3),
## grenades, reload, stance, first aid, end turn. Enemies are played by Battle.ai_step.
## Inside a building (setup.room) the room's own picture and furniture are the ground, on 1 m
## tiles; the squad comes in at the door.
extends Node2D

var main: Node
var setup: Dictionary                 # {local, town, centre, from, men, vehicles, squad_vehicle, back}
var b: Battle
var lm: LocalMap
var origin := Vector2.ZERO            # metres of tile (0, 0)
const SIZE := Vector2i(40, 30)
var size := SIZE                      # tiles (indoors: the room)
var tile := Battle.TILE               # metres a tile (indoors 1)
var room: Dictionary = {}             # data/rooms.json entry when the fight is indoors
const SC := 3.0
const K := 12.0 * SC                  # screen px per metre
var cam: Camera2D
var world: Node2D
var sprites := {}                     # unit id -> Node2D
var phase := "deploy"                 # deploy, plan, execute, battle, enemy, over
var selected := -1                    # unit id (deploy) / the acting unit
var mode := "snap"                    # snap, aimed, burst, grenade, aid
var hover := Vector2i(-1, -1)
var reach: Dictionary = {}
var walkers: Dictionary = {}            # id -> {path, i, t} for the simultaneous execution
var plan_selected := -1                 # which squad man is being planned (planning phase)
var _used_faces := {"M": {}, "F": {}}   # the face indexes the squad already wears: enemies never share them
var ai_t := 0.0
var flashes: Array = []               # {from, to, t, color}
var booms: Array = []                 # {at, t, size, debris}: the original EXPLOD frames, then smoke
var fx: Node2D                        # explosions are drawn over the units
var explod: Array = []                # the 3 frames of CMBT/EXPLOD
var shake := 0.0
var tree_at := {}                     # tile -> tree sprite (to lay it down when it falls)
var holes: Array = []                 # [tile, size] craters to draw
const BOOM_T := 1.8
const EXPLOD_FRAMES := [Rect2(0, 0, 19, 32), Rect2(19, 0, 22, 32), Rect2(41, 0, 32, 32)]
var log_lbl: RichTextLabel
var top_lbl: Label
var unit_lbl: Label
var tip_lbl: Label
var bar: HBoxContainer
var end_panel: Panel
var cr: ChargenRules
var squad_ids: Array = []
var ai_squad := false                 # tests: the computer plays the squad too
var quick_battle := false             # skip the planning phase and fight one-at-a-time
var shown_log := 0
var props: Array = []                 # tree sprites (made see-through when a man stands behind)
var fire_pose := {}                   # unit id -> seconds left of the CMBT firing stance
var shooter_box: TextureRect          # the firing close-ups: shooter top-left, target top-right
var shooter_lbl: Label
var target_box: TextureRect
var target_lbl: Label
var face_t := 0.0
var face_cache := {}                  # face key -> Texture2D

# ---------------- projection ----------------
func iso(m: Vector2) -> Vector2:
	var d := m - origin
	return Vector2((d.x + d.y) * K, (d.y - d.x) * K * 0.5)

func uniso(s: Vector2) -> Vector2:
	var sum := s.x / K
	var dif := s.y * 2.0 / K
	return origin + Vector2((sum - dif) * 0.5, (sum + dif) * 0.5)

func tile_centre(t: Vector2i) -> Vector2:
	return origin + (Vector2(t) + Vector2(0.5, 0.5)) * tile

func tile_at_screen(p: Vector2) -> Vector2i:
	return Vector2i(((uniso(p) - origin) / tile).floor())

# ---------------- set-up ----------------
func _ready() -> void:
	cr = ChargenRules.new(GameData._json("res://data/careers.json"), main.data.chargen, main.rng_seed)
	if setup.has("room"):
		room = GameData._json("res://data/rooms.json")[setup["room"]["key"]]
		size = Vector2i(int(room["size"][0]), int(room["size"][1]))
		tile = 1.0
		origin = Vector2.ZERO                 # room metres, the projection the room picture uses
		b = Forces.make_room_battle(room, main.data.items, main.rng_seed + int(main.world.minutes))
	else:
		lm = setup["local"]
		var centre: Vector2 = setup["centre"]
		origin = centre - Vector2(size) * tile * 0.5
		b = Forces.make_battle(lm, setup.get("town"), origin, size, main.data.items, main.rng_seed + int(main.world.minutes))
	b.options["story"] = main.difficulty == "story"
	var rng := RandomNumberGenerator.new()
	rng.seed = main.rng_seed + 17 + int(main.world.minutes)
	var from: Vector2 = setup.get("from", Vector2(-1, 0))
	if from.length() < 0.01:
		from = Vector2(-1, 0)
	from = from.normalized()
	var mid := Vector2(size) * 0.5
	var squad_at := Vector2i((mid + from * 12.0).round())
	var enemy_at := Vector2i((mid - from * 11.0).round())
	if not room.is_empty():
		# in at the door; they wait at the far wall
		var inward: Vector2 = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][int(room["facing"])]
		var door := Vector2(room["door"][0], room["door"][1])
		var depth: float = absf(inward.dot(Vector2(size)))
		squad_at = Vector2i((door + inward * 0.6).floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
		enemy_at = Vector2i((door + inward * (depth - 1.5)).floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
		from = -inward
	# the squad (living members), possibly in their vehicle
	var men: Array = []
	for i in range(main.squad.size()):
		var r: Dictionary = main.squad[i]
		if r.get("dead", false):
			continue
		Forces.equip(r)
		men.append(b.add_man("squad", r, squad_at, i))
	squad_ids = men.map(func(u): return u["id"])
	for r in main.squad:                   # the faces the squad wears: the enemy must not share them
		if r.get("dead", false):
			continue
		_used_faces["F" if r.get("gender", "M") == "F" else "M"][int(r.get("face", 0)) % 15] = true
	if setup.get("tank", false):
		Forces.issue_at_weapons(men)
		b.log.append("KRAKOW'S ARMOURY HAS ISSUED A LAW 80 TO EVERY MAN WITHOUT A LAUNCHER.")
	if setup.get("squad_vehicle", "") != "":
		var v := b.add_vehicle("squad", Forces.vehicle_data(setup["squad_vehicle"]), squad_at, Battle._dir_index(Vector2i((-from).round())))
		for u in men.slice(0, int(v["data"]["crew"])):
			b.board(u, v)
	var foes: Array = []
	for t in setup.get("men", []):
		foes.append(b.add_man("enemy", t, enemy_at))
	if main.campaign.done_count == 0:                     # the one-time first-battle chalk talk
		b.log.append("FIRST FIGHT: CLICK MOVES A SOLDIER, 1/2/3 PICKS THE FIRE MODE, 4 = GRENADE, T RESERVES AP FOR A SNAP SHOT, E ENDS THE TURN.")
		b.log.append("THE ENEMIES STAY IN THE DARK UNTIL THEY ARE SPOTTED - MOVE UP CAREFULLY.")
	if room.is_empty():
		Forces.deploy_squad(b, men.filter(func(u): return int(u["in_vehicle"]) < 0), squad_at, -from)
		Forces.deploy_enemies(b, foes, enemy_at, from, rng)
	else:
		Forces.deploy_defenders(b, foes, squad_at, rng)
		Forces.deploy_near(b, men, squad_at, -from)
	for vn in setup.get("vehicles", []):
		var vd := Forces.vehicle_data(vn)
		if not vd.is_empty():
			# story mode: the enemy's crews are green (gunnery 2, not 4)
			var vu := b.add_vehicle("enemy", vd, enemy_at - Vector2i((from * 4.0).round()), Battle._dir_index(Vector2i(from.round())), 2 if main.difficulty == "story" else 4)
			for k in range(20):
				if b.is_free_tile(vu["pos"], vu["id"]):
					break
				vu["pos"] += Vector2i(0, 1)
	b.refresh_seen()                                      # the opening sight at the battlefield
	b.seek = enemy_at                                    # the squad hunts the garrison in the fog
	_build_scene()
	_build_ui()
	selected = squad_ids[0] if not squad_ids.is_empty() else -1
	cam.position = iso(tile_centre(squad_at)).lerp(iso(tile_centre(enemy_at)), 0.35) if room.is_empty() else iso(Vector2(size) * 0.5)
	_log("DEPLOYMENT: click a soldier, then a tile to move him (up to %d tiles from his nearest squad mate). BEGIN when ready." % Forces.MAX_DEPLOY)
	_refresh()

func _build_scene() -> void:
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	cam.zoom = Vector2.ONE * 0.62
	var tint := CanvasModulate.new()
	var light := clampf(0.5 - 0.5 * cos((main.world.hour() - 2.0) / 24.0 * TAU), 0.0, 1.0)
	tint.color = Color(0.45, 0.45, 0.6).lerp(Color.WHITE, light)
	add_child(tint)
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	if not room.is_empty():
		_build_room()
	for pr in (lm.props if lm != null else []):
		if Rect2(origin, Vector2(size) * tile).has_point(pr["pos"]):
			var sp := Sprite2D.new()
			sp.texture = lm.tex[pr["kind"]]
			sp.centered = false
			sp.scale = Vector2.ONE * SC
			sp.offset = Vector2(-sp.texture.get_width() / 2.0, -sp.texture.get_height() + 3)
			sp.position = iso(pr["pos"])
			world.add_child(sp)
			props.append(sp)
			if pr["kind"] != "bush":
				tree_at[Vector2i(((pr["pos"] - origin) / tile).floor())] = [sp, pr["kind"]]
	var town: Town = setup.get("town")
	if town != null:
		for bd in town.near(origin + Vector2(size) * tile * 0.5, 120.0):
			var sp := Sprite2D.new()
			sp.texture = load("res://original/graphics/BUILDING/composed/%s.png" % bd["key"])
			sp.centered = false
			var m: Dictionary = town.meta[bd["key"]]
			var sz: Vector2 = bd["size"]
			var c := Vector2(m["nw"][0], m["nw"][1]) + Vector2((sz.x + sz.y) * 6.0, (sz.y - sz.x) * 3.0)
			sp.scale = Vector2.ONE * SC
			sp.offset = -c
			sp.position = iso(bd["centre"])
			world.add_child(sp)
	for u in b.units:
		_make_sprite(u)
	fx = Node2D.new()
	fx.z_index = 20
	add_child(fx)
	fx.draw.connect(_draw_fx)
	var ex: Texture2D = _cmbt("EXPLOD")
	if ex != null:
		for r in EXPLOD_FRAMES:                 # the frames touch: cut at the measured columns
			var at := AtlasTexture.new()
			at.atlas = ex
			at.region = r
			explod.append(at)

## Indoors: the room picture (its NW floor corner at room metres 0, 0) and its furniture, as the
## interior view draws them; the camera fits the room.
func _build_room() -> void:
	var key: String = setup["room"]["key"]
	var bg := Sprite2D.new()
	bg.texture = load("res://original/graphics/BUILDING/rooms/%s.png" % key)
	bg.centered = false
	bg.scale = Vector2.ONE * SC
	bg.position = -Vector2(room["nw"][0], room["nw"][1]) * SC
	bg.z_index = -2
	add_child(bg)
	for f in room["furniture"]:
		var sp := Sprite2D.new()
		sp.texture = load("res://original/graphics/BUILDING/rooms/%s.png" % f["pic"])
		sp.centered = false
		sp.scale = Vector2.ONE * SC
		sp.position = iso(Vector2(f["centre"][0], f["centre"][1]))
		sp.offset = Vector2(-sp.texture.get_width() / 2.0, float(f["r"]) * 12.0 - sp.texture.get_height())
		if f["flat"]:
			sp.z_index = -1
			add_child(sp)
		else:
			world.add_child(sp)
			props.append(sp)                 # see-through when a man stands behind it
	var px: Vector2 = bg.texture.get_size() * SC
	cam.zoom = Vector2.ONE * clampf(minf(1180.0 / px.x, 560.0 / px.y), 0.6, 2.2)

func _make_sprite(u: Dictionary) -> void:
	var n: Node2D
	if u["kind"] == "vehicle":
		var sp := Sprite2D.new()
		sp.centered = true
		sp.scale = Vector2.ONE * SC
		n = sp
	else:
		var s := Soldier.new()
		s.body = "EM" if u["team"] == "enemy" and String(u.get("name", "")).begins_with("BLACK") else ("AF" if u.get("gender", "M") == "F" else "AM")
		s.head = int(u.get("head", 0))
		n = s
	world.add_child(n)
	sprites[u["id"]] = n

func _cmbt(name: String) -> Texture2D:
	var p := "res://original/graphics/CMBT/%s_rgba.png" % name
	return load(p) if ResourceLoader.exists(p) else null

## A corner close-up frame (hidden until someone fires).
func _face_box(parent: Node, at: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.position = at
	t.size = Vector2(110, 92)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.visible = false
	parent.add_child(t)
	return t

## The close-up faces: the shooter top-left, the target top-right (as in the original battle).
## The enemy's box is tinted red so a friendly face is never mistaken for a hostile one.
func _show_faces(shooter: Dictionary, target: Dictionary) -> void:
	_put_face(shooter_box, shooter_lbl, shooter)
	_put_face(target_box, target_lbl, target)
	face_t = 1.2
	shooter_box.modulate = Color(1.0, 0.55, 0.5) if not shooter.is_empty() and shooter.get("team", "") == "enemy" else Color.WHITE
	target_box.modulate = Color(1.0, 0.55, 0.5) if not target.is_empty() and target.get("team", "") == "enemy" else Color.WHITE
	shooter_box.visible = shooter_box.texture != null
	target_box.visible = target_box.texture != null
	shooter_lbl.visible = shooter_box.visible
	target_lbl.visible = target_box.visible

func _put_face(box: TextureRect, lbl: Label, u: Dictionary) -> void:
	if u.is_empty() or u.get("kind", "") != "man":
		box.texture = null
		lbl.text = ""
		return
	var key := "%s/%s/%s" % [u["team"], u.get("ref", -1), u.get("face", u.get("head", 0))]
	if not face_cache.has(key):
		face_cache[key] = _face_tex(u)
	box.texture = face_cache[key]
	lbl.text = String(u["name"])

## The recruit's own talk-portrait; everyone else (the enemy, civilians) gets one of the
## FACES-sheet portraits, picked by the unit's head variant (as in the original battle).
func _face_tex(u: Dictionary) -> Texture2D:
	if int(u.get("ref", -1)) >= 0 and int(u.get("ref", -1)) < main.squad.size():
		var frames := Portraits.recruit(main.squad[int(u["ref"])])
		if not frames.is_empty():
			return frames[0]
	# the enemies' own portraits: FACES/enemies.png, one face per unit (the squad's faces
	# live on other sheets: nobody on the other side shares a face)
	var p: String = main.art("FACES", "enemies")
	if ResourceLoader.exists(p):
		var esheet: Texture2D = load(p)
		if esheet != null:
			var n := int(esheet.get_height() / 43.0) * 5     # the sheet: 5 cols x 3 rows of 48x43
			var j := int(u.get("face", 0)) % n
			var easetex := AtlasTexture.new()
			easetex.atlas = esheet
			easetex.region = Rect2((j % 5) * 48, (j / 5) * 43, 48, 43)
			return easetex
	# no enemies sheet yet: fall back to the FACES sheets (the original's close-up portraits):
	# 15 faces of 48x43 per gender; nobody on the other side wears the squad's face.
	var g := "F" if u.get("gender", "M") == "F" else "M"
	var i := int(u.get("head", 0)) % 15
	var used: Dictionary = _used_faces[g]
	for k in range(15):
		if not used.has(i):
			break
		i = (i + 1) % 15
	var sheet: Texture2D = load(main.art("FACES", "men" if g == "M" else "women"))
	var div := float(sheet.get_width()) / 320.0
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2((i % 5) * 48 * div, (i / 5) * 43 * div, 48 * div, 43 * div)
	return at

## Which firing-pose art (CMBT) the unit uses: the weapon decides, the enemy has its own set.
## (the CMBT data has all 8 directions for every set: HG, SMG, PISTOL, PUNCH, BAZOOK and
## the enemy's EHG, ESMG, EPIST; DEFAULT falls back to the body, see _place_units)
func _fire_pose_art(u: Dictionary) -> String:
	var enemy: bool = String(u.get("name", "")).begins_with("BLACK")
	var w := String(u.get("weapon", "")).to_upper()
	if w.contains("ROCKET") or w.contains("LAW") or w.contains("RPG") or w.contains("TOW") \
			or w.contains("GUSTAV") or w.contains("BREAKER") or w.contains("DRAGON") \
			or w.contains("AT-5") or w.contains("AT-7"):
		return "EHG" if enemy else "BAZOOK"
	if w.contains("SMG") or w.contains("MP") or w.contains("UZI") or w.contains("M12") \
			or w.contains("G11"):
		return "ESMG" if enemy else "SMG"
	if w.contains("PISTOL") or w.contains("MAKAROV") or w.contains("REVOLVER") \
			or w.contains("M9") or w.contains("MAGNUM") or w.contains("SNUBNOSE") \
			or w.contains("HP-35"):
		return "EPIST" if enemy else "PISTOL"
	if w.contains("KNIFE") or w.contains("BAYONET") or w.contains("PUNCH") or w.contains("E-TOOL"):
		return "EPIST" if enemy else "PUNCH"
	return "EHG" if enemy else "HG"

## Trees in front of a man are drawn see-through, so nobody hides behind the art.
func _fade_props() -> void:
	var pts: Array = []
	for u in b.units:
		if u["state"] != "dead" and int(u.get("in_vehicle", -1)) < 0:
			pts.append(iso(tile_centre(u["pos"])))
	for sp in props:
		var r := Rect2(sp.position + sp.offset * SC, sp.texture.get_size() * SC)
		var behind := false
		for p in pts:
			if r.has_point(p + Vector2(0, -30)) and p.y < sp.position.y:
				behind = true
		sp.modulate = Color(1, 1, 1, 0.4 if behind else 1.0)

## Place and pose every unit (standing soldier, kneeling, lying, vehicles and wrecks).
func _place_units() -> void:
	_fade_props()
	for u in b.units:
		if not sprites.has(u["id"]):
			_make_sprite(u)
		var n: Node2D = sprites[u["id"]]
		var p := iso(tile_centre(u["pos"]))
		n.visible = int(u.get("in_vehicle", -1)) < 0 and not u.get("fled", false) \
			and (u["team"] == "squad" or phase == "deploy" or b.is_seen(u, "squad"))
		if u["kind"] == "vehicle":
			var sp := n as Sprite2D
			var enemy: bool = u["team"] == "enemy"
			var key: String = (u["data"]["enemy_wreck"] if enemy else u["data"]["wreck"]) if u["state"] == "dead" else (u["data"]["enemy_sprite"] if enemy else u["data"]["sprite"])
			sp.texture = load("res://original/graphics/BUILDING/%s_rgba.png" % key)
			# the art faces south-east on screen (world east); mirror for the western half
			var f: int = int(u["facing"])
			sp.flip_h = f in [5, 6, 7, 0]
			sp.position = p + Vector2(0, -20)
			continue
		var s := n as Soldier
		s.dir = int(u["facing"])
		if walkers.has(u["id"]):
			var w: Dictionary = walkers[u["id"]]
			var path: Array = w["path"]
			var i: int = int(w["i"])
			var t: float = float(w["t"])
			var a_tile: Vector2i = path[i]
			var b_tile: Vector2i = path[mini(i + 1, path.size() - 1)]
			var pt := Vector2(a_tile).lerp(Vector2(b_tile), t)
			s.position = iso(origin + (pt + Vector2(0.5, 0.5)) * tile)
			s.walking = true
		else:
			s.position = p
			s.walking = false
		var pose: String = u["stance"] if u["state"] == "ok" else "down"
		if u["state"] == "dead":
			pose = "dead"
		s.modulate = Color(1, 1, 1) if u["state"] == "ok" else (Color(0.8, 0.5, 0.5) if u["state"] == "down" else Color(0.45, 0.35, 0.35))
		var alt: Sprite2D = s.get_node_or_null("Pose")
		if pose == "stand" or pose == "crouch":
			# crouching: the standing figure drawn lower (the CMBT "KNEEL" art is a prone shooter)
			s.scale = Vector2(1.0, 0.8 if pose == "crouch" else 1.0)
			var ftex: Texture2D = null
			var firing: bool = fire_pose.get(u["id"], 0.0) > 0.0 and pose == "stand"
			if firing:
				# the original's firing stance: the weapon in the hands (CMBT art, the enemy its own)
				ftex = _cmbt(_fire_pose_art(u) + Soldier.DIRS[s.dir])
				if ftex == null:
					firing = false               # no art for this set/direction: the body stays
					s.visible_body = true
				if alt == null:
					alt = Sprite2D.new()
					alt.name = "Pose"
					alt.centered = false
					alt.scale = Vector2.ONE * SC
					s.add_child(alt)
				alt.texture = ftex
				alt.visible = firing
				if firing:
					alt.offset = Vector2(-ftex.get_width() / 2.0, -ftex.get_height() + 2)
			else:
				s.visible_body = true
				if alt:
					alt.visible = false
		else:
			s.scale = Vector2.ONE
			s.visible_body = false
			if alt == null:
				alt = Sprite2D.new()
				alt.name = "Pose"
				alt.centered = false
				alt.scale = Vector2.ONE * SC
				s.add_child(alt)
			var dname: String = Soldier.DIRS[s.dir]
			var tex := _cmbt(("KNEEL" if pose == "prone" else "WOUND") + dname)
			alt.texture = tex
			alt.visible = tex != null
			s.visible_body = tex == null             # no pose art: the standing body stays
			if tex:
				alt.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height() + 2)

# ---------------- UI ----------------
func _label(parent: Node, at: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var top := ColorRect.new()
	top.color = Color(0.05, 0.03, 0.02, 0.8)
	top.size = Vector2(1280, 40)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top)
	top_lbl = _label(ui, Vector2(14, 6), 20, Color(1, 0.85, 0.45))
	shooter_box = _face_box(ui, Vector2(14, 52))
	shooter_lbl = _label(ui, Vector2(14, 148), 15, Color(1, 0.9, 0.6))
	shooter_lbl.size = Vector2(220, 20)
	target_box = _face_box(ui, Vector2(1280 - 124, 52))
	target_lbl = _label(ui, Vector2(1280 - 240, 148), 15, Color(1, 0.9, 0.6))
	target_lbl.size = Vector2(226, 20)
	target_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bottom := ColorRect.new()
	bottom.color = Color(0.05, 0.03, 0.02, 0.88)
	bottom.position = Vector2(0, 640)
	bottom.size = Vector2(1280, 160)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bottom)
	unit_lbl = _label(ui, Vector2(14, 646), 17, Color(1, 0.75, 0.6))
	unit_lbl.size = Vector2(420, 110)
	unit_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar = HBoxContainer.new()
	bar.position = Vector2(14, 752)
	bar.add_theme_constant_override("separation", 6)
	ui.add_child(bar)
	log_lbl = RichTextLabel.new()
	log_lbl.position = Vector2(450, 646)
	log_lbl.size = Vector2(816, 100)
	log_lbl.scroll_following = true
	log_lbl.add_theme_font_size_override("normal_font_size", 14)
	log_lbl.add_theme_color_override("default_color", Color(1, 0.45, 0.35))
	log_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(log_lbl)
	tip_lbl = _label(ui, Vector2(0, 0), 16, Color(1, 1, 0.8))
	tip_lbl.z_index = 5
	end_panel = Panel.new()
	end_panel.position = Vector2(240, 120)
	end_panel.size = Vector2(800, 460)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.02, 0.96)
	sb.border_color = Color(0.6, 0.12, 0.08)
	sb.set_border_width_all(3)
	end_panel.add_theme_stylebox_override("panel", sb)
	end_panel.visible = false
	ui.add_child(end_panel)

func _button(text: String, cb: Callable, on := true, active := false) -> void:
	var btn := Button.new()
	btn.text = text
	btn.disabled = not on
	btn.toggle_mode = true
	btn.button_pressed = active
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(cb)
	bar.add_child(btn)

func _refresh() -> void:
	for c in bar.get_children():
		c.queue_free()
	var u := b.current() if phase != "deploy" else b.unit(selected)
	if phase == "deploy":
		top_lbl.text = "DEPLOYMENT  -  %s  -  %s" % [main.world.date_text(), setup.get("title", "")]
		_button("BEGIN THE BATTLE", begin)
		_button("QUICK BATTLE", func(): quick_battle = true; begin())
		_button("AUTO-PLACE", func(): Forces.deploy_squad(b, squad_ids.map(func(i): return b.unit(i)).filter(func(x): return int(x["in_vehicle"]) < 0), b.unit(squad_ids[0])["pos"], Vector2(1, 0)); _refresh())
	elif phase == "over":
		top_lbl.text = "THE BATTLE IS OVER"
	else:
		var whose: String = "YOUR TURN" if (not u.is_empty() and u["team"] == "squad" and not ai_squad) else "ENEMY TURN"
		top_lbl.text = "ROUND %d  -  %s  -  %s%s" % [b.round_no, whose, u.get("name", ""), " [QUICK]" if quick_battle else ""]
		if not u.is_empty() and u["team"] == "squad" and not ai_squad:
			var man: bool = u["kind"] == "man"
			_button("1 SNAP (%d)" % b.ap_for("snap", u), func(): mode = "snap"; _refresh(), true, mode == "snap")
			_button("2 AIMED (%d)" % b.ap_for("aimed", u), func(): mode = "aimed"; _refresh(), man, mode == "aimed")
			_button("3 BURST (%d)" % b.ap_for("burst", u), func(): mode = "burst"; _refresh(), man and int(b.weapon_of(u).get("rof", 0)) > 0 or not man, mode == "burst")
			if man:
				_button("4 GRENADE x%d" % int(u["grenades"]), func(): mode = "grenade"; _refresh(), int(u["grenades"]) > 0, mode == "grenade")
				_button("M MELEE", func(): mode = "melee"; _refresh(), true, mode == "melee")
				if u["launcher"] != "":
					_button("5 %s x%d" % [String(u["launcher"]).split(" ")[0], int(u["rockets"])], func(): mode = "rocket"; _refresh(), int(u["rockets"]) > 0, mode == "rocket")
				_button("R RELOAD", func(): b.reload(u); _after_action(), int(u["mags"]) > 0)
				_button("C " + ("STAND" if u["stance"] == "crouch" else "CROUCH"), func(): b.set_stance(u, "stand" if u["stance"] == "crouch" else "crouch"); _after_action())
				_button("P " + ("STAND" if u["stance"] == "prone" else "PRONE"), func(): b.set_stance(u, "stand" if u["stance"] == "prone" else "prone"); _after_action())
				_button("F FIRST AID", func(): mode = "aid"; _refresh(), true, mode == "aid")
				if phase == "plan":
					var nplanned := 0
					for uu in b.units:
						if uu["team"] == "squad" and uu["kind"] == "man":
							nplanned += int(uu["plan"].size())
					_button("CLEAR PLAN", func():
						for uu in b.units:
							if uu["team"] == "squad" and uu["kind"] == "man":
								b.clear_plan(uu)
						_refresh(), nplanned > 0)
					_button("EXECUTE (%d)" % nplanned, func(): _execute_plan(), nplanned > 0)
					if b.interrupted:
						_button("REPLAN", func():
							b.interrupted = false
							b.interrupt_enemies = []
							for uu in b.units:
								if uu["team"] == "squad" and uu["kind"] == "man":
									b.clear_plan(uu)
							_refresh())
				_button("T " + ("RES OFF" if u.get("reserve", false) else "RES ON"), func():
					b.set_reserve(u)
					_refresh(), true, u.get("reserve", false))
			_button("E END TURN", func(): b.end_turn(); _turn_changed())
	_unit_text(u)
	reach = b.reachable(u) if (phase == "battle" or phase == "plan") and not u.is_empty() and u["team"] == "squad" and not ai_squad else {}
	if phase == "plan":
		if plan_selected < 0 or b.unit(plan_selected).is_empty() or b.unit(plan_selected)["team"] != "squad":
			plan_selected = b.current()["id"] if (not b.current().is_empty() and b.current()["team"] == "squad") else -1
		var pu := b.unit(plan_selected)
		reach = b.reachable(pu) if (not pu.is_empty() and pu["team"] == "squad") else {}
	_place_units()
	queue_redraw()

func _unit_text(u: Dictionary) -> void:
	if u.is_empty():
		unit_lbl.text = ""
		return
	if u["kind"] == "vehicle":
		var c: Dictionary = u["comp"]
		unit_lbl.text = "%s   AP %d/%d\nCREW %d   ENGINE %d%%  SUSPENSION %d%%  GUN %d%%\nAMMO %s" % [u["name"], int(u["ap"]), Battle.AP_MAX, int(u["crew_left"]), c["engine"], c["susp"], c["gun"], str(u["ammo"])]
		return
	var wp: Dictionary = b.weapon_of(u)
	var plan_txt: String = ""
	if phase == "plan" and u["team"] == "squad" and u["kind"] == "man":
		plan_txt = "   PLAN AP %d/%d" % [int(u.get("plan_ap", 0)), int(u["ap"])]
	var parts: Array = []
	for l in Battle.LOCS:
		var d := int(u["dmg"].get(l, 0))
		if d > 0:
			parts.append("%s %d/%d" % [l, d, int(u["hits"].get(l, 0))])
	unit_lbl.text = "%s  (%s)   AP %d/%d%s%s   MORALE %d\n%s %d/%d  +%d MAGS   GRENADES %d\n%s%s" % [u["name"], u["stance"].to_upper(), int(u["ap"]), Battle.AP_MAX,
		("   RESERVED FOR A SNAP SHOT" if u.get("reserve", false) else ""), plan_txt, int(u.get("morale", 100)),
		wp.get("name", "-"), int(u["ammo"]), int(wp.get("magazine", 0)), int(u["mags"]), int(u["grenades"]),
		"UNHURT" if parts.is_empty() else "WOUNDS: " + ", ".join(parts), ("   BLEEDING %d" % int(u["bleed"])) if int(u["bleed"]) > 0 else ""]

func _log(s: String) -> void:
	log_lbl.append_text(s + "\n")

## Which original effect a shot uses (chosen by the firing weapon's name).
func _gun_sound(w: String) -> String:
	var n := w.to_upper()
	if n.contains("ROCKET") or n.contains("LAW ") or n.contains("RPG") or n.contains("TOW"):
		return "TROCKET1"
	if n.contains("M60") or n.contains("M2") or n.contains("PK") or n.contains("MG"):
		return "TMGUN1"
	if n.contains("SHOTGUN"):
		return "TSHOTGUN"
	if n.contains("CANNON") or n.contains("GUN"):
		return "TTNKGUN"
	return "TRIFLE"

func _pull_log() -> void:
	while shown_log < b.log.size():
		_log(b.log[shown_log])
		shown_log += 1
	for e in b.events:
		match e["type"]:
			"fire":
				var a := b.unit(e["id"])
				var t := b.unit(e["target"])
				if not a.is_empty() and not t.is_empty():
					flashes.append({"from": iso(tile_centre(a["pos"])) + Vector2(0, -60), "to": iso(tile_centre(t["pos"])) + Vector2(0, -50), "t": 0.25})
				if main:
					main.play_sfx(_gun_sound(String(e.get("weapon", ""))))
				fire_pose[e["id"]] = 0.5
				_show_faces(a, t)
			"explode":
				var deb: Array = []
				for i in range(10 if int(e.get("size", 1)) >= 2 else 6):
					deb.append(Vector2(randf_range(-1.0, 1.0), randf_range(-1.6, -0.6)) * randf_range(120.0, 260.0))
				booms.append({"at": iso(tile_centre(e["tile"])), "t": BOOM_T, "size": int(e.get("size", 1)), "debris": deb})
				shake = maxf(shake, 0.25 if int(e.get("size", 1)) >= 2 else 0.12)
				if main:
					main.play_sfx("TEXPLOS" if int(e.get("size", 1)) >= 2 else "TGRENLAN")
			"tree_down":
				_lay_down(e["tile"], e["dir"])
			"crater":
				holes.append([e["tile"], int(e["size"])])
			"move":
				walkers[e["id"]] = {"path": e["path"], "i": 0, "t": 0.0}
	b.events.clear()

# ---------------- deployment ----------------
func begin() -> void:
	if phase != "deploy":
		return
	phase = "plan" if not ai_squad and not quick_battle else "battle"
	_log("THE BATTLE BEGINS.")
	b.start()
	_turn_changed()

# ---------------- turns ----------------
func _turn_changed() -> void:
	_pull_log()
	if b.over:
		_finish()
		return
	var u := b.current()
	if u.is_empty():
		return
	mode = "snap"
	phase = "enemy" if (u["team"] == "enemy" or ai_squad) else ("battle" if quick_battle else "plan")
	ai_t = 0.45
	var target := iso(tile_centre(u["pos"]))
	if cam.position.distance_to(target) > 500.0:
		cam.position = target
	_refresh()

func _after_action() -> void:
	_pull_log()
	if b.over:
		_finish()
		return
	_refresh()

func _execute_plan() -> void:
	if phase != "plan":
		return
	b.execute_plan()
	_pull_log()
	if b.interrupted:
		phase = "plan"
		_log("NEW ENEMY SPOTTED - REPLAN")
		_refresh()
		return
	_turn_changed()

func _process(delta: float) -> void:
	for f in flashes:
		f["t"] -= delta
	flashes = flashes.filter(func(f): return f["t"] > 0)
	var spent: Array = []
	for k in fire_pose:
		fire_pose[k] = float(fire_pose[k]) - delta
		if float(fire_pose[k]) <= 0.0:
			spent.append(k)
	for k in spent:
		fire_pose.erase(k)
	if face_t > 0.0:
		face_t -= delta
		if face_t <= 0.0:
			shooter_box.visible = false
			target_box.visible = false
			shooter_lbl.visible = false
			target_lbl.visible = false
	for e in booms:
		e["t"] -= delta
	booms = booms.filter(func(e): return e["t"] > 0)
	if shake > 0.0:
		shake -= delta
		cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0 * maxf(shake, 0.0) / 0.25
	else:
		cam.offset = Vector2.ZERO
	if fx:
		fx.queue_redraw()
	if phase == "enemy":
		ai_t -= delta
		if ai_t <= 0.0:
			ai_t = 0.35
			var u := b.current()
			if u.is_empty() or not b.ai_step(u):
				if not b.over:
					b.end_turn()
				_turn_changed()
			else:
				_after_action()
	queue_redraw()
	# advance the simultaneous-execute walkers (Jagged Alliance-style move animation)
	var done: Array = []
	for id in walkers.keys():
		var w: Dictionary = walkers[id]
		w["t"] = float(w["t"]) + delta * 4.0
		if float(w["t"]) >= 1.0:
			w["i"] = int(w["i"]) + 1
			w["t"] = 0.0
			if int(w["i"]) >= int(w["path"].size()) - 1:
				done.append(id)
		walkers[id] = w
	for id in done:
		walkers.erase(id)

func _unhandled_input(ev: InputEvent) -> void:
	if not main.input_ok(ev) or phase == "over":
		return
	if ev is InputEventMouseMotion:
		if ev.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			cam.position -= ev.relative / cam.zoom
		hover = tile_at_screen(get_global_mouse_position())
		_tip()
		queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var z := cam.zoom.x * (1.15 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
			cam.zoom = Vector2.ONE * clampf(z, 0.25, 1.2)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			click(tile_at_screen(get_global_mouse_position()))
	elif ev is InputEventKey and ev.pressed and phase == "battle":
		var u := b.current()
		match ev.keycode:
			KEY_1: mode = "snap"
			KEY_2: mode = "aimed"
			KEY_3: mode = "burst"
			KEY_4: mode = "grenade"
			KEY_M: mode = "melee"
			KEY_5: mode = "rocket"
			KEY_F: mode = "aid"
			KEY_R: b.reload(u)
			KEY_C: b.set_stance(u, "stand" if u["stance"] == "crouch" else "crouch")
			KEY_P: b.set_stance(u, "stand" if u["stance"] == "prone" else "prone")
			KEY_T: b.set_reserve(u)
			KEY_E:
				b.end_turn()
				_turn_changed()
				return
		_after_action()

## A click on a tile: select / place in deployment; move, fire or aid in battle.
func click(t: Vector2i) -> void:
	if phase == "deploy":
		var o := b.at_tile(t)
		if not o.is_empty() and o["team"] == "squad":
			selected = o["id"]
		elif selected >= 0:
			var u := b.unit(selected)
			var why := Forces.placement_problem(b, u, t)
			if why == "":
				u["pos"] = t
			else:
				_log(why)
		_refresh()
		return
	if phase != "battle" and phase != "plan":
		return
	if phase == "plan":
		var u := b.current()
		if u.is_empty() or u["team"] != "squad":
			return
		if plan_selected < 0 or b.unit(plan_selected).is_empty():
			plan_selected = u["id"]
		var sel := b.unit(plan_selected)
		var o := b.at_tile(t)
		if not o.is_empty() and o["team"] == "squad" and o["state"] != "dead":
			plan_selected = int(o["id"])
			_refresh()
			return
		if mode in ["snap", "aimed", "burst", "rocket"] and not o.is_empty() and o["team"] == "enemy" and o["state"] != "dead" and b.is_seen(o, "squad"):
			b.plan_fire(sel, o, mode)
			_refresh()
			return
		if mode == "grenade":
			b.plan_grenade(sel, t)
			_refresh()
			return
		if reach.has(t):
			b.plan_move(sel, t)
			_refresh()
			return
		return
	var u := b.current()
	if u.is_empty() or u["team"] != "squad":
		return
	var o := b.at_tile(t)
	if mode == "aid":
		if not o.is_empty() and o["team"] == "squad":
			b.first_aid(u, o)
		mode = "snap"
	elif mode == "grenade":
		b.throw_grenade(u, t)
		mode = "snap"
	elif mode == "melee" and not o.is_empty() and o["team"] == "enemy" and o["state"] != "dead" and b.is_seen(o, "squad"):
		b.melee(u, o)
		mode = "snap"
	elif not o.is_empty() and o["team"] == "enemy" and o["state"] != "dead" and b.is_seen(o, "squad"):
		if mode == "rocket" and u["kind"] == "man" and u["launcher"] != "":
			var keep: String = u["weapon"]
			var ka := int(u["ammo"])
			u["weapon"] = u["launcher"]
			u["ammo"] = 1
			if b.fire(u, o, "aimed"):
				u["rockets"] = int(u["rockets"]) - 1
				if int(u["rockets"]) <= 0:
					u["launcher"] = ""
			u["weapon"] = keep
			u["ammo"] = ka
			mode = "snap"
		else:
			b.fire(u, o, mode)
	elif reach.has(t):
		b.move(u, t)
	_after_action()

func _tip() -> void:
	tip_lbl.text = ""
	if phase != "battle":
		return
	var u := b.current()
	var o := b.at_tile(hover)
	if u.is_empty() or o.is_empty() or o["team"] != "enemy" or o["state"] == "dead" or not b.is_seen(o, "squad"):
		return
	var wp := b.weapon_of(u, u["launcher"] if mode == "rocket" else "")
	var m := "snap" if mode in ["grenade", "aid", "rocket"] else mode
	var ch := b.hit_chance(u, o, wp, m)
	tip_lbl.text = "%s  %d m  HIT %d%%%s" % [o["name"], int(b.dist_m(u["pos"], o["pos"])), int(ch * 100), "  (COVER)" if b.cover(o["pos"], u["pos"]) == 2 else ""]
	tip_lbl.position = get_viewport().get_mouse_position() + Vector2(18, 10)

# ---------------- drawing ----------------
func _diamond(t: Vector2i) -> PackedVector2Array:
	var a := origin + Vector2(t) * tile
	return PackedVector2Array([iso(a), iso(a + Vector2(tile, 0)), iso(a + Vector2(tile, tile)), iso(a + Vector2(0, tile))])

func _draw() -> void:
	# ground: the season tiles (indoors the room picture lies under all this), then the grid
	for y in range(size.y if lm != null else 0):
		for x in range(size.x):
			var a := origin + Vector2(x, y) * tile
			var tx := int(floor(a.x / 2.0))
			var ty := int(floor(a.y / 2.0))
			var p := iso(a)
			draw_texture_rect(lm.tiles[lm.tile_at(tx, ty)], Rect2(p.x, p.y - 36.0, 144.0, 72.0), false)
	# craters: a dark hole with a lighter rim of thrown-up earth (the ring round a big one is
	# rough ground in the rules, drawn as part of the one crater)
	for c in holes:
		_draw_crater(iso(tile_centre(c[0])), c[1])
	for y in range(size.y + 1):
		draw_line(iso(origin + Vector2(0, y) * tile), iso(origin + Vector2(size.x, y) * tile), Color(0, 0, 0, 0.18), 1.0)
	for x in range(size.x + 1):
		draw_line(iso(origin + Vector2(x, 0) * tile), iso(origin + Vector2(x, size.y) * tile), Color(0, 0, 0, 0.18), 1.0)
	if phase == "deploy" and selected >= 0:
		var u := b.unit(selected)
		for y in range(size.y):
			for x in range(size.x):
				var t := Vector2i(x, y)
				if Forces.placement_problem(b, u, t) == "":
					draw_colored_polygon(_diamond(t), Color(0.3, 0.9, 0.3, 0.16))
	for t in reach:
		draw_colored_polygon(_diamond(t), Color(0.3, 0.6, 1.0, 0.13))
	# ghost/waypoint preview of the queued paths (planning phase): faint diamonds at each
	# path tile plus a thin line connecting them, per queued move action
	if phase == "plan":
		for uu in b.units:
			if uu["team"] != "squad" or uu["kind"] != "man" or uu["plan"].is_empty():
				continue
			for a in uu["plan"]:
				if a["type"] != "move" or not a.has("path"):
					continue
				var path: Array = a["path"]
				if path.size() == 0:
					continue
				var pts := PackedVector2Array()
				for t in path:
					draw_colored_polygon(_diamond(t), Color(1, 0.6, 0, 0.25))
					pts.append(iso(tile_centre(t)))
				if pts.size() >= 2:
					draw_polyline(pts, Color(1, 0.6, 0, 0.25), 1.0)
	var cu := b.current() if phase != "deploy" else b.unit(selected)
	if not cu.is_empty():
		draw_polyline(_close(_diamond(cu["pos"])), Color(1, 0.9, 0.2), 3.0)
	for u in b.units:
		if u["team"] == "enemy" and u["state"] == "ok" and int(u.get("in_vehicle", -1)) < 0 and not u.get("fled", false):
			draw_polyline(_close(_diamond(u["pos"])), Color(1, 0.2, 0.15, 0.8), 2.0)
	if b.inside(hover):
		draw_polyline(_close(_diamond(hover)), Color(1, 1, 1, 0.7), 2.0)
	for f in flashes:
		draw_line(f["from"], f["to"], Color(1, 0.95, 0.5, f["t"] * 4.0), 3.0)
func _close(p: PackedVector2Array) -> PackedVector2Array:
	p.append(p[0])
	return p

func _draw_crater(c: Vector2, size: int) -> void:
	var rx := 120.0 if size >= 2 else 55.0          # a tile is 144 px wide
	var pts := PackedVector2Array()
	var rim := PackedVector2Array()
	for i in range(16):
		var a := TAU * i / 16.0
		var j := 1.0 + 0.12 * sin(a * 3.0 + c.x)     # a little ragged
		pts.append(c + Vector2(cos(a) * rx, sin(a) * rx * 0.5) * j)
		rim.append(c + Vector2(cos(a) * rx * 1.3, sin(a) * rx * 0.65) * j)
	draw_colored_polygon(rim, Color(0.58, 0.40, 0.22, 0.95))
	draw_colored_polygon(pts, Color(0.26, 0.15, 0.08, 1.0))
	draw_colored_polygon(PackedVector2Array(Array(pts).map(func(p): return c + (p - c) * 0.55 + Vector2(0, rx * 0.08))), Color(0.12, 0.07, 0.04, 1.0))

## Explosions over everything: the original fireball (3 frames growing), then grey smoke that
## rises and spreads, and clods thrown out.
func _draw_fx() -> void:
	for e in booms:
		var age: float = BOOM_T - e["t"]
		var big: bool = e["size"] >= 2
		var s := SC * (2.6 if big else 1.5)
		var at: Vector2 = e["at"]
		for i in range(5 if big else 3):                 # smoke
			var k := age / BOOM_T
			var off := Vector2((i - 2) * 22.0 * s / SC, -60.0 * k * s - i * 10.0)
			var r := (16.0 + 46.0 * k) * s / SC * (1.0 + 0.2 * i)
			fx.draw_circle(at + off, r, Color(0.3, 0.29, 0.27, 0.8 * (1.0 - k)))
		for d in e["debris"]:                             # clods of earth
			if age < 0.7:
				var p: Vector2 = at + d * age + Vector2(0, 520.0 * age * age)
				fx.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0.2, 0.15, 0.1, 1.0 - age / 0.7))
		if not explod.is_empty() and age < 0.45:          # the fireball
			var f: Texture2D = explod[mini(int(age / 0.15), explod.size() - 1)]
			var sz := f.get_size() * s
			fx.draw_texture_rect(f, Rect2(at - Vector2(sz.x / 2.0, sz.y * 0.75), sz), false)
		elif explod.is_empty() and age < 0.45:
			fx.draw_circle(at, 30.0 * s * age / 0.45, Color(1, 0.6, 0.1, 1.0 - age / 0.45))

## A tree knocked down: the sprite falls over away from the vehicle and stays lying, darker; a
## stump is crushed flat. Either way it then lies on the ground, under the units.
func _lay_down(t: Vector2i, dir: Vector2i) -> void:
	var pair: Array = tree_at.get(t, [])
	if pair.is_empty():
		return
	tree_at.erase(t)
	var sp: Sprite2D = pair[0]
	props.erase(sp)
	sp.modulate = Color.WHITE
	var ground := Node2D.new()                    # sorted first: everything stands on it
	ground.position = sp.position - Vector2(0, 4000)
	world.add_child(ground)
	sp.reparent(ground)
	var tw := create_tween()
	if pair[1] == "stump":
		tw.tween_property(sp, "scale", Vector2(SC * 1.2, SC * 0.3), 0.25)
		tw.parallel().tween_property(sp, "modulate", Color(0.6, 0.55, 0.45), 0.25)
		return
	var sx := iso(origin + Vector2(dir)).x - iso(origin).x   # which way the fall looks on screen
	var to := 1.35 if sx >= 0.0 else -1.35
	tw.tween_property(sp, "rotation", to, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(sp, "modulate", Color(0.75, 0.7, 0.6), 0.6)
	tw.tween_property(sp, "scale", Vector2(SC, SC * 0.8), 0.15)

# ---------------- the end ----------------
func _finish() -> void:
	if phase == "over":
		return
	phase = "over"
	if main.test_name != "":                      # tests: how it went, in the console
		print("[test] battle over: winner %s after %d rounds" % [b.winner, b.round_no])
		for l in b.log.slice(-25):
			print("[battle] ", l)
	_pull_log()
	var lines: Array = []
	lines.append("THERE ARE NO MORE ENEMIES." if b.winner == "squad" else ("THE SQUAD HAS FALLEN." if b.winner == "enemy" else "THE FIGHTING DIES DOWN."))
	lines.append_array(b.aftermath())
	var improve := b.write_back(main.squad, cr)
	for u in b.units:
		if u["team"] == "squad" and u["kind"] == "vehicle" and u["state"] == "dead" and u["name"] == main.squad_vehicle:
			lines.append("THE %s IS LOST." % u["name"])
			main.lose_vehicle()
	for u in b.units:
		if u["team"] == "squad" and u["kind"] == "man":
			var state: String = {"ok": "ON %s FEET" % ("HER" if u.get("gender", "M") == "F" else "HIS"), "down": "DOWN BUT ALIVE", "dead": "KILLED IN ACTION"}[u["state"]]
			lines.append("%s: %s" % [u["name"], state])
	lines.append_array(improve)
	var enemy_dead := b.units.filter(func(u): return u["team"] == "enemy" and u["state"] == "dead" and u["kind"] == "man").size()
	lines.append("ENEMY KILLED: %d" % enemy_dead)
	var lt := RichTextLabel.new()
	lt.position = Vector2(24, 20)
	lt.size = Vector2(752, 360)
	lt.add_theme_font_size_override("normal_font_size", 17)
	lt.add_theme_color_override("default_color", Color(1, 0.5, 0.4))
	lt.text = "\n".join(lines)
	end_panel.add_child(lt)
	var btn := Button.new()
	btn.text = "CONTINUE"
	btn.position = Vector2(24, 400)
	btn.pressed.connect(done)
	end_panel.add_child(btn)
	end_panel.visible = true
	_refresh()

func done() -> void:
	var killed := b.units.filter(func(u): return u["team"] == "enemy" and u["state"] != "ok" and u["kind"] == "man").size()
	main.battle_over(setup, b.winner, killed)

# ---------------- tests ----------------
func test_place(i: int, dx: int, dy: int) -> void:
	var u := b.unit(squad_ids[i])
	click(u["pos"])
	click(u["pos"] + Vector2i(dx, dy))

## Tests: the computer plays the squad too; once over, continue (so a mission run can call
## this again and again until it is back on the map).
func test_auto() -> void:
	if phase == "over":
		done()
		return
	if ai_squad:
		return
	ai_squad = true
	if phase == "deploy":
		begin()
	else:
		_turn_changed()

## Tests: the squad's vehicle drives through the nearest trees it can reach.
func test_drive_through_trees() -> void:
	for u in b.units:
		if u["team"] == "squad" and u["kind"] == "vehicle":
			u["ap"] = 60.0
			var best := Vector2i(-1, -1)
			var bd := 1e9
			for y in range(size.y):
				for x in range(size.x):
					var t := Vector2i(x, y)
					if b.tree[b.idx(t)] == 1 and b.passable(u, t) and tree_at.get(t, [null, "stump"])[1] != "stump":
						var d := Vector2(t - u["pos"]).length()
						if d < bd:
							bd = d
							best = t
			if best.x < 0:
				return
			b.move(u, best)                       # straight into the tree (a path would go round it)
			cam.position = iso(tile_centre(u["pos"]))
			_place_units()
			_after_action()
			return

## Tests: a burst (big = a TOW, else a hand grenade) some tiles from the squad's first unit.
func test_blast(dx: int, dy: int, big: bool) -> void:
	var at: Vector2i = b.unit(squad_ids[0])["pos"] + Vector2i(dx, dy) if not squad_ids.is_empty() else size / 2
	for u in b.units:
		if u["team"] == "squad" and u["kind"] == "vehicle":
			at = u["pos"] + Vector2i(dx, dy)
	var wp: Dictionary
	if big:
		wp = b.weapon_of({"kind": "vehicle", "data": {"weapons": ["TOW II"]}}, "TOW II")
	else:
		wp = b.items.get("FRAGMENTATION GRENADE", {})
	b._explode({}, at, wp, {})
	cam.position = iso(tile_centre(at)).lerp(cam.position, 0.5)
	_after_action()

func test_close_dialog() -> void:
	pass
