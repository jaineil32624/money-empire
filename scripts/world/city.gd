extends Node3D
## Procedural city: five districts on a 60 m road grid, built from batched primitives
## (MultiMesh) so it runs on phones and in the browser. No imported art required.
##
## Layout (top view, -Z is north):
##            LUXURY DISTRICT (mansions, airport)
##   SUBURBS      DOWNTOWN        INDUSTRIAL
##              HARBOR  ~~~~ water ~~~~

const C = preload("res://scripts/core/catalog.gd")

const GRID := 60.0
const HALF := 360.0
const ROAD_W := 10.0
const WATER_Z := 300.0
const LOT := 17.0          # buildings stay within +-LOT of a cell centre, leaving a sidewalk ring

var rng := RandomNumberGenerator.new()
var markers: Array = []    # {node, kind, id, label, pos, radius}
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var window_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D
var static_body: StaticBody3D

var cars: Array = []       # {node, axis, line, dir, speed, pos}
var peds_mm: MultiMesh
var peds: Array = []       # {a: Vector3, b: Vector3, t, speed}

var _batches := {}
var _endgame := {}         # project id -> Node3D
var _mansion_root: Node3D
var _mansion_sig := ""


# ------------------------------------------------------------- batching helper
class Batch:
	var mesh: Mesh
	var mat: Material
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []

	func add(t: Transform3D, c: Color) -> void:
		xf.append(t)
		col.append(c)

	func build(parent: Node3D, node_name: String, shadows := true) -> MultiMeshInstance3D:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
			mm.set_instance_color(i, col[i])
		var mi := MultiMeshInstance3D.new()
		mi.name = node_name
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		return mi


func _batch(key: String, mesh: Mesh, mat: Material = null) -> Batch:
	if not _batches.has(key):
		var b := Batch.new()
		b.mesh = mesh
		if mat == null:
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.roughness = 0.85
			mat = m
		b.mat = mat
		_batches[key] = b
	return _batches[key]


func _box(pos: Vector3, size: Vector3, color: Color, solid := true, key := "box") -> void:
	_batch(key, BoxMesh.new()).add(Transform3D(Basis.from_scale(size), pos + Vector3(0, size.y * 0.5, 0)), color)
	if solid:
		_solid(pos + Vector3(0, size.y * 0.5, 0), size)


func _solid(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = center
	static_body.add_child(cs)


static func district_of(x: float, z: float) -> String:
	if z > 150.0:
		return "harbor"
	if z < -150.0:
		return "luxury"
	if x < -150.0:
		return "suburbs"
	if x > 150.0:
		return "industrial"
	return "downtown"


static func cell_center(i: int, j: int) -> Vector3:
	return Vector3(-330.0 + GRID * i, 0.0, -330.0 + GRID * j)


static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(round((x + 330.0) / GRID)), int(round((z + 330.0) / GRID)))


# ------------------------------------------------------------- build
func build(seed_value: int = 2026) -> void:
	rng.seed = seed_value
	static_body = StaticBody3D.new()
	static_body.name = "Collision"
	add_child(static_body)
	_environment()
	_ground()
	_roads()
	var reserved := _reserved_cells()
	for i in 12:
		for j in 12:
			var c := cell_center(i, j)
			if c.z > WATER_Z:
				continue
			var key := Vector2i(int(c.x), int(c.z))
			if reserved.has(key):
				_landmark(reserved[key], c)
			else:
				_populate(c)
	_water()
	_lamps()
	_bounds()
	for k in _batches:
		var shadows: bool = not (k in ["window", "pad", "lamp", "line", "lampbulb"])
		_batches[k].build(self, "MM_" + k, shadows)
	_place_markers()
	_traffic()
	_pedestrians()
	_build_endgame()


func _environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#2f6fd6")
	sky_mat.sky_horizon_color = Color("#a8d4ff")
	sky_mat.ground_bottom_color = Color("#2f5a2e")
	sky_mat.ground_horizon_color = Color("#a8d4ff")
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.72, 0.72)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_energy = 0.55
	env.tonemap_exposure = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#b8d6f5")
	env.fog_density = 0.0008
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = bool(Game.settings.get("shadows", true))
	sun.directional_shadow_max_distance = 140.0
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-50, -35, 0)
	add_child(sun)
	window_mat = StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.12, 0.17, 0.26)
	window_mat.metallic = 0.6
	window_mat.roughness = 0.15
	window_mat.emission_enabled = true
	window_mat.emission = Color(1.0, 0.82, 0.5)
	window_mat.emission_energy_multiplier = 0.0
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1, 0.95, 0.8)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.85, 0.55)
	lamp_mat.emission_energy_multiplier = 0.2


