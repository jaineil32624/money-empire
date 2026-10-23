extends RefCounted
## Custom-drawn widgets: sparkline charts, the minimap, the touch joystick and the GPS arrow.

const K = preload("res://scripts/ui/ui_kit.gd")


class Sparkline extends Control:
	var values: Array = []
	var line_color := K.GREEN
	var fill := true
	var show_ends := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(v: Array) -> void:
		values = v
		if values.size() >= 2:
			line_color = K.GREEN if float(values[-1]) >= float(values[0]) else K.RED
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.25))
		if values.size() < 2:
			return
		var lo := INF
		var hi := -INF
		for v in values:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		if hi - lo < 0.0001:
			hi = lo + 1.0
		var pts := PackedVector2Array()
		for i in values.size():
			var x := r.size.x * float(i) / float(values.size() - 1)
			var y := r.size.y - 3.0 - (r.size.y - 6.0) * (float(values[i]) - lo) / (hi - lo)
			pts.append(Vector2(x, y))
		if fill:
			var poly := pts.duplicate()
			poly.append(Vector2(r.size.x, r.size.y))
			poly.append(Vector2(0, r.size.y))
			draw_colored_polygon(poly, Color(line_color, 0.18))
		draw_polyline(pts, line_color, 2.0, true)


class Minimap extends Control:
	var world  # world.gd
	var scale_px := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(190, 190)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func w2m(p: Vector3) -> Vector2:
		return size * 0.5 + Vector2(p.x, p.z) * (size.x / 780.0)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.07, 0.11, 0.85))
		if world == null:
			return
		var C = preload("res://scripts/core/catalog.gd")
		var s := size.x / 780.0
		var zones := {
			"downtown": Rect2(-150, -150, 300, 300), "suburbs": Rect2(-360, -150, 210, 300),
			"industrial": Rect2(150, -150, 210, 300), "luxury": Rect2(-360, -360, 720, 210),
			"harbor": Rect2(-360, 150, 720, 150),
		}
		for z in zones:
			var rr: Rect2 = zones[z]
			draw_rect(Rect2(size * 0.5 + rr.position * s, rr.size * s), Color(C.DISTRICTS[z].color, 0.22))
		draw_rect(Rect2(size * 0.5 + Vector2(-390, 300) * s, Vector2(780, 90) * s), Color("#1f6fa8"))
		for k in 13:
			var p := -360.0 + 60.0 * k
			draw_line(w2m(Vector3(p, 0, -360)), w2m(Vector3(p, 0, 300)), Color(1, 1, 1, 0.12), 1.0)
			if p <= 300.0:
				draw_line(w2m(Vector3(-360, 0, p)), w2m(Vector3(360, 0, p)), Color(1, 1, 1, 0.12), 1.0)
		for m in world.city.markers:
			var col: Color = world.city.MARKER_COLORS.get(m.kind, Color.WHITE)
			draw_circle(w2m(m.pos), 3.0, col)
		var pulse := 3.0 + 2.0 * absf(sin(Time.get_ticks_msec() / 250.0))
		for t in world.job.get("targets", []):
			draw_circle(w2m(t.pos), pulse, Color("#ffe14d"))
		for id in world.remote:
			draw_circle(w2m(world.remote[id].node.global_position), 3.5, Color.WHITE)
		var pl: Node3D = world.player
		var c := w2m(pl.global_position)
		var a: float = pl.visual.rotation.y
		var f := Vector2(sin(a), cos(a))
		var r := Vector2(f.y, -f.x)
		draw_colored_polygon(PackedVector2Array([c + f * 8.0, c - f * 5.0 + r * 5.0, c - f * 5.0 - r * 5.0]), K.GOLD)
		draw_rect(Rect2(Vector2.ZERO, size), K.LINE, false, 2.0)


class Arrow extends Control:
	var angle := 0.0
	var color := Color("#ffe14d")

	func _init() -> void:
		custom_minimum_size = Vector2(44, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var f := Vector2(sin(angle), -cos(angle))
		var r := Vector2(-f.y, f.x)
		draw_circle(c, 20.0, Color(0, 0, 0, 0.4))
		draw_colored_polygon(PackedVector2Array([c + f * 16.0, c - f * 9.0 + r * 11.0, c - f * 3.0, c - f * 9.0 - r * 11.0]), color)


class Joystick extends Control:
	signal moved(v: Vector2)
	var knob := Vector2.ZERO
	var active_index := -1
	var radius := 70.0

	func _init() -> void:
		custom_minimum_size = Vector2(180, 180)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch:
			if e.pressed and active_index < 0:
				active_index = e.index
				_update(e.position)
			elif not e.pressed and e.index == active_index:
				active_index = -1
				knob = Vector2.ZERO
				moved.emit(Vector2.ZERO)
				queue_redraw()
			accept_event()
		elif e is InputEventScreenDrag and e.index == active_index:
			_update(e.position)
			accept_event()
		elif e is InputEventMouseButton or e is InputEventMouseMotion:
			accept_event()   # swallow emulated mouse so the camera doesn't spin

	func _update(p: Vector2) -> void:
		var v := p - size * 0.5
		if v.length() > radius:
			v = v.normalized() * radius
		knob = v
		moved.emit(v / radius)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, radius + 12.0, Color(1, 1, 1, 0.08))
		draw_arc(c, radius + 12.0, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
		draw_circle(c + knob, 34.0, Color(0.96, 0.77, 0.26, 0.75))
