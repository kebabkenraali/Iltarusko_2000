## Headless check of the vehicle system (M6)
## Tests basic vehicle mechanics: creation, physics, fuel, cargo, damage.
extends SceneTree

func _init() -> void:
	var fails := 0
	
	# Test vehicle data loading
	var VehicleClass = preload("res://scripts/vehicle.gd")
	var vehicle = VehicleClass.new()
	
	var all_vehicles = vehicle.get_all_vehicles()
	if all_vehicles.size() != 8:
		fails += 1
		print("FAIL: expected 8 vehicles, got ", all_vehicles.size())
	
	# Test vehicle creation (HMMWV in the data)
	var humvee = vehicle.create_instance("HMMWV", Vector2(159500, 257500), 0, 1.0)
	if humvee == null:
		fails += 1
		print("FAIL: could not create HMMWV")
	else:
		# Test fuel range (90L / 30L per 100km = 300km)
		var range = humvee.get_fuel_range_km()
		if range < 290 or range > 310:
			fails += 1
			print("FAIL: HMMWV fuel range unexpected: ", range)
		
		# Test max speed (com_move[0]=50m per 5s = 36 km/h)
		var max_speed = humvee.get_max_speed()
		if max_speed < 35 or max_speed > 37:
			fails += 1
			print("FAIL: HMMWV max speed wrong: ", max_speed)
		
		# Test offroad speed (com_move[1]=15m per 5s = 10.8 km/h)
		var offroad_speed = humvee.get_offroad_speed()
		if offroad_speed < 10 or offroad_speed > 12:
			fails += 1
			print("FAIL: HMMWV offroad speed wrong: ", offroad_speed)
		
		# Test armor (HF = 1)
		if humvee.get_armor("front") != 1:
			fails += 1
			print("FAIL: HMMWV front armor wrong: ", humvee.get_armor("front"))
		
		# Test engine start
		if not vehicle.start_engine(humvee):
			fails += 1
			print("FAIL: engine start failed")
		
		# Test cargo (HMMWV load_t = 1.25t = 1250kg)
		if not vehicle.load_cargo(humvee, 500):
			fails += 1
			print("FAIL: cargo load failed")
		if humvee.cargo_kg != 500:
			fails += 1
			print("FAIL: cargo amount wrong: ", humvee.cargo_kg)
		
		# Try to overload (max is 1250, already have 500)
		if vehicle.load_cargo(humvee, 800):  # should fail, would exceed 1250
			fails += 1
			print("FAIL: cargo overload should fail")
		
		# Test physics process
		vehicle.physics_process(humvee, 1.0, Vector2(0, 1), "road")  # full throttle for 1s
		# accel = 30, so after 1s at full throttle: speed = 30 km/h (but capped at max 36)
		if humvee.speed_kmh < 25 or humvee.speed_kmh > 35:
			fails += 1
			print("FAIL: speed after 1s acceleration: ", humvee.speed_kmh)
		
		# Test fuel consumption
		var fuel_before = humvee.fuel_l
		vehicle.physics_process(humvee, 3600.0, Vector2(0, 1), "road")  # 1 hour at speed
		var fuel_used = fuel_before - humvee.fuel_l
		# HMMWV: 30L/100km at 36km/h = 10.8L/h
		if fuel_used < 9 or fuel_used > 13:
			fails += 1
			print("FAIL: fuel consumption wrong: ", fuel_used, "L/h")
		
		# Test combat damage (armor front = 1, pen 10 vs armor 1 -> penetrates)
		var penetrated = vehicle.apply_combat_damage(humvee, "front", 10, 50)
		if not penetrated:
			fails += 1
			print("FAIL: should penetrate HMMWV front armor")
		if humvee.damage.get("front", 0) < 40:
			fails += 1
			print("FAIL: damage not applied: ", humvee.damage.get("front", 0))
		
		# Test engine damage
		vehicle.apply_combat_damage(humvee, "engine", 10, 100)
		if humvee.engine_running:
			fails += 1
			print("FAIL: engine should be destroyed")
		
		# Test save/load
		var dict = vehicle.instance_to_dict(humvee)
		var humvee2 = vehicle.instance_from_dict(dict)
		if humvee2 == null:
			fails += 1
			print("FAIL: load from dict failed")
		else:
			if abs(humvee2.pos.x - humvee.pos.x) > 0.1:
				fails += 1
				print("FAIL: position not saved correctly")
			if abs(humvee2.fuel_l - humvee.fuel_l) > 0.1:
				fails += 1
				print("FAIL: fuel not saved correctly")
	
	# Test 2 1/2 TON TRUCK (no armor)
	var truck = vehicle.create_instance("2 1/2 TON TRUCK", Vector2(159500, 257500))
	if truck:
		if truck.get_armor("front") != 1:
			fails += 1
			print("FAIL: truck should have 1 armor (HF=1): ", truck.get_armor("front"))
		# com_move = [45, 8] -> 32.4 km/h road, 5.76 km/h offroad
		var truck_speed = truck.get_max_speed()
		if truck_speed < 31 or truck_speed > 33:
			fails += 1
			print("FAIL: truck speed wrong: ", truck_speed)
	
	# Test M1A1 (heavy armor, HF=300)
	var abrams = vehicle.create_instance("M1A1", Vector2(159500, 257500))
	if abrams:
		if abrams.get_armor("front") != 300:
			fails += 1
			print("FAIL: M1A1 front armor wrong: ", abrams.get_armor("front"))
		# Small arms should not penetrate (pen 5 vs armor 300)
		var pen = vehicle.apply_combat_damage(abrams, "front", 5, 20)
		if pen:
			fails += 1
			print("FAIL: small arms should not penetrate M1A1 front")
		# TOW II should not penetrate front (pen 160 vs armor 300)
		var pen2 = vehicle.apply_combat_damage(abrams, "front", 160, 50)
		if pen2:
			fails += 1
			print("FAIL: TOW II should not penetrate M1A1 front (armor 300)")
		# But TOW II should penetrate side (HS=16)
		var pen3 = vehicle.apply_combat_damage(abrams, "side", 160, 50)
		if not pen3:
			fails += 1
			print("FAIL: TOW II should penetrate M1A1 side (armor 16)")
	
	print("VEHICLE TEST ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)