## Vehicle system for Twilight: 2000 (M6)
## 3D vehicle driving with physics, damage, fuel, cargo, and crew management.
class_name Vehicle
extends RefCounted

## Vehicle instance (runtime state)
class Instance:
	var data: Dictionary
	var fuel_l: float = 0
	var cargo_kg: float = 0
	var crew: Array = []
	var passengers: Array = []
	var damage: Dictionary = {}
	var engine_running: bool = false
	var speed_kmh: float = 0
	var pos: Vector2 = Vector2.ZERO
	var heading: float = 0
	var in_combat: bool = false
	
	func get_max_speed() -> float:
		# com_move[0] = meters per 5s turn on road -> km/h
		if data.has("com_move") and data["com_move"].size() > 0:
			return float(data["com_move"][0]) * 3.6 / 5.0
		return float(data.get("speed_road_kmh", 60))
	
	func get_offroad_speed() -> float:
		# com_move[1] = meters per 5s turn offroad -> km/h
		if data.has("com_move") and data["com_move"].size() > 1:
			return float(data["com_move"][1]) * 3.6 / 5.0
		return float(data.get("speed_offroad_kmh", 30))
	
	func get_fuel_type() -> String:
		return data.get("fuel_type", "D")
	
	func can_use_fuel(fuel_type: String) -> bool:
		# D = diesel, G = gasoline, A = avgas
		# Multi-fuel engines (turbines) can use D, G, A
		var vtype = get_fuel_type()
		if vtype == "D":
			return fuel_type == "D"
		elif vtype == "G":
			return fuel_type == "G"
		elif vtype == "A":
			return fuel_type == "A"
		elif vtype == "M":  # multi-fuel (turbine)
			return true
		return false
	
	func get_fuel_range_km() -> float:
		# fuel_cons is litres per 100km
		if float(data.get("fuel_cons", 1)) > 0:
			return fuel_l / float(data["fuel_cons"]) * 100.0
		return 0.0
	
	func get_total_weight_kg() -> float:
		# cargo_kg in JSON is load_t (tonnes)
		var weight = float(data.get("load_t", 0)) * 1000.0
		weight += cargo_kg
		for c in crew:
			weight += 80
		for p in passengers:
			weight += 80
		return weight
	
	func is_operational() -> bool:
		return damage.get("engine", 0) < 100 and fuel_l > 0.5
	
	func get_armor(loc: String) -> int:
		# JSON armor uses HF, HS, HR, TF, TS, TR
		var armor_map = {"front": "HF", "side": "HS", "rear": "HR", "turret_front": "TF", "turret_side": "TS", "turret_rear": "TR"}
		var key = armor_map.get(loc.to_lower(), loc.to_upper())
		if data.has("armor") and data["armor"].has(key):
			return int(data["armor"][key])
		return int(data.get("armor_" + loc.to_lower(), 0))
	
	func take_damage(loc: String, amount: float) -> void:
		damage[loc] = damage.get(loc, 0) + amount
		if loc == "engine" and damage[loc] >= 100:
			engine_running = false


## Static vehicle data loaded from JSON
var vehicle_data: Array = []
var instances: Array[Instance] = []

func _init() -> void:
	load_vehicle_data()

func load_vehicle_data() -> void:
	var f = FileAccess.open("res://data/vehicles.json", FileAccess.READ)
	if f == null:
		push_error("Missing vehicles.json")
		return
	var json = JSON.parse_string(f.get_as_text())
	f.close()
	if json is Dictionary and json.has("vehicles"):
		vehicle_data = json["vehicles"]
	else:
		vehicle_data = json if json is Array else []

func get_vehicle(name: String) -> Dictionary:
	for v in vehicle_data:
		if v["name"] == name:
			return v
	return {}

func get_all_vehicles() -> Array:
	return vehicle_data
## Create a new vehicle instance
func create_instance(vehicle_name: String, pos: Vector2, heading: float = 0, fuel_pct: float = 1.0) -> Instance:
	var vdata = get_vehicle(vehicle_name)
	if vdata.is_empty():
		push_error("Unknown vehicle: " + vehicle_name)
		return null
	
	var inst = Instance.new()
	inst.data = vdata
	inst.pos = pos
	inst.heading = heading
	inst.fuel_l = float(vdata.get("fuel_cap", 100)) * fuel_pct
	inst.cargo_kg = 0
	inst.damage = {}
	instances.append(inst)
	return inst


## Remove instance
func remove_instance(inst: Instance) -> void:
	instances.erase(inst)