## Called every frame with the game minute (0..1440).
func set_time_of_day(minute: float) -> void:
	var t := minute / 1440.0
	var elev := sin((t - 0.25) * TAU)          # 1 at noon, -1 at midnight
	sun.rotation_degrees = Vector3(-10.0 - 70.0 * maxf(0.0, elev), t * 360.0 - 90.0, 0)
	var day := clampf(elev * 2.0 + 0.5, 0.0, 1.0)
	sun.light_energy = lerpf(0.05, 0.62, day)
	sun.light_color = Color(1.0, 0.75, 0.55).lerp(Color(1, 0.97, 0.92), clampf(elev * 3.0, 0.0, 1.0))
	sky_mat.sky_top_color = Color("#070b1d").lerp(Color("#2f6fd6"), day)
	var dusk := clampf(1.0 - absf(elev) * 4.0, 0.0, 1.0)
	sky_mat.sky_horizon_color = Color("#141c3a").lerp(Color("#a8d4ff"), day).lerp(Color("#ff9a5c"), dusk * 0.6)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	env.ambient_light_energy = lerpf(0.28, 0.42, day)
	env.ambient_light_color = Color(0.2, 0.24, 0.4).lerp(Color(0.74, 0.73, 0.71), day)
	env.fog_light_color = sky_mat.sky_horizon_color
	var night := 1.0 - day
	window_mat.emission_energy_multiplier = night * 1.6
	lamp_mat.emission_energy_multiplier = 0.2 + night * 3.0


func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#3f6e3c")
	gm.roughness = 1.0
	g.material_override = gm
	add_child(g)
	_solid(Vector3(0, -1, 0), Vector3(900, 2, 900))
	# district-tinted lots (sidewalk + yard)
	var pad := BoxMesh.new()
	for i in 12:
		for j in 12:
			var c := cell_center(i, j)
			if c.z > WATER_Z:
				continue
			var col: Color
			match district_of(c.x, c.z):
				"downtown": col = Color("#767d88")
				"suburbs": col = Color("#4c8a43")
				"industrial": col = Color("#766c5e")
				"luxury": col = Color("#b3a78f")
				_: col = Color("#6f7780")
			_batch("pad", pad).add(Transform3D(Basis.from_scale(Vector3(GRID - ROAD_W, 0.12, GRID - ROAD_W)), c + Vector3(0, 0.06, 0)), col)
			# curb ring
			var ring := Color("#a9aeb6")
			for s in [-1.0, 1.0]:
				_batch("pad", pad).add(Transform3D(Basis.from_scale(Vector3(GRID - ROAD_W, 0.2, 1.2)), c + Vector3(0, 0.1, s * (GRID - ROAD_W) * 0.5)), ring)
				_batch("pad", pad).add(Transform3D(Basis.from_scale(Vector3(1.2, 0.2, GRID - ROAD_W)), c + Vector3(s * (GRID - ROAD_W) * 0.5, 0.1, 0)), ring)


func _roads() -> void:
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("#2b2e35")
	asphalt.roughness = 0.95
	for k in 13:
		var p := -HALF + GRID * k
		for axis in 2:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			if axis == 0:   # runs along X at z = p
				if p > WATER_Z:
					continue
				bm.size = Vector3(HALF * 2.0 + ROAD_W, 0.08, ROAD_W)
				mi.position = Vector3(0, 0.04, p)
			else:           # runs along Z at x = p
				bm.size = Vector3(ROAD_W, 0.08, HALF + WATER_Z + ROAD_W)
				mi.position = Vector3(p, 0.04, (WATER_Z - HALF) * 0.5)
			mi.mesh = bm
			mi.material_override = asphalt
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	# dashed centre lines
	var dash := BoxMesh.new()
	var yellow := Color("#f5c542")
	for k in 13:
		var p := -HALF + GRID * k
		var d := -HALF
		while d < HALF:
			if fmod(absf(d - p), GRID) > 7.0:
				if p <= WATER_Z:
					_batch("line", dash).add(Transform3D(Basis.from_scale(Vector3(3.0, 0.02, 0.25)), Vector3(d, 0.09, p)), yellow)
				if d <= WATER_Z:
					_batch("line", dash).add(Transform3D(Basis.from_scale(Vector3(0.25, 0.02, 3.0)), Vector3(p, 0.09, d)), yellow)
			d += 6.0


func _water() -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 160)
	w.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("#1f6fa8")
	wm.metallic = 0.3
	wm.roughness = 0.08
	w.material_override = wm
	w.position = Vector3(0, -0.3, WATER_Z + 80.0 + 5.0)
	add_child(w)
	# quay wall
	_box(Vector3(0, -1.0, WATER_Z + 5.5), Vector3(900, 1.4, 1.5), Color("#6d737c"))
	# cargo ships
	for k in 4:
		var x := -300.0 + k * 170.0 + rng.randf_range(-20, 20)
		var z := WATER_Z + 40.0 + rng.randf_range(0, 50)
		var hull := Color("#b33a3a") if k % 2 == 0 else Color("#24476b")
		_box(Vector3(x, -0.5, z), Vector3(70, 7, 16), hull, false)
		_box(Vector3(x + 28, 6.5, z), Vector3(10, 10, 14), Color("#eeeeee"), false)
		for cx in 6:
			for cy in rng.randi_range(1, 3):
				_box(Vector3(x - 28 + cx * 8.5, 6.5 + cy * 2.6, z + rng.randf_range(-3, 3)), Vector3(8, 2.6, 6), _container_color(), false)


