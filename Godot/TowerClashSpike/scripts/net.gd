extends Node
## Autoload. ENet transport, RPC surface and the authoritative server loop.
## Server: owns a MatchSim, sends full-state snapshots, then resets for the next match
## (unless --quit-on-end). Clients: send intents only; can connect/leave repeatedly.

signal connected_to_host
signal joined(player_index: int)
signal match_info_received(names: Array)
signal snapshot_received(snap: Dictionary)
signal match_ended_received(res: Dictionary)
signal action_feedback(res: Dictionary)
## Connection failed, server went away, or the server rejected us (see reject_reason).
signal disconnected

const DEFAULT_PORT := 7777
## ENet slots. More than 2 so a third client gets an explicit "full" instead of a timeout.
const MAX_PEERS := 6
const NO_HELLO_KICK_S := 15.0
const POST_MATCH_KICK_S := 20.0

var args: Dictionary = {}
var is_server := false
var sim: MatchSim
var my_index := -1
var names: Array = ["", ""]
var reject_reason := ""

# server
var _peer_to_index: Dictionary = {}
var _peer_seen_at: Dictionary = {}
var _decks: Array = [null, null]
var _snap_interval := 0.1
var _snap_acc := 0.0
var _sim_acc := 0.0
var _sim_dt := 1.0 / 30.0
var _timescale := 1.0
var _ended_at := -1.0
var _wall := 0.0
var _matches := 0
var _use_eos := false
var _quitting := false
var _net_stats := {}

# client
var _hello: Dictionary = {}
var _leaving := false


func _ready() -> void:
	args = parse_args()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_net_stats = _fresh_stats()
	# Connected once; SceneMultiplayer keeps them across peer changes, so repeated
	# start_client() calls never stack duplicate handlers.
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


static func parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			out[s] = "1"
	return out


func log_line(msg: String) -> void:
	var role := "SERVER" if is_server else "CLIENT%s" % (str(my_index) if my_index >= 0 else "?")
	print("[%8.2f] %s %s" % [_wall, role, msg])


func _fresh_stats() -> Dictionary:
	return {"snapshots": 0, "snapshot_bytes": 0, "max_snapshot_bytes": 0,
		"naive_samples": 0, "naive_bytes": 0, "naive_max": 0, "codec_checks": 0, "codec_failures": 0}


# ---------------------------------------------------------------- server

## --eos advertises the server through EOS sessions; --public-address sets the address
## clients are told to connect to (default 127.0.0.1). --max-matches=N quits after N matches.
func start_server(port: int) -> void:
	is_server = true
	GameData.ensure_loaded()
	Engine.physics_ticks_per_second = int(args.get("tick", "30"))
	_timescale = float(args.get("timescale", "1"))
	_sim_dt = 1.0 / Engine.physics_ticks_per_second
	# Headless has no vsync, so the idle loop would spin flat out. One frame per tick is enough:
	# SceneMultiplayer polls ENet once per process frame. Accelerated test runs scale the cap so
	# input latency in sim time stays the same as at 1x.
	var fps_cap := int(Engine.physics_ticks_per_second * maxf(1.0, _timescale))
	Engine.max_fps = int(args.get("maxfps", str(fps_cap)))
	_snap_interval = 1.0 / float(args.get("snaprate", "10"))
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		log_line("ERROR create_server %d -> %s" % [port, error_string(err)])
		get_tree().quit(2)
		return
	multiplayer.multiplayer_peer = peer
	# No client<->client relay: clients only talk to the authority. Also stops the server from
	# notifying an already-disconnected peer when both clients drop in the same frame.
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.peer_connected.connect(_on_server_peer_connected)
	multiplayer.peer_disconnected.connect(_on_server_peer_disconnected)
	log_line("listening on %d (tick %d Hz, snapshots %d Hz, timescale %s)" % [
		port, Engine.physics_ticks_per_second, int(round(1.0 / _snap_interval)), _timescale])
	if args.has("eos"):
		var addr := "%s:%d" % [args.get("public-address", "127.0.0.1"), port]
		_use_eos = await Online.server_advertise(addr)
		if not _use_eos:
			log_line("ERROR EOS advertise failed (%s); direct connections still work" % Online.last_error)


