extends Node
## Net — ENet multiplayer for up to 100 players.
##   * Host (listen server) from the in-game phone
##   * Join by IP
##   * Headless dedicated server:  godot --headless -- --server [--port 7777]
## The server is authoritative for the shared world: economy phase, stock prices, clock, chat,
## money transfers and the online leaderboard. Each player's wallet is simulated on their own
## device; the server sanity-checks reported net worth and kicks peers that spike impossibly.

signal players_changed
signal chat(from_name: String, text: String, kind: String)
signal status_changed(text: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 100
const STATE_HZ := 10.0
const ECON_SYNC_SECONDS := 5.0
const MAX_CHAT_LEN := 160
const CHAT_COOLDOWN := 0.6
const MAX_TRANSFER := 1_000_000_000.0

var players := {}            # peer_id -> {name, pos, yaw, vehicle, skin, networth, cash, company}
var dedicated := false
var port := DEFAULT_PORT
var status := "Offline"
var local := {"pos": Vector3.ZERO, "yaw": 0.0, "vehicle": ""}
var chat_log: Array = []     # [{from, text, kind}]

var _send_t := 0.0
var _econ_t := 0.0
var _chat_t := {}            # peer -> last chat time
var _nw_seen := {}           # peer -> {"t": msec, "nw": float}
var _strikes := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _set_status("Connection failed."); leave())
	multiplayer.server_disconnected.connect(func(): _set_status("Server closed the connection."); leave())
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if "--server" in args or OS.has_feature("dedicated_server"):
		dedicated = true
		var i := args.find("--port")
		if i >= 0 and i + 1 < args.size():
			port = int(args[i + 1])


# ------------------------------------------------------------- state queries
func is_online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_server() -> bool:
	return is_online() and multiplayer.is_server()


func is_client() -> bool:
	return is_online() and not multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func remote_players() -> Array:
	var out: Array = []
	for id in players:
		if id != my_id():
			out.append(players[id])
	return out


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)
	print("[net] ", t)


func _my_info() -> Dictionary:
	var s = Game.sim
	return {"name": s.player_name, "pos": local.pos, "yaw": local.yaw, "vehicle": local.vehicle,
		"skin": s.skin, "networth": s.networth(), "cash": s.cash, "company": s.company}


# ------------------------------------------------------------- connect / leave
func host(p_port: int = DEFAULT_PORT) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p_port, MAX_PLAYERS)
	if err != OK:
		_set_status("Could not host on port %d (error %d)." % [p_port, err])
		return status
	multiplayer.multiplayer_peer = peer
	players.clear()
	if not dedicated:
		players[1] = _my_info()
	_set_status(("Dedicated server" if dedicated else "Hosting") + " on port %d — up to %d players." % [p_port, MAX_PLAYERS])
	players_changed.emit()
	return status


func join(address: String, p_port: int = DEFAULT_PORT) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), p_port)
	if err != OK:
		_set_status("Could not connect (error %d)." % err)
		return status
	multiplayer.multiplayer_peer = peer
	_set_status("Connecting to %s:%d ..." % [address, p_port])
	return status


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	players_changed.emit()
	if not status.begins_with("Connection") and not status.begins_with("Server closed"):
		_set_status("Offline")


func _on_connected() -> void:
	_set_status("Connected! Shared economy synced from the server.")
	_register.rpc_id(1, _my_info())


func _on_peer_connected(_id: int) -> void:
	pass  # wait for _register


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		var n: String = players[id].name
		players.erase(id)
		if is_server():
			_sync_players.rpc(players)
			_system("%s left the city." % n)
	players_changed.emit()


