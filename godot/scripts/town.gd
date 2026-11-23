## The buildings of every city, laid out from the original TWI2D templates
## (data/city_templates.json) and drawn with the sprites composed from the BUILDING kits
## (tools/compose_buildings.py -> BUILDING/composed, data/buildings.json).
## World coordinates as everywhere: a = east, b = south, metres.
class_name Town
extends RefCounted

var buildings: Array = []        # {city, type, facing, centre: Vector2, size: Vector2, door: Vector2, key}
var meta: Dictionary = {}

const INTERIOR := {"HOUSE": "HOUSE", "TAVERN": "TAVERN", "MARKET": "MARKET", "JAIL": "JAIL",
		"HOSPITAL": "HOSP", "BANK": "BANK", "FACTORY": "FACT", "CHURCH": "CHURCH", "BARN": "HOUSE"}

func _init(cities: Array) -> void:
	var tpl = GameData._json("res://data/city_templates.json")
	meta = GameData._json("res://data/buildings.json")
	for c in cities:
		# Checiny (size 255, Czarny's seat) has no template of its own: it gets the largest town's
		var recs: Array = tpl["sizes"].get(str(int(c["size"])), tpl["sizes"]["0"])
		for r in recs:
			var key := "%s_%d" % [r["type"], int(r["facing"])]
			var m: Dictionary = meta.get(key, {})
			if m.is_empty():
				continue
			var size := Vector2(m["size"][0], m["size"][1])
			var centre := Vector2(float(c["a"]) + float(r["dx"]), float(c["b"]) + float(r["dy"]))
			var sides: Array = [Vector2(0, size.y / 2), Vector2(-size.x / 2, 0), Vector2(0, -size.y / 2), Vector2(size.x / 2, 0)]
			var door: Vector2 = centre + sides[int(r["facing"])]
			buildings.append({"city": c["name"], "type": r["type"], "facing": int(r["facing"]), "centre": centre,
				"size": size, "door": door, "key": key})

## Buildings within `radius` metres of a point.
func near(p: Vector2, radius: float) -> Array:
	var out: Array = []
	for b in buildings:
		if b["centre"].distance_to(p) < radius:
			out.append(b)
	return out

## The building whose walls (plus a margin) contain the point, or {}.
func blocking(p: Vector2, margin := 0.6) -> Dictionary:
	for b in buildings:
		var half: Vector2 = b["size"] / 2 + Vector2(margin, margin)
		var d: Vector2 = p - b["centre"]
		if absf(d.x) < half.x and absf(d.y) < half.y:
			return b
	return {}

## Building whose door is within `reach` metres, or {}.
func door_at(p: Vector2, reach := 2.5) -> Dictionary:
	for b in buildings:
		if b["door"].distance_to(p) < reach:
			return b
	return {}

## Interior picture of a building (IS/IW/IN/IE + name), seen from the door's side.
static func interior_picture(b: Dictionary) -> String:
	return ["IS", "IW", "IN", "IE"][int(b["facing"])] + INTERIOR.get(b["type"], "HOUSE")