func _on_server_peer_connected(id: int) -> void:
	_peer_seen_at[id] = _wall
	log_line("peer connected %d" % id)


func _on_server_peer_disconnected(id: int) -> void:
	log_line("peer disconnected %d" % id)
	_peer_seen_at.erase(id)
	if not _peer_to_index.has(id):
		return
	var idx: int = _peer_to_index[id]
	_peer_to_index.erase(id)
	if sim == null:
		# Left (or cancelled) before the match started: free the seat.
		_decks[idx] = null
		names[idx] = ""
	elif sim.phase != MatchSim.Phase.ENDED:
		sim._finish(1 - idx, "opponent_left")
		_broadcast_end()


func _physics_process(delta: float) -> void:
	_wall += delta
	if not is_server:
		return
	_kick_idle_peers()
	if sim == null:
		return
	if sim.phase != MatchSim.Phase.ENDED:
		# Fixed sim step regardless of timescale: Engine.time_scale would stretch the physics
		# delta instead and coarsen the sim (fewer, bigger steps), changing outcomes.
		_sim_acc += delta * _timescale
		while _sim_acc >= _sim_dt - 1e-6 and sim.phase != MatchSim.Phase.ENDED:
			_sim_acc -= _sim_dt
			_sim_tick()
	elif _ended_at >= 0.0 and not _quitting:
		var since := _wall - _ended_at
		if args.has("quit-on-end"):
			if since > 2.0:
				_quit_server()
		elif _peer_to_index.is_empty() or since > POST_MATCH_KICK_S:
			_reset_for_next_match()


## Peers that connect but never say hello would otherwise hold a seat-less ENet slot forever.
func _kick_idle_peers() -> void:
	for id in _peer_seen_at.keys():
		if not _peer_to_index.has(id) and _wall - float(_peer_seen_at[id]) > NO_HELLO_KICK_S:
			log_line("kicking silent peer %d" % id)
			_peer_seen_at.erase(id)
			multiplayer.multiplayer_peer.disconnect_peer(id)


func _reset_for_next_match() -> void:
	_matches += 1
	for id in _connected_player_peers():
		multiplayer.multiplayer_peer.disconnect_peer(id)
	sim = null
	_peer_to_index.clear()
	_decks = [null, null]
	names = ["", ""]
	_ended_at = -1.0
	_sim_acc = 0.0
	_snap_acc = 0.0
	_net_stats = _fresh_stats()
	var max_matches := int(args.get("max-matches", "0"))
	if max_matches > 0 and _matches >= max_matches:
		log_line("played %d matches, shutting down" % _matches)
		_quit_server()
		return
	log_line("ready for next match (%d played)" % _matches)
	if _use_eos:
		Online.server_set_state(Online.STATE_OPEN)


func _quit_server() -> void:
	_quitting = true
	log_line("quitting")
	if _use_eos:
		await Online.server_destroy()
	Online.quit(0)


func _sim_tick() -> void:
	sim.step(_sim_dt)
	_snap_acc += _sim_dt
	if _snap_acc >= _snap_interval - 1e-6 or sim.phase == MatchSim.Phase.ENDED:
		_snap_acc -= _snap_interval
		var snap := sim.snapshot()
		var bytes := SnapCodec.encode(snap)
		var size := bytes.size()
		_net_stats.snapshots += 1
		_net_stats.snapshot_bytes += size
		_net_stats.max_snapshot_bytes = max(_net_stats.max_snapshot_bytes, size)
		if _net_stats.snapshots % 10 == 1:
			# Sampled comparison against naive Variant encoding of the same Dictionary.
			var naive := var_to_bytes(snap).size()
			_net_stats.naive_samples += 1
			_net_stats.naive_bytes += naive
			_net_stats.naive_max = max(_net_stats.naive_max, naive)
		if args.has("codec-check") and _net_stats.snapshots % 50 == 1:
			_codec_check(snap, bytes)
		for id in _connected_player_peers():
			snapshot.rpc_id(id, bytes)
		if sim.phase == MatchSim.Phase.ENDED:
			_broadcast_end()


