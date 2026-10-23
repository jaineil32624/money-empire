extends CanvasLayer
## Title screen shown over a slowly orbiting live city.

const K = preload("res://scripts/ui/ui_kit.gd")
const C = preload("res://scripts/core/catalog.gd")

signal continue_pressed
signal new_game_pressed(player_name: String)
signal online_pressed(player_name: String)

var root: Control
var name_edit: LineEdit
var cont_btn: Button
var msg: Label


func _ready() -> void:
	layer = 20
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = K.make_theme()
	add_child(root)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.03, 0.05, 0.09, 0.96))
	grad.set_color(1, Color(0.03, 0.05, 0.09, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 760
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var v := K.vbox(12)
	root.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE)
	v.position.x = 70
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.add_child(K.label("START BROKE.  DIE RICH.", 18, K.GREEN, true))
	var logo := K.label("MONEY\nEMPIRE", 92, K.GOLD, true)
	logo.add_theme_constant_override("line_spacing", -22)
	logo.add_theme_constant_override("outline_size", 10)
	logo.add_theme_color_override("font_outline_color", Color("#3d2b00"))
	v.add_child(logo)
	var tag := K.label("You're homeless with $100. Work jobs, buy businesses, flip houses,\ntrade stocks, survive crashes — and race everyone to $1 BILLION.", 19, K.TEXT)
	v.add_child(tag)
	var nh := K.hbox(10)
	nh.add_child(K.label("Your name", 17, K.MUTED))
	name_edit = LineEdit.new()
	name_edit.text = str(Game.settings.get("name", "Player"))
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(260, 44)
	nh.add_child(name_edit)
	v.add_child(nh)
	cont_btn = K.button("CONTINUE", func(): continue_pressed.emit(), K.GREEN, 360)
	cont_btn.custom_minimum_size.y = 58
	cont_btn.add_theme_font_size_override("font_size", 24)
	v.add_child(cont_btn)
	var ng := K.button("NEW GAME", func(): new_game_pressed.emit(name_edit.text), K.GOLD, 360)
	ng.custom_minimum_size.y = 58
	ng.add_theme_font_size_override("font_size", 24)
	v.add_child(ng)
	var on := K.button("PLAY ONLINE", func(): online_pressed.emit(name_edit.text), K.BLUE, 360)
	on.custom_minimum_size.y = 50
	v.add_child(on)
	if not (OS.has_feature("web") or OS.has_feature("mobile")):
		var q := K.button("QUIT", func(): get_tree().quit(), Color(0, 0, 0, 0), 360)
		v.add_child(q)
	msg = K.label("", 16, K.RED)
	v.add_child(msg)
	var foot := K.label("v%s  ·  Built with Godot 4  ·  Single-player + online up to 100 players" % C.VERSION, 14, K.MUTED)
	root.add_child(foot)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	foot.position += Vector2(70, -24)
	refresh()


func refresh() -> void:
	cont_btn.visible = Game.has_save()
	msg.text = ""


func show_error(t: String) -> void:
	msg.text = t
