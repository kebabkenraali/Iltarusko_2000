## The HQ resupply economy (M9 round 2): prices derived from the item data and the caps
## each recruit can carry. The original data has no ammunition prices (all 0) and no
## explicit caps, so a magazine costs a tenth of the weapon's price (rounded to 10,
## minimum 10), a med kit or a grenade its item price. These are OUR derived rules -
## documented in SUUNNITELMA ch. 15/16, not the 1991 tables.
class_name Economy
extends RefCounted

const MAG_CAP := 12                    # spare magazines on one recruit
const MEDKIT_CAP := 3
const GRENADE_CAP := 12

## Price of one spare magazine of `name`, or 0 when the weapon is unknown.
static func mag_cost(items: Array, weapon: String) -> int:
	for it in items:
		if String(it["name"]) == weapon and int(it.get("magazine", 0)) > 0:
			return maxi(10, int(roundf(int(it["price"]) / 10.0)))
	return 0

static func medkit_cost(items: Array) -> int:
	return price_of(items, "PERSONAL MEDICAL KIT")

static func grenade_cost(items: Array) -> int:
	return price_of(items, "FRAGMENTATION GRENADE")

static func price_of(items: Array, name: String) -> int:
	for it in items:
		if String(it["name"]) == name:
			return int(it["price"])
	return 0

## The recruit's gear bank; "" weapon means the recruit has not been issued anything yet.
## null-safe: a recruit without gear (Forces.equip runs at the first battle) cannot buy
static func gear(r: Dictionary) -> Dictionary:
	return r.get("gear", {})

static func has_gear(r: Dictionary) -> bool:
	return r.has("gear")

## Buy up to `n` spare magazines. Returns how many were bought, 0 at the cap, -1 with no gear.
static func add_mags(r: Dictionary, n: int) -> int:
	if not r.has("gear"):
		return -1
	var g: Dictionary = r["gear"]
	var before := int(g.get("mags", 0))
	var space := maxi(0, MAG_CAP - before)
	var bought := mini(n, space)
	g["mags"] = before + bought
	r["gear"] = g
	return bought

static func add_medkits(r: Dictionary, n: int) -> int:
	if not r.has("gear"):
		return -1
	var g: Dictionary = r["gear"]
	var before := int(g.get("medkits", 0))
	var bought := mini(n, maxi(0, MEDKIT_CAP - before))
	g["medkits"] = before + bought
	r["gear"] = g
	return bought

static func add_grenades(r: Dictionary, n: int) -> int:
	if not r.has("gear"):
		return -1
	var g: Dictionary = r["gear"]
	var before := int(g.get("grenades", 0))
	var bought := mini(n, maxi(0, GRENADE_CAP - before))
	g["grenades"] = before + bought
	r["gear"] = g
	return bought
