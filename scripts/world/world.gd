extends Node3D
## World: city + player + job missions + interaction markers + other online players.

const C = preload("res://scripts/core/catalog.gd")
const City = preload("res://scripts/world/city.gd")
const Player = preload("res://scripts/world/player.gd")

signal prompt_changed(text: String)
signal open_tab(tab: String, focus: String)
signal job_changed

const SPAWN := Vector3(0, 1, 6)
const TRAVEL := {
	"downtown": Vector3(0, 1, 6), "suburbs": Vector3(-240, 1, 6), "industrial": Vector3(240, 1, 6),
	"luxury": Vector3(0, 1, -240), "harbor": Vector3(0, 1, 240),
}

var city: City
var player: Player
var current := {}            # marker the player stands on
var job := {}                # active job state, {} when idle
var remote := {}             # peer id -> {"node", "vehicle"}
var _t := 0.0
var _owned_t := 0.0


func _ready() -> void:
	city = City.new()
	city.name = "City"
	add_child(city)
	city.build()
	player = Player.new()
	player.name = "Player"
	player.position = SPAWN
	add_child(player)
	player.snap_camera()
	city.refresh_owned(Game.sim)
	Game.sim_replaced.connect(func(): cancel_job(true); city.refresh_owned(Game.sim))


func _process(delta: float) -> void:
	_t += delta
	var sim = Game.sim
	city.set_time_of_day(sim.minute)
	city.animate_markers(_t)
	city.update_life(delta)
	_owned_t += delta
	if _owned_t > 0.5:
		_owned_t = 0.0
		city.refresh_owned(sim)
	var m := city.nearest_marker(player.global_position)
	if m != current:
		current = m
		prompt_changed.emit(_prompt_for(m))
	if Game.running and not player.frozen and Input.is_action_just_pressed("interact"):
		interact()
	if not job.is_empty():
		_job_tick(delta)
	_sync_remote(delta)


func _prompt_for(m: Dictionary) -> String:
	if m.is_empty():
		return ""
	var verb := "Open"
	match m.kind:
		"job": verb = "Start job"
		"crime": verb = "Plan"
		"endgame": verb = "View project"
	return "%s — %s" % [verb, m.label]


func interact() -> void:
	if current.is_empty():
		return
	var kind: String = current.kind
	var id: String = current.id
	match kind:
		"job": start_job(id, current.pos)
		"crime": open_tab.emit("crime", id)
		"endgame": open_tab.emit("empire", id)
		_: open_tab.emit(kind, id)


func teleport(district: String) -> void:
	player.global_position = TRAVEL.get(district, SPAWN)
	player.velocity = Vector3.ZERO
	player.snap_camera()


# ------------------------------------------------------------- jobs
func start_job(id: String, hub: Vector3) -> void:
	var sim = Game.sim
	if not job.is_empty():
		Game.emit_toast("Finish (or cancel) your current job first.", "bad")
		return
	if sim.in_jail():
		Game.emit_toast("You're in jail. Wait it out.", "bad")
		return
	if not sim.job_unlocked(id):
		Game.emit_toast("Locked — complete %d jobs first." % int(C.JOBS[id].unlock_jobs), "bad")
		return
	var j: Dictionary = C.JOBS[id]
	job = {"id": id, "kind": j.kind, "hub": hub, "step": 0, "done": 0, "need": 1, "progress": 0.0,
		"limit": float(j.get("time_limit", 0.0)), "time_left": float(j.get("time_limit", 0.0)),
		"elapsed": 0.0, "targets": [], "carrying": false, "pickup": hub, "drop": hub}
	match j.kind:
		"deliver":
			job.need = int(j.stops)
			_set_target(city.random_spot(j.district, hub, 45.0, 170.0))
		"hold":
			job.need = 1
			_set_target(hub, 4.0)
		"patches":
			job.need = int(j.patches)
			var centre: Vector3 = hub - Vector3(0, 0, 21)
			var spots := []
			for k in job.need:
				var side: Vector3 = [Vector3(0, 0, 21), Vector3(0, 0, -21), Vector3(21, 0, 0), Vector3(-21, 0, 0)][k % 4]
				var along := city.rng.randf_range(-16, 16)
				spots.append(centre + side + (Vector3(along, 0, 0) if side.x == 0 else Vector3(0, 0, along)))
			for p in spots:
				var mk := city.add_marker("target", "", "MOW", p, 2.6)
				job.targets.append(mk)
		"carry":
			job.need = int(j.loads)
			job.drop = city.random_spot(j.district, hub, 30.0, 80.0)
			_set_target(hub + Vector3(0, 0, -0.1), 3.0)
	Sfx.play("click")
	Game.emit_toast("%s started: %s" % [j.name, j.desc], "info")
	job_changed.emit()


func _set_target(p: Vector3, radius := 3.5) -> void:
	for t in job.targets:
		city.remove_marker(t)
	job.targets = [city.add_marker("target", "", "", p, radius)]


