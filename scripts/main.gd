extends Node
## Entry point: wires the world, HUD, phone and title screen together.
## Also runs the headless dedicated server (--server) and the screenshot tour (--tour=DIR).

const World = preload("res://scripts/world/world.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const Title = preload("res://scripts/ui/title.gd")
const K = preload("res://scripts/ui/ui_kit.gd")
const C = preload("res://scripts/core/catalog.gd")

var world
var hud
var phone
var title
var menu_cam: Camera3D
var chat_layer: CanvasLayer
var chat_edit: LineEdit
var _orbit := 0.0


func _ready() -> void:
	if Net.dedicated:
		_run_dedicated()
		return
	world = World.new()
	world.name = "World"
	add_child(world)
	hud = Hud.new()
	hud.world = world
	add_child(hud)
	phone = Phone.new()
	phone.world = world
	phone.hud = hud
	add_child(phone)
	world.prompt_changed.connect(hud.set_prompt)
	world.open_tab.connect(func(t, f): phone.open(t, f))
	hud.phone_requested.connect(func(t): phone.open(t))
	hud.chat_requested.connect(open_chat)
	phone.main_menu_requested.connect(show_title)
	_build_chat()
	menu_cam = Camera3D.new()
	menu_cam.far = 1500.0
	add_child(menu_cam)
	title = Title.new()
	add_child(title)
	title.continue_pressed.connect(_on_continue)
	title.new_game_pressed.connect(_on_new)
	title.online_pressed.connect(_on_online)
	show_title()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			_tour(a.substr(7))
		elif a.begins_with("--quickshot="):
			_quickshot(a.substr(12))
		elif a.begins_with("--autojoin="):
			_autojoin(a.substr(11))


func _process(delta: float) -> void:
	if title and title.visible:
		_orbit += delta * 0.04
		menu_cam.global_position = Vector3(cos(_orbit) * 230.0, 95.0, sin(_orbit) * 230.0)
		menu_cam.look_at(Vector3(0, 25, 0))
		Game.sim.advance(delta * 20.0)   # time-lapse sky on the title screen
	if chat_layer and chat_layer.visible == false and Game.running and Input.is_action_just_pressed("chat") and not phone.is_open():
		open_chat()


func show_title() -> void:
	Game.running = false
	world.cancel_job(true)
	hud.visible = false
	title.visible = true
	title.refresh()
	world.player.frozen = true
	menu_cam.current = true


func start_game() -> void:
	title.visible = false
	hud.visible = true
	world.player.frozen = false
	world.player.cam.current = true
	world.teleport("downtown")
	Game.start()
	hud.refresh()


func _on_continue() -> void:
	var err: String = Game.load_game()
	if err != "":
		title.show_error(err)
		return
	start_game()
	Game.emit_toast("Welcome back, %s. Day %d." % [Game.sim.player_name, Game.sim.day], "info")


func _on_new(player_name: String) -> void:
	Game.new_game(player_name)
	start_game()


func _on_online(player_name: String) -> void:
	if Game.has_save():
		Game.load_game()
		Game.sim.player_name = player_name.strip_edges() if player_name.strip_edges() != "" else Game.sim.player_name
	else:
		Game.new_game(player_name)
	start_game()
	phone.open("online")


# ------------------------------------------------------------- chat input
func _build_chat() -> void:
	chat_layer = CanvasLayer.new()
	chat_layer.layer = 12
	chat_layer.visible = false
	add_child(chat_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = K.make_theme()
	chat_layer.add_child(root)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Say something...  (Enter to send, Esc to close)"
	chat_edit.max_length = 160
	root.add_child(chat_edit)
	chat_edit.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	chat_edit.custom_minimum_size = Vector2(620, 48)
	chat_edit.position += Vector2(-310, -170)
	chat_edit.text_submitted.connect(func(t):
		Net.send_chat(t)
		close_chat())
	chat_edit.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			close_chat())


func open_chat() -> void:
	chat_layer.visible = true
	chat_edit.text = ""
	chat_edit.grab_focus()
	world.player.frozen = true


func close_chat() -> void:
	chat_layer.visible = false
	chat_edit.release_focus()
	world.player.frozen = phone.is_open()


# ------------------------------------------------------------- dedicated server
func _run_dedicated() -> void:
	print("Money Empire dedicated server v%s" % C.VERSION)
	Game.new_game("Dedicated Server")
	Game.running = true
	Game.time_scale = 1.0
	print(Net.host(Net.port))
	var t := Timer.new()
	t.wait_time = 60.0
	t.autostart = true
	t.timeout.connect(func(): print("[server] day %d %s · %s economy · %d players" % [Game.sim.day, Game.sim.clock_text(), Game.sim.economy.phase, Net.players.size()]))
	add_child(t)


func _quickshot(path: String) -> void:
	Game.new_game("Jaineil")
	start_game()
	Game.running = false
	Game.sim.minute = 10.0 * 60.0
	_aim(world.player, Vector3(-14, 1, -3), Vector3(-30, 2, -9), -0.22)
	await _shot(path.get_base_dir(), path.get_file(), 30)
	get_tree().quit()


# ------------------------------------------------------------- network smoke test client
## godot --headless --path . -- --autojoin=127.0.0.1:7777   (used by CI / local testing)
func _autojoin(addr: String) -> void:
	var parts := addr.split(":")
	Game.new_game("Bot%d" % (randi() % 1000))
	start_game()
	Net.join(parts[0], int(parts[1]) if parts.size() > 1 else Net.DEFAULT_PORT)
	for i in 300:
		await get_tree().process_frame
		if Net.is_online() and Net.players.size() > 0:
			break
	print("[autojoin] online=%s players=%d phase=%s" % [Net.is_online(), Net.players.size(), Game.sim.economy.phase])
	Net.send_chat("hello from " + Game.sim.player_name)
	world.player.global_position = Vector3(42, 1, 6)
	await get_tree().create_timer(4.0).timeout
	for id in Net.players:
		if id != Net.my_id():
			Net.send_money(id, 10.0)
	await get_tree().create_timer(2.0).timeout
	print("[autojoin] players=%d chat_log=%d cash=%.0f remote_avatars=%d" % [Net.players.size(), Net.chat_log.size(), Game.sim.cash, world.remote.size()])
	print("AUTOJOIN OK" if Net.is_online() and Net.chat_log.size() > 0 else "AUTOJOIN FAIL")
	get_tree().quit()


# ------------------------------------------------------------- screenshot tour (marketing/docs)
func _aim(p, from: Vector3, to: Vector3, pitch := -0.2) -> void:
	p.global_position = from
	p.velocity = Vector3.ZERO
	var d := to - from
	p.yaw = atan2(-d.x, -d.z)
	p._facing = atan2(d.x, d.z)
	p.visual.rotation.y = p._facing
	p.pitch = pitch
	p.snap_camera()


func _shot(dir: String, file: String, frames := 25) -> void:
	for i in frames:
		if i == frames - 2:
			hud.refresh()
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(file))
	print("[tour] saved ", file)


