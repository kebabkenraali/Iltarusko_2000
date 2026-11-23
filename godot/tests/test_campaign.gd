## Headless check of the mission logic: godot --headless --path . -s tests/test_campaign.gd
## Plays every playable mission type through its steps and checks the texts.
extends SceneTree

func _init() -> void:
	var data := GameData.new()
	data.load_all()
	var fails := 0
	var cp := Campaign.new(data.missions, data.cities, data.items, 4242)
	for t in Campaign.PLAYABLE:
		var m := cp.new_mission(t)
		# M9 economy round 2: dump mission requires a 2 1/2 TON TRUCK
		if t == "dump":
			cp.squad_vehicle = func(): return "2 1/2 TON TRUCK"
		var texts: Array = [cp.briefing("ANNA")]
		var guard := 0
		while not cp.mission.is_empty() and guard < 40:
			guard += 1
			var st := cp.step()
			var c := cp.place(st)
			match st.split(":")[0]:
				"talk":
					# visit the town in trouble first (opening + a reminder), then the step's town
					texts.append_array(cp.talk_leader(m["target"], "ANNA"))
					if not cp.mission.is_empty():
						texts.append_array(cp.talk_leader(cp.place(cp.step()), "ANNA") if cp.step().begins_with("talk:") else [])
				"clear":
					cp.enemy_down(c)
				"treat":
					cp.patient_treated()
				"spy":
					if cp.is_spy(int(cp.mission["spy"])):
						cp.spy_dead()
				"search":
					for b in range(3):
						var line := cp.searched(c, b)
						if line != "":
							texts.append(line)
							break
				"reach":
					texts.append_array(cp.arrived(c, "ANNA"))
				"repair":
					while cp.enemies_in(c) > 0:          # the scavengers first
						cp.enemy_down(c)
					texts.append(cp.objective_text())
					texts.append_array(cp.repaired("ANNA"))
		if not cp.mission.is_empty():
			fails += 1
			print("FAIL %s did not finish (step %s)" % [t, cp.step()])
		for s in texts:
			if String(s).contains("{") or String(s).contains("%s") or String(s).strip_edges() == "":
				fails += 1
				print("FAIL %s text: %s" % [t, String(s).substr(0, 160)])
		print("%-9s %s -> %s | %s" % [t, m["target"], "done" if cp.mission.is_empty() else "STUCK", String(texts[0]).substr(0, 110)])
	if cp.stores.size() != Campaign.PLAYABLE.size():
		fails += 1
		print("FAIL rewards: ", cp.stores)
	if cp.story_index == 0:
		fails += 1
		print("FAIL no story messages")
	# the wounded do not wait: treat in time and get the reward, come too late and get nothing
	var now := [0.0]
	cp.clock = func(): return now[0]
	for story in [false, true]:
		cp.is_story = func(): return story
		for late in [false, true]:
			var m := cp.new_mission("wounded")
			var total := int(m["patients"])
			var times := cp.sick_times()
			cp.talk_leader(m["target"], "ANNA")
			if late:
				now[0] += (times[0] + times[1] * total) * 60.0       # every one of them gone
			else:
				now[0] += (times[0] - 1.0) * 60.0
			var stores_before := cp.stores.size()
			while cp.step().begins_with("treat:") and cp.patient_treated() == false:
				pass
			var lines := cp.talk_leader(m["target"], "ANNA")
			var rewarded := cp.stores.size() > stores_before
			print("%s wounded in %s, %s (grace %.1f h, one dies every %.0f h): %s" % ["STORY " if story else "NORMAL", m["target"], "too late" if late else "in time",
				times[0], times[1], String(lines[0]).substr(0, 70)])
			if rewarded == late or not cp.mission.is_empty():
				fails += 1
				print("FAIL wounded %s late=%s: rewarded=%s" % ["story" if story else "normal", late, rewarded])
	if cp.motor_pool.size() != 1:
		fails += 1
		print("FAIL motor pool: ", cp.motor_pool)
	print("motor pool: ", cp.motor_pool)
	print("stores: ", cp.stores)
	print("story messages queued: ", cp.story_index)

	# Test vehicle purchase
	var VehicleClass = preload("res://scripts/vehicle.gd")
	var vehicle = VehicleClass.new()
	var purchasable = cp.get_purchasable_vehicles()
	if purchasable.size() != 8:
		fails += 1
		print("FAIL: expected 8 purchasable vehicles, got ", purchasable.size())
	for v in purchasable:
		if not v.has("name") or not v.has("price") or not v.has("fuel_type"):
			fails += 1
			print("FAIL: purchasable vehicle missing fields: ", v)

	# Test purchase_vehicle
	var cp2 = Campaign.new(data.missions, data.cities, data.items, 4243)
	var humvee_price = cp2.get_vehicle_price("HMMWV")
	if humvee_price != 20000:
		fails += 1
		print("FAIL: HMMWV price wrong: ", humvee_price)
	# Can afford
	if not cp2.purchase_vehicle("HMMWV", 50000):
		fails += 1
		print("FAIL: should be able to purchase HMMWV with 50000")
	if cp2.motor_pool.size() != 1 or cp2.motor_pool[0] != "HMMWV":
		fails += 1
		print("FAIL: motor_pool after purchase: ", cp2.motor_pool)
	# Cannot afford
	var cp3 = Campaign.new(data.missions, data.cities, data.items, 4244)
	if cp3.purchase_vehicle("M1A1", 10000):
		fails += 1
		print("FAIL: should not afford M1A1 with 10000")

	# Test fuel type compatibility
	if not cp.can_refuel_with("HMMWV", "D"):
		fails += 1
		print("FAIL: HMMWV should accept diesel")
	if cp.can_refuel_with("HMMWV", "G"):
		fails += 1
		print("FAIL: HMMWV should not accept gasoline")
	if cp.can_refuel_with("HMMWV", "A"):
		fails += 1
		print("FAIL: HMMWV should not accept avgas")

	# Test field_repair
	var damaged_vehicle = {
		"damage": {"engine": 50, "front": 30, "side": 20},
		"engine_running": false
	}
	var repaired = cp.field_repair(damaged_vehicle, 5)  # skill 5
	if repaired["damage"].get("engine", 0) >= 50:
		fails += 1
		print("FAIL: engine damage should be reduced")
	if repaired["damage"].get("front", 0) >= 30:
		fails += 1
		print("FAIL: front damage should be reduced")
	if not repaired["engine_running"]:
		fails += 1
		print("FAIL: engine should be running after repair")

	print("CAMPAIGN TEST ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
