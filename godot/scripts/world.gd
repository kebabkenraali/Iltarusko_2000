## The world outside the towns: the original 1 km terrain grid (data/worldmap.json, from
## GAMEDATA/DW_GFY.UYB), the squad's position on it, the clock, what has been explored, and the
## chance of running into trouble on the way. Travel is the original LCD mapper's MOVE feature
## ("MOVE TO WHERE?", "YOU SPEND %s MARCHING AND RESTING") made into a Fallout-style map trip.
class_name World
extends RefCounted

var w := 0
var h := 0
var origin := Vector2(100, 178)       # km of cell (0, 0)
var terrain := ""                     # one letter per cell (see tools/extract_worldmap.py)
var codes: Array = []
var pos := Vector2(59.5, 79.5)        # squad position in cells (km from origin), Krakow
var minutes := 21.0 * 60.0            # since 1 October 2000 00:00
var explored := PackedByteArray()
var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var since_trouble := 0.0              # km walked since the last encounter
var drive_grids := {}                 # "wheeled" / "tracked" -> AStarGrid2D (made when first needed)

# minutes per km on foot ("marching and resting": about 4 km/h on a road)
const COST := {"R": 15.0, "B": 15.0, "T": 15.0, "G": 24.0, "F": 36.0, "V": 50.0, "X": 30.0}
# minutes per km driving (the original "YOU SPEND %s DRIVING"): wheeled vehicles keep to roads
# (about 50 km/h) and crawl through forest; tracks are slower on the road but go anywhere. Rivers
# are crossed only at bridges; water not at all.
const DRIVE := {
	"wheeled": {"R": 1.2, "B": 1.2, "T": 2.0, "G": 4.0, "X": 5.0, "F": 10.0},
	"tracked": {"R": 1.7, "B": 1.7, "T": 2.5, "G": 2.5, "X": 3.0, "F": 5.0},
}
const START_DAY := 274                # 1 October 2000 = day 274 of the year (0-based)

func _init(seed_value := 0) -> void:
	var m = GameData._json("res://data/worldmap.json")
	w = int(m["w"])
	h = int(m["h"])
	origin = Vector2(m["origin_km"][0], m["origin_km"][1])
	terrain = m["terrain"]
	codes = m["codes"]
	explored.resize(w * h)
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in range(h):
		for x in range(w):
			var t := at(Vector2i(x, y))
			if t == "W":
				astar.set_point_solid(Vector2i(x, y), true)
			else:
				astar.set_point_weight_scale(Vector2i(x, y), COST.get(t, 30.0) / 15.0)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	reveal(cell(), 4)

func at(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return "W"
	return terrain[c.y * w + c.x]

func cell() -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))

## World metres (the town / field view's a, b) <-> cells.
func to_metres(p: Vector2) -> Vector2:
	return (p + origin) * 1000.0

func from_metres(m: Vector2) -> Vector2:
	return m / 1000.0 - origin

func city_cell(c: Dictionary) -> Vector2:
	return from_metres(Vector2(c["a"], c["b"]))

func reveal(c: Vector2i, r: int) -> void:
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x >= 0 and y >= 0 and x < w and y < h and Vector2(x - c.x, y - c.y).length() <= r + 0.5:
				explored[y * w + x] = 1