# ------------------------------------------------------------- RPCs: players
@rpc("any_peer", "reliable")
func _register(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var clean := {"name": _clean_name(str(info.get("name", "Player"))), "pos": Vector3.ZERO, "yaw": 0.0, "vehicle": "",
		"skin": str(info.get("skin", "default")), "networth": float(info.get("networth", 100.0)),
		"cash": float(info.get("cash", 100.0)), "company": _clean_name(str(info.get("company", "")))}
	players[id] = clean
	_sync_players.rpc(players)
	_econ_sync.rpc_id(id, _econ_snapshot())
	_system("%s arrived in the city." % clean.name)
	players_changed.emit()


@rpc("authority", "call_local", "reliable")
func _sync_players(p: Dictionary) -> void:
	if not multiplayer.is_server():
		players = p
	players_changed.emit()


func _clean_name(n: String) -> String:
	n = n.strip_edges().replace("[", "(").replace("]", ")")
	return n.substr(0, 20)


# ------------------------------------------------------------- RPCs: movement + world
func _process(delta: float) -> void:
	if not is_online():
		return
	_send_t += delta
	if _send_t >= 1.0 / STATE_HZ:
		_send_t = 0.0
		var s = Game.sim
		if is_server():
			if not dedicated:
				_apply_state(1, local.pos, local.yaw, local.vehicle, s.networth(), s.cash)
			var compact := {}
			for id in players:
				var pl: Dictionary = players[id]
				compact[id] = [pl.pos, pl.yaw, pl.vehicle, pl.networth]
			_world_state.rpc(compact)
		else:
			_push_state.rpc_id(1, local.pos, local.yaw, local.vehicle, s.networth(), s.cash)
	if is_server():
		_econ_t += delta
		if _econ_t >= ECON_SYNC_SECONDS:
			_econ_t = 0.0
			_econ_sync.rpc(_econ_snapshot())


@rpc("any_peer", "unreliable_ordered")
func _push_state(pos: Vector3, yaw: float, vehicle: String, nw: float, cash: float) -> void:
	if not multiplayer.is_server():
		return
	_apply_state(multiplayer.get_remote_sender_id(), pos, yaw, vehicle, nw, cash)


func _apply_state(id: int, pos: Vector3, yaw: float, vehicle: String, nw: float, cash: float) -> void:
	if not players.has(id):
		return
	var pl: Dictionary = players[id]
	# keep players inside the map
	pl.pos = Vector3(clampf(pos.x, -420, 420), clampf(pos.y, -5, 200), clampf(pos.z, -420, 420))
	pl.yaw = yaw
	pl.vehicle = vehicle.substr(0, 16)
	pl.cash = cash
	pl.networth = _check_networth(id, nw)


## Anti-cheat: net worth can't grow faster than the best legal play allows.
func _check_networth(id: int, nw: float) -> float:
	var now := Time.get_ticks_msec()
	if not _nw_seen.has(id):
		_nw_seen[id] = {"t": now, "nw": nw}
		return nw
	var prev: Dictionary = _nw_seen[id]
	var dt := maxf(0.05, float(now - int(prev.t)) / 1000.0)
	var allowed: float = float(prev.nw) * pow(1.5, dt) + 2_000_000.0 * dt
	if nw > allowed and id != 1:
		_strikes[id] = int(_strikes.get(id, 0)) + 1
		push_warning("[anticheat] peer %d net worth spike %.0f -> %.0f" % [id, prev.nw, nw])
		if int(_strikes[id]) >= 3:
			_system("%s was removed by anti-cheat." % players[id].name)
			multiplayer.multiplayer_peer.disconnect_peer(id)
		return float(prev.nw)
	_nw_seen[id] = {"t": now, "nw": nw}
	return nw


@rpc("authority", "unreliable_ordered")
func _world_state(states: Dictionary) -> void:
	for id in states:
		if players.has(id):
			var st: Array = states[id]
			players[id].pos = st[0]
			players[id].yaw = st[1]
			players[id].vehicle = st[2]
			players[id].networth = st[3]


func _econ_snapshot() -> Dictionary:
	var s = Game.sim
	return {"economy": s.economy.to_dict(), "market": s.market.to_dict(), "day": s.day, "minute": s.minute}


@rpc("authority", "reliable")
func _econ_sync(d: Dictionary) -> void:
	var s = Game.sim
	var was_phase: String = s.economy.phase
	s.economy.from_dict(d.economy)
	s.market.from_dict(d.market)
	var server_t := float(int(d.day) - 1) * 1440.0 + float(d.minute)
	if absf(server_t - s.total_minutes()) > 30.0:
		s.day = int(d.day)
		s.minute = float(d.minute)
	if s.economy.phase != was_phase:
		Game.emit_toast(s.economy.headlines[0].text if s.economy.headlines.size() > 0 else "Economy shift!", "news")
	Game.mark_changed()


# ------------------------------------------------------------- chat
func send_chat(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	if not is_online():
		_add_chat(Game.sim.player_name, text, "self")
		return
	if is_server():
		_handle_chat(1, text)
	else:
		_chat_req.rpc_id(1, text)


@rpc("any_peer", "reliable")
func _chat_req(text: String) -> void:
	if multiplayer.is_server():
		_handle_chat(multiplayer.get_remote_sender_id(), text)


func _handle_chat(id: int, text: String) -> void:
	if not players.has(id):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_chat_t.get(id, -10.0)) < CHAT_COOLDOWN:
		return
	_chat_t[id] = now
	text = text.strip_edges().substr(0, MAX_CHAT_LEN).replace("[", "(")
	_chat_msg.rpc(players[id].name, text, "player")


func _system(text: String) -> void:
	if is_server():
		_chat_msg.rpc("SERVER", text, "system")


@rpc("authority", "call_local", "reliable")
func _chat_msg(from: String, text: String, kind: String) -> void:
	_add_chat(from, text, kind)


func _add_chat(from: String, text: String, kind: String) -> void:
	chat_log.append({"from": from, "text": text, "kind": kind})
	if chat_log.size() > 60:
		chat_log.pop_front()
	chat.emit(from, text, kind)
	if dedicated:
		print("[chat] %s: %s" % [from, text])


# ------------------------------------------------------------- trading: send money
func send_money(to_id: int, amount: float) -> String:
	amount = floorf(amount)
	if not is_online():
		return "You're offline."
	if amount <= 0 or amount > Game.sim.cash:
		return "Not enough cash."
	if is_server():
		_handle_transfer(1, to_id, amount)
	else:
		_transfer_req.rpc_id(1, to_id, amount)
	return ""


@rpc("any_peer", "reliable")
func _transfer_req(to_id: int, amount: float) -> void:
	if multiplayer.is_server():
		_handle_transfer(multiplayer.get_remote_sender_id(), to_id, amount)


func _handle_transfer(from_id: int, to_id: int, amount: float) -> void:
	if not players.has(from_id) or not players.has(to_id) or from_id == to_id:
		return
	if amount <= 0.0 or amount > MAX_TRANSFER or amount > float(players[from_id].cash) + 1.0:
		return
	players[from_id].cash = float(players[from_id].cash) - amount
	_transfer_done.rpc_id(from_id, players[to_id].name, amount)
	_receive_money.rpc_id(to_id, players[from_id].name, amount)
	_system("%s sent $%s to %s." % [players[from_id].name, Game.sim.fmt_money(amount), players[to_id].name])


@rpc("authority", "call_local", "reliable")
func _transfer_done(to_name: String, amount: float) -> void:
	Game.sim.cash -= amount
	Game.emit_toast("Sent $%s to %s." % [Game.sim.fmt_money(amount), to_name], "money")
	Game.mark_changed()


@rpc("authority", "call_local", "reliable")
func _receive_money(from: String, amount: float) -> void:
	Game.sim.cash += amount
	Game.emit_toast("%s sent you $%s!" % [from, Game.sim.fmt_money(amount)], "money")
	Sfx.play("coin")
	Game.mark_changed()


# ------------------------------------------------------------- teams / corporations
func set_company(company_name: String) -> void:
	Game.sim.company = _clean_name(company_name)
	if is_server():
		if players.has(1):
			players[1].company = Game.sim.company
		_sync_players.rpc(players)
	elif is_client():
		_company_req.rpc_id(1, Game.sim.company)
	Game.mark_changed()


@rpc("any_peer", "reliable")
func _company_req(company_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].company = _clean_name(company_name)
		_sync_players.rpc(players)


## Company leaderboard: sum of member net worth.
func company_board() -> Array:
	var totals := {}
	var all: Array = remote_players()
	all.append({"name": Game.sim.player_name, "networth": Game.sim.networth(), "company": Game.sim.company})
	for p in all:
		var c := str(p.get("company", ""))
		if c == "":
			continue
		if not totals.has(c):
			totals[c] = {"name": c, "networth": 0.0, "members": 0}
		totals[c].networth += float(p.networth)
		totals[c].members += 1
	var rows: Array = totals.values()
	rows.sort_custom(func(a, b): return a.networth > b.networth)
	return rows
