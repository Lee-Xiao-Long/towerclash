class_name ArenaView
extends Node3D
## Client presentation. Turns server snapshots (player index, slot index, path distance)
## into cosmetics. Own board at the bottom, opponent's board rotated 180 deg at the top.

const BOARD_OFFSET_M := 4.0
const INTERP_DELAY_S := 0.12
const TILT_FROM_VERTICAL_DEG := 40.0   # Canonical.json camera.tilt_from_vertical_deg
const LIGHT_AZIMUTH_DEG := 135.0       # Canonical.json key_light
const LIGHT_ELEVATION_DEG := 45.0
const VIEW_WIDTH_M := 10.6
const BAR_PUSH_M := 3.1

var camera: Camera3D
var cam_basis: Basis
var hud: Hud

var _buf: Array = []
var _latest: Dictionary = {}
var _enemy_nodes: Dictionary = {}     # id -> {sprite, bar, fill}
var _tower_nodes: Dictionary = {}     # "p:slot" -> {sprite, label, type, level}
var _gates: Array = [null, null]
var _tracers: Array = []
var _floaters: Array = []
var _now := 0.0
var _joined_at := -1.0
var _result: Dictionary = {}
var _counts := {"snapshots": 0, "shots": 0, "kills": 0, "base_hits": 0, "max_enemies": 0, "place_ok": 0, "place_fail": 0, "merge_ok": 0, "merge_fail": 0}

var _bot := false
var _bot_cd := 0.0
var _bot_pending := false
var _bot_rng := RandomNumberGenerator.new()
var _shots_at: Array = []
var _shot_prefix := ""
var _drag_src := -1


func _ready() -> void:
	GameData.ensure_loaded()
	_bot = Net.args.has("bot")
	_bot_rng.seed = hash(Net.args.get("name", "bot")) + Time.get_ticks_usec()
	_shot_prefix = Net.args.get("shot-prefix", "")
	for s in String(Net.args.get("shots", "")).split(",", false):
		_shots_at.append(float(s))
	_build_world()
	hud = Hud.new()
	add_child(hud)
	hud.add_tower_pressed.connect(func(): Net.request_place.rpc_id(1))
	Net.joined.connect(_on_joined)
	Net.snapshot_received.connect(_on_snapshot)
	Net.match_ended_received.connect(_on_match_ended)
	Net.action_feedback.connect(_on_action)
	Net.disconnected.connect(func():
		if _result.is_empty() and Net.args.has("quit-on-end"):
			get_tree().quit(3))