## Physics update (called from tactical 3D scene)
func physics_process(inst: Instance, delta: float, input_vector: Vector2, terrain_type: String) -> void:
	if not inst.is_operational() or not inst.engine_running:
		inst.speed_kmh = maxi(0, inst.speed_kmh - 20 * delta)
		return
	
	var throttle = input_vector.y
	var steer = input_vector.x
	
	var max_speed = inst.get_max_speed()
	if terrain_type != "road":
		max_speed = inst.get_offroad_speed()
	
	var accel = 30.0
	var decel = 40.0
	var brake = 80.0
	
	if throttle > 0:
		inst.speed_kmh = min(inst.speed_kmh + accel * throttle * delta, max_speed)
	elif throttle < 0:
		inst.speed_kmh = maxi(0, inst.speed_kmh + throttle * brake * delta)
	else:
		inst.speed_kmh = maxi(0, inst.speed_kmh - decel * delta)
	
	if inst.speed_kmh > 1:
		var turn_rate = (inst.speed_kmh / 100.0) * 2.0
		inst.heading += steer * turn_rate * delta
	
	var consumption = float(inst.data.get("fuel_cons", 10))
	var dist_km = inst.speed_kmh / 3600.0 * delta
	inst.fuel_l -= consumption / 100.0 * dist_km
	inst.fuel_l = maxi(0, inst.fuel_l)
	
	var speed_ms = inst.speed_kmh / 3.6
	var dx = sin(inst.heading) * speed_ms * delta
	var dy = -cos(inst.heading) * speed_ms * delta
	inst.pos += Vector2(dx, dy) * 1000.0


## Start/stop engine
func start_engine(inst: Instance) -> bool:
	if inst.fuel_l > 0.5 and inst.damage.get("engine", 0) < 100:
		inst.engine_running = true
		return true
	return false

func stop_engine(inst: Instance) -> void:
	inst.engine_running = false


## Cargo management
func load_cargo(inst: Instance, kg: float) -> bool:
	var max_cargo = float(inst.data.get("load_t", 0)) * 1000.0
	if inst.cargo_kg + kg <= max_cargo:
		inst.cargo_kg += kg
		return true
	return false

func unload_cargo(inst: Instance, kg: float) -> float:
	var amount = min(kg, inst.cargo_kg)
	inst.cargo_kg -= amount
	return amount


## Crew management
func add_crew(inst: Instance, participant) -> bool:
	var max_crew = int(inst.data.get("crew", 2))
	if inst.crew.size() < max_crew:
		inst.crew.append(participant)
		return true
	return false

func add_passenger(inst: Instance, participant) -> bool:
	var max_pass = int(inst.data.get("passengers", 0))
	if inst.passengers.size() < max_pass:
		inst.passengers.append(participant)
		return true
	return false

func remove_occupant(inst: Instance, participant) -> void:
	inst.crew.erase(participant)
	inst.passengers.erase(participant)


## Damage from combat
func apply_combat_damage(inst: Instance, hit_loc: String, penetration: int, damage: int) -> bool:
	var armor = inst.get_armor(hit_loc)
	if penetration > armor:
		var dmg = float(damage) * (1.0 - float(armor) / float(penetration))
		inst.take_damage(hit_loc, dmg)
		return true
	return false


## Get vehicle status text
func get_status_text(inst: Instance) -> String:
	var txt = "%s\n" % inst.data["name"]
	txt += "Fuel: %.1f/%.0f L (%.0f km range)\n" % [inst.fuel_l, inst.data["fuel_capacity_l"], inst.get_fuel_range_km()]
	txt += "Speed: %.0f km/h\n" % inst.speed_kmh
	txt += "Cargo: %.0f/%.0f kg\n" % [inst.cargo_kg, inst.data["cargo_kg"]]
	txt += "Crew: %d/%d  Passengers: %d/%d\n" % [inst.crew.size(), inst.data["crew"], inst.passengers.size(), inst.data["passengers"]]
	txt += "Engine: %s\n" % ["RUNNING", "STOPPED"][int(not inst.engine_running)]
	if not inst.damage.is_empty():
		txt += "Damage: "
		for loc in inst.damage:
			txt += "%s %.0f%% " % [loc, inst.damage[loc]]
		txt += "\n"
	return txt


## Save/load
func instance_to_dict(inst: Instance) -> Dictionary:
	return {
		"name": inst.data["name"],
		"pos": [inst.pos.x, inst.pos.y],
		"heading": inst.heading,
		"fuel_l": inst.fuel_l,
		"cargo_kg": inst.cargo_kg,
		"damage": inst.damage,
		"engine_running": inst.engine_running,
		"speed_kmh": inst.speed_kmh,
	}

func instance_from_dict(data: Dictionary) -> Instance:
	var inst = create_instance(data["name"], Vector2(data["pos"][0], data["pos"][1]), data["heading"])
	if inst:
		inst.fuel_l = data["fuel_l"]
		inst.cargo_kg = data["cargo_kg"]
		inst.damage = data["damage"]
		inst.engine_running = data["engine_running"]
		inst.speed_kmh = data["speed_kmh"]
	return inst


## Get all instances data for saving
func get_all_instances_data() -> Array:
	var result = []
	for inst in instances:
		result.append(instance_to_dict(inst))
	return result


## Restore all instances from saved data
func restore_instances(data_array: Array) -> void:
	instances.clear()
	for d in data_array:
		var inst = instance_from_dict(d)
		if inst:
			instances.append(inst)