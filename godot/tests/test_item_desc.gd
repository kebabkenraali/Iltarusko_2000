## Headless check of the original item descriptions in Inventory INFO/DESCRIPTION.
## godot --headless --path . --script tests/test_item_desc.gd
extends SceneTree

func _init() -> void:
	var data := GameData.new()
	data.load_all()
	var fails := 0
	# Known entries from the original EQUIP.TXT offset table (item id -> description).
	var checks := {
		"M9": "THE STANDARD SIDEARM FOR U.S. MILITARY FORCES.",
		"AKM": "THE MODERN VERSION OF THE UBIQUITOUS AK-47.",
		"UZI": "THE ISRAELI-DESIGNED UZI IS THE MOST COMMON SUBMACHINEGUN.",
		"PM MAKAROV": "THE STANDARD MILITARY SIDEARM OF MOST EASTERN EUROPEAN STATES",
	}
	for nm in checks.keys():
		var d: String = data.item_description(String(nm))
		if not d.begins_with(String(checks[nm])):
			prints("FAIL description", nm, "->", d.substr(0, 60))
			fails += 1
	# Ammunition and added items have no original description.
	for nm in ["5.56MM N", "FIELD RATIONS", "(unarmed)"]:
		var d2: String = data.item_description(nm)
		if d2 != "":
			prints("FAIL expected empty description for", nm)
			fails += 1
	# A missing name yields an empty string.
	if data.item_description("NO SUCH ITEM") != "":
		prints("FAIL unknown item")
		fails += 1
	if fails == 0:
		prints("ITEM DESC TEST PASS")
	else:
		prints("ITEM DESC TEST FAIL", fails)
	quit()