# ---------------------------------------------------------------- world

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.72, 0.9)
	e.ambient_light_energy = 0.45
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	var az := deg_to_rad(LIGHT_AZIMUTH_DEG)
	var el := deg_to_rad(LIGHT_ELEVATION_DEG)
	var from := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	add_child(sun)
	sun.look_at_from_position(from * 10.0, Vector3.ZERO, Vector3.UP)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = VIEW_WIDTH_M
	camera.near = 0.1
	camera.far = 200.0
	camera.rotation_degrees = Vector3(-(90.0 - TILT_FROM_VERTICAL_DEG), 0, 0)
	camera.position = camera.basis.z * 40.0
	add_child(camera)
	cam_basis = camera.basis

	for p in 2:
		_build_board(p == 0)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _box(size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(c)
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return mi


## mine = the board shown at the bottom (the local player's). Board-local geometry is
## identical for both; only the world transform differs.
func _build_board(mine: bool) -> void:
	var tint := Color(0.33, 0.5, 0.3) if mine else Color(0.42, 0.36, 0.3)
	var centre := _board_world(mine, Vector2.ZERO)
	_box(Vector3(10.4, 0.1, 7.6), centre + Vector3(0, -0.05, 0), tint)
	for s in GameData.slot_count():
		var p := _board_world(mine, BoardLayout.slot_pos(s))
		_box(Vector3(1.1, 0.04, 1.1), p + Vector3(0, 0.02, 0), tint.lightened(0.25))
	var pts := BoardLayout.path_points()
	for i in range(1, pts.size()):
		var a := _board_world(mine, pts[i - 1])
		var b := _board_world(mine, pts[i])
		var mid := (a + b) * 0.5
		var size := Vector3(absf(b.x - a.x) + 0.8, 0.03, absf(b.z - a.z) + 0.8)
		_box(size, mid + Vector3(0, 0.015, 0), Color(0.55, 0.45, 0.3))
	_box(Vector3(0.9, 0.3, 0.9), _board_world(mine, pts[0]) + Vector3(0, 0.15, 0), Color(0.3, 0.3, 0.35))
	var gate := _box(Vector3(1.0, 0.8, 0.5), _board_world(mine, pts[pts.size() - 1]) + Vector3(0, 0.4, 0), Color(0.75, 0.7, 0.6))
	gate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_gates[0 if mine else 1] = gate


## Board-local cm -> world metres. "mine" boards sit at the bottom, unrotated.
func _board_world(mine: bool, v: Vector2) -> Vector3:
	if mine:
		return Vector3(v.x / 100.0, 0, v.y / 100.0 + BOARD_OFFSET_M)
	return Vector3(-v.x / 100.0, 0, -v.y / 100.0 - BOARD_OFFSET_M)


func _is_mine(board: int) -> bool:
	return board == Net.my_index or Net.my_index < 0 and board == 0


func _heading_world(board: int, v: Vector2) -> Vector2:
	return v if _is_mine(board) else -v


# ---------------------------------------------------------------- snapshots

func _on_joined(_idx: int) -> void:
	_joined_at = _now


func _on_snapshot(snap: Dictionary) -> void:
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
		_tracer(int(s[0]), int(s[1]), int(s[2]))
	for k in snap.k:
		_counts.kills += 1
		_floater(int(k[0]), "+recycle" if k[2] else "x")
	for h in snap.h:
		_counts.base_hits += 1
		_flash_gate(int(h[0]))
	hud.update_from(snap, Net.my_index)


func _sync_towers(snap: Dictionary) -> void:
	var seen := {}
	for p in 2:
		for row in snap.tw[p]:
			var key := "%d:%d" % [p, int(row[0])]
			seen[key] = true
			var type: String = _tower_type(int(row[1]))
			var level := int(row[2])
			var n: Dictionary = _tower_nodes.get(key, {})
			if n.is_empty():
				var spr := DirSprite.new()
				add_child(spr)
				spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				spr.setup(SpriteSheet.get_sheet("StandIn_Blocky"), "Idle", cam_basis)
				spr.set_foot(_board_world(_is_mine(p), BoardLayout.slot_pos(int(row[0]))))
				spr.set_heading(Vector2(0, 1) if _is_mine(p) else Vector2(0, -1))
				var lbl := Label3D.new()
				lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lbl.font_size = 48
				lbl.pixel_size = 0.005
				lbl.outline_size = 12
				lbl.no_depth_test = true
				lbl.position = spr.position + cam_basis.y * 0.85
				add_child(lbl)
				n = {"sprite": spr, "label": lbl, "type": "", "level": 0}
				_tower_nodes[key] = n
			if n.type != type or n.level != level:
				n.type = type
				n.level = level
				var c: Array = GameData.towers[type].tint
				n.sprite.modulate = Color(c[0], c[1], c[2])
				n.label.text = "%s %s" % [type, "*".repeat(level)]
				n.label.modulate = Color(c[0], c[1], c[2])
			var aim := float(row[3])
			if aim < 8.0:
				n.sprite.set_heading(_heading_world(p, Vector2.from_angle(aim)))
	for key in _tower_nodes.keys():
		if not seen.has(key):
			_tower_nodes[key].sprite.queue_free()
			_tower_nodes[key].label.queue_free()
			_tower_nodes.erase(key)


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
	_update_enemies()
	_update_fx(delta)
	_bot_tick(delta)
	_screenshot_tick()


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
			_enemy_nodes[id].root.queue_free()
			_enemy_nodes.erase(id)


func _place_enemy(id: int, row: Array, dist: float) -> void:
	var board := int(row[1])
	var n: Dictionary = _enemy_nodes.get(id, {})
	if n.is_empty():
		var def: Dictionary = GameData.enemies[_enemy_type(int(row[2]))]
		var root := Node3D.new()
		add_child(root)
		var spr := DirSprite.new()
		root.add_child(spr)
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sheet := SpriteSheet.get_sheet(def.sprite)
		spr.setup(sheet, def.anim, cam_basis)
		var bar := Node3D.new()
		root.add_child(bar)
		bar.basis = cam_basis
		var back := _quad(Vector2(0.5, 0.06), Color(0.1, 0.1, 0.1))
		bar.add_child(back)
		var fill := _quad(Vector2(0.5, 0.06), Color(0.3, 1.0, 0.3))
		fill.position.z = 0.01
		bar.add_child(fill)
		var top := (sheet.pivot.y - sheet.content_rect.position.y) * sheet.cm_per_pixel / 100.0 + 0.08
		var c: Array = def.tint
		n = {"root": root, "sprite": spr, "bar": bar, "fill": fill, "top": top, "tint": Color(c[0], c[1], c[2])}
		_enemy_nodes[id] = n
	var mine := _is_mine(board)
	var foot := _board_world(mine, BoardLayout.path_point(dist))
	var ahead := _board_world(mine, BoardLayout.path_point(dist + 5.0))
	n.sprite.set_foot(foot)
	n.sprite.set_heading(Vector2(ahead.x - foot.x, ahead.z - foot.z))
	n.bar.position = foot + cam_basis.z * BAR_PUSH_M + cam_basis.y * n.top
	var frac := float(row[4])
	n.fill.scale.x = maxf(frac, 0.001)
	n.fill.position.x = -0.25 * (1.0 - frac)
	var flags := int(row[5])
	var col: Color = n.tint
	if flags & 1:
		col = col.lerp(Color(0.4, 0.9, 1.0), 0.6) * 1.3
	if flags & 2:
		col = col.lerp(Color(0.3, 0.5, 1.0), 0.4)
	n.sprite.modulate = col


func _quad(size: Vector2, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- fx

func _tracer(p: int, slot: int, enemy_id: int) -> void:
	if not _enemy_nodes.has(enemy_id):
		return
	var from := _board_world(_is_mine(p), BoardLayout.slot_pos(slot)) + Vector3(0, 0.55, 0)
	var en: Dictionary = _enemy_nodes[enemy_id]
	var to: Vector3 = en.sprite.position - cam_basis.z * DirSprite.CAMERA_PUSH_M + Vector3(0, 0.35, 0)
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 0.6)
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	im.surface_add_vertex(from + cam_basis.z * 2.9)
	im.surface_add_vertex(to + cam_basis.z * 2.9)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_tracers.append({"node": mi, "t": 0.08})


func _floater(enemy_id: int, text: String) -> void:
	if not _enemy_nodes.has(enemy_id):
		return
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 40
	lbl.pixel_size = 0.005
	lbl.outline_size = 10
	lbl.modulate = Color(0.5, 1, 1) if text.begins_with("+") else Color(1, 0.6, 0.4)
	lbl.position = _enemy_nodes[enemy_id].bar.position
	add_child(lbl)
	_floaters.append({"node": lbl, "t": 0.8})


func _flash_gate(board: int) -> void:
	var g: MeshInstance3D = _gates[0 if _is_mine(board) else 1]
	var m: StandardMaterial3D = (g.mesh as BoxMesh).material
	m.albedo_color = Color(1, 0.2, 0.2)
	get_tree().create_timer(0.3).timeout.connect(func(): m.albedo_color = Color(0.75, 0.7, 0.6))


func _update_fx(delta: float) -> void:
	for t in _tracers.duplicate():
		t.t -= delta
		if t.t <= 0.0:
			t.node.queue_free()
			_tracers.erase(t)
	for f in _floaters.duplicate():
		f.t -= delta
		f.node.position += cam_basis.y * delta * 0.6
		if f.t <= 0.0:
			f.node.queue_free()
			_floaters.erase(f)


# ---------------------------------------------------------------- input (drag to merge)

func _unhandled_input(event: InputEvent) -> void:
	if Net.my_index < 0 or _latest.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var slot := _slot_under(event.position)
		if event.pressed:
			_drag_src = slot if _has_my_tower(slot) else -1
		elif _drag_src >= 0:
			if slot >= 0 and slot != _drag_src and _has_my_tower(slot):
				Net.request_merge.rpc_id(1, _drag_src, slot)
			_drag_src = -1


func _slot_under(screen_pos: Vector2) -> int:
	var o := camera.project_ray_origin(screen_pos)
	var d := camera.project_ray_normal(screen_pos)
	if absf(d.y) < 1e-5:
		return -1
	var hit := o + d * (-o.y / d.y)
	var local := Vector2(hit.x * 100.0, (hit.z - BOARD_OFFSET_M) * 100.0)
	for s in GameData.slot_count():
		if BoardLayout.slot_pos(s).distance_to(local) <= 60.0:
			return s
	return -1


func _has_my_tower(slot: int) -> bool:
	return slot >= 0 and _tower_nodes.has("%d:%d" % [Net.my_index, slot])


func _on_action(res: Dictionary) -> void:
	_bot_pending = false
	var key := "%s_%s" % [res.get("action", "?"), "ok" if res.get("ok", false) else "fail"]
	if _counts.has(key):
		_counts[key] += 1


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


# ---------------------------------------------------------------- end / screenshots

func _on_match_ended(res: Dictionary) -> void:
	if not _result.is_empty():
		return
	_result = res
	hud.show_result(res, Net.my_index)
	var mine: Array = _latest.p[Net.my_index] if not _latest.is_empty() else []
	var report := {
		"index": Net.my_index, "winner": res.winner, "reason": res.reason,
		"server_base_hp": res.base_hp, "server_gold": res.gold,
		"last_snapshot_me": mine, "counts": _counts,
	}
	Net.log_line("CLIENT_RESULT " + JSON.stringify(report))
	if _shot_prefix != "":
		await get_tree().create_timer(0.5).timeout
		await _save_shot(_shot_prefix + "_end.png")
	if Net.args.has("quit-on-end"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


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