func _demo_rich() -> void:
	var s = Game.sim
	s.player_name = "Jaineil"
	s.cash = 2_450_000_000.0
	for id in ["taco", "suds", "restaurant", "gas", "hotel", "factory", "shipping", "mall", "resort", "bank"]:
		s.businesses[id] = {"level": 3 + (id.length() % 3), "workers": 2 + id.length() % 4}
	for id in ["studio", "duplex", "family", "townhouse", "penthouse", "waterfront", "mansion", "villa"]:
		s.properties.append({"id": id, "reno": id.length() % 2 == 0, "rented": id != "mansion", "features": [], "decor": []})
	s.home = 6
	s.properties[6].features = ["pool", "helipad", "trophy", "security", "garage"]
	s.vehicles = ["bike", "sedan", "sports", "hyper", "heli", "yacht", "jet"]
	s.active_vehicle = "hyper"
	s.paint = "factory"
	s.holdings = {"NEUR": {"shares": 120000, "cost": 9_000_000.0}, "ORBT": {"shares": 400000, "cost": 6_000_000.0}, "VOLT": {"shares": 50000, "cost": 2_400_000.0}}
	s.jobs_done = 214
	s.coins = 1840
	s.pass_xp = 1350
	s.skin = "gold"
	s.owned_cosmetics.append("skin:gold")
	s.company = "Rana Holdings"
	s.projects = ["skyscraper", "rocket", "statue"]
	s.billionaire_day = 47
	s.day = 63
	s.achievements = ["first_paycheck", "owner", "landlord", "investor", "chain", "mansion", "hyper", "billionaire", "project_skyscraper"]
	var nw := 100.0
	s.networth_history = []
	for d in 63:
		nw *= 1.0 + 0.32 * exp(-float(d) / 40.0)
		s.networth_history.append(nw)
	for i in 80:
		s.market.tick_hour(s.economy)
	s.economy.set_phase("boom", 63)
	s.stats = {"jobs": 48_210.0, "business": 1_840_000_000.0, "rent": 92_000_000.0, "stocks": 310_000_000.0, "crime": 0.0, "fines": 0.0, "salaries": 61_000_000.0}


