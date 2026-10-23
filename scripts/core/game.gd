extends Node
## Game — autoload that owns the running EmpireSim, the clock, saving and settings.
## UI and world talk to the simulation only through here.

const C = preload("res://scripts/core/catalog.gd")
const Sim = preload("res://scripts/core/empire_sim.gd")
const SaveUtil = preload("res://scripts/core/save_util.gd")

const SAVE_PATH := "user://money_empire_save.json"
const SETTINGS_PATH := "user://settings.cfg"

signal changed                         # throttled "something about money/state changed"
signal toast(text: String, kind: String)
signal hour_passed
signal day_passed(day: int)
signal sim_replaced

var sim: Sim
var running := false                   # false while on the title screen
var time_scale := 1.0
var settings := {"music": 0.55, "sfx": 0.9, "shadows": true, "time_scale": 1.0, "show_touch": "auto", "name": "Player"}
var _changed_t := 0.0
var _autosave_t := 0.0
var _pending_change := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_load_settings()
	_set_sim(Sim.new())


func _set_sim(s: Sim) -> void:
	sim = s
	sim.notify.connect(func(t: String, k: String): emit_toast(t, k))
	sim.hour_passed.connect(func(): hour_passed.emit(); _pending_change = true)
	sim.day_passed.connect(_on_day)
	sim_replaced.emit()
	_pending_change = true


func _on_day(d: int) -> void:
	day_passed.emit(d)
	if running and not Net.is_client():
		save_game()


func new_game(player_name: String) -> void:
	var s := Sim.new()
	s.player_name = player_name.strip_edges() if player_name.strip_edges() != "" else "Player"
	settings.name = s.player_name
	_save_settings()
	_set_sim(s)
	emit_toast("Day 1. You have $100, no home and no car. Visit a JOB marker to start earning.", "info")


func start() -> void:
	running = true
	time_scale = float(settings.time_scale)


func _process(delta: float) -> void:
	if not running or get_tree().paused:
		return
	var scale := time_scale
	if Net.is_online():
		scale = 1.0
	sim.advance(delta * 1440.0 / C.DAY_SECONDS * scale)
	_changed_t += delta
	if _changed_t >= 0.25 or _pending_change:
		_changed_t = 0.0
		_pending_change = false
		changed.emit()
	_autosave_t += delta
	if _autosave_t > 45.0:
		_autosave_t = 0.0
		save_game()


func mark_changed() -> void:
	_pending_change = true


## Run a sim action result through the feedback layer (toast + sound).
func act(result: Dictionary, money_sound := true) -> Dictionary:
	var ok: bool = result.get("ok", false)
	emit_toast(str(result.get("msg", "")), "good" if ok else "bad")
	if ok:
		Sfx.play("coin" if money_sound else "click")
	else:
		Sfx.play("error")
	_pending_change = true
	return result


func emit_toast(text: String, kind: String = "info") -> void:
	if text == "":
		return
	toast.emit(text, kind)
	match kind:
		"goal": Sfx.play("levelup")
		"news": Sfx.play("news")


# ------------------------------------------------------------- save / load
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	if Net.is_client():
		return false  # online characters are saved per-session; see docs/MULTIPLAYER.md
	var data := JSON.stringify(sim.to_dict())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"data": data, "sig": SaveUtil.sign_data(data)}))
	return true


## Returns "" on success or an error message.
func load_game() -> String:
	if not has_save():
		return "No save found."
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var wrapper = JSON.parse_string(txt)
	if typeof(wrapper) != TYPE_DICTIONARY or not wrapper.has("data"):
		return "Save file is corrupted."
	var data: String = wrapper.data
	if SaveUtil.sign_data(data) != str(wrapper.get("sig", "")):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_PATH + ".tampered"))
		return "Save file was modified outside the game and was rejected."
	var d = JSON.parse_string(data)
	if typeof(d) != TYPE_DICTIONARY:
		return "Save file is corrupted."
	var s := Sim.new()
	s.from_dict(d)
	_set_sim(s)
	settings.name = s.player_name
	return ""


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ------------------------------------------------------------- settings
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cf.get_value("settings", k, settings[k])


func _save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func set_setting(k: String, v) -> void:
	settings[k] = v
	if k == "time_scale":
		time_scale = float(v)
	if k == "music" or k == "sfx":
		Sfx.apply_volumes()
	_save_settings()
	_pending_change = true


func show_touch_controls() -> bool:
	var mode := str(settings.show_touch)
	if mode == "on":
		return true
	if mode == "off":
		return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


# ------------------------------------------------------------- input map
func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_SHOULDER], [])
	_bind("interact", [KEY_E, KEY_ENTER], [JOY_BUTTON_A], [])
	_bind("phone", [KEY_TAB, KEY_M], [JOY_BUTTON_Y], [])
	_bind("vehicle", [KEY_V], [JOY_BUTTON_X], [])
	_bind("chat", [KEY_T], [JOY_BUTTON_BACK], [])
	_bind("cancel", [KEY_ESCAPE], [JOY_BUTTON_B], [])
	_bind("jump", [KEY_SPACE], [JOY_BUTTON_LEFT_SHOULDER], [])


func _bind(action: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)
