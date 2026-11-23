## The ground under the field view, made from the season's terrain kit (BUILDING/<S>O1..O3,
## S = F autumn, W winter, P spring, S summer) and the 1 km world cell the squad is in: open
## country, forest, a road or a river running through in the direction the world map gives.
## Ground tiles are 2 m squares (the kits' 48 px diamonds at 12 px/m); trees, stumps and bushes
## stand on it and the trunks block the way.
class_name LocalMap
extends RefCounted

var season := "F"
var world: World
var centre := Vector2.ZERO           # metres (a, b) of the local map's centre
var radius := 60.0
var kind := "G"                      # terrain letter of the centre cell
var road_dirs: Array = []            # unit vectors along roads through the centre
var river_dirs: Array = []
var props: Array = []                # {pos, kind: spruce/tree/stump/bush, r}
var tiles: Array = []                # 6 AtlasTextures: grass, water, mud, dirt, asphalt, rocky grass
var tex := {}                        # prop textures

const T_GRASS := 0
const T_WATER := 1
const T_MUD := 2
const T_DIRT := 3
const T_ASPHALT := 4
const T_ROCKY := 5

func _init(w: World, at_metres: Vector2, r: float, town := false) -> void:
	world = w
	centre = at_metres
	radius = r
	season = w.season()
	var cell := Vector2i(world.from_metres(at_metres).floor())
	kind = "T" if town else world.at(cell)
	# roads / rivers leaving the centre cell towards neighbouring cells of the same network
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var t := world.at(cell + d)
		if t in ["R", "B", "T"]:
			road_dirs.append(Vector2(d).normalized())
		if t == "V":
			river_dirs.append(Vector2(d).normalized())
	if kind in ["R", "B"] and road_dirs.is_empty():
		road_dirs = [Vector2(1, 0)]
	if kind != "V":
		river_dirs = []
	elif river_dirs.is_empty():
		river_dirs = [Vector2(0, 1)]
	var kit: Texture2D = load("res://original/graphics/BUILDING/%sO1_rgba.png" % season)
	for i in range(6):
		var at := AtlasTexture.new()
		at.atlas = kit
		at.region = Rect2((i % 3) * 48, (i / 3) * 23, 48, 23)
		tiles.append(at)
	var stump := AtlasTexture.new()
	stump.atlas = kit
	stump.region = Rect2(144, 0, 32, 32)
	var bush := AtlasTexture.new()
	bush.atlas = kit
	bush.region = Rect2(149, 33, 22, 14)
	tex = {"spruce": load("res://original/graphics/BUILDING/%sO2_rgba.png" % season),
		"tree": load("res://original/graphics/BUILDING/%sO3_rgba.png" % season), "stump": stump, "bush": bush}
	if not town:
		_scatter()

## Distance of a point to the band along one of the directions (road / river line).
func _band(p: Vector2, dirs: Array) -> float:
	var best := 1e9
	var d := p - centre
	for v in dirs:
		var along: float = d.dot(v)
		if along < -2.0:
			continue                          # a road only goes out the way it leads
		best = minf(best, absf(d.x * v.y - d.y * v.x))
	return best

func on_road(p: Vector2) -> bool:
	return _band(p, road_dirs) < 2.6

func in_river(p: Vector2) -> bool:
	return _band(p, river_dirs) < 3.0

## Ground tile index at a 2 m tile (tx, ty in tile units of the world).
func tile_at(tx: int, ty: int) -> int:
	var p := Vector2(tx * 2 + 1, ty * 2 + 1)
	var h := hash(Vector2i(tx, ty))
	if in_river(p):
		return T_WATER
	if on_road(p):
		return T_ASPHALT
	if kind == "W":
		return T_WATER
	if kind == "T":
		# trodden town ground: grass worn to earth here and there
		return T_DIRT if h % 6 == 0 else (T_ROCKY if h % 23 == 0 else T_GRASS)
	if h % 131 == 0:
		return T_MUD
	if h % 31 == 0:
		return T_ROCKY
	if h % 43 == 0:
		return T_DIRT
	return T_GRASS

## Trees and bushes: thick in forest, a few in open country; never on the road, in the river or
## where the squad comes in (the centre).
func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(centre.x), int(centre.y)))
	var n := 0
	match kind:
		"F": n = 150
		"G": n = 22
		"R", "B": n = 30
		"V": n = 26
		_: n = 18
	for i in range(n):
		var p := centre + Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))
		if p.distance_to(centre) < 9.0 or on_road(p) or in_river(p):
			continue
		var r := rng.randf()
		var k := "spruce" if r < 0.45 else ("tree" if r < 0.75 else ("stump" if r < 0.87 else "bush"))
		props.append({"pos": p, "kind": k, "r": {"spruce": 0.7, "tree": 0.6, "stump": 0.45, "bush": 0.0}[k]})

func blocking(p: Vector2) -> bool:
	for pr in props:
		if pr["r"] > 0.0 and p.distance_to(pr["pos"]) < pr["r"] + 0.4:
			return true
	return false

## A free spot at about `dist` metres from the centre (for the people of an encounter).
func free_spot(rng: RandomNumberGenerator, dmin: float, dmax: float) -> Vector2:
	for i in range(60):
		var a := rng.randf() * TAU
		var p := centre + Vector2(cos(a), sin(a)) * rng.randf_range(dmin, dmax)
		if not blocking(p) and not in_river(p):
			return p
	return centre + Vector2(dmin, 0)
