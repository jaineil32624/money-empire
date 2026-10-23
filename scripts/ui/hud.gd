extends CanvasLayer
## In-game HUD: wallet, goal progress, clock & economy, minimap, job tracker,
## toasts, interaction prompt, touch controls, chat feed and the stock ticker.

const K = preload("res://scripts/ui/ui_kit.gd")
const W = preload("res://scripts/ui/widgets.gd")
const C = preload("res://scripts/core/catalog.gd")

signal phone_requested(tab: String)
signal chat_requested

var world
var root: Control
var cash_lbl: Label
var nw_lbl: Label
var who_lbl: Label
var goal_bar: ProgressBar
var goal_lbl: Label
var heat_lbl: Label
var clock_lbl: Label
var phase_lbl: Label
var phase_box: PanelContainer
var minimap
var job_panel: PanelContainer
var job_title: Label
var job_obj: Label
var job_timer: Label
var job_dist: Label
var arrow
var prompt_panel: PanelContainer
var prompt_lbl: Label
var toast_box: VBoxContainer
var chat_box: VBoxContainer
var ticker: Label
var ticker_clip: Control
var act_btn: Button
var veh_btn: Button
var joystick
var jail_panel: PanelContainer
var jail_lbl: Label
var banner: PanelContainer
var touch_root: Control
var _ticker_x := 0.0
var gps_target = null      # Vector3 set from the phone ("Set GPS")
var gps_label := ""


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = K.make_theme()
	add_child(root)
	_build_wallet()
	_build_clock()
	_build_minimap()
	_build_job()
	_build_prompt()
	_build_toasts()
	_build_buttons()
	_build_chat()
	_build_ticker()
	_build_jail()
	Game.toast.connect(_on_toast)
	Game.changed.connect(refresh)
	Net.chat.connect(_on_chat)
	refresh()


func _anchor(c: Control, preset: int, offset: Vector2) -> void:
	# Explicit anchors + offsets (robust at any resolution / before layout has run).
	root.add_child(c)
	var m := c.get_combined_minimum_size()
	var ax := 0.0
	var ay := 0.0
	match preset:
		Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT: ax = 1.0
		Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER: ax = 0.5
	match preset:
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM: ay = 1.0
		Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER: ay = 0.5
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = offset.x - m.x * ax
	c.offset_right = c.offset_left + m.x
	c.offset_top = offset.y - m.y * ay
	c.offset_bottom = c.offset_top + m.y
	c.grow_horizontal = [Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN][int(ax * 2.0)]
	c.grow_vertical = [Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN][int(ay * 2.0)]


func _pin(c: Control, top_left_from_bottom_left: Vector2, sz: Vector2) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 0.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = top_left_from_bottom_left.x
	c.offset_top = top_left_from_bottom_left.y
	c.offset_right = c.offset_left + sz.x
	c.offset_bottom = c.offset_top + sz.y


# ------------------------------------------------------------- builders
func _build_wallet() -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(300, 0)
	var v := K.vbox(2)
	p.add_child(v)
	who_lbl = K.label("", 14, K.MUTED)
	v.add_child(who_lbl)
	cash_lbl = K.label("$100", 34, K.GOLD, true)
	v.add_child(cash_lbl)
	nw_lbl = K.label("", 16, K.TEXT)
	v.add_child(nw_lbl)
	goal_bar = ProgressBar.new()
	goal_bar.max_value = 1.0
	goal_bar.step = 0.0001
	goal_bar.show_percentage = false
	goal_bar.custom_minimum_size = Vector2(0, 10)
	v.add_child(goal_bar)
	goal_lbl = K.label("", 13, K.MUTED)
	v.add_child(goal_lbl)
	heat_lbl = K.label("", 15, K.RED, true)
	v.add_child(heat_lbl)
	_anchor(p, Control.PRESET_TOP_LEFT, Vector2(12, 12))


