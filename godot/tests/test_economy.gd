## Headless check of the HQ resupply economy (economy.gd + computer.gd math):
## derived prices, caps, funds flow, and the refusal lines. The computer UI itself is
## exercised by --test=computer / fullgame (windowed).
## godot --headless --path . --script tests/test_economy.gd
extends SceneTree

func _init() -> void:
	var items: Array = GameData._json("res://data/items.json")
	# derived prices: a mag costs one tenth of the weapon price (min 10), med kit and
	# grenade their item price
	assert(Economy.mag_cost(items, "AKM") == 30, "AKM mag = 30 MK")
	assert(Economy.mag_cost(items, "M9") == 15, "M9 mag = 15 MK (150/10)")
	assert(Economy.mag_cost(items, "LAW 80 ROCKET LAUNCHER") == 0, "mag 0 launcher: no mags")
	assert(Economy.medkit_cost(items) == 100, "med kit = 100 MK")
	assert(Economy.grenade_cost(items) == 4, "grenade = 4 MK")
	# a recruit without gear cannot buy (Forces.equip issues gear at the first battle);
	# buying respects the caps
	var r := {"name": "SERGEI NOWAK", "weapon": "AKM"}
	assert(Economy.add_mags(r, 1) == -1 and Economy.add_medkits(r, 1) == -1, "no gear: refuse with the original's line")
	r["gear"] = {"weapon": "AKM", "mags": 0, "medkits": 0, "grenades": 0}
	assert(Economy.gear(r)["weapon"] == "AKM", "gear bank with the weapon")
	assert(Economy.add_mags(r, 5) == 5 and Economy.gear(r)["mags"] == 5)
	assert(Economy.add_mags(r, 99) == Economy.MAG_CAP - 5, "cap stops the rest")
	assert(Economy.add_mags(r, 1) == 0, "at cap: nothing bought")
	assert(Economy.add_medkits(r, 99) == Economy.MEDKIT_CAP)
	assert(Economy.add_medkits(r, 1) == 0)
	assert(Economy.add_grenades(r, 200) == Economy.GRENADE_CAP)
	# the kill/med kit numbers flow through write_back: mags drop in battle, HQ refills them
	var r2 := {"name": "ANNI", "gear": {"weapon": "M9", "mags": 0, "medkits": 0, "grenades": 0}}
	for i in range(3):
		Economy.add_mags(r2, 1)
	assert(Economy.gear(r2)["mags"] == 3)
	print("ECONOMY TEST PASS")
	quit(0)
