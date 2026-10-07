class_name Toon
extends RefCounted
## Shared look helpers for the placeholder art (Rush Royale baseline, see Docs/Art_Baseline.md):
## cached toon materials, inverted-hull outlines, primitive mesh nodes and the UI/3D font.
## Everything is procedural so it can be swapped for Houdini sprites/models later.

const OUTLINE_COLOR := Color(0.16, 0.11, 0.12)
const FONT_PATH := "res://assets/fonts/LilitaOne-Regular.ttf"

static var _mats: Dictionary = {}
static var _font: Font


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH)
	return _font


static func hex(s: String) -> Color:
	return Color.html(s)


## Banded (toon) diffuse, no specular, soft rim. Cached by colour + flags so boards share materials.
static func mat(c: Color, outline := 0.0, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%.3f|%.2f" % [c.to_html(), outline, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	# Rim only on outlined characters: at the 40 deg view every ground top face is near grazing,
	# so rim on the environment washes the whole board out.
	if outline > 0.0:
		m.rim_enabled = true
		m.rim = 0.3
		m.rim_tint = 0.6
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	if outline > 0.0:
		m.next_pass = outline_mat(outline)
	_mats[key] = m
	return m


static func unlit(c: Color, transparent := false) -> StandardMaterial3D:
	var key := "unlit|%s|%s" % [c.to_html(), transparent]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if transparent or c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


## Inverted hull: front faces culled, vertices pushed out along normals. Works on smooth meshes
## (spheres, capsules, cylinders); flat-shaded boxes would show gaps, so boxes skip it.
static func outline_mat(width: float) -> StandardMaterial3D:
	var key := "outline|%.3f" % width
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = OUTLINE_COLOR
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = width
	_mats[key] = m
	return m


static func shader_mat(path: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func node(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, shadow := true) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return node(parent, bm, mat(c), pos, shadow)


static func sphere(parent: Node3D, r: float, pos: Vector3, c: Color, outline := 0.0, segs := 16) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = segs / 2
	return node(parent, sm, mat(c, outline), pos)


static func cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, c: Color, outline := 0.0, segs := 20) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	return node(parent, cm, mat(c, outline), pos)


static func torus(parent: Node3D, r_in: float, r_out: float, pos: Vector3, c: Color, emission := 0.0) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	tm.rings = 32
	tm.ring_segments = 8
	return node(parent, tm, mat(c, 0.0, emission), pos, false)


static func label3d(text: String, size := 40, c := Color.WHITE, outline := 12) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = size
	l.pixel_size = 0.005
	l.outline_size = outline
	l.outline_modulate = OUTLINE_COLOR
	l.modulate = c
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	return l
