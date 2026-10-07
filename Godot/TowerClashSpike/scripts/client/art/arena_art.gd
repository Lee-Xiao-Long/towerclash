class_name ArenaArt
extends Node3D
## Static arena dressing in the Rush Royale baseline style: checkered 5x3 grid in a stone frame,
## sand path around three sides, purple spawn portal, stone castle at the gate, a river between
## the boards and cartoon scenery. Board-local geometry comes from BoardLayout (cm); the world
## mapping is board_world(). The opponent board is mirrored across the river (not rotated), so
## both players see the portal on the left and the castle on the right, like the reference.

const BOARD_OFFSET_M := 4.6
const RIVER_HALF_M := 0.62
const PATH_W := 1.1
const TILE_GAP := 0.05

const GRASS := Color("5fae3f")
const GRASS_DARK := Color("4b9733")
const TILE_A := Color("a9d85c")
const TILE_B := Color("9dcd50")
const GRID_BASE := Color("7fb240")
const STUD := Color("e8eccf")
const SAND := Color("f2c27e")
const SAND_EDGE := Color("d99a5c")
const STONE := Color("d9d2c7")
const STONE_DARK := Color("bdb4a6")
const CASTLE := Color("b8b3ad")
const CASTLE_DARK := Color("8f8a86")
const WOOD := Color("8a5532")
const BANK := Color("7a4f31")
const CLIFF := Color("c98468")
const CLIFF_TOP := Color("79c255")
const LEAF := Color("3f9a3c")
const LEAF_LIGHT := Color("58b546")
const TRUNK := Color("7b4a2c")
const MINE_COLOR := Color("3a8ee6")
const OPP_COLOR := Color("e24a4a")

var portals: Array = [null, null]   # [mine, opponent] portal shader materials
var castles: Array = [null, null]   # [mine, opponent] castle root nodes


## Board-local cm -> world metres. mine = the local player's board (bottom of the screen).
static func board_world(mine: bool, v: Vector2) -> Vector3:
	var z := v.y / 100.0 + BOARD_OFFSET_M
	return Vector3(v.x / 100.0, 0.0, z if mine else -z)


## Board-local direction -> world XZ direction (the opponent board is mirrored in z).
static func heading_world(mine: bool, v: Vector2) -> Vector2:
	return v if mine else Vector2(v.x, -v.y)


## World point on the ground -> board-local cm for the local player's board.
static func world_to_mine(p: Vector3) -> Vector2:
	return Vector2(p.x * 100.0, (p.z - BOARD_OFFSET_M) * 100.0)


func build() -> void:
	_environment()
	_ground()
	_river()
	for mine: bool in [true, false]:
		_board(mine)
	_scenery()


func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = GRASS_DARK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.86, 0.9, 1.0)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_strength = 0.9
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.1
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	var az := deg_to_rad(ArenaView.LIGHT_AZIMUTH_DEG)
	var el := deg_to_rad(ArenaView.LIGHT_ELEVATION_DEG)
	var from := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	add_child(sun)
	sun.look_at_from_position(from * 20.0, Vector3.ZERO, Vector3.UP)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 0.68
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0


func _ground() -> void:
	Toon.box(self, Vector3(40, 0.1, 50), Vector3(0, -0.06, 0), GRASS, false)
	# Lighter grass mats under each board area.
	for s: float in [1.0, -1.0]:
		Toon.box(self, Vector3(11.4, 0.02, 8.6), Vector3(0, -0.005, s * (BOARD_OFFSET_M + 0.1)), Color("67b745"), false)