func _container_color() -> Color:
	return [Color("#c0392b"), Color("#2980b9"), Color("#27ae60"), Color("#f39c12"), Color("#8e44ad"), Color("#16a085"), Color("#d35400")][rng.randi() % 7]


func _lamps() -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.12
	pole.bottom_radius = 0.16
	pole.height = 1.0
	var bulb := SphereMesh.new()
	bulb.radius = 0.5
	bulb.height = 1.0
	for i in 13:
		for j in 12:
			var x := -HALF + GRID * i + 6.5
			var z := -HALF + GRID * j + 6.5
			if z > WATER_Z:
				continue
			_batch("lamp", pole).add(Transform3D(Basis.from_scale(Vector3(1, 7, 1)), Vector3(x, 3.5, z)), Color("#3a3f47"))
			_batch("lampbulb", bulb, lamp_mat).add(Transform3D(Basis.from_scale(Vector3(0.8, 0.8, 0.8)), Vector3(x, 7.2, z)), Color.WHITE)


func _bounds() -> void:
	_solid(Vector3(-HALF - 12, 10, 0), Vector3(2, 40, 900))
	_solid(Vector3(HALF + 12, 10, 0), Vector3(2, 40, 900))
	_solid(Vector3(0, 10, -HALF - 12), Vector3(900, 40, 2))
	_solid(Vector3(0, 10, WATER_Z + 6.5), Vector3(900, 40, 1))


# ------------------------------------------------------------- districts
func _populate(c: Vector3) -> void:
	match district_of(c.x, c.z):
		"downtown": _downtown(c)
		"suburbs": _suburbs(c)
		"industrial": _industrial(c)
		"luxury": _luxury(c)
		"harbor": _harbor(c)


func _tower(pos: Vector3, w: float, d: float, h: float, col: Color) -> void:
	_box(pos, Vector3(w, h, d), col)
	# glass bands that light up at night
	var bm := BoxMesh.new()
	var y := 4.0
	while y < h - 2.5:
		_batch("window", bm, window_mat).add(Transform3D(Basis.from_scale(Vector3(w * 0.86, 1.4, 0.15)), pos + Vector3(0, y, d * 0.5 + 0.05)), Color.WHITE)
		_batch("window", bm, window_mat).add(Transform3D(Basis.from_scale(Vector3(w * 0.86, 1.4, 0.15)), pos + Vector3(0, y, -d * 0.5 - 0.05)), Color.WHITE)
		_batch("window", bm, window_mat).add(Transform3D(Basis.from_scale(Vector3(0.15, 1.4, d * 0.86)), pos + Vector3(w * 0.5 + 0.05, y, 0)), Color.WHITE)
		_batch("window", bm, window_mat).add(Transform3D(Basis.from_scale(Vector3(0.15, 1.4, d * 0.86)), pos + Vector3(-w * 0.5 - 0.05, y, 0)), Color.WHITE)
		y += 3.6
	# roof cap
	_box(pos + Vector3(0, h, 0), Vector3(w * 0.6, 2.5, d * 0.6), col.darkened(0.25), false)


func _downtown(c: Vector3) -> void:
	var centrality := 1.0 - clampf(Vector2(c.x, c.z).length() / 170.0, 0.0, 1.0)
	var palette := [Color("#5d7a99"), Color("#7f8fa6"), Color("#3e5c76"), Color("#8aa1b1"), Color("#4b6584"), Color("#a5b1c2"), Color("#2d4059")]
	if rng.randf() < 0.45:
		var h := rng.randf_range(35, 60) + centrality * 50.0
		_tower(c, 26, 26, h, palette[rng.randi() % palette.size()])
	else:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var h := rng.randf_range(16, 40) + centrality * rng.randf_range(10, 45)
				_tower(c + Vector3(sx * 8.5, 0, sz * 8.5), 14, 14, h, palette[rng.randi() % palette.size()])