func _tour(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Game.settings.music = 0.0
	Game.sim.minute = 17.2 * 60.0
	await _shot(dir, "01_title.png", 60)
	# --- early game: homeless with $100, first job
	Game.new_game("Jaineil")
	start_game()
	for c in hud.toast_box.get_children():
		c.queue_free()
	var s = Game.sim
	Game.running = false
	s.minute = 10.0 * 60.0
	var p = world.player
	_aim(p, Vector3(-14, 1, -3), Vector3(-30, 2, -9), -0.22)
	world.start_job("package", Vector3(-30, 0, -9))
	await _shot(dir, "02_first_job.png", 40)
	world.cancel_job(true)
	# --- downtown skyline on foot
	s.minute = 16.5 * 60.0
	_aim(p, Vector3(0, 1, 140), Vector3(0, 30, 0), 0.05)
	await _shot(dir, "03_downtown.png")
	# --- rich mid/late game
	_demo_rich()
	Game.mark_changed()
	s.minute = 18.3 * 60.0
	_aim(p, Vector3(-120, 1, 2), Vector3(0, 1, 2), -0.18)
	await _shot(dir, "04_hypercar.png", 40)
	# mansion
	s.minute = 11.0 * 60.0
	p.zoom = 1.6
	_aim(p, Vector3(30, 1, -232), Vector3(30, 4, -270), -0.3)
	world.city.refresh_owned(s)
	await _shot(dir, "05_mansion.png", 40)
	p.zoom = 1.0
	# night skyline from the helicopter over the harbor
	s.active_vehicle = "heli"
	s.minute = 21.5 * 60.0
	_aim(p, Vector3(40, 42, 225), Vector3(0, 40, 0), -0.12)
	await _shot(dir, "06_night_heli.png", 60)
	# endgame mega-projects (drone camera)
	s.minute = 9.5 * 60.0
	s.active_vehicle = "sports"
	_aim(p, Vector3(150, 1, 0), Vector3(150, 1, -40))
	menu_cam.current = true
	menu_cam.global_position = Vector3(250, 150, 140)
	menu_cam.look_at(Vector3(40, 50, -110))
	await _shot(dir, "07_endgame.png", 40)
	world.player.cam.current = true
	# harbor
	s.minute = 7.4 * 60.0
	_aim(p, Vector3(-120, 1, 240), Vector3(0, 1, 330), -0.15)
	await _shot(dir, "08_harbor.png", 40)
	# phone screens
	s.minute = 13.0 * 60.0
	_aim(p, Vector3(0, 1, 6), Vector3(0, 1, -40))
	for t in [["business", "09_phone_business.png"], ["stocks", "10_phone_stocks.png"], ["realestate", "11_phone_realestate.png"],
			["empire", "12_phone_empire.png"], ["leaders", "13_phone_leaderboard.png"], ["shop", "14_phone_shop.png"], ["crime", "15_phone_crime.png"]]:
		phone.open(t[0])
		await _shot(dir, t[1], 20)
	phone.close()
	print("[tour] done")
	get_tree().quit()