func _connected_player_peers() -> Array:
	var live := multiplayer.get_peers()
	var out: Array = []
	for id in _peer_to_index:
		if live.has(id):
			out.append(id)
	return out


## Round-trips a snapshot through the codec and checks every field is within quantisation.
func _codec_check(snap: Dictionary, bytes: PackedByteArray) -> void:
	var d := SnapCodec.decode(bytes)
	var ok: bool = d.p == snap.p and d.tw.size() == 2 and d.en.size() == snap.en.size() \
			and d.sh.size() == snap.sh.size() and d.k.size() == snap.k.size() and d.h.size() == snap.h.size() \
			and int(d.ph) == int(snap.ph) and int(d.r) == int(snap.r)
	for i in d.en.size() if ok else 0:
		var a: Array = d.en[i]
		var e: Array = snap.en[i]
		if int(a[0]) != int(e[0]) or int(a[1]) != int(e[1]) or int(a[2]) != int(e[2]) or int(a[5]) != int(e[5]) \
				or absf(float(a[3]) - float(e[3])) > 0.51 or absf(float(a[4]) - float(e[4])) > 0.006:
			ok = false
	for p in 2 if ok else 0:
		if d.tw[p].size() != snap.tw[p].size():
			ok = false
			break
		for i in d.tw[p].size():
			var a: Array = d.tw[p][i]
			var t: Array = snap.tw[p][i]
			var aim_ok: bool = (float(t[3]) > 7.0) == (float(a[3]) > 7.0)
			if aim_ok and float(t[3]) <= 7.0:
				aim_ok = absf(angle_difference(float(a[3]), float(t[3]))) < TAU / 254.0
			if int(a[0]) != int(t[0]) or int(a[1]) != int(t[1]) or int(a[2]) != int(t[2]) or not aim_ok:
				ok = false
	_net_stats.codec_checks += 1
	if not ok:
		_net_stats.codec_failures += 1
		log_line("ERROR codec mismatch")


func _broadcast_end() -> void:
	if _ended_at >= 0.0:
		return
	_ended_at = _wall
	var res := sim.result.duplicate(true)
	res["names"] = names.duplicate()
	var n: int = max(1, _net_stats.snapshots)
	res["net"] = {
		"snapshots": _net_stats.snapshots,
		"avg_snapshot_bytes": _net_stats.snapshot_bytes / n,
		"max_snapshot_bytes": _net_stats.max_snapshot_bytes,
		"naive_variant_avg_bytes": _net_stats.naive_bytes / max(1, _net_stats.naive_samples),
		"naive_variant_max_bytes": _net_stats.naive_max,
		"codec_checks": _net_stats.codec_checks,
		"codec_failures": _net_stats.codec_failures,
		"snapshot_payload_bytes_per_s_per_client": int(float(_net_stats.snapshot_bytes) / max(sim.time, 0.001)),
	}
	log_line("RESULT " + JSON.stringify(res))
	for id in _connected_player_peers():
		match_ended.rpc_id(id, res)


