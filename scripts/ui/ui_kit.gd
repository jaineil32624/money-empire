extends RefCounted
## Shared look & feel: theme, colors, and small widget builders. All UI is built in code.

const BG := Color("#0b111c")
const PANEL := Color("#131c2e")
const PANEL2 := Color("#1a2540")
const LINE := Color("#2a3a5c")
const GOLD := Color("#f5c542")
const GREEN := Color("#2ecc71")
const RED := Color("#ff5c5c")
const BLUE := Color("#4f8cff")
const PURPLE := Color("#b388ff")
const TEXT := Color("#e8edf5")
const MUTED := Color("#8a96ab")

const KIND_COLORS := {"money": GOLD, "good": GREEN, "bad": RED, "info": BLUE, "news": PURPLE, "crime": RED, "goal": GOLD}


static func flat(bg: Color, radius := 12, border := Color(0, 0, 0, 0), bw := 0, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	s.anti_aliasing = true
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", BG)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.6))
	t.set_stylebox("normal", "Button", flat(Color("#22304f"), 10, LINE, 1, 14))
	t.set_stylebox("hover", "Button", flat(Color("#2d3f68"), 10, BLUE, 1, 14))
	t.set_stylebox("pressed", "Button", flat(GOLD, 10, GOLD, 1, 14))
	t.set_stylebox("disabled", "Button", flat(Color("#161f33"), 10, Color("#1f2a44"), 1, 14))
	t.set_stylebox("focus", "Button", flat(Color(0, 0, 0, 0), 10, GOLD, 2, 14))
	t.set_stylebox("panel", "PanelContainer", flat(Color(PANEL, 0.94), 16, LINE, 1, 14))
	t.set_stylebox("panel", "Panel", flat(Color(PANEL, 0.94), 16, LINE, 1, 14))
	t.set_stylebox("normal", "LineEdit", flat(Color("#0e1626"), 8, LINE, 1, 10))
	t.set_stylebox("focus", "LineEdit", flat(Color("#0e1626"), 8, GOLD, 1, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("background", "ProgressBar", flat(Color("#0e1626"), 6, LINE, 1, 0))
	t.set_stylebox("fill", "ProgressBar", flat(GOLD, 6, GOLD, 0, 0))
	t.set_color("font_color", "ProgressBar", BG)
	t.set_stylebox("slider", "HSlider", flat(Color("#0e1626"), 4, LINE, 1, 3))
	t.set_stylebox("grabber_area", "HSlider", flat(GOLD, 4, GOLD, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(GOLD, 4, GOLD, 0, 3))
	t.set_stylebox("panel", "TooltipPanel", flat(PANEL2, 8, LINE, 1, 8))
	return t


static func label(text: String, size := 18, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_constant_override("outline_size", 1)
		l.add_theme_color_override("font_outline_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, cb: Callable, color := Color(0, 0, 0, 0), min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	if color.a > 0.0:
		b.add_theme_stylebox_override("normal", flat(color.darkened(0.35), 10, color, 1, 14))
		b.add_theme_stylebox_override("hover", flat(color.darkened(0.15), 10, color.lightened(0.3), 1, 14))
	b.pressed.connect(cb)
	return b


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func card(color := PANEL2, radius := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(color, radius, LINE, 1, 12))
	return p


static func money(v: float) -> String:
	return "$" + preload("res://scripts/core/empire_sim.gd").fmt_money(v)
