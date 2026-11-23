## Krakow Motor Pool: buy, repair, refuel vehicles.
extends Control

var main: Node
var tip: Label
var vehicle_list: VBoxContainer
var selected_vehicle: Dictionary = {}
var funds: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.03, 0.95)
	bg.size = Vector2(1280, 800)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	
	# Title
	var title := Label.new()
	title.text = "KRAKOW MOTOR POOL"
	title.position = Vector2(40, 20)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	add_child(title)
	
	# Funds display
	funds = _get_funds()
	var funds_lbl := Label.new()
	funds_lbl.text = "FUNDS: %d MK" % funds
	funds_lbl.position = Vector2(40, 60)
	funds_lbl.add_theme_font_size_override("font_size", 20)
	funds_lbl.add_theme_color_override("font_color", Color(0.8, 1, 0.6))
	funds_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	funds_lbl.add_theme_constant_override("outline_size", 3)
	add_child(funds_lbl)
	
	# Vehicle list
	var list_bg := ColorRect.new()
	list_bg.color = Color(0.08, 0.06, 0.04, 0.8)
	list_bg.position = Vector2(40, 100)
	list_bg.size = Vector2(600, 560)
	add_child(list_bg)
	
	vehicle_list = VBoxContainer.new()
	vehicle_list.position = Vector2(50, 110)
	vehicle_list.size = Vector2(580, 540)
	add_child(vehicle_list)
	
	# Right panel for selected vehicle
	var panel_bg := ColorRect.new()
	panel_bg.color = Color(0.08, 0.06, 0.04, 0.8)
	panel_bg.position = Vector2(660, 100)
	panel_bg.size = Vector2(580, 560)
	add_child(panel_bg)
	
	tip = Label.new()
	tip.position = Vector2(680, 120)
	tip.size = Vector2(540, 520)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 18)
	tip.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8))
	tip.add_theme_color_override("font_outline_color", Color.BLACK)
	tip.add_theme_constant_override("outline_size", 2)
	add_child(tip)
	
	# Close button
	var close_btn := Button.new()
	close_btn.text = "RETURN TO OFFICE"
	close_btn.position = Vector2(680, 700)
	close_btn.size = Vector2(200, 40)
	close_btn.pressed.connect(_on_close)
	add_child(close_btn)
	
	_refresh_list()

func _get_funds() -> int:
	# the mission pay accumulates in Krakow's cash box (campaign.funds)
	return main.campaign.funds

func _refresh_list() -> void:
	for child in vehicle_list.get_children():
		child.queue_free()
	
	var purchasable = main.campaign.get_purchasable_vehicles()
	for v in purchasable:
		var btn := Button.new()
		btn.text = "%s  (%d MK)  [%s]" % [v["name"], v["price"], v["fuel_type"]]
		btn.size = Vector2(560, 36)
		btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.theme_type_variation = "Flat"
		btn.pressed.connect(_on_vehicle_selected.bind(v))
		vehicle_list.add_child(btn)
	
	# Also show motor pool vehicles
	if main.campaign.motor_pool.size() > 0:
		var sep := Label.new()
		sep.text = "--- IN MOTOR POOL ---"
		sep.add_theme_font_size_override("font_size", 16)
		sep.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vehicle_list.add_child(sep)
		
		for vname in main.campaign.motor_pool:
			var btn := Button.new()
			btn.text = "%s  (READY)" % vname
			btn.size = Vector2(560, 36)
			btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.disabled = true
			btn.theme_type_variation = "Flat"
			vehicle_list.add_child(btn)

func _on_vehicle_selected(v: Dictionary) -> void:
	selected_vehicle = v
	var can_afford = funds >= v["price"]
	var in_pool = main.campaign.motor_pool.has(v["name"])
	
	var txt = "%s\n" % v["name"]
	txt += "Price: %d MK\n" % v["price"]
	txt += "Fuel type: %s\n" % v["fuel_type"]
	txt += "Type: %s\n" % v["kind"]
	if v.has("description"):
		txt += "\n" + v["description"] + "\n"
	txt += "\n"
	if in_pool:
		txt += "ALREADY IN MOTOR POOL"
	elif can_afford:
		txt += "CAN AFFORD - Click PURCHASE to buy"
	else:
		txt += "CANNOT AFFORD (need %d more MK)" % (v["price"] - funds)
	
	tip.text = txt
	
	# Add purchase button if not owned and can afford
	if not in_pool and can_afford:
		var buy_btn := Button.new()
		buy_btn.text = "PURCHASE FOR %d MK" % v["price"]
		buy_btn.position = Vector2(680, 600)
		buy_btn.size = Vector2(240, 40)
		buy_btn.pressed.connect(_on_purchase.bind(v))
		add_child(buy_btn)
		buy_btn.name = "BuyButton"

func _on_purchase(v: Dictionary) -> void:
	if main.campaign.purchase_vehicle(v["name"], main.campaign.funds):
		main.campaign.funds -= int(v["price"])
		funds = _get_funds()
		tip.text = "PURCHASED: %s\nAdded to motor pool." % v["name"]
		# Remove purchase button
		if has_node("BuyButton"):
			get_node("BuyButton").queue_free()
		_refresh_list()
		# Update funds display
		for child in get_children():
			if child is Label and child.text.begins_with("FUNDS:"):
				child.text = "FUNDS: %d MK" % funds
	else:
		tip.text = "PURCHASE FAILED"

func _on_close() -> void:
	main.show_office()