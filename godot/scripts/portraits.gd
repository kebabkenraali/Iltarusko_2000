## Talking heads for the conversations (tools/make_portraits.py -> FACES/talk, data/portraits.json):
## the recruits' own portraits, Exor 1 from the briefing picture, and townspeople made from the
## recruits' faces (civilian clothes, leaders in suits, patients bandaged). Each head is a list of
## frames: [mouth shut, mouth open (, open again)].
class_name Portraits
extends RefCounted

static var meta: Dictionary = {}
static var sheets := {}
const PALS := ["grey", "blue", "brown", "maroon"]

static func _meta() -> Dictionary:
	if meta.is_empty():
		meta = GameData._json("res://data/portraits.json")
	return meta

static func _sheet(name: String) -> Texture2D:
	if not sheets.has(name):
		var p := "res://original/graphics/FACES/talk/%s.png" % name
		sheets[name] = load(p) if ResourceLoader.exists(p) else null
	return sheets[name]

static func _frames(set_name: String, i: int) -> Array:
	var tex := _sheet(set_name)
	if tex == null:
		return []
	var c: Array = _meta()["cell"]
	var out: Array = []
	for k in range(2):
		var a := AtlasTexture.new()
		a.atlas = tex
		a.region = Rect2(k * c[0], i * c[1], c[0], c[1])
		out.append(a)
	return out

## Exor 1: three frames (shut, and two open from the briefing's mouth strip).
static func exor() -> Array:
	var tex := _sheet("exor")
	if tex == null:
		return []
	var e: Dictionary = _meta()["exor"]
	var out: Array = []
	for k in range(int(e["frames"])):
		var a := AtlasTexture.new()
		a.atlas = tex
		a.region = Rect2(k * e["cell"][0], 0, e["cell"][0], e["cell"][1])
		out.append(a)
	return out

## A recruit's own chargen portrait.
static func recruit(r: Dictionary) -> Array:
	return _frames("squad_" + ("F" if r.get("gender", "M") == "F" else "M"), int(r.get("face", 0)) % 15)

## Someone in a town or on the road (a field-view person or an indoor resident). The same person
## always has the same face; leaders and patients have their own looks.
static func person(p: Dictionary) -> Array:
	var body := String(p.get("body", ""))
	if body == "" and p.get("sprite") is Soldier:
		body = p["sprite"].body
	var g := "F" if body == "AF" else "M"
	var civil: Array = _meta()["civil"][g]
	var key := hash(String(p.get("city", "")) + String(p.get("kind", "")) + str(p.get("index", 0)) + str(p.get("pos", Vector2.ZERO).floor()))
	if p.get("kind", "") == "leader":
		key = hash(String(p.get("city", "")))       # one leader per town, whatever moves
	var face: int = civil[absi(key) % civil.size()]
	match String(p.get("kind", "")):
		"leader":
			return _frames("leader_" + g, face)
		"patient":
			return _frames("patient_" + g, face)
	return _frames("civ_%s_%s" % [PALS[absi(key / 7) % PALS.size()], g], face)
