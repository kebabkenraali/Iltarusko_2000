## Krakow HQ computer: the cash box, the stores, the motor pool, the squad's state and
## (M9 economy round 2) the squad's resupply: spare magazines, medical kits and grenades
## bought with the cash box (battle write_back had emptied them). The purchase rules live
## in Economy (derived from the item prices; the original has no ammunition prices).
## The office hotspot "computer" opens it; CLOSE (or Esc) goes back to the office.
extends Control

var main: Node
const GREEN := Color(0.55, 1.0, 0.6)
const DIM := Color(0.4, 0.75, 0.45)
var funds_lbl: Label
var res_box: VBoxContainer
var res_lbl: Label
var food_lbl: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.03, 0.97)
	bg.size = Vector2(1280, 800)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_title("KRAKOW HQ COMPUTER", Vector2(40, 16), 30)
	_title("STORE ROOM (MISSION REWARDS)", Vector2(680, 16), 22)

	var c: Campaign = main.campaign
	funds_lbl = _line(Vector2(40, 44), "")
	_refresh_head()
	var y := 72.0
	y = _addline(Vector2(40, y), "SQUAD: %d ACTIVE, %d FALLEN" % [main.squad.size(), main.fallen.size()])
	y = _addline(Vector2(40, y), "RATIONS: %d  (1 = one meal for one soldier, %d MK each)" % [int(c.food), c.RATION_PRICE], GREEN)
	food_lbl = _line(Vector2(40, y), "", Color(1, 0.85, 0.5))
	food_lbl.size = Vector2(620, 22)
	if main.squad_vehicle != "":
		y = _addline(Vector2(40, y), "VEHICLE: %s   FUEL %.0f / %.0f L" % [main.squad_vehicle, main.vehicle_fuel, main.fuel_cap()])
	y = _addline(Vector2(40, y), "MOTOR POOL: %s" % ("NONE" if c.motor_pool.is_empty() else ", ".join(c.motor_pool)))
	y = _addline(Vector2(40, y), "TOWNS OWING A FAVOUR: %d" % c.friends.size())
	y = _addline(Vector2(40, y + 8.0), "SQUAD STATUS", DIM)
	for r in main.squad:
		y = _addline(Vector2(40, y), "%-18s %s%s" % [String(r["name"]), Healing.condition(r), ("  HUNGRY" if bool(r.get("hungry", false)) else "")])

	# six bar graphs from the original computer screen: food, ammunition, medicine,
	# fuel, people, morale
	y = _addline(Vector2(680, y), "SQUAD RESOURCES", DIM)
	_bar_graph(Vector2(680, y + 4), "FOOD", _bar_food(c), c.food, int(main.squad.size()) * 3)
	_bar_graph(Vector2(680, y + 32), "AMMO", _bar_ammo(c), _total_mags(c), int(main.squad.size()) * Economy.MAG_CAP)
	_bar_graph(Vector2(680, y + 60), "MEDICINE", _bar_med(c), _total_medkits(c), int(main.squad.size()) * Economy.MEDKIT_CAP)
	_bar_graph(Vector2(680, y + 88), "FUEL", _bar_fuel(c), main.vehicle_fuel, main.fuel_cap())
	_bar_graph(Vector2(680, y + 116), "PEOPLE", _bar_people(c), main.squad.size(), 4)
	_bar_graph(Vector2(680, y + 144), "MORALE", _bar_morale(c), _avg_morale(c), 100)

	# the original's flow line: re-equipping at headquarters before the next mission
	_title("ADD AMMO TO WHICH WEAPON?  (RESUPPLY)", Vector2(40, y + 16.0), 17)
	res_box = VBoxContainer.new()
	res_box.position = Vector2(40, y + 44.0)
	res_box.add_theme_constant_override("separation", 2)
	add_child(res_box)
	_rebuild_resupply()
	res_lbl = _line(Vector2(40, 720), "", Color(1, 0.85, 0.5))
	res_lbl.size = Vector2(620, 50)
	res_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var stores: Dictionary = {}
	for s in c.stores:
		stores[s] = int(stores.get(s, 0)) + 1
	var sy := 72.0
	if stores.is_empty():
		_addline(Vector2(680, sy), "EMPTY - REWARDS ARRIVE WITH FINISHED MISSIONS", DIM)
	else:
		var keys: Array = stores.keys()
		keys.sort()
		for i in range(mini(keys.size(), 18)):
			sy = _addline(Vector2(680, sy), "%-34s x%d" % [String(keys[i]), int(stores[keys[i]])])
		if keys.size() > 18:
			_addline(Vector2(680, sy), "AND %d MORE LINES..." % (keys.size() - 18), DIM)

	var close := Button.new()
	close.text = "CLOSE"
	close.position = Vector2(1040, 720)
	close.size = Vector2(200, 44)
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(main.show_office)
	add_child(close)