func _river() -> void:
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, RIVER_HALF_M * 2.0)
	water.mesh = pm
	water.material_override = Toon.shader_mat("res://assets/shaders/water.gdshader", {"bank_z": RIVER_HALF_M})
	water.position = Vector3(0, -0.04, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	for s: float in [1.0, -1.0]:
		Toon.box(self, Vector3(40, 0.12, 0.16), Vector3(0, -0.02, s * (RIVER_HALF_M + 0.06)), BANK, false)
	# A few stepping stones and a rubber duck, because the reference has one.
	for p in [Vector3(-3.6, 0, 0.25), Vector3(3.9, 0, -0.2), Vector3(4.3, 0, 0.3)]:
		var st := Toon.sphere(self, 0.13, p, Color("9aa3a8"))
		st.scale = Vector3(1.3, 0.45, 1.0)
	_duck(Vector3(-1.2, -0.02, 0.05))


func _duck(p: Vector3) -> void:
	var d := Node3D.new()
	d.position = p
	add_child(d)
	var body := Toon.sphere(d, 0.13, Vector3(0, 0.06, 0), Color("ffd23c"), 0.012)
	body.scale = Vector3(1.25, 0.8, 1.0)
	Toon.sphere(d, 0.08, Vector3(0.1, 0.17, 0), Color("ffd23c"), 0.012)
	var beak := Toon.sphere(d, 0.04, Vector3(0.18, 0.16, 0), Color("ff8a2a"))
	beak.scale = Vector3(1.4, 0.6, 1.0)
	Toon.sphere(d, 0.016, Vector3(0.14, 0.2, 0.05), Color("222222"))


func _w(mine: bool, x: float, y: float) -> Vector3:
	return board_world(mine, Vector2(x, y))


func _board(mine: bool) -> void:
	var cols := int(GameData.rules.slot_cols)
	var rows := int(GameData.rules.slot_rows)
	var pitch := float(GameData.rules.slot_pitch_cm) / 100.0
	var gw := cols * pitch
	var gh := rows * pitch
	var centre := board_world(mine, Vector2.ZERO)

	# Path: darker sand rim under a lighter sand band, rounded at the corners.
	var pts := BoardLayout.path_points()
	for layer in [[PATH_W + 0.14, SAND_EDGE, 0.0], [PATH_W, SAND, 0.012]]:
		var w: float = layer[0]
		for i in range(1, pts.size()):
			var a := board_world(mine, pts[i - 1])
			var b := board_world(mine, pts[i])
			var size := Vector3(absf(b.x - a.x) + (0.0 if absf(b.x - a.x) > 0.01 else w), 0.03,
					absf(b.z - a.z) + (0.0 if absf(b.z - a.z) > 0.01 else w))
			Toon.box(self, size, (a + b) * 0.5 + Vector3(0, layer[2], 0), layer[1], false)
		for i in pts.size():
			var c := board_world(mine, pts[i])
			Toon.cyl(self, w * 0.5, w * 0.5, 0.03, c + Vector3(0, layer[2], 0), layer[1], 0.0, 28).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lane extensions into the portal and the castle (toward the owner's edge).
	for i in [0, pts.size() - 1]:
		var c := board_world(mine, pts[i])
		var toward := board_world(mine, pts[i] + Vector2(0, 70))
		Toon.box(self, Vector3(PATH_W, 0.03, absf(toward.z - c.z)), (c + toward) * 0.5 + Vector3(0, 0.012, 0), SAND, false)

	# Grid: base slab, checker tiles, diamond studs.
	Toon.box(self, Vector3(gw + 0.12, 0.08, gh + 0.12), centre + Vector3(0, 0.0, 0), GRID_BASE, false)
	for s in GameData.slot_count():
		var p := board_world(mine, BoardLayout.slot_pos(s))
		var c := s % cols
		var r := s / cols
		Toon.box(self, Vector3(pitch - TILE_GAP, 0.04, pitch - TILE_GAP), p + Vector3(0, 0.05, 0),
				TILE_A if (c + r) % 2 == 0 else TILE_B, false)
	for c in range(1, cols):
		for r in range(1, rows):
			var local := Vector2((c - cols * 0.5) * pitch * 100.0, (r - rows * 0.5) * pitch * 100.0)
			var stud := Toon.box(self, Vector3(0.1, 0.03, 0.1), board_world(mine, local) + Vector3(0, 0.075, 0), STUD, false)
			stud.rotation.y = PI * 0.25

	# Stone frame with corner posts and a coloured gate in the middle of the near and far walls.
	var t := 0.2
	var hx := gw * 0.5 + t * 0.5 + 0.04
	var hz := gh * 0.5 + t * 0.5 + 0.04
	for sz: float in [-1.0, 1.0]:
		Toon.box(self, Vector3(gw + 0.1, 0.2, t), centre + Vector3(0, 0.1, sz * hz), STONE)
		Toon.box(self, Vector3(gw + 0.1, 0.04, t + 0.04), centre + Vector3(0, 0.21, sz * hz), Color.WHITE.lerp(STONE, 0.4))
	for sx: float in [-1.0, 1.0]:
		Toon.box(self, Vector3(t, 0.2, gh + 0.1), centre + Vector3(sx * hx, 0.1, 0), STONE)
		Toon.box(self, Vector3(t + 0.04, 0.04, gh + 0.1), centre + Vector3(sx * hx, 0.21, 0), Color.WHITE.lerp(STONE, 0.4))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var post := centre + Vector3(sx * hx, 0, sz * hz)
			Toon.box(self, Vector3(0.36, 0.34, 0.36), post + Vector3(0, 0.17, 0), STONE)
			Toon.box(self, Vector3(0.42, 0.06, 0.42), post + Vector3(0, 0.36, 0), Color.WHITE.lerp(STONE, 0.5))
	var team := MINE_COLOR if mine else OPP_COLOR
	for sz: float in [-1.0, 1.0]:
		var g := centre + Vector3(0, 0, sz * hz)
		Toon.box(self, Vector3(1.0, 0.24, t + 0.06), g + Vector3(0, 0.12, 0), team)
		Toon.box(self, Vector3(1.08, 0.05, t + 0.1), g + Vector3(0, 0.26, 0), Color("f3c443"))

	_portal(mine, board_world(mine, pts[0] + Vector2(0, 60)))
	_castle(mine, board_world(mine, pts[pts.size() - 1] + Vector2(0, 75)), team)


func _portal(mine: bool, p: Vector3) -> void:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	# Stone lip so the swirl reads as a hole in the ground.
	Toon.cyl(root, 0.66, 0.72, 0.08, Vector3(0, 0.02, 0), Color("6f5a7d"), 0.0, 32)
	var disc := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.2, 1.2)
	disc.mesh = pm
	var m := Toon.shader_mat("res://assets/shaders/portal.gdshader")
	disc.material_override = m
	disc.position = Vector3(0, 0.07, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.7, 0.35, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 1.8
	glow.position = Vector3(0, 0.5, 0)
	root.add_child(glow)
	portals[0 if mine else 1] = m


func _castle(mine: bool, p: Vector3, team: Color) -> void:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	Toon.box(root, Vector3(1.3, 0.75, 0.8), Vector3(0, 0.375, 0), CASTLE)
	Toon.box(root, Vector3(1.4, 0.08, 0.9), Vector3(0, 0.77, 0), CASTLE_DARK)
	for i in 4:
		Toon.box(root, Vector3(0.2, 0.16, 0.2), Vector3(-0.55 + i * 0.367, 0.89, 0.32), CASTLE)
	# Door faces the camera (+z) on both boards so the gate always reads.
	Toon.box(root, Vector3(0.46, 0.5, 0.06), Vector3(0, 0.25, 0.41), WOOD)
	Toon.box(root, Vector3(0.54, 0.06, 0.08), Vector3(0, 0.52, 0.41), Color("f3c443"))
	for sx: float in [-1.0, 1.0]:
		var tower := Toon.cyl(root, 0.26, 0.3, 1.25, Vector3(sx * 0.66, 0.625, 0), CASTLE, 0.0, 16)
		tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		Toon.cyl(root, 0.33, 0.33, 0.14, Vector3(sx * 0.66, 1.3, 0), CASTLE_DARK, 0.0, 16)
		Toon.cyl(root, 0.0, 0.34, 0.45, Vector3(sx * 0.66, 1.6, 0), team, 0.0, 16)
	var flag := Toon.box(root, Vector3(0.3, 0.18, 0.02), Vector3(0.82, 1.98, 0), team)
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Toon.box(root, Vector3(0.03, 0.5, 0.03), Vector3(0.66, 1.9, 0), WOOD)
	castles[0 if mine else 1] = root


func _scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Cliffs and trees beyond each board's back edge (under the HUD bars) and down the sides.
	for s: float in [1.0, -1.0]:
		var back := s * (BOARD_OFFSET_M + 4.6)
		_cliff(Vector3(-3.4, 0, back), Vector3(3.2, 0.7, 1.6))
		_cliff(Vector3(3.6, 0, back + s * 0.4), Vector3(2.6, 0.5, 1.4))
		_cliff(Vector3(0.2, 0, back + s * 1.2), Vector3(2.4, 0.9, 1.4))
		for i in 7:
			var x := rng.randf_range(-6.0, 6.0)
			_tree(Vector3(x, 0, back + s * rng.randf_range(0.9, 2.6)), rng.randf_range(0.5, 0.8))
	for sx: float in [-1.0, 1.0]:
		for i in 9:
			var z := rng.randf_range(-9.0, 9.0)
			if absf(z) < RIVER_HALF_M + 0.3:
				continue
			_bush(Vector3(sx * rng.randf_range(5.75, 6.4), 0, z), rng.randf_range(0.3, 0.5))
	# Little rocks in the grass between the lanes and the wall.
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := rng.randf_range(-8.0, 8.0)
		if absf(z) < 1.0:
			continue
		var rock := Toon.sphere(self, rng.randf_range(0.05, 0.09), Vector3(side * rng.randf_range(3.62, 3.82), 0.02, z), Color("c9cfd3"))
		rock.scale.y = 0.6


func _cliff(p: Vector3, size: Vector3) -> void:
	Toon.box(self, size, p + Vector3(0, size.y * 0.5, 0), CLIFF)
	Toon.box(self, Vector3(size.x - 0.12, 0.1, size.z - 0.12), p + Vector3(0, size.y + 0.05, 0), CLIFF_TOP)


func _tree(p: Vector3, s: float) -> void:
	Toon.cyl(self, 0.08 * s, 0.12 * s, 0.6 * s, p + Vector3(0, 0.3 * s, 0), TRUNK, 0.0, 8)
	Toon.sphere(self, 0.55 * s, p + Vector3(0, 0.95 * s, 0), LEAF, 0.0, 12)
	Toon.sphere(self, 0.38 * s, p + Vector3(0.25 * s, 1.3 * s, 0.1 * s), LEAF_LIGHT, 0.0, 12)


func _bush(p: Vector3, s: float) -> void:
	Toon.sphere(self, s, p + Vector3(0, s * 0.5, 0), LEAF, 0.0, 12)
	Toon.sphere(self, s * 0.7, p + Vector3(s * 0.5, s * 0.6, s * 0.2), LEAF_LIGHT, 0.0, 12)


## Short red flash + shake on the castle when an enemy reaches the gate.
func hit_castle(mine: bool) -> void:
	var c: Node3D = castles[0 if mine else 1]
	if c == null:
		return
	var base := c.position
	var t := create_tween()
	for i in 6:
		t.tween_property(c, "position", base + Vector3(randf_range(-0.08, 0.08), 0, randf_range(-0.05, 0.05)), 0.035)
	t.tween_property(c, "position", base, 0.04)
	var sc := c.scale
	var t2 := create_tween()
	t2.tween_property(c, "scale", sc * Vector3(1.08, 0.9, 1.08), 0.06)
	t2.tween_property(c, "scale", sc, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func pulse_portal(mine: bool) -> void:
	var m: ShaderMaterial = portals[0 if mine else 1]
	if m == null:
		return
	var t := create_tween()
	t.tween_method(func(v: float): m.set_shader_parameter("pulse", v), 0.8, 0.0, 0.35)