func _tree(pos: Vector3, palm := false) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = 1.0
	var leaf := SphereMesh.new()
	leaf.radius = 0.5
	leaf.height = 1.0
	if palm:
		_batch("trunk", trunk).add(Transform3D(Basis.from_scale(Vector3(1, 7, 1)), pos + Vector3(0, 3.5, 0)), Color("#8a6a45"))
		_batch("leaf", leaf).add(Transform3D(Basis.from_scale(Vector3(4.5, 1.4, 4.5)), pos + Vector3(0, 7.2, 0)), Color("#3c9a3c"))
	else:
		_batch("trunk", trunk).add(Transform3D(Basis.from_scale(Vector3(1, 2.5, 1)), pos + Vector3(0, 1.25, 0)), Color("#6b4f33"))
		var s := rng.randf_range(3.2, 4.6)
		_batch("leaf", leaf).add(Transform3D(Basis.from_scale(Vector3(s, s * 1.1, s)), pos + Vector3(0, 2.5 + s * 0.45, 0)), Color("#2f7d32").lerp(Color("#6aa84f"), rng.randf()))
	_solid(pos + Vector3(0, 2, 0), Vector3(0.7, 4, 0.7))


func _house(pos: Vector3, rot: float) -> void:
	var cols := [Color("#f6e3c5"), Color("#d6eadf"), Color("#f2c6c2"), Color("#c9daf8"), Color("#fff2cc"), Color("#e6d0f0")]
	var roofs := [Color("#8e3b2f"), Color("#4a4e69"), Color("#5c3d2e"), Color("#2f4858")]
	var h := rng.randf_range(4.5, 6.5)
	_box(pos, Vector3(10, h, 9), cols[rng.randi() % cols.size()])
	var prism := PrismMesh.new()
	var b := Basis(Vector3.UP, rot).scaled(Vector3(11, 3.2, 10))
	_batch("roof", prism).add(Transform3D(b, pos + Vector3(0, h + 1.6, 0)), roofs[rng.randi() % roofs.size()])
	_box(pos + Vector3(0, 0, 4.6), Vector3(1.6, 2.6, 0.2), Color("#5b3a29"), false)


func _suburbs(c: Vector3) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_house(c + Vector3(sx * 8.5, 0, sz * 8.5), 0.0)
	_tree(c + Vector3(0, 0, 0))
	if rng.randf() < 0.5:
		_tree(c + Vector3(rng.randf_range(-3, 3), 0, 15))


func _industrial(c: Vector3) -> void:
	var cols := [Color("#8d6e63"), Color("#9e9e9e"), Color("#a1887f"), Color("#78909c"), Color("#b0a089")]
	if rng.randf() < 0.55:
		var h := rng.randf_range(10, 16)
		_box(c, Vector3(30, h, 24), cols[rng.randi() % cols.size()])
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.6
		cyl.height = 1.0
		for k in rng.randi_range(1, 3):
			var p := c + Vector3(-10 + k * 8, 0, -6)
			var ch := rng.randf_range(22, 34)
			_batch("chimney", cyl).add(Transform3D(Basis.from_scale(Vector3(1, ch, 1)), p + Vector3(0, ch * 0.5, 0)), Color("#6d4c41"))
			_batch("chimney", cyl).add(Transform3D(Basis.from_scale(Vector3(1.05, 1.5, 1.05)), p + Vector3(0, ch - 2.5, 0)), Color("#e53935"))
	else:
		_box(c + Vector3(0, 0, -8), Vector3(32, 9, 14), cols[rng.randi() % cols.size()])
		for k in 6:
			_box(c + Vector3(-12 + k * 4.6, 0, 9 + rng.randf_range(-1, 1)), Vector3(4, 2.6 * rng.randi_range(1, 2), 7), _container_color())


func _luxury(c: Vector3) -> void:
	var i := cell_of(c.x, c.z)
	# private airport runway along the north-east
	if c.x > 150.0 and c.z < -240.0:
		_box(c + Vector3(0, 0.05, 0), Vector3(GRID, 0.08, 22), Color("#30343b"), false, "pad")
		for k in 5:
			_box(c + Vector3(-24 + k * 12, 0.12, 0), Vector3(6, 0.04, 0.8), Color("#f5f5f5"), false, "pad")
		if i.x == 10:
			_jet(c + Vector3(0, 0, 0))
		return
	var white := [Color("#f7f3ea"), Color("#efe6d2"), Color("#ffffff"), Color("#e9e4f0")]
	var col: Color = white[rng.randi() % white.size()]
	_box(c + Vector3(0, 0, -3), Vector3(24, 8, 16), col)
	_box(c + Vector3(-3, 8, -5), Vector3(14, 6, 10), col.darkened(0.04))
	_box(c + Vector3(0, 0, 9), Vector3(12, 0.4, 6), Color("#36c5f0"), false)  # pool
	for k in 4:
		_tree(c + Vector3(-14 + k * 9.3, 0, 15), true)
	# a supercar in the driveway
	_car_static(c + Vector3(11, 0, 9), [Color("#e8423f"), Color("#f5c542"), Color("#111111"), Color("#2ec4c4")][rng.randi() % 4])


