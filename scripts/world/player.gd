extends CharacterBody3D
## The player: third-person on foot, arcade driving in owned vehicles, and helicopter flight.
## Works with keyboard+mouse, gamepad, and the on-screen touch joystick.

const C = preload("res://scripts/core/catalog.gd")

const WALK := 7.5
const SPRINT := 1.45
const GRAVITY := 28.0
const JUMP := 9.0
const HELI_ALT := 42.0

var yaw := PI                 # camera yaw (PI = looking north)
var pitch := -0.32
var zoom := 1.0
var move_input := Vector2.ZERO   # from the touch joystick
var touch_sprint := false
var frozen := false              # phone open / cut-scenes

var cam_pivot: Node3D
var spring: SpringArm3D
var cam: Camera3D
var visual: Node3D
var body_mi: MeshInstance3D
var head_mi: MeshInstance3D
var body_mat := StandardMaterial3D.new()
var vehicle_root: Node3D
var carry_box: MeshInstance3D
var rotor: Node3D

var _facing := 0.0
var _shown_vehicle := "?"
var _shown_skin := "?"
var _shown_paint := "?"


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	floor_snap_length = 0.4
	visual = Node3D.new()
	add_child(visual)
	body_mi = MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.42
	bm.height = 1.45
	body_mi.mesh = bm
	body_mi.position.y = 0.75
	body_mat.roughness = 0.5
	body_mi.material_override = body_mat
	visual.add_child(body_mi)
	head_mi = MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.3
	hm.height = 0.6
	head_mi.mesh = hm
	head_mi.position.y = 1.68
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#e0ac69")
	head_mi.material_override = skin
	visual.add_child(head_mi)
	var shades := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.5, 0.1, 0.12)
	shades.mesh = sb
	shades.position = Vector3(0, 1.72, 0.26)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("#111111")
	sm.metallic = 0.8
	shades.material_override = sm
	head_mi.add_child(shades)
	shades.position = Vector3(0, 0.04, 0.26)
	vehicle_root = Node3D.new()
	visual.add_child(vehicle_root)
	carry_box = MeshInstance3D.new()
	var cbm := BoxMesh.new()
	cbm.size = Vector3(0.8, 0.6, 0.8)
	carry_box.mesh = cbm
	var cbmat := StandardMaterial3D.new()
	cbmat.albedo_color = Color("#c8a165")
	carry_box.material_override = cbmat
	carry_box.position = Vector3(0, 2.4, 0)
	carry_box.visible = false
	visual.add_child(carry_box)
	# camera rig
	cam_pivot = Node3D.new()
	cam_pivot.top_level = true
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 7.0
	spring.margin = 0.4
	spring.add_excluded_object(get_rid())
	cam_pivot.add_child(spring)
	cam = Camera3D.new()
	cam.far = 1200.0
	cam.fov = 70.0
	spring.add_child(cam)
	cam.current = true


func set_carrying(on: bool) -> void:
	carry_box.visible = on


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and (e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
		yaw -= e.relative.x * 0.006
		pitch = clampf(pitch - e.relative.y * 0.004, -1.25, 0.25)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 0.1, 0.4, 2.5)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 0.1, 0.4, 2.5)
	elif e is InputEventMagnifyGesture:
		zoom = clampf(zoom / e.factor, 0.4, 2.5)


