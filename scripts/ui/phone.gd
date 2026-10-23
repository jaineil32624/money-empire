extends CanvasLayer
## The Phone: every management screen in one place — jobs, businesses, real estate, mansion,
## vehicles, stocks, crime, empire/endgame, leaderboards, online play, cosmetics shop, settings.
##
## Rows are built once per tab; live numbers update in place through "updaters" so buttons
## never get rebuilt under the player's finger. After an action the tab is rebuilt (deferred).

const K = preload("res://scripts/ui/ui_kit.gd")
const W = preload("res://scripts/ui/widgets.gd")
const C = preload("res://scripts/core/catalog.gd")

signal closed
signal main_menu_requested

const TABS := [
	["jobs", "Jobs"], ["business", "Business"], ["realestate", "Real Estate"], ["mansion", "Mansion"],
	["vehicles", "Vehicles"], ["stocks", "Stocks"], ["crime", "Crime"], ["empire", "Empire"],
	["leaders", "Leaderboard"], ["online", "Online"], ["shop", "Shop"], ["settings", "Settings"],
]

var world
var hud
var root: Control
var panel: PanelContainer
var tab_buttons := {}
var content: VBoxContainer
var scroll: ScrollContainer
var title_lbl: Label
var cash_lbl: Label
var tab := "jobs"
var focus := ""
var updaters: Array[Callable] = []
var _confirm_reset := false
var _send_amount := 1000.0


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = K.make_theme()
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	root.add_child(dim)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", K.flat(Color(K.BG, 0.97), 22, K.LINE, 2, 16))
	root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = 24
	panel.offset_bottom = -24
	var outer := K.vbox(10)
	panel.add_child(outer)
	# header
	var head := K.hbox(12)
	title_lbl = K.label("PHONE", 28, K.GOLD, true)
	head.add_child(title_lbl)
	head.add_child(K.spacer())
	cash_lbl = K.label("", 22, K.GOLD, true)
	head.add_child(cash_lbl)
	head.add_child(K.button("  CLOSE  ", close, K.RED))
	outer.add_child(head)
	var body := K.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	# tab rail
	var rail_scroll := ScrollContainer.new()
	rail_scroll.custom_minimum_size.x = 170
	rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rail := K.vbox(6)
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail_scroll.add_child(rail)
	body.add_child(rail_scroll)
	for t in TABS:
		var id: String = t[0]
		var b := K.button(t[1], func(): open(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 42
		rail.add_child(b)
		tab_buttons[id] = b
	# content
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	content = K.vbox(8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	Game.changed.connect(_update)
	Net.players_changed.connect(func(): if is_open() and tab in ["online", "leaders"]: _rebuild.call_deferred())
	Net.status_changed.connect(func(_t): if is_open() and tab == "online": _rebuild.call_deferred())


func is_open() -> bool:
	return root.visible


func open(t: String = "", f: String = "") -> void:
	if t != "":
		tab = t
	focus = f
	root.visible = true
	if world:
		world.player.frozen = true
	_rebuild()
	scroll.scroll_vertical = 0


func close() -> void:
	if not root.visible:
		return
	root.visible = false
	if world:
		world.player.frozen = false
	closed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if not Game.running:
		return
	if e.is_action_pressed("phone"):
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("cancel") and is_open():
		close()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------- plumbing
func _rebuild() -> void:
	updaters.clear()
	for ch in content.get_children():
		ch.queue_free()
	for id in tab_buttons:
		var b: Button = tab_buttons[id]
		var on: bool = id == tab
		b.add_theme_stylebox_override("normal", K.flat(K.GOLD.darkened(0.55) if on else Color("#22304f"), 10, K.GOLD if on else K.LINE, 1, 14))
	for t in TABS:
		if t[0] == tab:
			title_lbl.text = str(t[1]).to_upper()
	call("_tab_" + tab)
	_update()


func _update() -> void:
	if not is_open():
		return
	cash_lbl.text = K.money(Game.sim.cash)
	for u in updaters:
		u.call()


func _do(cb: Callable, money_sound := true) -> void:
	var r = cb.call()
	if r is Dictionary:
		Game.act(r, money_sound)
	_rebuild.call_deferred()


func _h(text: String, sub := "") -> void:
	var v := K.vbox(0)
	v.add_child(K.label(text, 22, K.GOLD, true))
	if sub != "":
		var l := K.label(sub, 15, K.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	content.add_child(v)


func _note(text: String, color := K.MUTED, size := 15) -> Label:
	var l := K.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(l)
	return l


## A row card: title, live subtitle, and action buttons.
## actions: [{"text": String|Callable, "do": Callable, "enabled": Callable, "color": Color}]
func _row(title: String, sub: Callable, actions: Array, accent := K.LINE, extra: Control = null) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", K.flat(K.PANEL2, 12, accent, 1, 12))
	var h := K.hbox(10)
	card.add_child(h)
	if extra:
		h.add_child(extra)
	var v := K.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(K.label(title, 18, K.TEXT, true))
	var sl := K.label("", 14, K.MUTED)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sl)
	updaters.append(func(): sl.text = str(sub.call()))
	for a in actions:
		var txt = a.text
		var b := K.button(str(txt.call()) if txt is Callable else str(txt), func(): _do(a.do, a.get("money", true)), a.get("color", Color(0, 0, 0, 0)))
		b.custom_minimum_size.y = 40
		h.add_child(b)
		var en: Callable = a.get("enabled", Callable())
		updaters.append(func():
			if txt is Callable:
				b.text = str(txt.call())
			if en.is_valid():
				b.disabled = not bool(en.call()))
	content.add_child(card)
	return card


func _m(v: float) -> String:
	return K.money(v)


# ------------------------------------------------------------- JOBS
func _tab_jobs() -> void:
	var s = Game.sim
	_h("Jobs", "Walk (or drive) to a green JOB marker and press ACT. Faster deliveries earn tips. Living in your own home pays +10%.")
	_note("Jobs done: %d  ·  Job level %d  ·  Earned from jobs: %s" % [s.jobs_done, s.job_level(), _m(s.stats.jobs)], K.TEXT)
	if world and not world.job.is_empty():
		_row("ACTIVE: " + world.job_title(), func(): return world.job_objective(),
			[{"text": "Cancel job", "do": func(): world.cancel_job(), "color": K.RED, "money": false}], K.GREEN)
	for id in C.JOBS:
		var j: Dictionary = C.JOBS[id]
		var job_id: String = id
		_row(j.name, func():
			var lock := "" if s.job_unlocked(job_id) else "  ·  LOCKED until %d jobs" % int(j.unlock_jobs)
			return "%s  ·  pays %s%s\n%s" % [C.DISTRICTS[j.district].name, _m(s.job_pay(job_id)), lock, j.desc],
			[{"text": "Set GPS", "do": func(): _gps_to_marker("job", job_id), "money": false}])


func _gps_to_marker(kind: String, id: String, label := "") -> Dictionary:
	if world == null:
		return {}
	for m in world.city.markers:
		if m.kind == kind and (id == "" or m.id == id):
			hud.gps_target = m.pos
			hud.gps_label = m.label if label == "" else label
			close.call_deferred()
			return {"ok": true, "msg": "GPS set: " + m.label}
	return {"ok": false, "msg": "No marker found."}


# ------------------------------------------------------------- BUSINESS
func _tab_business() -> void:
	var s = Game.sim
	_h("Businesses", "Buy businesses for passive income every in-game hour. Upgrade (+50%/level) and hire workers (+10% each, they draw salaries). Income follows the economy.")
	var summary := _note("", K.TEXT)
	updaters.append(func(): summary.text = "Owned: %d  ·  Income %s/day  ·  Salaries %s/day  ·  Economy x%.2f" % [s.businesses.size(), _m(s.daily_business_income()), _m(s.daily_salaries()), s.economy.income_mult()])
	var tier := 0
	for row in C.BUSINESSES:
		if row.tier != tier:
			tier = row.tier
			_note("— %s —" % C.TIER_NAMES[tier].to_upper(), K.GOLD, 16)
		var id: String = row.id
		if s.businesses.has(id):
			_row(row.name, func():
				var b: Dictionary = s.businesses[id]
				return "OWNED  ·  Level %d/%d  ·  %d workers  ·  earns %s/day  ·  value %s" % [b.level, C.MAX_BUSINESS_LEVEL, b.workers, _m(s.business_income(id)), _m(s.business_value(id))],
				[{"text": func(): return "MAX" if int(s.businesses[id].level) >= C.MAX_BUSINESS_LEVEL else "Upgrade " + _m(s.upgrade_cost(id)),
					"do": func(): return s.upgrade_business(id), "enabled": func(): return int(s.businesses[id].level) < C.MAX_BUSINESS_LEVEL and s.cash >= s.upgrade_cost(id), "color": K.GREEN},
				 {"text": func(): return "Hire " + _m(s.worker_cost(id)), "do": func(): return s.hire_worker(id),
					"enabled": func(): return int(s.businesses[id].workers) < C.MAX_WORKERS and s.cash >= s.worker_cost(id)},
				 {"text": "Sell", "do": func(): return s.sell_business(id), "color": K.RED}], K.GOLD)
		else:
			_row(row.name, func():
				var inc: float = float(row.income) * s.economy.income_mult() * s.economy.price_index
				return "%s  ·  earns ~%s/day  ·  pays back in ~%d days" % [C.DISTRICTS[row.district].name, _m(inc), int(ceil(s.business_price(id) / maxf(1.0, inc)))],
				[{"text": func(): return "Buy " + _m(s.business_price(id)), "do": func(): return s.buy_business(id),
					"enabled": func(): return s.cash >= s.business_price(id), "color": K.GOLD}])


# ------------------------------------------------------------- REAL ESTATE
func _tab_realestate() -> void:
	var s = Game.sim
	_h("Real Estate", "Buy, rent out, renovate and flip. Each district's market moves with the economy — buy in a crash, sell in a boom.")
	var market := []
	for d in C.DISTRICTS:
		var pct: float = (float(s.economy.district_index[d]) * s.economy.asset_mult() - 1.0) * 100.0
		market.append("%s %s%d%%" % [C.DISTRICTS[d].name, "+" if pct >= 0 else "", int(round(pct))])
	_note("Market vs launch:  " + "   ".join(market), K.TEXT)
	_note("Rent income: %s/day  ·  %s" % [_m(s.daily_rent_income()), "Homeless (buy anything to move in: +10% job pay)" if s.home < 0 else "Home: " + s.property_row(s.properties[s.home].id).name], K.TEXT)
	if s.properties.size() > 0:
		_note("— YOUR PROPERTIES —", K.GOLD, 16)
	for i in s.properties.size():
		var idx: int = i
		var p: Dictionary = s.properties[idx]
		var row: Dictionary = s.property_row(p.id)
		_row(row.name + ("  (HOME)" if idx == s.home else ""), func():
			var st := "Home" if idx == s.home else ("Rented: +%s/day" % _m(s.property_rent(idx)) if p.rented else "Vacant")
			return "%s  ·  value %s  ·  %s%s" % [C.DISTRICTS[row.district].name, _m(s.property_value(idx)), st, "  ·  Renovated" if p.reno else ""],
			[{"text": "Live here", "do": func(): return s.set_home(idx), "enabled": func(): return idx != s.home, "money": false},
			 {"text": "Evict" if p.rented else "Rent out", "do": func(): return s.toggle_rent(idx), "enabled": func(): return idx != s.home, "money": false},
			 {"text": func(): return "Renovated" if p.reno else "Renovate " + _m(s.property_market_price(p.id) * C.RENOVATE_COST),
				"do": func(): return s.renovate_property(idx), "enabled": func(): return not p.reno and s.cash >= s.property_market_price(p.id) * C.RENOVATE_COST},
			 {"text": func(): return "Sell " + _m(s.property_value(idx)), "do": func(): return s.sell_property(idx), "color": K.RED}], K.BLUE)
	_note("— LISTINGS —", K.GOLD, 16)
	for row in C.PROPERTIES:
		var id: String = row.id
		_row(row.name, func():
			return "%s  ·  %s  ·  rent %s/day  ·  you own %d/%d" % [C.DISTRICTS[row.district].name, row.kind.capitalize(), _m(float(row.rent) * s.economy.price_index * s.economy.income_mult()), s.owned_count(id), row.max],
			[{"text": func(): return "Buy " + _m(s.property_market_price(id)), "do": func(): return s.buy_property(id),
				"enabled": func(): return s.cash >= s.property_market_price(id) and s.owned_count(id) < int(row.max), "color": K.GOLD}])


# ------------------------------------------------------------- MANSION
func _tab_mansion() -> void:
	var s = Game.sim
	_h("Mansion", "Luxury homes worth millions. Install features to raise value and prestige. Your best mansion is built on the YOUR MANSION lot in the Luxury District — friends online can visit.")
	var any := false
	for i in s.properties.size():
		var idx: int = i
		var row: Dictionary = s.property_row(s.properties[idx].id)
		if row.kind != "mansion" and row.kind != "island":
			continue
		any = true
		_note("— %s —  value %s" % [row.name.to_upper(), _m(s.property_value(idx))], K.GOLD, 17)
		for f in C.MANSION_FEATURES:
			var fid: String = f
			var fr: Dictionary = C.MANSION_FEATURES[fid]
			_row(fr.name, func():
				return "Installed" if fid in s.properties[idx].features else "Adds %s value · +%d prestige" % [_m(s.feature_cost(idx, fid) * C.FEATURE_VALUE_RETURN), fr.prestige],
				[{"text": func(): return "Installed" if fid in s.properties[idx].features else "Install " + _m(s.feature_cost(idx, fid)),
					"do": func(): return s.add_feature(idx, fid),
					"enabled": func(): return not fid in s.properties[idx].features and s.cash >= s.feature_cost(idx, fid), "color": K.GOLD}], Color("#ff6fb5"))
	if not any:
		_note("You don't own a mansion yet. The Hillside Villa (Real Estate) is the cheapest way in.", K.TEXT, 17)
		_row("Hillside Villa", func(): return "Market price " + _m(s.property_market_price("villa")),
			[{"text": "Open Real Estate", "do": func(): open.call_deferred("realestate"), "money": false}])
	_note("Prestige: %d  ·  Decor is cosmetic and lives in the Shop." % s.prestige(), K.TEXT)
	_row("Visit your mansion", func(): return "Set GPS to the Luxury District lot",
		[{"text": "Set GPS", "do": func(): return _gps_to_marker("mansion", ""), "money": false}])


# ------------------------------------------------------------- VEHICLES
func _tab_vehicles() -> void:
	var s = Game.sim
	_h("Vehicles", "Faster vehicles mean more jobs per hour. Helicopters fly over traffic; yachts and jets unlock fast travel.")
	_row("Currently: " + ("on foot" if s.active_vehicle == "" else s.vehicle_row(s.active_vehicle).name), func(): return "Speed x%.1f  ·  press V (or the CAR button) to hop in and out" % s.speed_mult(),
		[{"text": "Walk", "do": func(): return s.set_vehicle(""), "enabled": func(): return s.active_vehicle != "", "money": false}], K.BLUE)
	if s.has_fast_travel():
		_note("— FAST TRAVEL —", K.GOLD, 16)
		var h := K.hbox(8)
		for d in C.DISTRICTS:
			var did: String = d
			h.add_child(K.button(C.DISTRICTS[d].name, func(): world.teleport(did); close(); Sfx.play("click")))
		content.add_child(h)
	_note("— DEALERS —", K.GOLD, 16)
	for row in C.VEHICLES:
		var id: String = row.id
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 40)
		swatch.color = row.color
		if id in s.vehicles:
			var acts := []
			if float(row.speed) > 0.0:
				acts.append({"text": "Drive", "do": func(): return s.set_vehicle(id), "enabled": func(): return s.active_vehicle != id, "money": false, "color": K.GREEN})
			acts.append({"text": func(): return "Sell " + _m(s.vehicle_price(id) * C.VEHICLE_RESALE), "do": func(): return s.sell_vehicle(id), "color": K.RED})
			_row(row.name + "  (OWNED)", func(): return "%s  ·  +%d prestige" % [("speed x%.1f" % row.speed) if float(row.speed) > 0 else ("fast travel" if row.kind != "land" else ""), row.prestige], acts, K.GOLD, swatch)
		else:
			_row(row.name, func(): return "%s  ·  +%d prestige" % [("speed x%.1f" % row.speed) if float(row.speed) > 0 else "unlocks fast travel", row.prestige],
				[{"text": func(): return "Buy " + _m(s.vehicle_price(id)), "do": func(): return s.buy_vehicle(id),
					"enabled": func(): return s.cash >= s.vehicle_price(id), "color": K.GOLD}], K.LINE, swatch)


# ------------------------------------------------------------- STOCKS
func _tab_stocks() -> void:
	var s = Game.sim
	_h("Stock Market", "Prices move every in-game hour. Booms lift everything, crashes drag it down — AI and Space swing the hardest.")
	var top := _note("", K.TEXT, 17)
	updaters.append(func(): top.text = "Portfolio %s  ·  Economy: %s  ·  Trading P/L %s" % [_m(s.portfolio_value()), s.economy.phase_info().name, _m(s.stats.stocks)])
	for st in s.market.order:
		var t: String = st
		var spark := W.Sparkline.new()
		spark.custom_minimum_size = Vector2(150, 48)
		updaters.append(func(): spark.set_values(s.market.stocks[t].history))
		_row("%s  ·  %s" % [t, s.market.stocks[t].name], func():
			var ch: float = s.market.day_change_pct(t)
			var own := ""
			if s.shares(t) > 0:
				var avg: float = float(s.holdings[t].cost) / s.shares(t)
				own = "\nYou own %d (%s)  ·  avg %s  ·  P/L %s" % [s.shares(t), _m(s.shares(t) * s.market.price(t)), _m(avg), _m((s.market.price(t) - avg) * s.shares(t))]
			return "%s  ·  $%.2f  ·  today %s%.2f%%%s" % [s.market.stocks[t].sector, s.market.price(t), "+" if ch >= 0 else "", ch, own],
			[{"text": "Buy 10", "do": func(): return s.buy_shares(t, 10), "enabled": func(): return s.cash >= s.market.price(t) * 10, "color": K.GREEN},
			 {"text": "Buy Max", "do": func(): return s.buy_shares(t, s.max_affordable_shares(t)), "enabled": func(): return s.max_affordable_shares(t) > 0, "color": K.GREEN},
			 {"text": "Sell 10", "do": func(): return s.sell_shares(t, 10), "enabled": func(): return s.shares(t) > 0},
			 {"text": "Sell All", "do": func(): return s.sell_shares(t, s.shares(t)), "enabled": func(): return s.shares(t) > 0, "color": K.RED}], K.PURPLE, spark)
	_note("— HEADLINES —", K.GOLD, 16)
	for hl in s.economy.headlines.slice(0, 6):
		_note("Day %d: %s" % [hl.day, hl.text], K.TEXT)


# ------------------------------------------------------------- CRIME
func _tab_crime() -> void:
	var s = Game.sim
	_h("Crime (optional)", "High risk, high reward. Getting caught means a fine, jail time, and at high heat the police seize property. You can win the whole game without ever doing crime.")
	var heat := _note("", K.RED, 17)
	updaters.append(func(): heat.text = "Heat %d/%d  (cools 1 per day)  ·  Crimes %d  ·  Busted %d times  ·  Crime income %s  ·  Fines paid %s" % [s.heat, C.MAX_HEAT, s.crimes_done, s.times_caught, _m(s.stats.crime), _m(s.stats.fines)])
	for id in C.CRIMES:
		var cid: String = id
		var c: Dictionary = C.CRIMES[cid]
		_row(c.name, func():
			var why: String = s.crime_available(cid)
			var at := _near_marker("crime", cid)
			return "%s\nPayout %s–%s  ·  catch chance %d%%%s" % [c.desc, _m(float(c.min) * s.economy.price_index), _m(float(c.max) * s.economy.price_index),
				int(s.crime_chance(cid) * 100.0), ("  ·  " + why) if why != "" else ("" if at else "  ·  Go to the red SHADY marker")],
			[{"text": "Do it", "do": func(): return _crime(cid), "enabled": func(): return s.crime_available(cid) == "" and _near_marker("crime", cid), "color": K.RED},
			 {"text": "Set GPS", "do": func(): return _gps_to_marker("crime", cid), "money": false}], K.RED)


func _near_marker(kind: String, id: String) -> bool:
	if world == null:
		return true
	var m: Dictionary = world.current
	return not m.is_empty() and m.kind == kind and m.id == id


func _crime(id: String) -> Dictionary:
	var r: Dictionary = Game.sim.attempt_crime(id)
	if r.get("caught", false):
		Sfx.play("alarm")
		Game.emit_toast(r.msg, "crime")
		close.call_deferred()
		return {}
	return r


# ------------------------------------------------------------- EMPIRE
func _tab_empire() -> void:
	var s = Game.sim
	_h("Empire", "Your fortune at a glance, endgame mega-projects, and your corporation.")
	var chart := W.Sparkline.new()
	chart.custom_minimum_size = Vector2(0, 110)
	chart.set_values(s.networth_history + [s.networth()])
	content.add_child(chart)
	_note("Net worth %s  ·  Cash %s  ·  Prestige %d  ·  Day %d%s" % [_m(s.networth()), _m(s.cash), s.prestige(), s.day, ("  ·  Billionaire on day %d" % s.billionaire_day) if s.billionaire_day > 0 else ""], K.TEXT, 17)
	_note("Earned  ·  Jobs %s  ·  Business %s  ·  Rent %s  ·  Stocks %s  ·  Crime %s  ·  Paid: salaries %s, fines %s" % [
		_m(s.stats.jobs), _m(s.stats.business), _m(s.stats.rent), _m(s.stats.stocks), _m(s.stats.crime), _m(s.stats.salaries), _m(s.stats.fines)])
	_note("— ENDGAME PROJECTS —  (unlock at $1 Billion)", K.GOLD, 16)
	for id in C.PROJECTS:
		var pid: String = id
		var p: Dictionary = C.PROJECTS[pid]
		_row(p.name, func():
			var why: String = s.project_available(pid)
			return "%s\n%s  ·  +%d prestige%s" % [p.desc, _m(float(p.cost) * s.economy.price_index), p.prestige, ("  ·  " + why) if why != "" else ""],
			[{"text": func(): return "BUILT" if pid in s.projects else "Build", "do": func(): return s.start_project(pid),
				"enabled": func(): return s.project_available(pid) == "" and s.cash >= float(p.cost) * s.economy.price_index, "color": K.GOLD}],
			K.GOLD if pid == focus else K.LINE)
	_note("— CORPORATION —", K.GOLD, 16)
	var h := K.hbox(8)
	var le := LineEdit.new()
	le.placeholder_text = "Corporation name"
	le.text = s.company
	le.max_length = 20
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(le)
	h.add_child(K.button("Form / Join", func(): Net.set_company(le.text); Game.emit_toast("Corporation: " + (le.text if le.text != "" else "none"), "good"), K.GOLD))
	content.add_child(h)
	_note("Online, players who use the same corporation name form a team and appear together on the corporate leaderboard. Hire workers inside each business to grow payroll.")
	_note("— ACHIEVEMENTS (%d) —" % s.achievements.size(), K.GOLD, 16)
	_note(", ".join(s.achievements.map(func(a): return str(a).replace("_", " ").capitalize())) if s.achievements.size() > 0 else "None yet.", K.TEXT)


# ------------------------------------------------------------- LEADERBOARD
func _tab_leaders() -> void:
	var s = Game.sim
	_h("Leaderboard", "Race the city's tycoons (and real players online) to the first billion — then the first trillion.")
	var lb: Array = s.leaderboard(Net.remote_players())
	for i in lb.size():
		var r: Dictionary = lb[i]
		var col := K.GOLD if r.you else (K.BLUE if r.get("online", false) else K.LINE)
		_row("#%d  %s%s" % [i + 1, r.name, "  (online)" if r.get("online", false) else ""], func(): return _m(float(r.networth)), [], col)
	var cb: Array = Net.company_board()
	if cb.size() > 0:
		_note("— CORPORATIONS —", K.GOLD, 16)
		for i in cb.size():
			var c: Dictionary = cb[i]
			_row("#%d  %s" % [i + 1, c.name], func(): return "%s  ·  %d members" % [_m(c.networth), c.members], [])


# ------------------------------------------------------------- ONLINE
func _tab_online() -> void:
	var s = Game.sim
	_h("Online Multiplayer", "Up to 100 players share one economy: the same boom/bust cycle, stock prices and clock. Trade cash, form corporations, chat, and race up the leaderboard.")
	_note("Status: " + Net.status, K.GREEN if Net.is_online() else K.TEXT, 17)
	var nh := K.hbox(8)
	nh.add_child(K.label("Your name", 16, K.MUTED))
	var name_le := LineEdit.new()
	name_le.text = s.player_name
	name_le.max_length = 20
	name_le.custom_minimum_size.x = 220
	name_le.text_submitted.connect(func(t): s.player_name = t.strip_edges() if t.strip_edges() != "" else s.player_name; Game.set_setting("name", s.player_name))
	name_le.focus_exited.connect(func(): if name_le.text.strip_edges() != "": s.player_name = name_le.text.strip_edges(); Game.set_setting("name", s.player_name))
	nh.add_child(name_le)
	content.add_child(nh)
	if not Net.is_online():
		var hh := K.hbox(8)
		var ip := LineEdit.new()
		ip.placeholder_text = "Server IP (e.g. 192.168.1.20)"
		ip.text = "127.0.0.1"
		ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hh.add_child(ip)
		var port := LineEdit.new()
		port.text = str(Net.DEFAULT_PORT)
		port.custom_minimum_size.x = 90
		hh.add_child(port)
		hh.add_child(K.button("Join", func(): Net.join(ip.text, int(port.text)); _rebuild.call_deferred(), K.GREEN))
		hh.add_child(K.button("Host", func(): Net.host(int(port.text)); _rebuild.call_deferred(), K.GOLD))
		content.add_child(hh)
		_note("Host on your PC and friends on the same Wi-Fi join with your local IP. For internet play, forward UDP port 7777 or run the dedicated server (see docs/MULTIPLAYER.md). The browser build can't host or join (browsers block raw UDP).")
	else:
		content.add_child(K.button("Leave server", func(): Net.leave(); _rebuild.call_deferred(), K.RED))
		var ah := K.hbox(8)
		ah.add_child(K.label("Send amount:", 16, K.MUTED))
		for amt in [100.0, 1000.0, 10000.0, 100000.0, 1000000.0]:
			var a: float = amt
			ah.add_child(K.button(_m(a), func(): _send_amount = a; _rebuild.call_deferred(), K.GOLD if a == _send_amount else Color(0, 0, 0, 0)))
		content.add_child(ah)
		_note("— PLAYERS ONLINE (%d) —" % Net.players.size(), K.GOLD, 16)
		for id in Net.players:
			var pid: int = id
			var info: Dictionary = Net.players[pid]
			if pid == Net.my_id():
				continue
			_row(str(info.name), func(): return "Net worth %s%s" % [_m(float(info.networth)), ("  ·  " + str(info.company)) if str(info.company) != "" else ""],
				[{"text": func(): return "Send " + _m(_send_amount), "do": func():
					var err := Net.send_money(pid, _send_amount)
					return {"ok": err == "", "msg": "Sending..." if err == "" else err}, "enabled": func(): return s.cash >= _send_amount}], K.BLUE)
	_note("Voice chat is on the roadmap (Steam Voice / WebRTC). Text chat: press T or the CHAT button.", K.MUTED)


# ------------------------------------------------------------- SHOP
func _tab_shop() -> void:
	var s = Game.sim
	_h("Empire Store", "Cosmetics only — nothing here changes your money or speed. Empire Coins come from milestones, the daily reward and the Season Pass.")
	var coins := _note("", K.GOLD, 20)
	updaters.append(func(): coins.text = "Empire Coins: %d" % s.coins)
	_row("Daily reward", func(): return "+%d coins once per in-game day" % C.DAILY_COINS,
		[{"text": "Claim", "do": func(): return s.claim_daily(), "enabled": func(): return s.last_daily_claim != s.day, "color": K.GOLD}])
	_note("— SEASON 1: GOLD RUSH PASS —  tier %d/%d" % [s.pass_tier(), C.PASS_TIERS], K.GOLD, 16)
	var bar := ProgressBar.new()
	bar.max_value = C.PASS_XP_PER_TIER
	bar.value = s.pass_xp % C.PASS_XP_PER_TIER
	bar.show_percentage = false
	bar.custom_minimum_size.y = 12
	content.add_child(bar)
	if not s.pass_premium:
		_row("Premium track", func(): return "Bigger coin rewards every tier (%d coins)" % C.PASS_PREMIUM_COST,
			[{"text": "Unlock", "do": func(): return s.buy_premium_pass(), "enabled": func(): return s.coins >= C.PASS_PREMIUM_COST, "color": K.PURPLE}])
	for tier in range(1, mini(C.PASS_TIERS, s.pass_tier() + 3) + 1):
		var t: int = tier
		_row("Tier %d" % t, func(): return "Free: %d coins  ·  Premium: %d coins%s" % [s.pass_reward(t, false), s.pass_reward(t, true), "" if t <= s.pass_tier() else "  ·  locked"],
			[{"text": "Free", "do": func(): return s.claim_pass(t, false), "enabled": func(): return t <= s.pass_tier() and not ("%df" % t) in s.pass_claimed},
			 {"text": "Premium", "do": func(): return s.claim_pass(t, true), "enabled": func(): return s.pass_premium and t <= s.pass_tier() and not ("%dp" % t) in s.pass_claimed, "color": K.PURPLE}])
	_shop_section("CHARACTER SKINS", "skin", C.SKINS)
	_shop_section("CAR PAINT", "paint", C.PAINTS)
	_shop_section("MANSION DECOR", "decor", C.DECOR)
	_note("Real-money purchases are not enabled in this build. See docs/MONETIZATION.md for the planned cosmetic-only store.")


func _shop_section(title: String, kind: String, table: Dictionary) -> void:
	var s = Game.sim
	_note("— %s —" % title, K.GOLD, 16)
	for id in table:
		var iid: String = id
		var row: Dictionary = table[iid]
		var sw: Control = null
		if row.has("color") and row.color.a > 0.0:
			var cr := ColorRect.new()
			cr.color = row.color
			cr.custom_minimum_size = Vector2(36, 36)
			sw = cr
		_row(row.name, func():
			var owned: bool = (kind + ":" + iid) in s.owned_cosmetics
			var equipped: bool = (kind == "skin" and s.skin == iid) or (kind == "paint" and s.paint == iid)
			return "EQUIPPED" if equipped else ("Owned" if owned else "%d coins" % int(row.cost)),
			[{"text": func():
				var owned: bool = (kind + ":" + iid) in s.owned_cosmetics
				return ("Owned" if kind == "decor" else "Equip") if owned else "Buy",
				"do": func(): return s.buy_cosmetic(kind, iid), "money": false,
				"enabled": func():
					var owned: bool = (kind + ":" + iid) in s.owned_cosmetics
					if owned:
						return kind != "decor" and not ((kind == "skin" and s.skin == iid) or (kind == "paint" and s.paint == iid))
					return s.coins >= int(row.cost),
				"color": K.PURPLE}], K.LINE, sw)


# ------------------------------------------------------------- SETTINGS
func _tab_settings() -> void:
	var s = Game.sim
	_h("Settings")
	var sp := K.hbox(8)
	sp.add_child(K.label("Game speed", 17))
	for v in [1.0, 2.0, 4.0]:
		var val: float = v
		var b := K.button("x%d" % int(val), func(): Game.set_setting("time_scale", val); _rebuild.call_deferred(), K.GOLD if Game.time_scale == val else Color(0, 0, 0, 0))
		b.disabled = Net.is_online()
		sp.add_child(b)
	sp.add_child(K.label("  (online games always run at x1)", 14, K.MUTED))
	content.add_child(sp)
	for k in [["music", "Music volume"], ["sfx", "Sound effects"]]:
		var key: String = k[0]
		var h := K.hbox(8)
		var l := K.label(k[1], 17)
		l.custom_minimum_size.x = 170
		h.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(Game.settings[key])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(func(v): Game.set_setting(key, v))
		h.add_child(sl)
		content.add_child(h)
	var g := K.hbox(8)
	g.add_child(K.label("Shadows", 17))
	g.add_child(K.button("On" if bool(Game.settings.shadows) else "Off", func():
		Game.set_setting("shadows", not bool(Game.settings.shadows))
		if world:
			world.city.sun.shadow_enabled = bool(Game.settings.shadows)
		_rebuild.call_deferred()))
	g.add_child(K.label("   Touch controls", 17))
	for m in ["auto", "on", "off"]:
		var mode: String = m
		g.add_child(K.button(mode.capitalize(), func(): Game.set_setting("show_touch", mode); _rebuild.call_deferred(), K.GOLD if str(Game.settings.show_touch) == mode else Color(0, 0, 0, 0)))
	content.add_child(g)
	var a := K.hbox(8)
	a.add_child(K.button("Save now", func(): Game.emit_toast("Game saved." if Game.save_game() else "Online: progress is kept by the session.", "good"), K.GREEN))
	a.add_child(K.button("Main menu", func(): Game.save_game(); close(); main_menu_requested.emit()))
	a.add_child(K.button("Delete save..." if not _confirm_reset else "Really delete? Tap again", func():
		if _confirm_reset:
			Game.delete_save()
			Game.emit_toast("Save deleted. Start a new game from the main menu.", "bad")
			_confirm_reset = false
		else:
			_confirm_reset = true
		_rebuild.call_deferred(), K.RED))
	content.add_child(a)
	_note("— CONTROLS —", K.GOLD, 16)
	_note("Keyboard: WASD move · Shift run · Space jump · E interact · Tab/M phone · V vehicle · T chat · drag mouse to look · wheel zoom\nGamepad: left stick move · right stick camera · A interact · Y phone · X vehicle · B back · RB run\nTouch: left joystick · drag the right side to look · pinch to zoom · ACT / PHONE / CAR buttons", K.TEXT)
	_note("Money Empire v%s  ·  Godot 4.3  ·  %s" % [C.VERSION, "Steam API detected" if Engine.has_singleton("Steam") else "Steam API not loaded (see docs/STEAM.md)"])