func _harbor(c: Vector3) -> void:
	if c.z > 240.0 and rng.randf() < 0.6:
		# gantry crane at the quay
		_box(c + Vector3(-8, 0, 18), Vector3(1.5, 26, 1.5), Color("#f39c12"))
		_box(c + Vector3(8, 0, 18), Vector3(1.5, 26, 1.5), Color("#f39c12"))
		_box(c + Vector3(0, 26, 24), Vector3(20, 2, 40), Color("#e67e22"), false)
	for row in 3:
		for k in 4:
			var stack := rng.randi_range(0, 3)
			for s in stack:
				_box(c + Vector3(-12 + k * 8, s * 2.6, -10 + row * 7), Vector3(7, 2.6, 3), _container_color())
	if rng.randf() < 0.5:
		_box(c + Vector3(0, 0, 6), Vector3(26, 8, 10), Color("#7f8c8d"))


func _car_static(pos: Vector3, col: Color) -> void:
	_box(pos, Vector3(2.2, 0.9, 4.4), col, true, "car")
	_box(pos + Vector3(0, 0.9, -0.3), Vector3(1.9, 0.7, 2.2), Color("#1c2530"), false, "car")


func _jet(pos: Vector3) -> void:
	_box(pos + Vector3(0, 1.5, 0), Vector3(26, 3.2, 3.2), Color("#eef2f6"), true, "car")
	_box(pos + Vector3(-2, 2.2, 0), Vector3(6, 0.4, 22), Color("#dfe6ee"), false, "car")
	_box(pos + Vector3(11, 3.5, 0), Vector3(3, 4.5, 0.4), Color("#4f8cff"), false, "car")


# ------------------------------------------------------------- landmarks + markers
## Cells with a special building instead of filler. key = Vector2i(x, z) of cell centre.
func _reserved_cells() -> Dictionary:
	return {
		Vector2i(30, 30): "exchange", Vector2i(-30, 30): "cityhall", Vector2i(90, -90): "tower_site",
		Vector2i(-90, -90): "plaza", Vector2i(30, -270): "mansion_lot", Vector2i(330, -90): "spaceport",
		Vector2i(-90, 30): "realty", Vector2i(-90, 90): "store",
	}


func _landmark(kind: String, c: Vector3) -> void:
	match kind:
		"exchange":
			_tower(c, 24, 24, 70, Color("#1e2a3a"))
			_box(c + Vector3(0, 70, 0), Vector3(26, 3, 26), Color("#f5c542"), false)
			_box(c + Vector3(0, 0, 13), Vector3(22, 8, 2), Color("#f5c542"), false)
		"cityhall":
			_box(c, Vector3(28, 12, 20), Color("#ece4d4"))
			for k in 6:
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.8
				cyl.bottom_radius = 0.8
				cyl.height = 1.0
				_batch("column", cyl).add(Transform3D(Basis.from_scale(Vector3(1, 11, 1)), c + Vector3(-11 + k * 4.4, 5.5, 11.5)), Color("#ffffff"))
			_box(c + Vector3(0, 12, 0), Vector3(30, 2, 22), Color("#d8ccb4"), false)
		"realty":
			_tower(c, 22, 22, 30, Color("#3c6e71"))
		"store":
			_box(c, Vector3(26, 9, 22), Color("#ffb703"))
			_box(c + Vector3(0, 9, 11), Vector3(26, 2.5, 1), Color("#fb8500"), false)
		"tower_site":
			for s in [-1.0, 1.0]:
				_box(c + Vector3(s * 17, 0, 0), Vector3(0.3, 2.5, 34), Color("#f39c12"), false)
				_box(c + Vector3(0, 0, s * 17), Vector3(34, 2.5, 0.3), Color("#f39c12"), false)
			_box(c + Vector3(10, 0, -10), Vector3(1, 40, 1), Color("#f1c40f"))
			_box(c + Vector3(0, 40, -10), Vector3(26, 1, 1), Color("#f1c40f"), false)
		"plaza":
			_box(c, Vector3(12, 1.2, 12), Color("#cfd8dc"))
			_tree(c + Vector3(-14, 0, -14))
			_tree(c + Vector3(14, 0, -14))
			_tree(c + Vector3(-14, 0, 14))
			_tree(c + Vector3(14, 0, 14))
		"mansion_lot":
			_box(c + Vector3(0, 0.15, 0), Vector3(34, 0.1, 34), Color("#6fae5a"), false, "pad")
			_mansion_root = Node3D.new()
			_mansion_root.name = "PlayerMansion"
			_mansion_root.position = c
			add_child(_mansion_root)
		"spaceport":
			_box(c, Vector3(30, 1.5, 30), Color("#7f8c8d"))
			_box(c + Vector3(12, 1.5, 0), Vector3(3, 36, 3), Color("#c0392b"))