func _job_tick(delta: float) -> void:
	var sim = Game.sim
	if sim.in_jail():
		cancel_job()
		return
	job.elapsed += delta
	if job.limit > 0.0:
		job.time_left -= delta
		if job.time_left <= 0.0:
			Game.emit_toast("Too slow! The customer cancelled the order.", "bad")
			Sfx.play("error")
			cancel_job(true)
			return
	var p := player.global_position
	match job.kind:
		"deliver":
			if _at(job.targets[0], p):
				job.done += 1
				Sfx.play("click")
				if job.done >= job.need:
					_finish()
				else:
					_set_target(city.random_spot(C.JOBS[job.id].district, p, 40.0, 160.0))
					job_changed.emit()
		"hold":
			if _at(job.targets[0], p) and player.velocity.length() < 3.0:
				job.progress += delta
				if job.progress >= float(C.JOBS[job.id].hold):
					job.done = 1
					_finish()
		"patches":
			for t in job.targets.duplicate():
				if _at(t, p):
					t["mow"] = float(t.get("mow", 0.0)) + delta
					if t.mow >= 0.8:
						city.remove_marker(t)
						job.targets.erase(t)
						job.done += 1
						Sfx.play("click")
						job_changed.emit()
			if job.done >= job.need:
				_finish()
		"carry":
			if _at(job.targets[0], p):
				if not job.carrying:
					job.carrying = true
					player.set_carrying(true)
					_set_target(job.drop, 3.0)
				else:
					job.carrying = false
					player.set_carrying(false)
					job.done += 1
					Sfx.play("click")
					if job.done >= job.need:
						_finish()
						return
					_set_target(job.pickup, 3.0)
				job_changed.emit()


func _at(t: Dictionary, p: Vector3) -> bool:
	return Vector2(p.x - t.pos.x, p.z - t.pos.z).length() <= float(t.radius)


func _finish() -> void:
	var q := 1.0
	if job.limit > 0.0:
		q = 1.0 + 0.5 * clampf(job.time_left / job.limit, 0.0, 1.0)   # tips for speed
	var id: String = job.id
	cancel_job(true)
	var r: Dictionary = Game.sim.complete_job(id, q)
	if r.ok:
		Game.emit_toast(r.msg + (" (incl. tip!)" if q > 1.05 else ""), "money")
		Sfx.play("job")
	else:
		Game.act(r)
	Game.mark_changed()


func cancel_job(silent := false) -> void:
	if job.is_empty():
		return
	for t in job.targets:
		city.remove_marker(t)
	player.set_carrying(false)
	job = {}
	if not silent:
		Game.emit_toast("Job cancelled.", "info")
	job_changed.emit()


func job_title() -> String:
	return "" if job.is_empty() else str(C.JOBS[job.id].name)


func job_objective() -> String:
	if job.is_empty():
		return ""
	match job.kind:
		"deliver": return "Deliver to the yellow marker  (%d/%d)" % [job.done, job.need]
		"hold": return "Stay in the wash bay  %d%%" % int(100.0 * job.progress / float(C.JOBS[job.id].hold))
		"patches": return "Mow the yellow patches  (%d/%d)" % [job.done, job.need]
		"carry": return ("Drop the pallet at the marker" if job.carrying else "Pick up a pallet") + "  (%d/%d)" % [job.done, job.need]
	return ""


func job_target() -> Variant:
	if job.is_empty() or job.targets.is_empty():
		return null
	# nearest remaining target
	var best = null
	var bd := INF
	for t in job.targets:
		var d: float = player.global_position.distance_to(t.pos)
		if d < bd:
			bd = d
			best = t.pos
	return best


# ------------------------------------------------------------- online players
func _sync_remote(delta: float) -> void:
	var me := Net.my_id()
	var seen := {}
	for id in Net.players:
		if id == me:
			continue
		seen[id] = true
		var info: Dictionary = Net.players[id]
		if not remote.has(id):
			remote[id] = {"node": _make_avatar(info), "vehicle": "?"}
			add_child(remote[id].node)
			remote[id].node.global_position = info.pos
		var r: Dictionary = remote[id]
		var n: Node3D = r.node
		n.global_position = n.global_position.lerp(info.pos, minf(1.0, 10.0 * delta))
		n.rotation.y = lerp_angle(n.rotation.y, float(info.yaw), minf(1.0, 10.0 * delta))
		var lbl: Label3D = n.get_node("Name")
		lbl.text = "%s\n$%s%s" % [info.name, Game.sim.fmt_money(float(info.networth)), ("  [" + info.company + "]") if str(info.company) != "" else ""]
		if r.vehicle != info.vehicle:
			r.vehicle = info.vehicle
			var vr: Node3D = n.get_node("Vehicle")
			for ch in vr.get_children():
				ch.queue_free()
			n.get_node("Body").visible = info.vehicle == "" or info.vehicle in ["bike", "scooter"]
			if info.vehicle != "":
				var row: Dictionary = Game.sim.vehicle_row(info.vehicle)
				if not row.is_empty():
					Player.build_vehicle_mesh(vr, info.vehicle, row.color)
	for id in remote.keys():
		if not seen.has(id):
			remote[id].node.queue_free()
			remote.erase(id)


func _make_avatar(info: Dictionary) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Body"
	var cm := CapsuleMesh.new()
	cm.radius = 0.42
	cm.height = 1.8
	body.mesh = cm
	body.position.y = 0.9
	var m := StandardMaterial3D.new()
	m.albedo_color = C.SKINS.get(str(info.get("skin", "default")), C.SKINS.default).color
	body.material_override = m
	root.add_child(body)
	var vr := Node3D.new()
	vr.name = "Vehicle"
	root.add_child(vr)
	var lbl := Label3D.new()
	lbl.name = "Name"
	lbl.position.y = 3.0
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 40
	lbl.pixel_size = 0.015
	lbl.outline_size = 10
	lbl.modulate = Color("#ffe082")
	root.add_child(lbl)
	return root