func _build_clock() -> void:
	var h := K.hbox(8)
	var cp := PanelContainer.new()
	clock_lbl = K.label("DAY 1 · 08:00", 20, K.TEXT, true)
	cp.add_child(clock_lbl)
	h.add_child(cp)
	phase_box = PanelContainer.new()
	phase_lbl = K.label("STABLE", 16, K.BG, true)
	phase_box.add_child(phase_lbl)
	h.add_child(phase_box)
	_anchor(h, Control.PRESET_CENTER_TOP, Vector2(0, 12))


func _build_minimap() -> void:
	minimap = W.Minimap.new()
	minimap.world = world
	_anchor(minimap, Control.PRESET_TOP_RIGHT, Vector2(-12, 12))


func _build_job() -> void:
	job_panel = PanelContainer.new()
	job_panel.custom_minimum_size = Vector2(320, 0)
	var h := K.hbox(10)
	job_panel.add_child(h)
	arrow = W.Arrow.new()
	h.add_child(arrow)
	var v := K.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	job_title = K.label("", 18, K.GREEN, true)
	v.add_child(job_title)
	job_obj = K.label("", 15)
	job_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(job_obj)
	var row := K.hbox(10)
	job_dist = K.label("", 14, K.MUTED)
	job_timer = K.label("", 14, K.GOLD, true)
	row.add_child(job_dist)
	row.add_child(job_timer)
	v.add_child(row)
	job_panel.visible = false
	_anchor(job_panel, Control.PRESET_CENTER_LEFT, Vector2(12, -40))


func _build_prompt() -> void:
	prompt_panel = PanelContainer.new()
	prompt_panel.add_theme_stylebox_override("panel", K.flat(Color(0.05, 0.08, 0.13, 0.9), 22, K.GOLD, 2, 18))
	prompt_lbl = K.label("", 20, K.TEXT, true)
	prompt_panel.add_child(prompt_lbl)
	prompt_panel.visible = false
	_anchor(prompt_panel, Control.PRESET_CENTER_BOTTOM, Vector2(0, -110))


func _build_toasts() -> void:
	toast_box = K.vbox(6)
	toast_box.custom_minimum_size = Vector2(520, 0)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(toast_box, Control.PRESET_CENTER_TOP, Vector2(0, 64))


func _build_buttons() -> void:
	var col := K.vbox(10)
	var top := K.hbox(10)
	veh_btn = K.button("CAR", func(): _toggle_vehicle(), K.BLUE, 92)
	veh_btn.custom_minimum_size.y = 56
	top.add_child(veh_btn)
	var chat := K.button("CHAT", func(): chat_requested.emit(), K.PURPLE, 92)
	chat.custom_minimum_size.y = 56
	top.add_child(chat)
	col.add_child(top)
	var bottom := K.hbox(10)
	act_btn = K.button("ACT  [E]", func(): world.interact(), K.GREEN, 92)
	act_btn.custom_minimum_size = Vector2(120, 72)
	bottom.add_child(act_btn)
	var phone := K.button("PHONE\n[Tab]", func(): phone_requested.emit(""), K.GOLD, 92)
	phone.custom_minimum_size = Vector2(120, 72)
	bottom.add_child(phone)
	col.add_child(bottom)
	_anchor(col, Control.PRESET_BOTTOM_RIGHT, Vector2(-16, -44))
	# touch-only: joystick + sprint/jump
	touch_root = Control.new()
	touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(touch_root)
	joystick = W.Joystick.new()
	touch_root.add_child(joystick)
	_pin(joystick, Vector2(24, -224), Vector2(180, 180))
	joystick.moved.connect(func(v: Vector2): world.player.move_input = v)
	var sprint := K.button("RUN", func(): pass, K.BLUE, 80)
	sprint.custom_minimum_size.y = 56
	sprint.button_down.connect(func(): world.player.touch_sprint = true)
	sprint.button_up.connect(func(): world.player.touch_sprint = false)
	touch_root.add_child(sprint)
	_pin(sprint, Vector2(220, -116), Vector2(80, 56))