func _place_markers() -> void:
	var defs := [
		# kind, id, label, cell x, cell z
		["job", "package", "JOB: Package Delivery", -30, -30],
		["job", "food", "JOB: Food Delivery", 90, 30],
		["job", "carwash", "JOB: Car Wash", -210, 30],
		["job", "lawn", "JOB: Lawn Mowing", -270, -90],
		["job", "warehouse", "JOB: Warehouse Shift", 210, -30],
		["job", "dockhand", "JOB: Dock Hand", 90, 210],
		["stocks", "", "STOCK EXCHANGE", 30, 30],
		["business", "", "BUSINESS REGISTRY", -30, 30],
		["business", "", "INDUSTRIAL PARK SALES", 270, 30],
		["business", "", "HARBOR TRADE OFFICE", -90, 210],
		["realestate", "", "REAL ESTATE OFFICE", -90, 30],
		["realestate", "", "HOMES FOR SALE", -270, 30],
		["vehicles", "", "BIKE & SCOOTER SHOP", -210, -30],
		["vehicles", "", "APEX MOTORS (CARS)", -90, -210],
		["vehicles", "", "PRIVATE AIRPORT", 270, -210],
		["vehicles", "", "MARINA (YACHTS)", 210, 270],
		["mansion", "", "YOUR MANSION", 30, -270],
		["shop", "", "EMPIRE STORE (COSMETICS)", -90, 90],
		["crime", "robbery", "SHADY: Corner Store", -330, 90],
		["crime", "scam", "SHADY: Back-Alley Office", 330, 90],
		["crime", "smuggle", "SHADY: Smuggler's Dock", -270, 270],
		["crime", "heist", "SHADY: Bank Vault", 30, -90],
		["endgame", "skyscraper", "EMPIRE TOWER SITE", 90, -90],
		["endgame", "statue", "GOLDEN STATUE PLAZA", -90, -90],
		["endgame", "rocket", "STARFORGE SPACEPORT", 330, -90],
	]
	for d in defs:
		var pos := Vector3(d[3], 0, d[4] + 21.0)
		add_marker(d[0], d[1], d[2], pos)


const MARKER_COLORS := {
	"job": Color("#2ecc71"), "business": Color("#f5c542"), "realestate": Color("#4f8cff"),
	"vehicles": Color("#2ec4c4"), "stocks": Color("#b388ff"), "crime": Color("#ff4d4d"),
	"mansion": Color("#ff6fb5"), "endgame": Color("#ffffff"), "shop": Color("#ffb703"), "target": Color("#ffe14d"),
}


func add_marker(kind: String, id: String, label: String, pos: Vector3, radius := 4.0) -> Dictionary:
	var col: Color = MARKER_COLORS.get(kind, Color.WHITE)
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = radius - 0.6
	rm.outer_radius = radius
	ring.mesh = rm
	ring.position.y = 0.2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.8
	cm.height = 14.0
	beam.mesh = cm
	beam.position.y = 7.0
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(col, 0.18)
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	var lbl := Label3D.new()
	lbl.text = label
	lbl.position.y = 5.0
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 56
	lbl.pixel_size = 0.018
	lbl.outline_size = 14
	lbl.modulate = col.lightened(0.3)
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	lbl.visibility_range_end = 140.0
	root.add_child(lbl)
	var m := {"node": root, "kind": kind, "id": id, "label": label, "pos": pos, "radius": radius, "ring": ring, "beam": beam, "text": lbl}
	if kind != "target":
		markers.append(m)
	return m


func remove_marker(m: Dictionary) -> void:
	if m.has("node") and is_instance_valid(m.node):
		m.node.queue_free()
	markers.erase(m)


func nearest_marker(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for m in markers:
		var d := Vector2(p.x - m.pos.x, p.z - m.pos.z).length()
		if d < float(m.radius) + 0.8 and d < bd:
			bd = d
			best = m
	return best


func animate_markers(t: float) -> void:
	for m in markers:
		m.ring.rotation.y = t * 0.8
		m.text.position.y = 5.0 + sin(t * 2.0 + m.pos.x) * 0.25


# ------------------------------------------------------------- traffic + people
func _traffic() -> void:
	var body := BoxMesh.new()
	body.size = Vector3(2.0, 0.9, 4.2)
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.8, 0.7, 2.0)
	var cols := [Color("#e74c3c"), Color("#3498db"), Color("#f1c40f"), Color("#ecf0f1"), Color("#2c3e50"), Color("#16a085"), Color("#e67e22"), Color("#9b59b6")]
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("#1c2530")
	glass.metallic = 0.5
	glass.roughness = 0.2
	for k in 30:
		var root := Node3D.new()
		var b := MeshInstance3D.new()
		b.mesh = body
		b.position.y = 0.75
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[k % cols.size()]
		m.metallic = 0.4
		m.roughness = 0.35
		b.material_override = m
		root.add_child(b)
		var cb := MeshInstance3D.new()
		cb.mesh = cabin
		cb.position = Vector3(0, 1.5, -0.2)
		cb.material_override = glass
		root.add_child(cb)
		add_child(root)
		var axis := k % 2
		var line := -HALF + GRID * rng.randi_range(1, 11)
		if axis == 0 and line > WATER_Z - 5:
			line = 240.0
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		cars.append({"node": root, "axis": axis, "line": line, "dir": dir, "speed": rng.randf_range(10, 17), "s": rng.randf_range(-HALF, HALF)})