func _refresh_head() -> void:
	funds_lbl.text = "FUNDS: %d MK" % int(main.campaign.funds)

# ---------------- resupply (M9 economy round 2) ----------------
## One row per recruit: name, weapon, and three buy buttons (mag / med kit / grenade).
func _rebuild_resupply() -> void:
	for n in res_box.get_children():
		n.queue_free()
	var items: Array = main.data.items
	var alive: Array = main.squad.filter(func(r): return not r.get("dead", false))
	for r in alive:
		var g: Dictionary = Economy.gear(r)
		var w: String = String(g.get("weapon", "")) if Economy.has_gear(r) else ""
		var wtxt: String = w if w != "" else "(NOT ISSUED YET)"
		var mc: int = Economy.mag_cost(items, w)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := Label.new()
		name_l.text = "%-17s %-24s %2d/%d MAGS  %d/%d MED  %2d/%d GRE" % [
			String(r["name"]).substr(0, 17), wtxt.substr(0, 24),
			int(g.get("mags", 0)) if Economy.has_gear(r) else 0, Economy.MAG_CAP,
			int(g.get("medkits", 0)) if Economy.has_gear(r) else 0, Economy.MEDKIT_CAP,
			int(g.get("grenades", 0)) if Economy.has_gear(r) else 0, Economy.GRENADE_CAP]
		name_l.add_theme_font_size_override("font_size", 15)
		name_l.add_theme_color_override("font_color", GREEN)
		name_l.custom_minimum_size = Vector2(560, 22)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_l)
		if mc > 0:
			row.add_child(_buy_btn("MAG %d" % mc, "mag", r, mc))
		row.add_child(_buy_btn("MED %d" % Economy.medkit_cost(items), "med", r, Economy.medkit_cost(items)))
		row.add_child(_buy_btn("GRE %d" % Economy.grenade_cost(items), "gre", r, Economy.grenade_cost(items)))
		res_box.add_child(row)

func _buy_btn(text: String, what: String, r: Dictionary, cost: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(90, 24)
	b.add_theme_font_size_override("font_size", 14)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_buy.bind(what, r, cost))
	return b