func _build_chat() -> void:
	chat_box = K.vbox(2)
	chat_box.custom_minimum_size = Vector2(420, 0)
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(chat_box, Control.PRESET_BOTTOM_LEFT, Vector2(16, -250))


func _build_ticker() -> void:
	ticker_clip = Control.new()
	ticker_clip.clip_contents = true
	ticker_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ticker_clip)
	ticker_clip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ticker_clip.offset_top = -28
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.09, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker_clip.add_child(bg)
	ticker = K.label("", 15, K.TEXT)
	ticker.position = Vector2(0, 3)
	ticker_clip.add_child(ticker)


func _build_jail() -> void:
	jail_panel = PanelContainer.new()
	jail_panel.add_theme_stylebox_override("panel", K.flat(Color(0.35, 0.03, 0.05, 0.92), 18, K.RED, 2, 20))
	var v := K.vbox(4)
	jail_panel.add_child(v)
	v.add_child(K.label("BUSTED — IN JAIL", 30, Color.WHITE, true))
	jail_lbl = K.label("", 18, Color("#ffd0d0"))
	v.add_child(jail_lbl)
	jail_panel.visible = false
	_anchor(jail_panel, Control.PRESET_CENTER, Vector2.ZERO)


# ------------------------------------------------------------- updates
func refresh() -> void:
	var s = Game.sim
	cash_lbl.text = K.money(s.cash)
	var nw: float = s.networth()
	nw_lbl.text = "Net worth  " + K.money(nw)
	var online := Net.remote_players()
	var lb: Array = s.leaderboard(online)
	var rank := 1
	for i in lb.size():
		if lb[i].you:
			rank = i + 1
	who_lbl.text = "%s  ·  Rank #%d of %d%s" % [s.player_name.to_upper(), rank, lb.size(), ("  ·  " + s.company) if s.company != "" else ""]
	goal_bar.value = s.goal_progress()
	if nw >= C.GOAL:
		goal_lbl.text = "BILLIONAIRE!  Next: $1 Trillion (%.2f%%)" % (nw / C.STRETCH_GOAL * 100.0)
	else:
		goal_lbl.text = "Road to $1 Billion  ·  %d%%" % int(s.goal_progress() * 100.0)
	heat_lbl.visible = s.heat > 0
	heat_lbl.text = "WANTED  " + "#".repeat(s.heat) + "-".repeat(C.MAX_HEAT - s.heat)
	var ph: Dictionary = s.economy.phase_info()
	phase_lbl.text = ph.name
	phase_box.add_theme_stylebox_override("panel", K.flat(ph.color, 12, ph.color, 0, 12))
	var speed := "" if Net.is_online() or Game.time_scale <= 1.0 else "  x%d" % int(Game.time_scale)
	clock_lbl.text = "DAY %d  ·  %s%s" % [s.day, s.clock_text(), speed]
	jail_panel.visible = s.in_jail()
	if s.in_jail():
		var m := int(s.jail_minutes_left())
		jail_lbl.text = "Released in %dh %02dm (game time). Your businesses keep earning." % [m / 60, m % 60]
	if world and world.player:
		var v_id: String = s.active_vehicle
		veh_btn.text = "WALK" if v_id != "" else ("DRIVE" if s.best_vehicle() != "" else "CAR")
		veh_btn.disabled = v_id == "" and s.best_vehicle() == ""
	touch_root.visible = Game.show_touch_controls()
	_update_ticker_text()


func _toggle_vehicle() -> void:
	var s = Game.sim
	if s.active_vehicle != "":
		Game.act(s.set_vehicle(""), false)
	elif s.best_vehicle() != "":
		Game.act(s.set_vehicle(s.best_vehicle()), false)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("vehicle") and Game.running and not world.player.frozen:
		_toggle_vehicle()
	_update_job()
	var w: float = ticker.size.x
	_ticker_x -= 60.0 * delta
	if _ticker_x < -w * 0.5:
		_ticker_x = 0.0
	ticker.position.x = _ticker_x + 8.0


