class_name ArenaView
extends Node3D
## Client presentation. Turns server snapshots (player index, slot index, path distance)
## into cosmetics. Own board at the bottom, opponent's board mirrored across the river at the top
## (Rush Royale layout: both portals on the left, both castles on the right).
## In the app flow (app_mode) it is created per match and emits finished() instead of quitting.

signal match_started
## res is the server result, or empty if the connection was lost before the match ended.
signal finished(res: Dictionary)

const INTERP_DELAY_S := 0.12
const TILT_FROM_VERTICAL_DEG := 40.0   # Canonical.json camera.tilt_from_vertical_deg
const LIGHT_AZIMUTH_DEG := 135.0       # Canonical.json key_light
const LIGHT_ELEVATION_DEG := 45.0
const VIEW_WIDTH_M := 10.9
const CAMERA_LOOK_Z := 0.35            # screen centre sits slightly below the river (bottom HUD is taller)
const SLOT_PICK_CM := 62.0
const TURN_SPEED := 14.0
## Figures face the camera (yaw PI turns local -Z toward +Z) and only lean/turn toward their
## target or walk direction, so faces stay readable from the 40 deg view, like the reference.
const FACE_CAMERA_YAW := PI
const TOWER_TURN_LIMIT := 1.1
const CREATURE_LEAN := 0.75

var camera: Camera3D
var hud: Hud
var art: ArenaArt
var fx: Fx
var app_mode := false
var force_bot := false

var _buf: Array = []
var _latest: Dictionary = {}
var _enemy_nodes: Dictionary = {}     # id -> creature dict + {board, max_hp, last_hp, pos}
var _tower_nodes: Dictionary = {}     # "p:slot" -> tower dict + {type, level, yaw, want_yaw}
var _kills: Dictionary = {}           # enemy id -> [killer, to_opponent] awaiting node removal
var _flights: Dictionary = {}         # my slot -> true while the summon card is in the air
var _now := 0.0
var _joined_at := -1.0
var _result: Dictionary = {}
var _counts := {"snapshots": 0, "shots": 0, "kills": 0, "base_hits": 0, "max_enemies": 0, "place_ok": 0, "place_fail": 0, "merge_ok": 0, "merge_fail": 0}
var _last_wave := -1
var _flash_mat := Toon.unlit(Color(1, 1, 1, 0.65), true)
var _perf := {"max_draw_calls": 0, "max_objects": 0, "min_fps": 1000, "samples": 0, "fps_sum": 0.0}
var _perf_t := 0.0

var _bot := false
var _bot_cd := 0.0
var _bot_pending := false
var _bot_rng := RandomNumberGenerator.new()
var _shots_at: Array = []
var _shot_prefix := ""
var _input_test := false
var _input_drag: Dictionary = {}
var _drag_src := -1
var _drag_pos := Vector3.ZERO
var _started := false
var _finished := false


func _ready() -> void:
	GameData.ensure_loaded()
	_bot = force_bot or Net.args.has("bot")
	# --input-test: the bot merges only through synthetic mouse drags (exercises the real input path).
	_input_test = Net.args.has("input-test")
	_bot_rng.seed = hash(Net.args.get("name", "bot")) + Time.get_ticks_usec()
	_shot_prefix = Net.args.get("shot-prefix", "")
	for s in String(Net.args.get("shots", "")).split(",", false):
		_shots_at.append(float(s))
	_build_world()
	hud = Hud.new()
	hud.camera = camera
	add_child(hud)
	hud.add_tower_pressed.connect(_on_add_tower)
	hud.upgrade_pressed.connect(func(i: int): Net.request_upgrade.rpc_id(1, i))
	hud.return_pressed.connect(_finish)
	hud.set_names(Net.names, Net.my_index)
	if Net.my_index >= 0:
		_joined_at = 0.0
	Net.joined.connect(_on_joined)
	Net.match_info_received.connect(_on_match_info)
	Net.snapshot_received.connect(_on_snapshot)
	Net.match_ended_received.connect(_on_match_ended)
	Net.action_feedback.connect(_on_action)
	Net.disconnected.connect(_on_disconnected)