## One purchase: funds move first, the cap answers with the original's own line.
func _buy(what: String, r: Dictionary, cost: int) -> void:
	var f: int = int(main.campaign.funds)
	if f < cost:
		res_lbl.text = "NOT ENOUGH FUNDS.  (%s MK)" % cost
		return
	var bought := 0
	match what:
		"mag":
			var w: String = String(Economy.gear(r).get("weapon", ""))
			bought = Economy.add_mags(r, 1)
			if bought == -1:
				res_lbl.text = "%s ISN'T CARRYING ANY WEAPONS THAT USE ANY AMMO." % String(r["name"])
				return
			if bought == 0:
				res_lbl.text = "%s CANNOT CARRY ANY MORE AMMO FOR THE %s." % [String(r["name"]), w]
				return
		"med":
			bought = Economy.add_medkits(r, 1)
			if bought == -1:
				res_lbl.text = "%s ISN'T CARRYING ANY WEAPONS THAT USE ANY AMMO." % String(r["name"])
				return
			if bought == 0:
				res_lbl.text = "%s CANNOT CARRY ANY MORE MEDICAL KITS." % String(r["name"])
				return
		"gre":
			bought = Economy.add_grenades(r, 1)
			if bought == -1:
				res_lbl.text = "%s ISN'T CARRYING ANY WEAPONS THAT USE ANY AMMO." % String(r["name"])
				return
			if bought == 0:
				res_lbl.text = "%s CANNOT CARRY ANY MORE GRENADES." % String(r["name"])
				return
	main.campaign.funds = f - cost
	var w2: String = String(Economy.gear(r).get("weapon", ""))
	res_lbl.text = "%s BUYS %s FOR %d MK." % [String(r["name"]), "A MAGAZINE FOR THE %s" % w2 if what == "mag" else ("A MEDICAL KIT" if what == "med" else "A GRENADE"), cost]
	_refresh_head()
	_rebuild_resupply()

# ---------------- six bar graphs (M9 economy round 2) ----------------
func _bar_graph(at: Vector2, name: String, pct: float, cur: float, cap: float) -> void:
	var bar := ""
	var blocks := maxi(0, mini(20, int(pct / 5.0)))
	for i in range(20):
		bar += "█" if i < blocks else "░"
	var col := GREEN if pct >= 50 else (Color(1, 0.85, 0, 1) if pct >= 25 else Color(1, 0.4, 0.4, 1))
	_line(at, "%-10s %s  %3d%%  %d/%d" % [name, bar, int(pct), int(cur), int(cap)], col)

func _clamp01(v: float, cap: float) -> float:
	if cap <= 0:
		return 0.0
	return clampf(v / cap, 0.0, 1.0) * 100.0

func _bar_food(c: Campaign) -> float:
	return _clamp01(float(c.food), float(maxi(1, main.squad.size()) * 3.0))

func _total_mags(c: Campaign) -> int:
	var t := 0
	for r in main.squad:
		var g: Dictionary = Economy.gear(r)
		if Economy.has_gear(r):
			t = t + int(g.get("mags", 0))
	return t

func _bar_ammo(c: Campaign) -> float:
	return _clamp01(float(_total_mags(c)), float(maxi(1, main.squad.size()) * float(Economy.MAG_CAP)))

func _total_medkits(c: Campaign) -> int:
	var t := 0
	for r in main.squad:
		var g: Dictionary = Economy.gear(r)
		if Economy.has_gear(r):
			t = t + int(g.get("medkits", 0))
	return t

func _bar_med(c: Campaign) -> float:
	return _clamp01(float(_total_medkits(c)), float(maxi(1, main.squad.size()) * float(Economy.MEDKIT_CAP)))

func _bar_fuel(c: Campaign) -> float:
	if main.squad_vehicle == "":
		return 0.0
	return _clamp01(main.vehicle_fuel, main.fuel_cap())

func _bar_people(c: Campaign) -> float:
	return _clamp01(float(main.squad.size()), 4.0)

func _avg_morale(c: Campaign) -> float:
	if main.squad.is_empty():
		return 100.0
	var t := 0.0
	var n := 0
	for r in main.squad:
		if not r.get("dead", false):
			t = t + float(r.get("morale", 100))
			n = n + 1
	if n == 0:
		return 100.0
	return t / float(n)

func _bar_morale(c: Campaign) -> float:
	return _clamp01(_avg_morale(c), 100.0)


# ---------------- UI helpers ----------------
func _title(text: String, at: Vector2, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GREEN)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)

## One monitor line; returns the y for the next one.
func _addline(at: Vector2, text: String, color := GREEN) -> float:
	_line(at, text, color)
	return at.y + 28.0

func _line(at: Vector2, text: String, color := GREEN) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	add_child(l)
	return l

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		main.show_office()