func is_explored(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and explored[c.y * w + c.x] == 1

## Minutes per km of a cell: on foot (mode "foot") or driving ("wheeled", "tracked"). -1 = no way.
func cost(c: Vector2i, mode := "foot") -> float:
	var t := at(c)
	if t == "W":
		return -1.0
	if mode == "foot":
		return COST.get(t, 30.0)
	return float(DRIVE[mode].get(t, -1.0))

func _grid(mode: String) -> AStarGrid2D:
	if mode == "foot":
		return astar
	if not drive_grids.has(mode):
		var g := AStarGrid2D.new()
		g.region = Rect2i(0, 0, w, h)
		g.cell_size = Vector2.ONE
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()
		for y in range(h):
			for x in range(w):
				var k := cost(Vector2i(x, y), mode)
				if k < 0.0:
					g.set_point_solid(Vector2i(x, y), true)
				else:
					g.set_point_weight_scale(Vector2i(x, y), k)
		drive_grids[mode] = g
	return drive_grids[mode]

## Route (cells) on foot or driving, and its time in minutes.
func route(to: Vector2i, mode := "foot") -> Array:
	var from := cell()
	if cost(to, mode) < 0.0 or from == to:
		return []
	var g := _grid(mode)
	if g.is_point_solid(from):
		return []                           # a vehicle cannot start in a river
	return Array(g.get_id_path(from, to))

func route_minutes(path: Array, mode := "foot") -> float:
	var m := 0.0
	for i in range(1, path.size()):
		m += step_minutes(path[i - 1], path[i], mode)
	return m

func step_minutes(prev: Vector2i, c: Vector2i, mode := "foot") -> float:
	var step := 1.0 if (c - prev).abs() != Vector2i(1, 1) else 1.4142
	return maxf(0.0, cost(c, mode)) * step

# ---------------- time ----------------
func day_of_year() -> int:
	return (START_DAY + int(minutes / 1440.0)) % 365

func season() -> String:
	# the terrain kits: F autumn, W winter, P spring, S summer
	var d := day_of_year()
	if d >= 335 or d < 59:
		return "W"
	if d < 152:
		return "P"
	if d < 244:
		return "S"
	return "F"

func hour() -> float:
	return fmod(minutes / 60.0, 24.0)

func date_text() -> String:
	var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	var lens := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var d := day_of_year()
	var mo := 0
	while d >= lens[mo]:
		d -= lens[mo]
		mo += 1
	var year := 2000 + int((START_DAY + int(minutes / 1440.0)) / 365)
	return "%d %s %d  %02d:%02d" % [d + 1, months[mo], year, int(hour()), int(fmod(minutes, 60.0))]

## Duration as the original prints it: "%d DAY%s, %d HOUR%s, %d MINUTE%s".
static func span_text(m: float) -> String:
	var d := int(m / 1440.0)
	var hh := int(fmod(m, 1440.0) / 60.0)
	var mm := int(fmod(m, 60.0))
	var parts: Array = []
	if d > 0:
		parts.append("%d DAY%s" % [d, "S" if d != 1 else ""])
	if hh > 0:
		parts.append("%d HOUR%s" % [hh, "S" if hh != 1 else ""])
	parts.append("%d MINUTE%s" % [mm, "S" if mm != 1 else ""])
	return ", ".join(parts)

# ---------------- trouble on the way ----------------
## Groups met in the countryside (the tabletop referee's encounter list; the PC game names the
## Black Legion). hostile: fights unless evaded; count: people in the group.
const GROUPS := [
	{"name": "BLACK LEGION PATROL", "hostile": true, "min": 2, "max": 4, "weight": 4},
	{"name": "MARAUDERS", "hostile": true, "min": 3, "max": 6, "weight": 4},
	{"name": "STRAGGLERS", "hostile": true, "min": 1, "max": 3, "weight": 2},
	{"name": "HUNTERS", "hostile": false, "min": 2, "max": 3, "weight": 2},
	{"name": "REFUGEES", "hostile": false, "min": 3, "max": 6, "weight": 2},
	{"name": "MERCHANTS", "hostile": false, "min": 2, "max": 4, "weight": 1},
]

# wrecks left by the war: trucks and jeeps are common, tanks rarer (vehicles.json names, weight)
const WRECKS := [["HMMWV", 4], ["2 1/2 TON TRUCK", 4], ["M2A2 BRADLEY", 2], ["T-72", 2], ["T-80", 1], ["M1A1", 1]]

## Called for every kilometre (story mode only; the 1991 game has no such finds): seldom, a
## wrecked vehicle by the way, maybe with fuel left in it. About one in 170 km, with no
## guaranteed spacing. Returns {vehicle, burnt, fuel (litres left)} or {}.
const WRECK_CHANCE := 0.006

func check_wreck(fuel_cap_of: Callable) -> Dictionary:
	if rng.randf() >= WRECK_CHANCE:
		return {}
	var pool: Array = []
	for w in WRECKS:
		for i in range(int(w[1])):
			pool.append(w[0])
	var v: String = pool[rng.randi_range(0, pool.size() - 1)]
	var burnt := rng.randf() < 0.4                # burnt out: nothing left to drain
	var fuel := 0.0 if burnt else floorf(float(fuel_cap_of.call(v)) * rng.randf_range(0.05, 0.35))
	return {"vehicle": v, "burnt": burnt, "fuel": fuel}

## Called for every kilometre walked. Returns a group (Dictionary) when trouble comes.
func check_trouble(cities: Array, czarny: Vector2, scale := 1.0) -> Dictionary:
	since_trouble += 1.0
	if since_trouble < 3.0:
		return {}
	for c in cities:
		if city_cell(c).distance_to(pos) < 2.0:
			return {}                       # no ambushes at the town gates
	var t := at(cell())
	var p := 0.035 * (1.4 if t == "F" else 1.0) * (1.6 if hour() < 6.0 or hour() >= 21.0 else 1.0)
	var dz := pos.distance_to(czarny)
	if dz < 25.0:
		p *= 3.0                            # Czarny's land
	p *= scale                              # driving: fewer meetings for each km
	if rng.randf() >= p:
		return {}
	since_trouble = 0.0
	var pool: Array = []
	for g in GROUPS:
		var wgt: int = g["weight"] * (3 if dz < 25.0 and g["name"] == "BLACK LEGION PATROL" else 1)
		for i in range(wgt):
			pool.append(g)
	var g: Dictionary = pool[rng.randi_range(0, pool.size() - 1)].duplicate()
	g["count"] = rng.randi_range(int(g["min"]), int(g["max"]))
	g["terrain"] = t
	g["cell"] = cell()
	return g

# ---------------- save ----------------
func to_dict() -> Dictionary:
	return {"pos": [pos.x, pos.y], "minutes": minutes, "explored": Marshalls.raw_to_base64(explored),
		"since_trouble": since_trouble}

func from_dict(d: Dictionary) -> void:
	pos = Vector2(d["pos"][0], d["pos"][1])
	minutes = float(d["minutes"])
	explored = Marshalls.base64_to_raw(d["explored"])
	since_trouble = float(d.get("since_trouble", 0.0))
