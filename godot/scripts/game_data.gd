## Loads the data extracted from the original game (remake/assets_original via data/*.json).
class_name GameData
extends RefCounted

var cities: Array = []          # {name, a (east, m), b (south, m), size}
var items: Array = []
var chargen: Dictionary = {}
var missions: Dictionary = {}
var equip: Array = []           # item descriptions (EQUIP.json)

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

func city(name: String) -> Dictionary:
	for c in cities:
		if c["name"] == name:
			return c
	return {}