func _pedestrians() -> void:
	var cap := CapsuleMesh.new()
	cap.radius = 0.32
	cap.height = 1.75
	peds_mm = MultiMesh.new()
	peds_mm.transform_format = MultiMesh.TRANSFORM_3D
	peds_mm.use_colors = true
	peds_mm.mesh = cap
	peds_mm.instance_count = 60
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = peds_mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	mi.material_override = m
	add_child(mi)
	var shirt := [Color("#e74c3c"), Color("#3498db"), Color("#f39c12"), Color("#9b59b6"), Color("#1abc9c"), Color("#ecf0f1"), Color("#34495e")]
	for k in 60:
		# walk back and forth along a sidewalk edge in downtown/suburbs
		var cx := -330.0 + GRID * rng.randi_range(2, 7)
		var cz := -330.0 + GRID * rng.randi_range(4, 7)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var a := Vector3(cx - 22, 0.9, cz + side * 22.5)
		var b := Vector3(cx + 22, 0.9, cz + side * 22.5)
		if rng.randf() < 0.5:
			a = Vector3(cx + side * 22.5, 0.9, cz - 22)
			b = Vector3(cx + side * 22.5, 0.9, cz + 22)
		peds.append({"a": a, "b": b, "t": rng.randf(), "speed": rng.randf_range(0.03, 0.06)})
		peds_mm.set_instance_color(k, shirt[k % shirt.size()])


func update_life(delta: float) -> void:
	for c in cars:
		c.s += c.speed * c.dir * delta
		if c.s > HALF:
			c.s = -HALF
		elif c.s < -HALF:
			c.s = HALF
		var lane: float = 2.6 * c.dir
		var n: Node3D = c.node
		if c.axis == 0:
			n.position = Vector3(c.s, 0, c.line + lane)
			n.rotation.y = PI * 0.5 if c.dir > 0 else -PI * 0.5
		else:
			n.position = Vector3(c.line - lane, 0, c.s)
			n.rotation.y = 0.0 if c.dir > 0 else PI
	for k in peds.size():
		var p: Dictionary = peds[k]
		p.t += p.speed * delta
		var f := pingpong(p.t, 1.0)
		var pos: Vector3 = p.a.lerp(p.b, f)
		var dirv: Vector3 = (p.b - p.a).normalized() * (1.0 if fmod(p.t, 2.0) < 1.0 else -1.0)
		var bs := Basis.looking_at(dirv, Vector3.UP) if dirv.length() > 0.1 else Basis()
		pos.y = 0.9 + absf(sin(p.t * 60.0)) * 0.08
		peds_mm.set_instance_transform(k, Transform3D(bs, pos))


# ------------------------------------------------------------- endgame + mansion visuals
func _build_endgame() -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("#f5c542")
	gold.metallic = 0.9
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Color("#7a5a00")
	# Empire Tower
	var t := Node3D.new()
	t.position = Vector3(90, 0, -90)
	for k in 4:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w := 28.0 - k * 5.0
		bm.size = Vector3(w, 45, w)
		mi.mesh = bm
		mi.position.y = 22.5 + k * 45.0
		mi.material_override = window_mat if k % 2 == 0 else gold
		t.add_child(mi)
	var spire := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.1
	sm.bottom_radius = 2.0
	sm.height = 30
	spire.mesh = sm
	spire.position.y = 195
	spire.material_override = gold
	t.add_child(spire)
	_endgame.skyscraper = t
	# Rocket
	var r := Node3D.new()
	r.position = Vector3(330, 1.5, -90)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.5
	cm.bottom_radius = 2.5
	cm.height = 34
	body.mesh = cm
	body.position.y = 17
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("#f5f7fa")
	body.material_override = white
	r.add_child(body)
	var nose := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.05
	nm.bottom_radius = 2.5
	nm.height = 8
	nose.mesh = nm
	nose.position.y = 38
	nose.material_override = gold
	r.add_child(nose)
	_endgame.rocket = r
	# Statue
	var s := Node3D.new()
	s.position = Vector3(-90, 1.2, -90)
	var st := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 2.2
	cap.height = 12
	st.mesh = cap
	st.position.y = 6
	st.material_override = gold
	s.add_child(st)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 2.0
	hm.height = 4.0
	head.mesh = hm
	head.position.y = 13.5
	head.material_override = gold
	s.add_child(head)
	_endgame.statue = s
	for k in _endgame:
		_endgame[k].visible = false
		add_child(_endgame[k])


