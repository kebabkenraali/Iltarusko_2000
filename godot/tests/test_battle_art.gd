## Headless audit of the battle art: every weapon's firing pose (CMBT, 8 directions, both
## sets), the standing bodies (AM/AF/EM torsos with the AF N/NE/NW fallback), legs and the
## head strips, plus the KNEEL/WOUND pose art. Prevents regressions like a weapon falling
## to an art set that has no file in some direction (an invisible body while firing).
## godot --headless --path . --script tests/test_battle_art.gd
extends SceneTree

const HAND_CATEGORIES := ["assault rifle", "battle rifle", "sniper rifle", "machinegun",
	"automatic rifle", "heavy machinegun", "submachinegun", "automatic pistol", "revolver",
	"shotgun", "rocket launcher", "missile launcher", "grenade launcher", "hand tool"]

func _init() -> void:
	var bv := preload("res://scripts/battle_view.gd").new()
	var items: Array = GameData._json("res://data/items.json")
	var dirs: Array = Soldier.DIRS
	var counted: Array = []
	# every walkable weapon resolves to an art file that exists in all 8 directions
	var weapons := items.filter(func(it): return String(it["category"]) in HAND_CATEGORIES)
	assert(weapons.size() >= 30, "the items.json fire list is intact")
	for it in weapons:
		for art_of in [["BLACK LEGION SOLDIER", "enemy"], ["SERGEI NOWAK", "man"]]:
			var u := {"name": art_of[0], "weapon": String(it["name"])}
			var art: String = bv._fire_pose_art(u)
			for d in dirs:
				var t: Texture2D = bv._cmbt(art + d)
				assert(t != null, "CMBT %s%s missing for %s/%s" % [art, d, String(it["name"]), art_of[1]])
			var key: String = art + "/" + art_of[1]
			if not counted.has(key):
				counted.append(key)
	# the pose art (prone / wounded / killed) too, in all 8 directions
	for base in ["KNEEL", "WOUND"]:
		for d in dirs:
			assert(bv._cmbt(base + d) != null, "CMBT %s%s missing" % [base, d])
	# the set coverage: every art set except PUNCH (melee equipment is not in items.json)
	for art in ["EHG", "ESMG", "EPIST", "HG", "SMG", "PISTOL", "BAZOOK"]:
		var found := false
		for k in counted:
			if k.begins_with(art + "/"):
				found = true
		assert(found, "art set %s is not used by any weapon unassigned" % art)
	# standing bodies: torso frames for all 8 directions (AF falls back to AM towards north),
	# legs from the split cells, heads 0..14 (+ the enemy's one head)
	for body in ["AM", "AF", "EM"]:
		for d in dirs:
			var torso := Soldier._frames(body + d)
			if torso.is_empty():
				assert(body != "EM" and not Soldier._frames("AM" + d).is_empty(),
					"no torso frames for %s facing %s (and no AM fallback)" % [body, d])
			assert(Soldier._legs(d).size() > 0, "no leg frames facing %s" % d)
	for body in ["AM", "AF"]:
		for v in range(15):
			assert(not Soldier.head_image(body, v).is_empty(), "head %s%d missing" % [body, v])
	assert(not Soldier.head_image("EM", 3).is_empty(), "the enemy head strip is broken")
	print("BATTLE ART TEST PASS  (%d weapons, %d art sets)" % [weapons.size(), counted.size()])
	bv.free()
	quit(0)