@rpc("any_peer", "reliable")
func hello(deck: Array, player_name: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if _peer_to_index.has(id):
		return
	if sim != null or (_decks[0] != null and _decks[1] != null):
		log_line("rejecting %d: full" % id)
		rejected.rpc_id(id, "full")
		return
	if not GameData.validate_deck(deck):
		log_line("rejecting deck from %d: %s" % [id, str(deck)])
		rejected.rpc_id(id, "invalid_deck")
		return
	var idx := 0 if _decks[0] == null else 1
	_peer_to_index[id] = idx
	_decks[idx] = deck
	names[idx] = player_name.substr(0, 24)
	log_line("peer %d '%s' is player %d deck %s" % [id, names[idx], idx, str(deck)])
	welcome.rpc_id(id, idx)
	if _decks[0] != null and _decks[1] != null:
		sim = MatchSim.new()
		var seed_value := int(args.get("seed", str(Time.get_ticks_usec())))
		sim.setup(_decks, seed_value)
		sim.start()
		log_line("match started seed %d: '%s' vs '%s'" % [seed_value, names[0], names[1]])
		for pid in _connected_player_peers():
			match_info.rpc_id(pid, names)
		if _use_eos:
			Online.server_set_state(Online.STATE_IN_MATCH)


@rpc("any_peer", "reliable")
func request_place() -> void:
	if not is_server or sim == null:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _peer_to_index.has(id):
		return
	var res := sim.request_place(_peer_to_index[id])
	res["action"] = "place"
	if args.has("verbose"):
		log_line("place p%d -> %s" % [_peer_to_index[id], str(res)])
	action_result.rpc_id(id, res)


@rpc("any_peer", "reliable")
func request_merge(src: int, dst: int) -> void:
	if not is_server or sim == null:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _peer_to_index.has(id):
		return
	var res := sim.request_merge(_peer_to_index[id], src, dst)
	res["action"] = "merge"
	if args.has("verbose"):
		log_line("merge p%d %d->%d -> %s" % [_peer_to_index[id], src, dst, str(res)])
	action_result.rpc_id(id, res)


# ---------------------------------------------------------------- client

## Returns false if the ENet client could not be created. Success is signalled later by
## connected_to_host / joined, failure by disconnected.
func start_client(host: String, port: int, deck: Array, player_name: String) -> bool:
	leave()
	GameData.ensure_loaded()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		log_line("ERROR create_client %s:%d -> %s" % [host, port, error_string(err)])
		return false
	reject_reason = ""
	_hello = {"deck": deck, "name": player_name, "addr": "%s:%d" % [host, port]}
	multiplayer.multiplayer_peer = peer
	return true


## Drops the connection without emitting disconnected. Safe to call when not connected.
func leave() -> void:
	if is_server:
		return
	_leaving = true
	var p := multiplayer.multiplayer_peer
	if p != null and not (p is OfflineMultiplayerPeer):
		p.close()
	multiplayer.multiplayer_peer = null
	my_index = -1
	names = ["", ""]
	_hello = {}
	_leaving = false


func is_connected_to_host() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) \
			and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _on_connected_to_server() -> void:
	if is_server or _hello.is_empty():
		return
	log_line("connected to %s" % _hello.addr)
	connected_to_host.emit()
	hello.rpc_id(1, _hello.deck, _hello.name)


func _on_connection_failed() -> void:
	if is_server or _leaving:
		return
	log_line("ERROR connection failed")
	disconnected.emit()


func _on_server_disconnected() -> void:
	if is_server or _leaving:
		return
	log_line("server disconnected")
	disconnected.emit()


@rpc("authority", "reliable")
func welcome(index: int) -> void:
	my_index = index
	log_line("joined as player %d" % index)
	joined.emit(index)


@rpc("authority", "reliable")
func rejected(reason: String) -> void:
	reject_reason = reason
	log_line(("ERROR rejected: " if reason != "full" else "rejected: ") + reason)
	disconnected.emit()


@rpc("authority", "reliable")
func match_info(player_names: Array) -> void:
	names = player_names
	match_info_received.emit(player_names)


@rpc("authority", "unreliable_ordered")
func snapshot(bytes: PackedByteArray) -> void:
	snapshot_received.emit(SnapCodec.decode(bytes))


@rpc("authority", "reliable")
func match_ended(res: Dictionary) -> void:
	match_ended_received.emit(res)


@rpc("authority", "reliable")
func action_result(res: Dictionary) -> void:
	action_feedback.emit(res)