func refresh_owned(sim) -> void:
	for k in _endgame:
		_endgame[k].visible = k in sim.projects
	_refresh_mansion(sim)


func _refresh_mansion(sim) -> void:
	if _mansion_root == null:
		return
	var best := -1
	for i in sim.properties.size():
		var row: Dictionary = sim.property_row(sim.properties[i].id)
		if row.kind == "mansion" or row.kind == "island":
			if best < 0 or float(row.price) > float(sim.property_row(sim.properties[best].id).price):
				best = i
	var feats: Array = sim.properties[best].features if best >= 0 else []
	var sig := "%d|%s|%s|%s" % [best, ",".join(feats), ",".join(sim.vehicles), sim.paint]
	if sig == _mansion_sig:
		return
	_mansion_sig = sig
	for ch in _mansion_root.get_children():
		ch.queue_free()
	if best < 0:
		_mbox(Vector3(0, 0, 10), Vector3(6, 4, 0.3), Color("#ffffff"))
		_mlabel("FOR SALE — buy any mansion\nin Real Estate to build here", Vector3(0, 6, 10))
		return
	var stone := Color("#e8d9bc")
	_mbox(Vector3(0, 0, -6), Vector3(30, 10, 16), stone)
	_mbox(Vector3(0, 10, -8), Vector3(18, 7, 11), stone.darkened(0.03))
	_mbox(Vector3(-15, 0, -6), Vector3(2, 18, 2), Color("#e8dcc0"))
	_mbox(Vector3(15, 0, -6), Vector3(2, 18, 2), Color("#e8dcc0"))
	_mbox(Vector3(0, 0, 2.2), Vector3(6, 6, 0.3), Color("#5b3a29"))
	if "pool" in feats:
		_mbox(Vector3(-8, 0.05, 10), Vector3(14, 0.35, 7), Color("#29b6f6"))
	if "helipad" in feats:
		_mbox(Vector3(0, 17.05, -8), Vector3(9, 0.2, 9), Color("#2c3e50"))
		_mbox(Vector3(0, 17.3, -8), Vector3(1, 0.05, 5), Color("#f5c542"))
		if "heli" in sim.vehicles:
			_mbox(Vector3(0, 17.4, -8), Vector3(2.4, 2.2, 4.5), Color("#ffffff"))
	if "trophy" in feats:
		_mbox(Vector3(10, 0, 12), Vector3(1.6, 4, 1.6), Color("#f5c542"))
	if "security" in feats:
		for s in [-1.0, 1.0]:
			_mbox(Vector3(s * 16.5, 0, 0), Vector3(0.5, 2.2, 32), Color("#37474f"))
	if "theater" in feats:
		_mbox(Vector3(-12, 10, -6), Vector3(5, 4, 8), Color("#4a148c"))
	# garage: show your street cars lined up
	var x := 4.0
	for vid in sim.vehicles:
		var row: Dictionary = sim.vehicle_row(vid)
		if row.kind != "land" or vid == "bike" or vid == "scooter":
			continue
		var col: Color = row.color
		var paint: Color = C.PAINTS[sim.paint].color
		if paint.a > 0.0:
			col = paint
		_mbox(Vector3(x, 0, 12), Vector3(2.2, 0.9, 4.4), col)
		_mbox(Vector3(x, 0.9, 11.7), Vector3(1.9, 0.7, 2.2), Color("#1c2530"))
		x += 3.4
	_mlabel("%s'S MANSION" % sim.player_name.to_upper(), Vector3(0, 21, -6))


func _mbox(p: Vector3, s: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.position = p + Vector3(0, s.y * 0.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	mi.material_override = m
	_mansion_root.add_child(mi)


func _mlabel(t: String, p: Vector3) -> void:
	var l := Label3D.new()
	l.text = t
	l.position = p
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 48
	l.pixel_size = 0.03
	l.outline_size = 12
	l.modulate = Color("#ff9fd0")
	_mansion_root.add_child(l)


## A random sidewalk spot in a district, at least min_d from `from`.
func random_spot(district: String, from: Vector3, min_d := 40.0, max_d := 220.0) -> Vector3:
	for attempt in 200:
		var i := rng.randi_range(0, 11)
		var j := rng.randi_range(0, 11)
		var c := cell_center(i, j)
		if c.z > WATER_Z or district_of(c.x, c.z) != district:
			continue
		var side: Vector3 = [Vector3(0, 0, 21), Vector3(0, 0, -21), Vector3(21, 0, 0), Vector3(-21, 0, 0)][rng.randi() % 4]
		var p := c + side + Vector3(rng.randf_range(-12, 12) if side.x == 0 else 0.0, 0, rng.randf_range(-12, 12) if side.z == 0 else 0.0)
		var d := p.distance_to(from)
		if d >= min_d and d <= max_d:
			return p
	return from + Vector3(30, 0, 0)