func _exit_tree() -> void:
	for pair in [[Net.joined, _on_joined], [Net.match_info_received, _on_match_info],
			[Net.snapshot_received, _on_snapshot], [Net.match_ended_received, _on_match_ended],
			[Net.action_feedback, _on_action], [Net.disconnected, _on_disconnected]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _on_add_tower() -> void:
	Net.request_place.rpc_id(1)


func _on_match_info(player_names: Array) -> void:
	hud.set_names(player_names, Net.my_index)


func _on_disconnected() -> void:
	if not _result.is_empty():
		# Server closed the connection after the match (post-match timeout); just go home.
		if app_mode:
			_finish()
		return
	if Net.args.has("quit-on-end") and not app_mode:
		get_tree().quit(3)
		return
	hud.show_message("Connection lost")
	if app_mode:
		get_tree().create_timer(2.0).timeout.connect(_finish)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	finished.emit(_result)


# ---------------------------------------------------------------- world

func _build_world() -> void:
	art = ArenaArt.new()
	add_child(art)
	art.build()
	fx = Fx.new()
	add_child(fx)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = VIEW_WIDTH_M
	camera.near = 0.1
	camera.far = 200.0
	camera.rotation_degrees = Vector3(-(90.0 - TILT_FROM_VERTICAL_DEG), 0, 0)
	camera.position = Vector3(0, 0, CAMERA_LOOK_Z) + camera.basis.z * 40.0
	add_child(camera)
	fx.camera = camera


func _is_mine(board: int) -> bool:
	return board == Net.my_index or Net.my_index < 0 and board == 0


func _slot_world(p: int, slot: int) -> Vector3:
	return ArenaArt.board_world(_is_mine(p), BoardLayout.slot_pos(slot))


## Yaw that turns a figure's local -Z toward world direction d (x, z), clamped to an arc around
## facing the camera.
static func _yaw_for(d: Vector2, limit := TOWER_TURN_LIMIT) -> float:
	var full := atan2(-d.x, -d.y)
	return FACE_CAMERA_YAW + clampf(angle_difference(FACE_CAMERA_YAW, full), -limit, limit)


# ---------------------------------------------------------------- snapshots

func _on_joined(_idx: int) -> void:
	_joined_at = _now


func _on_snapshot(snap: Dictionary) -> void:
	if not _started:
		_started = true
		match_started.emit()
	_counts.snapshots += 1
	var by_id := {}
	for row in snap.en:
		by_id[int(row[0])] = row
	_buf.append({"rt": _now, "en": by_id})
	while _buf.size() > 12:
		_buf.pop_front()
	_latest = snap
	_counts.max_enemies = max(_counts.max_enemies, snap.en.size())
	_sync_towers(snap)
	for s in snap.sh:
		_counts.shots += 1
		_on_shot(int(s[0]), int(s[1]), int(s[2]))
	for k in snap.k:
		_counts.kills += 1
		_kills[int(k[0])] = [int(k[1]), bool(k[2])]
	for h in snap.h:
		_counts.base_hits += 1
		_on_base_hit(int(h[0]))
	if int(snap.ph) == MatchSim.Phase.WAVE and int(snap.r) != _last_wave:
		_last_wave = int(snap.r)
		hud.announce_wave(_last_wave + 1, _is_boss_round(_last_wave))
	hud.update_from(snap, Net.my_index)


func _is_boss_round(r: int) -> bool:
	if r < 0 or r >= GameData.rounds.size():
		return false
	for entry in GameData.rounds[r].spawns:
		if GameData.enemies[entry[0]].get("boss", false):
			return true
	return false


func _sync_towers(snap: Dictionary) -> void:
	var seen := {}
	for p in 2:
		for row in snap.tw[p]:
			var slot := int(row[0])
			var key := "%d:%d" % [p, slot]
			seen[key] = true
			var type: String = _tower_type(int(row[1]))
			var level := int(row[2])
			var n: Dictionary = _tower_nodes.get(key, {})
			if not n.is_empty() and n.type != type:
				# Merge result is a new random type: rebuild the figure in place.
				n.root.queue_free()
				_tower_nodes.erase(key)
				n = {}
			if n.is_empty():
				n = Figures.tower(type, level)
				add_child(n.root)
				n.root.position = _slot_world(p, slot)
				n.merge({"type": type, "level": level, "yaw": FACE_CAMERA_YAW, "want_yaw": FACE_CAMERA_YAW, "board": p, "slot": slot})
				n.body.rotation.y = n.yaw
				_tower_nodes[key] = n
				_apply_rank(n)
				if _is_mine(p) and _flights.has(slot):
					n.root.visible = false   # revealed when the summon card lands
				else:
					_reveal_tower(n, level > 1)
			elif n.level != level:
				n.level = level
				Figures.set_pips(n.pips, level)
				_apply_rank(n)
				_pop_in(n.root, true)
				if _is_mine(p):
					Sfx.play("merge", 0.0)
					Sfx.buzz(25)
			var aim := float(row[3])
			if aim < 8.0:
				n.want_yaw = _yaw_for(ArenaArt.heading_world(_is_mine(p), Vector2.from_angle(aim)))
	for key in _tower_nodes.keys():
		if not seen.has(key):
			var n: Dictionary = _tower_nodes[key]
			fx.puff(n.root.position, Color("fff3b0"), 5, 0.08)
			n.root.queue_free()
			_tower_nodes.erase(key)
			if _drag_src >= 0 and key == "%d:%d" % [Net.my_index, _drag_src]:
				_drag_src = -1


## Higher merge ranks read as stronger: the figure grows a little per rank.
func _apply_rank(n: Dictionary) -> void:
	var model: Node3D = n.body.get_child(0)
	model.scale = Vector3.ONE * (1.0 + 0.1 * (int(n.level) - 1))


func _reveal_tower(n: Dictionary, merged: bool) -> void:
	n.root.visible = true
	_pop_in(n.root, merged)
	fx.ring(n.root.position, Figures.look_color(GameData.towers[n.type]).lightened(0.4), 0.7, 0.35)
	if merged:
		fx.puff(n.root.position, Color("fff3b0"), 8, 0.1)
	if _is_mine(n.board):
		Sfx.play("merge" if merged else "summon", 0.04)
		if merged:
			Sfx.buzz(25)


func _on_summon_landed(slot: int) -> void:
	_flights.erase(slot)
	var key := "%d:%d" % [Net.my_index, slot]
	if _tower_nodes.has(key):
		var n: Dictionary = _tower_nodes[key]
		_reveal_tower(n, n.level > 1)
		fx.puff(n.root.position, Color.WHITE, 6, 0.09)


func _pop_in(root: Node3D, big: bool) -> void:
	root.scale = Vector3(0.2, 0.2, 0.2)
	var t := create_tween()
	t.tween_property(root, "scale", Vector3.ONE * (1.25 if big else 1.1), 0.12).set_ease(Tween.EASE_OUT)
	t.tween_property(root, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _tower_type(i: int) -> String:
	var keys: Array = GameData.towers.keys()
	keys.sort()
	return keys[i]


func _enemy_type(i: int) -> String:
	var keys: Array = GameData.enemies.keys()
	keys.sort()
	return keys[i]


func _process(delta: float) -> void:
	_now += delta
	_sample_perf(delta)
	_update_enemies()
	_update_towers(delta)
	_bot_tick(delta)
	_input_drag_tick(delta)
	_screenshot_tick()


## Render cost sampled once a second during the match (reported in CLIENT_RESULT) so the
## procedural placeholder art can be judged against the mobile budget.
func _sample_perf(delta: float) -> void:
	_perf_t += delta
	if _perf_t < 1.0 or not _started or not _result.is_empty():
		return
	_perf_t = 0.0
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var obj := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var fps := Engine.get_frames_per_second()
	_perf.max_draw_calls = maxi(_perf.max_draw_calls, dc)
	_perf.max_objects = maxi(_perf.max_objects, obj)
	if _perf.samples > 2:
		_perf.min_fps = mini(_perf.min_fps, int(fps))
	_perf.samples += 1
	_perf.fps_sum += fps


func _update_towers(delta: float) -> void:
	var drag_key := "%d:%d" % [Net.my_index, _drag_src] if _drag_src >= 0 else ""
	var drag_def := {}
	if drag_key != "" and _tower_nodes.has(drag_key):
		drag_def = _tower_nodes[drag_key]
	for key in _tower_nodes:
		var n: Dictionary = _tower_nodes[key]
		n.yaw = lerp_angle(n.yaw, n.want_yaw, minf(1.0, delta * TURN_SPEED))
		n.body.rotation.y = n.yaw
		# Idle breathing so the board never looks frozen.
		var ph := float(hash(key) % 100) * 0.1
		n.body.scale.y = lerpf(n.body.scale.y, 1.0 + sin(_now * 3.0 + ph) * 0.03, minf(1.0, delta * 10.0))
		var lift := 0.0
		var ring_glow := 1.0
		if not drag_def.is_empty():
			if key == drag_key:
				lift = 0.0
			elif n.board == Net.my_index and n.type == drag_def.type and n.level == drag_def.level \
					and n.level < int(GameData.rules.max_tower_level):
				ring_glow = 1.0 + 0.35 * (0.5 + 0.5 * sin(_now * 12.0))
		n.ring.scale = Vector3.ONE * ring_glow
		if key == drag_key:
			n.body.global_position = n.body.global_position.lerp(_drag_pos + Vector3(0, 0.45, 0), minf(1.0, delta * 25.0))
		else:
			n.body.position = n.body.position.lerp(Vector3(0, 0.12 + lift, 0), minf(1.0, delta * 18.0))


func _update_enemies() -> void:
	if _buf.is_empty():
		return
	var rt := _now - INTERP_DELAY_S
	var older: Dictionary = _buf[0]
	var newer: Dictionary = _buf[0]
	for i in _buf.size():
		if _buf[i].rt <= rt:
			older = _buf[i]
			newer = _buf[min(i + 1, _buf.size() - 1)]
	var span: float = newer.rt - older.rt
	var a := 1.0 if span <= 0.0 else clampf((rt - older.rt) / span, 0.0, 1.0)
	var live := {}
	for id in newer.en:
		var row: Array = newer.en[id]
		var d := float(row[3])
		if older.en.has(id):
			d = lerpf(float(older.en[id][3]), d, a)
		live[id] = true
		_place_enemy(id, row, d)
	for id in _enemy_nodes.keys():
		if not live.has(id):
			_remove_enemy(id)


func _remove_enemy(id: int) -> void:
	var n: Dictionary = _enemy_nodes[id]
	var pos: Vector3 = n.root.position
	if _kills.has(id):
		var k: Array = _kills[id]
		_kills.erase(id)
		fx.puff(pos, Color.WHITE, 7 if n.scale < 1.5 else 14, 0.11 * maxf(1.0, n.scale * 0.7))
		Sfx.play("kill", 0.12, 0.0 if _is_mine(n.board) else -12.0)
		if n.scale >= 1.5:
			fx.shake(0.12, 0.3)
		if k[1]:
			# Recycled: the kill reappears on the killer's opponent's board.
			var target_mine := not _is_mine(int(k[0]))
			var portal := ArenaArt.board_world(target_mine, BoardLayout.path_points()[0] + Vector2(0, 60))
			fx.recycle_orb(pos, portal, art.pulse_portal.bind(target_mine))
	n.root.queue_free()
	_enemy_nodes.erase(id)


func _place_enemy(id: int, row: Array, dist: float) -> void:
	var board := int(row[1])
	var n: Dictionary = _enemy_nodes.get(id, {})
	if n.is_empty():
		var type := _enemy_type(int(row[2]))
		n = Figures.creature(type)
		n.body.rotation.y = FACE_CAMERA_YAW
		add_child(n.root)
		n.merge({"board": board, "max_hp": float(GameData.enemies[type].hp), "last_frac": 1.0,
			"phase": randf() * TAU, "speed": float(GameData.enemies[type].speed), "flash": 0.0})
		n.hp_label.position = Vector3(-0.3 * n.scale - 0.12, 0.25 * n.scale, 0)
		_enemy_nodes[id] = n
		n.root.scale = Vector3.ONE * 0.3
		create_tween().tween_property(n.root, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if dist < 30.0:
			art.pulse_portal(_is_mine(board))
		if n.scale >= 2.0:
			# Boss entrance: big pop, shake, rumble.
			n.root.scale = Vector3.ONE * 0.05
			fx.shake(0.15, 0.5)
			fx.ring(n.root.position, Color("c77dff"), 1.6, 0.5, 2.0)
			Sfx.play("boss", 0.0, 0.0 if _is_mine(board) else -8.0)
	var mine := _is_mine(board)
	var foot := ArenaArt.board_world(mine, BoardLayout.path_point(dist))
	var ahead := ArenaArt.board_world(mine, BoardLayout.path_point(dist + 5.0))
	n.root.position = foot
	var dir := Vector2(ahead.x - foot.x, ahead.z - foot.z)
	if dir.length_squared() > 1e-8:
		n.body.rotation.y = lerp_angle(n.body.rotation.y, FACE_CAMERA_YAW + dir.normalized().x * CREATURE_LEAN, 0.2)
	# Waddle: hop + squash, speed-scaled.
	var t: float = _now * (6.0 + n.speed * 0.02) + n.phase
	var hop := absf(sin(t))
	n.body.position.y = hop * 0.06 * n.scale
	var sq := 1.0 - (1.0 - hop) * 0.12
	var hit: float = n.flash
	n.body.scale = Vector3(n.scale * (2.0 - sq + hit * 0.25), n.scale * (sq - hit * 0.2), n.scale * (2.0 - sq))
	n.flash = maxf(0.0, n.flash - get_process_delta_time() * 6.0)
	var frac := float(row[4])
	if frac < n.last_frac - 0.001:
		n.flash = 1.0
	n.blob.material_overlay = _flash_mat if n.flash > 0.45 else null
	n.last_frac = frac
	n.hp_label.text = str(maxi(1, int(ceil(frac * n.max_hp))))
	var flags := int(row[5])
	n.recycled.visible = flags & 1 != 0
	n.slowed.visible = flags & 2 != 0


# ---------------------------------------------------------------- events

func _on_shot(p: int, slot: int, enemy_id: int) -> void:
	var key := "%d:%d" % [p, slot]
	if not _tower_nodes.has(key):
		return
	var n: Dictionary = _tower_nodes[key]
	# Recoil punch on the figure.
	n.body.scale = Vector3(1.18, 0.82, 1.18)
	create_tween().tween_property(n.body, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not _enemy_nodes.has(enemy_id):
		return
	var kind := str(GameData.towers[n.type].get("look", {}).get("shot", "arrow"))
	var from: Vector3 = n.root.position + Vector3(0, 0.65, 0)
	fx.shoot(kind, from, _enemy_aim.bind(enemy_id), enemy_id)
	if _is_mine(p):
		Sfx.play("shot_" + kind, 0.1, -5.0)


## Current aim point on an enemy (chest height), or null once it is gone.
func _enemy_aim(enemy_id: int):
	if not _enemy_nodes.has(enemy_id):
		return null
	var n: Dictionary = _enemy_nodes[enemy_id]
	return n.root.position + Vector3(0, 0.28 * n.scale, 0)


func _on_base_hit(board: int) -> void:
	var mine := _is_mine(board)
	art.hit_castle(mine)
	var castle_pos := ArenaArt.board_world(mine, BoardLayout.path_points()[-1] + Vector2(0, 75))
	fx.puff(castle_pos + Vector3(0, 0.4, 0), Color("ff6b5b"), 10, 0.13)
	if mine:
		fx.shake(0.2, 0.35)
		Sfx.buzz(60)
	hud.base_hit(mine)


# ---------------------------------------------------------------- input (drag to merge)

func _unhandled_input(event: InputEvent) -> void:
	if Net.my_index < 0 or _latest.is_empty():
		return
	if event is InputEventMouseMotion and _drag_src >= 0:
		var g = _ground_point(event.position)
		if g != null:
			_drag_pos = g
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var slot := _slot_under(event.position)
		if event.pressed:
			_drag_src = slot if _has_my_tower(slot) else -1
			if _drag_src >= 0:
				var g = _ground_point(event.position)
				_drag_pos = g if g != null else _slot_world(Net.my_index, slot)
		elif _drag_src >= 0:
			if slot >= 0 and slot != _drag_src and _has_my_tower(slot):
				Net.request_merge.rpc_id(1, _drag_src, slot)
			_drag_src = -1


func _ground_point(screen_pos: Vector2):
	var o := camera.project_ray_origin(screen_pos)
	var d := camera.project_ray_normal(screen_pos)
	if absf(d.y) < 1e-5:
		return null
	return o + d * (-o.y / d.y)


func _slot_under(screen_pos: Vector2) -> int:
	var hit = _ground_point(screen_pos)
	if hit == null:
		return -1
	var local := ArenaArt.world_to_mine(hit)
	for s in GameData.slot_count():
		if BoardLayout.slot_pos(s).distance_to(local) <= SLOT_PICK_CM:
			return s
	return -1


func _has_my_tower(slot: int) -> bool:
	return slot >= 0 and _tower_nodes.has("%d:%d" % [Net.my_index, slot])


func _on_action(res: Dictionary) -> void:
	_bot_pending = false
	var key := "%s_%s" % [res.get("action", "?"), "ok" if res.get("ok", false) else "fail"]
	if _counts.has(key):
		_counts[key] += 1
	if not res.get("ok", false):
		hud.action_failed(str(res.get("action", "")), str(res.get("reason", "")))
	elif res.get("action", "") == "place":
		var slot := int(res.slot)
		var tkey := "%d:%d" % [Net.my_index, slot]
		if _tower_nodes.has(tkey):
			_tower_nodes[tkey].root.visible = false   # snapshot beat the reply: hide until landing
		_flights[slot] = true
		hud.fly_card(camera.unproject_position(_slot_world(Net.my_index, slot) + Vector3(0, 0.4, 0)), _on_summon_landed.bind(slot))


# ---------------------------------------------------------------- bot

func _bot_tick(delta: float) -> void:
	if not _bot or _latest.is_empty() or Net.my_index < 0 or not _result.is_empty():
		return
	_bot_cd -= delta
	if _bot_cd > 0.0 or _bot_pending:
		return
	# Think interval is in sim seconds; --bot-speed matches the server's --timescale.
	_bot_cd = _bot_rng.randf_range(0.3, 1.2) / float(Net.args.get("bot-speed", "1"))
	var me: Array = _latest.p[Net.my_index]
	var towers: Array = _latest.tw[Net.my_index]
	if _input_test:
		if _input_drag.is_empty():
			_start_input_drag(towers)
		if int(me[0]) >= int(me[2]) and towers.size() < GameData.slot_count():
			_bot_pending = true
			Net.request_place.rpc_id(1)
		return
	# Merge pairs of the same type/level now and then, always when the board is nearly full.
	if towers.size() >= 12 or _bot_rng.randf() < 0.15:
		var by_key := {}
		for row in towers:
			if int(row[2]) >= int(GameData.rules.max_tower_level):
				continue
			var k := "%d:%d" % [int(row[1]), int(row[2])]
			if by_key.has(k):
				_bot_pending = true
				Net.request_merge.rpc_id(1, int(by_key[k]), int(row[0]))
				return
			by_key[k] = int(row[0])
	if int(me[0]) >= int(me[2]) and towers.size() < GameData.slot_count():
		_bot_pending = true
		Net.request_place.rpc_id(1)
	elif towers.size() >= 8 and _bot_rng.randf() < 0.1:
		var i := _bot_rng.randi_range(0, me[5].size() - 1)
		var costs: Array = GameData.rules.card_upgrade_costs
		var lvl := int(me[5][i])
		if lvl <= costs.size() and int(me[0]) >= int(costs[lvl - 1]):
			_bot_pending = true
			Net.request_upgrade.rpc_id(1, i)


## Synthetic drag from one tower to a matching one, fed through Input like a real finger/mouse.
func _start_input_drag(towers: Array) -> void:
	var by_key := {}
	for row in towers:
		if int(row[2]) >= int(GameData.rules.max_tower_level):
			continue
		var k := "%d:%d" % [int(row[1]), int(row[2])]
		if by_key.has(k):
			var a := camera.unproject_position(_slot_world(Net.my_index, int(by_key[k])))
			var b := camera.unproject_position(_slot_world(Net.my_index, int(row[0])))
			_input_drag = {"a": a, "b": b, "t": 0.0}
			_counts["input_drags"] = int(_counts.get("input_drags", 0)) + 1
			_mouse(a, true)
			return
		by_key[k] = int(row[0])


func _input_drag_tick(delta: float) -> void:
	if _input_drag.is_empty():
		return
	_input_drag.t += delta
	var k := clampf(_input_drag.t / 0.35, 0.0, 1.0)
	var p: Vector2 = _input_drag.a.lerp(_input_drag.b, k)
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mm)
	if k >= 1.0:
		_mouse(p, false)
		_input_drag = {}


func _mouse(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	e.global_position = p
	Input.parse_input_event(e)


# ---------------------------------------------------------------- end / screenshots

func _on_match_ended(res: Dictionary) -> void:
	if not _result.is_empty():
		return
	_result = res
	hud.show_result(res, Net.my_index, app_mode)
	var mine: Array = _latest.p[Net.my_index] if not _latest.is_empty() else []
	var report := {
		"index": Net.my_index, "winner": res.winner, "reason": res.reason,
		"server_base_hp": res.base_hp, "server_gold": res.gold,
		"last_snapshot_me": mine, "counts": _counts,
		"perf": {"max_draw_calls": _perf.max_draw_calls, "max_objects": _perf.max_objects,
			"min_fps": _perf.min_fps, "avg_fps": snappedf(_perf.fps_sum / maxf(1.0, _perf.samples), 0.1)},
	}
	Net.log_line("CLIENT_RESULT " + JSON.stringify(report))
	if _shot_prefix != "":
		await get_tree().create_timer(0.8).timeout
		await _save_shot(_shot_prefix + "_end.png")
	if Net.args.has("quit-on-end") and not app_mode:
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)
	elif app_mode and _bot:
		# Bots linger on the result screen briefly so a watcher can read it.
		get_tree().create_timer(4.0).timeout.connect(_finish)


func _screenshot_tick() -> void:
	if _shot_prefix == "" or _shots_at.is_empty() or _joined_at < 0.0:
		return
	if _now - _joined_at >= float(_shots_at[0]):
		var t: float = _shots_at.pop_front()
		_save_shot("%s_%03d.png" % [_shot_prefix, int(t)])


func _save_shot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	Net.log_line("screenshot %s -> %s" % [path, error_string(err)])