func set_prompt(text: String) -> void:
	prompt_panel.visible = text != ""
	var touch := Game.show_touch_controls()
	prompt_lbl.text = ("Tap ACT  ·  " if touch else "[E]  ") + text
	act_btn.modulate = Color(1.3, 1.3, 1.3) if text != "" else Color(1, 1, 1, 0.6)


func _update_job() -> void:
	if world == null:
		return
	var target = world.job_target()
	var label := ""
	if target == null and gps_target != null:
		target = gps_target
		label = gps_label
	job_panel.visible = target != null
	if target == null:
		return
	if world.job.is_empty():
		job_title.text = "GPS"
		job_title.add_theme_color_override("font_color", K.BLUE)
		job_obj.text = label
		job_timer.text = ""
		var dd: float = world.player.global_position.distance_to(target)
		if dd < 6.0:
			gps_target = null
	else:
		job_title.text = world.job_title()
		job_title.add_theme_color_override("font_color", K.GREEN)
		job_obj.text = world.job_objective()
		job_timer.text = ("%ds left" % int(ceil(world.job.time_left))) if world.job.limit > 0.0 else ""
	var p: Vector3 = world.player.global_position
	var rel: Vector3 = target - p
	rel.y = 0
	job_dist.text = "%d m" % int(rel.length())
	var yaw: float = world.player.yaw
	var f := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
	var r := Vector3(1, 0, 0).rotated(Vector3.UP, yaw)
	arrow.angle = atan2(rel.normalized().dot(r), rel.normalized().dot(f))
	arrow.queue_redraw()


func _update_ticker_text() -> void:
	var s = Game.sim
	var parts: Array = []
	for t in s.market.order:
		var ch: float = s.market.day_change_pct(t)
		parts.append("%s %s %s%.1f%%" % [t, K.money(s.market.price(t)).replace("$", "$"), "+" if ch >= 0 else "", ch])
	if s.economy.headlines.size() > 0:
		parts.append("NEWS: " + str(s.economy.headlines[0].text))
	var one := "     |     ".join(parts)
	ticker.text = one + "          " + one + "          "


func _on_toast(text: String, kind: String) -> void:
	var p := PanelContainer.new()
	var col: Color = K.KIND_COLORS.get(kind, K.BLUE)
	p.add_theme_stylebox_override("panel", K.flat(Color(0.05, 0.08, 0.13, 0.92), 12, col, 2, 14))
	var l := K.label(text, 17, col.lightened(0.35) if kind != "money" else K.GOLD, kind == "goal")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 500
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(p)
	while toast_box.get_child_count() > 4:
		toast_box.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(4.5 if kind != "goal" else 7.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)
	if kind == "goal" and text.contains("BILLIONAIRE"):
		_show_banner("BILLIONAIRE!", "Day %d. You built a $1,000,000,000 empire.\nEndgame projects are open in Phone > Empire. Next: the first TRILLIONAIRE." % Game.sim.day)


func _show_banner(title: String, body: String) -> void:
	if banner and is_instance_valid(banner):
		banner.queue_free()
	banner = PanelContainer.new()
	banner.add_theme_stylebox_override("panel", K.flat(Color(0.08, 0.06, 0.0, 0.95), 24, K.GOLD, 3, 30))
	var v := K.vbox(10)
	banner.add_child(v)
	var t := K.label(title, 54, K.GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b := K.label(body, 20)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	v.add_child(K.button("KEEP BUILDING", func(): banner.queue_free(), K.GOLD))
	_anchor(banner, Control.PRESET_CENTER, Vector2.ZERO)


func _on_chat(from: String, text: String, kind: String) -> void:
	var col := K.MUTED if kind == "system" else (K.GOLD if kind == "self" else K.TEXT)
	var l := K.label("%s: %s" % [from, text], 15, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 420
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	chat_box.add_child(l)
	while chat_box.get_child_count() > 6:
		chat_box.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(12.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)