func _physics_process(delta: float) -> void:
	var sim = Game.sim
	var v_id: String = sim.active_vehicle
	var heli := v_id == "heli"
	var on_foot := v_id == ""
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + move_input
	if input.length() > 1.0:
		input = input.normalized()
	if frozen or sim.in_jail() or not Game.running:
		input = Vector2.ZERO
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	var sprinting := (Input.is_action_pressed("sprint") or touch_sprint) and on_foot
	var spd: float = WALK * sim.speed_mult() * (SPRINT if sprinting else 1.0)
	var accel := 12.0 if on_foot else (2.6 if heli else 3.2)
	var target := dir * spd
	velocity.x = lerpf(velocity.x, target.x, minf(1.0, accel * delta))
	velocity.z = lerpf(velocity.z, target.z, minf(1.0, accel * delta))
	if heli:
		velocity.y = (HELI_ALT - global_position.y) * 1.5
	else:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		elif on_foot and Input.is_action_just_pressed("jump") and not frozen:
			velocity.y = JUMP
	move_and_slide()
	if global_position.y < -20.0:
		global_position = Vector3(0, 2, 0)
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 0.6:
		_facing = lerp_angle(_facing, atan2(hv.x, hv.y), minf(1.0, 10.0 * delta))
	visual.rotation.y = _facing
	# gamepad right stick camera
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.15:
		yaw -= rx * 2.6 * delta
	if absf(ry) > 0.15:
		pitch = clampf(pitch - ry * 1.8 * delta, -1.25, 0.25)
	# camera follows, pulling back at speed
	var base_len := 7.0 if on_foot else (24.0 if heli else 11.0)
	spring.spring_length = lerpf(spring.spring_length, base_len * zoom, minf(1.0, 3.0 * delta))
	cam_pivot.global_position = cam_pivot.global_position.lerp(global_position + Vector3(0, 1.7, 0), minf(1.0, 14.0 * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	cam.fov = lerpf(cam.fov, 70.0 + clampf(hv.length() - 12.0, 0.0, 25.0) * 0.6, minf(1.0, 2.0 * delta))
	if rotor:
		rotor.rotation.y += 25.0 * delta
	_refresh_visuals(sim)
	Net.local.pos = global_position
	Net.local.yaw = _facing
	Net.local.vehicle = v_id


func snap_camera() -> void:
	cam_pivot.global_position = global_position + Vector3(0, 1.7, 0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)


func _refresh_visuals(sim) -> void:
	if sim.skin != _shown_skin:
		_shown_skin = sim.skin
		body_mat.albedo_color = C.SKINS.get(sim.skin, C.SKINS.default).color
		body_mat.metallic = 0.7 if sim.skin == "gold" else 0.0
		body_mat.emission_enabled = sim.skin == "neon"
		body_mat.emission = Color("#39ff88") * 0.5
	if sim.active_vehicle == _shown_vehicle and sim.paint == _shown_paint:
		return
	_shown_vehicle = sim.active_vehicle
	_shown_paint = sim.paint
	for ch in vehicle_root.get_children():
		ch.queue_free()
	rotor = null
	var id: String = sim.active_vehicle
	body_mi.visible = true
	head_mi.visible = true
	body_mi.position.y = 0.75
	head_mi.position.y = 1.68
	if id == "":
		return
	var row: Dictionary = sim.vehicle_row(id)
	var col: Color = row.color
	var paint: Color = C.PAINTS.get(sim.paint, C.PAINTS.factory).color
	if paint.a > 0.0:
		col = paint
	build_vehicle_mesh(vehicle_root, id, col)
	if id == "bike" or id == "scooter":
		body_mi.position.y = 1.15
		head_mi.position.y = 2.05
	else:
		body_mi.visible = false
		head_mi.visible = id == "heli"
		head_mi.position.y = 1.4
	if id == "heli":
		rotor = vehicle_root.get_node_or_null("Rotor")


## Shared by the local player and remote avatars.
static func build_vehicle_mesh(root: Node3D, id: String, col: Color) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.5
	m.roughness = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#15191f")
	dark.metallic = 0.4
	dark.roughness = 0.25
	var add := func(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = pos
		mi.material_override = mat
		root.add_child(mi)
		return mi
	var wheel := func(pos: Vector3, r: float) -> void:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = r * 0.7
		mi.mesh = cm
		mi.rotation.z = PI * 0.5
		mi.position = pos
		mi.material_override = dark
		root.add_child(mi)
	match id:
		"bike", "scooter":
			add.call(Vector3(0.12, 0.12, 1.5), Vector3(0, 0.6, 0), m)
			add.call(Vector3(0.1, 0.8, 0.1), Vector3(0, 0.9, 0.6), m)
			add.call(Vector3(0.6, 0.08, 0.08), Vector3(0, 1.3, 0.6), dark)
			wheel.call(Vector3(0, 0.35, 0.75), 0.35)
			wheel.call(Vector3(0, 0.35, -0.75), 0.35)
		"heli":
			add.call(Vector3(2.4, 2.2, 4.0), Vector3(0, 1.4, 0), m)
			add.call(Vector3(1.9, 1.2, 1.4), Vector3(0, 1.8, 1.6), dark)
			add.call(Vector3(0.4, 0.5, 4.5), Vector3(0, 1.8, -4.0), m)
			add.call(Vector3(0.1, 1.4, 1.0), Vector3(0, 2.4, -6.0), m)
			add.call(Vector3(0.15, 0.15, 3.2), Vector3(-0.9, 0.2, 0), dark)
			add.call(Vector3(0.15, 0.15, 3.2), Vector3(0.9, 0.2, 0), dark)
			var r := Node3D.new()
			r.name = "Rotor"
			r.position.y = 2.75
			root.add_child(r)
			var blade := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(9.5, 0.06, 0.4)
			blade.mesh = bb
			blade.material_override = dark
			r.add_child(blade)
			var blade2 := blade.duplicate()
			blade2.rotation.y = PI * 0.5
			r.add_child(blade2)
		_:
			var low := id == "sports" or id == "hyper"
			var h := 0.7 if low else 1.0
			var length := 4.6 if id != "suv" else 4.9
			add.call(Vector3(2.1, h, length), Vector3(0, 0.45 + h * 0.5, 0), m)
			add.call(Vector3(1.85, 0.65, length * 0.45), Vector3(0, 0.45 + h + 0.32, -0.25), dark)
			if id == "hyper":
				add.call(Vector3(2.2, 0.08, 0.6), Vector3(0, 1.55, -2.1), m)   # spoiler
				add.call(Vector3(0.12, 0.4, 0.12), Vector3(-0.7, 1.3, -2.1), dark)
				add.call(Vector3(0.12, 0.4, 0.12), Vector3(0.7, 1.3, -2.1), dark)
			var hl := StandardMaterial3D.new()
			hl.emission_enabled = true
			hl.emission = Color(1, 0.95, 0.8)
			hl.emission_energy_multiplier = 2.0
			add.call(Vector3(0.5, 0.15, 0.05), Vector3(-0.65, 0.45 + h * 0.6, length * 0.5), hl)
			add.call(Vector3(0.5, 0.15, 0.05), Vector3(0.65, 0.45 + h * 0.6, length * 0.5), hl)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					wheel.call(Vector3(sx * 1.0, 0.42, sz * length * 0.32), 0.42)
