## Loads the data extracted from the original game (remake/assets_original via data/*.json).
class_name GameData
extends RefCounted

var cities: Array = []          # {name, a (east, m), b (south, m), size}
var items: Array = []
var chargen: Dictionary = {}
var missions: Dictionary = {}
var equip: Array = []           # item descriptions (EQUIP.json)
var item_desc: Dictionary = {}  # item id -> index in equip[] (item_desc_map.json, from EQUIP.TXT offset table)

static func _json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing data file " + path)
		return null
	return JSON.parse_string(f.get_as_text())

func load_all() -> void:
	cities = _json("res://data/cities.json")
	items = _json("res://data/items.json")
	chargen = _json("res://data/chargen.json")
	missions = _json("res://data/missions.json")
	equip = _json("res://data/EQUIP.json")
	if equip == null:
		equip = []
	var im: Variant = _json("res://data/item_desc_map.json")
	item_desc = {}
	if im is Dictionary:
		for k in im.keys():
			var v: Variant = im[k]
			item_desc[str(k).to_int()] = (null if v == null else str(v).to_int())

func city(name: String) -> Dictionary:
	for c in cities:
		if c["name"] == name:
			return c
	return {}

## Long description of an item by its name (the original EQUIP.TXT text), or "".
## Ammunition and removed items have no description in the original data.
func item_description(item_name: String) -> String:
	var up := item_name.strip_edges().to_upper()
	if up == "" or up == "(UNARMED)":
		return ""
	for it in items:
		if String(it.get("name", "")).to_upper() == up:
			var raw: Variant = item_desc.get(str(it.get("id", -1)).to_int(), -1)
			if raw == null:                       # JSON null: the original has no description
				return ""
			var idx: int = str(raw).to_int()
			if idx >= 0 and idx < equip.size():
				return String(equip[idx])
			return ""
	return ""
