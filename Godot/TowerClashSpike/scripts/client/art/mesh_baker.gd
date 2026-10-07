class_name MeshBaker
extends RefCounted
## Merges a tree of primitive MeshInstance3D nodes (built with the Toon helpers) into one ArrayMesh
## with vertex colours, one surface per material class (toon / toon+outline / unlit), instead of one
## draw call per primitive. Emissive, transparent, shader and "no_bake"-tagged parts are left as
## they are. instance() caches the baked result per key and returns cheap duplicates that share
## the mesh resources. Merged instances are named "Baked" (casts shadows) and "BakedFlat" (does not).

static var _cache: Dictionary = {}
static var _mats: Dictionary = {}


## A fresh Node3D drawing what builder(parent: Node3D) draws, with static parts merged.
## Templates are cached as PackedScenes (RefCounted), not nodes, so nothing leaks at exit.
static func instance(key: String, builder: Callable) -> Node3D:
	if not _cache.has(key):
		var tmp := Node3D.new()
		builder.call(tmp)
		bake_in_place(tmp)
		_own(tmp, tmp)
		var ps := PackedScene.new()
		ps.pack(tmp)
		tmp.free()
		_cache[key] = ps
	return (_cache[key] as PackedScene).instantiate() as Node3D


static func _own(node: Node, owner: Node) -> void:
	for ch in node.get_children():
		ch.owner = owner
		_own(ch, owner)


static func bake_in_place(root: Node3D) -> void:
	var groups := {}
	var baked: Array[Node] = []
	_collect(root, Transform3D.IDENTITY, groups, baked)
	for n in baked:
		n.get_parent().remove_child(n)
		n.free()
	for shadow in [true, false]:
		var am := ArrayMesh.new()
		for key in groups:
			var g: Dictionary = groups[key]
			if g.shadow != shadow:
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = g.v
			arrays[Mesh.ARRAY_NORMAL] = g.n
			arrays[Mesh.ARRAY_COLOR] = g.c
			arrays[Mesh.ARRAY_INDEX] = g.i
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			am.surface_set_material(am.get_surface_count() - 1, _group_mat(g.outline, g.unshaded))
		if am.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Baked" if shadow else "BakedFlat"
		mi.mesh = am
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		root.move_child(mi, 0)


static func _bakeable(mi: MeshInstance3D) -> bool:
	var m := mi.material_override as StandardMaterial3D
	return m != null and mi.visible and mi.mesh != null and mi.material_overlay == null \
			and not m.emission_enabled and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and not mi.has_meta("no_bake")


static func _collect(node: Node, xf: Transform3D, groups: Dictionary, baked: Array[Node]) -> void:
	for child in node.get_children():
		if not child is Node3D or child.has_meta("no_bake"):
			continue
		var cx: Transform3D = xf * (child as Node3D).transform
		if child is MeshInstance3D and _bakeable(child):
			_append(child, cx, groups)
			if child.get_child_count() == 0:
				baked.append(child)
				continue
		_collect(child, cx, groups, baked)


static func _append(mi: MeshInstance3D, xf: Transform3D, groups: Dictionary) -> void:
	var m := mi.material_override as StandardMaterial3D
	var unshaded := m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
	var outline := 0.0
	if m.next_pass is StandardMaterial3D and (m.next_pass as StandardMaterial3D).grow:
		outline = (m.next_pass as StandardMaterial3D).grow_amount
	var shadow := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var key := "%s|%.3f|%s" % [unshaded, outline, shadow]
	if not groups.has(key):
		groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
			"i": PackedInt32Array(), "outline": outline, "unshaded": unshaded, "shadow": shadow}
	var g: Dictionary = groups[key]
	var nb := xf.basis.inverse().transposed()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx = arr[Mesh.ARRAY_INDEX]
		var base: int = g.v.size()
		for k in verts.size():
			g.v.append(xf * verts[k])
			g.n.append((nb * norms[k]).normalized() if k < norms.size() else Vector3.UP)
			g.c.append(m.albedo_color)
		if idx is PackedInt32Array and idx.size() > 0:
			for k in idx.size():
				g.i.append(base + idx[k])
		else:
			for k in verts.size():
				g.i.append(base + k)


static func _group_mat(outline: float, unshaded: bool) -> StandardMaterial3D:
	var key := "%.3f|%s" % [outline, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.roughness = 1.0
		if outline > 0.0:
			m.rim_enabled = true
			m.rim = 0.3
			m.rim_tint = 0.6
			m.next_pass = Toon.outline_mat(outline)
	_mats[key] = m
	return m
