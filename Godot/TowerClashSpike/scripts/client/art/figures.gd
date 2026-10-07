class_name Figures
extends RefCounted
## Procedural cartoon placeholders for towers ("units") and enemies, styled after the Rush Royale
## baseline: a unit is a coloured round pad on its tile with a chunky chibi character on top and
## merge-rank pips; enemies are round critters with big eyes. Looks come from the "look" block
## in data/towers.json and data/enemies.json, so swapping in real art later is a data change.
## Figure forward is local -Z (Node3D.look_at convention).

const PIP := Color("ffe066")
const SKIN := Color("ffd2a8")
const EYE_WHITE := Color("ffffff")
const EYE_DARK := Color("23181c")
const OUTLINE := 0.018
const CREATURE_SCALE := 1.55
const UNIT_SCALE := 1.2


static func look_color(def: Dictionary, key := "color", fallback := Color.WHITE) -> Color:
	var look: Dictionary = def.get("look", {})
	return Color.html(look[key]) if look.has(key) else fallback


# ---------------------------------------------------------------- units

## Returns {root, pad, ring, body, pips}. root stays unrotated; rotate body toward the target.
static func tower(type: String, level: int) -> Dictionary:
	var def: Dictionary = GameData.towers[type]
	var look: Dictionary = def.get("look", {})
	var c := look_color(def)
	var root := Node3D.new()
	var pad := Toon.cyl(root, 0.5, 0.52, 0.05, Vector3(0, 0.095, 0), c.darkened(0.15).lerp(Color.WHITE, 0.15), 0.0, 32)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := Toon.torus(root, 0.44, 0.53, Vector3(0, 0.125, 0), c.lightened(0.35), 0.35)
	var body := Node3D.new()
	body.position = Vector3(0, 0.12, 0)
	root.add_child(body)
	var model := Node3D.new()
	model.scale = Vector3.ONE * UNIT_SCALE
	body.add_child(model)
	_chibi(model, str(look.get("kind", "archer")), c, Color.html(look.get("accent", "#ffffff")))
	var pips := Node3D.new()
	root.add_child(pips)
	set_pips(pips, level)
	return {"root": root, "pad": pad, "ring": ring, "body": body, "pips": pips}


## Merge rank as gold studs along the pad's camera-side edge (always +z, so they stay visible on
## the mirrored opponent board too).
static func set_pips(pips: Node3D, level: int) -> void:
	for ch in pips.get_children():
		ch.queue_free()
	var n := maxi(level, 1)
	var spread := 0.16
	for i in n:
		var x := (i - (n - 1) * 0.5) * spread
		var a := x / 0.5
		var p := Toon.sphere(pips, 0.055, Vector3(x, 0.15, 0.46 * cos(a)), PIP, 0.01, 10)
		p.scale = Vector3(1, 0.7, 1)


static func _eyes(parent: Node3D, y: float, z: float, spread := 0.085, r := 0.05) -> void:
	for s: float in [-1.0, 1.0]:
		var w := Toon.sphere(parent, r, Vector3(s * spread, y, z), EYE_WHITE, 0.0, 10)
		w.scale = Vector3(1, 1.15, 0.6)
		Toon.sphere(parent, r * 0.55, Vector3(s * spread, y - r * 0.1, z - r * 0.45), EYE_DARK, 0.0, 8)


static func _chibi(body: Node3D, kind: String, c: Color, accent: Color) -> void:
	# Shared: tapered torso, big head with face toward -Z.
	Toon.cyl(body, 0.15, 0.23, 0.34, Vector3(0, 0.17, 0), c, OUTLINE)
	var head_y := 0.52
	Toon.sphere(body, 0.2, Vector3(0, head_y, 0), SKIN, OUTLINE)
	_eyes(body, head_y, -0.17)
	match kind:
		"archer":
			# Pointed hood + bow.
			var hood := Toon.cyl(body, 0.0, 0.23, 0.36, Vector3(0, head_y + 0.12, 0.04), c, OUTLINE)
			hood.rotation.x = deg_to_rad(-18)
			Toon.torus(body, 0.2, 0.235, Vector3(0.24, 0.32, -0.06), accent).rotation = Vector3(0, 0, PI * 0.5)
		"mage":
			Toon.cyl(body, 0.3, 0.3, 0.03, Vector3(0, head_y + 0.12, 0), c.darkened(0.2), OUTLINE)
			var hat := Toon.cyl(body, 0.0, 0.2, 0.5, Vector3(0, head_y + 0.37, 0.03), c, OUTLINE)
			hat.rotation.x = deg_to_rad(-12)
			Toon.cyl(body, 0.025, 0.025, 0.85, Vector3(0.27, 0.42, -0.05), Color("8a5532"))
			Toon.node(body, _orb(0.08), Toon.mat(accent, 0.0, 2.2), Vector3(0.27, 0.88, -0.05), false)
		"rapid":
			# Spiky hair + twin daggers.
			for i in 5:
				var a := (i - 2) * 0.45
				var spike := Toon.cyl(body, 0.0, 0.07, 0.2, Vector3(sin(a) * 0.12, head_y + 0.2, cos(a) * 0.05 + 0.04), c, OUTLINE)
				spike.rotation.z = -a * 0.6
			for s: float in [-1.0, 1.0]:
				var d := Toon.box(body, Vector3(0.04, 0.24, 0.04), Vector3(s * 0.27, 0.3, -0.06), accent)
				d.rotation.z = s * 0.4
		"bomber":
			Toon.sphere(body, 0.21, Vector3(0, head_y + 0.04, 0.02), c.darkened(0.1), OUTLINE).scale = Vector3(1.05, 0.55, 1.05)
			Toon.box(body, Vector3(0.3, 0.06, 0.04), Vector3(0, head_y + 0.02, -0.18), Color("3b2c2c"))
			Toon.sphere(body, 0.15, Vector3(0.25, 0.28, -0.12), Color("2e2a33"), OUTLINE)
			Toon.node(body, _orb(0.035), Toon.mat(accent, 0.0, 3.0), Vector3(0.3, 0.45, -0.12), false)
		"frost":
			var crystal := Toon.cyl(body, 0.0, 0.11, 0.32, Vector3(0, head_y + 0.3, 0), accent, OUTLINE, 6)
			crystal.material_override = Toon.mat(accent, OUTLINE, 0.8)
			var tip := Toon.cyl(body, 0.11, 0.0, 0.12, Vector3(0, head_y + 0.08, 0), accent, 0.0, 6)
			tip.material_override = Toon.mat(accent, 0.0, 0.8)
			Toon.torus(body, 0.15, 0.22, Vector3(0, 0.34, 0), Color.WHITE.lerp(accent, 0.3))
		_:
			pass


static func _orb(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	return sm


# ---------------------------------------------------------------- enemies

## Returns {root, body, scale, hp_label}. body bobs while walking; root is placed at the foot.
static func creature(type: String) -> Dictionary:
	var def: Dictionary = GameData.enemies[type]
	var look: Dictionary = def.get("look", {})
	var c := look_color(def, "color", Color("e05a5a"))
	var s := float(look.get("scale", 1.0)) * CREATURE_SCALE
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	body.scale = Vector3.ONE * s
	var r := 0.2
	# Feet (they stay on the ground; the body bobs above them).
	for sx: float in [-1.0, 1.0]:
		var f := Toon.sphere(root, 0.06 * s, Vector3(sx * 0.09 * s, 0.04 * s, 0), c.darkened(0.45), 0.0, 8)
		f.scale = Vector3(1, 0.6, 1.3)
	var blob := Toon.sphere(body, r, Vector3(0, 0.24, 0), c, OUTLINE / s, 16)
	blob.scale = Vector3(1.05, 0.92, 1.0)
	Toon.sphere(body, r * 0.65, Vector3(0, 0.19, -0.08), c.lightened(0.3), 0.0, 12).scale = Vector3(1, 0.8, 0.6)
	_eyes(body, 0.3, -0.16, 0.075, 0.055)
	match str(look.get("extra", "")):
		"ears":
			for sx: float in [-1.0, 1.0]:
				var e := Toon.cyl(body, 0.0, 0.06, 0.18, Vector3(sx * 0.15, 0.44, 0), c, OUTLINE / s, 8)
				e.rotation.z = -sx * 0.6
		"helmet":
			Toon.sphere(body, 0.15, Vector3(0, 0.44, 0.05), Color("9aa4ad"), OUTLINE / s, 12).scale = Vector3(1.15, 0.55, 1.1)
			Toon.cyl(body, 0.0, 0.03, 0.12, Vector3(0, 0.55, 0.05), Color("e04848"), 0.0, 6)
		"armor":
			Toon.torus(body, 0.17, 0.23, Vector3(0, 0.2, 0), Color("7d858c"))
			Toon.sphere(body, 0.14, Vector3(0, 0.44, 0.06), Color("7d858c"), OUTLINE / s, 12).scale = Vector3(1.2, 0.45, 1.1)
		"halo":
			Toon.torus(body, 0.1, 0.13, Vector3(0, 0.55, 0), Color("fff27a"), 1.5)
			Toon.box(body, Vector3(0.12, 0.04, 0.02), Vector3(0, 0.22, -0.2), Color("4cd964"))
			Toon.box(body, Vector3(0.04, 0.12, 0.02), Vector3(0, 0.22, -0.2), Color("4cd964"))
		"crown":
			Toon.cyl(body, 0.13, 0.12, 0.08, Vector3(0, 0.46, 0), Color("ffd23c"), 0.01, 10)
			for i in 5:
				var a := TAU * i / 5.0
				Toon.cyl(body, 0.0, 0.035, 0.08, Vector3(cos(a) * 0.11, 0.53, sin(a) * 0.11), Color("ffd23c"), 0.0, 6)
			for sx: float in [-1.0, 1.0]:
				var h := Toon.cyl(body, 0.0, 0.045, 0.16, Vector3(sx * 0.17, 0.42, 0), Color("f4eadf"), 0.008, 8)
				h.rotation.z = -sx * 0.7
		"antenna":
			Toon.cyl(body, 0.01, 0.01, 0.14, Vector3(0, 0.48, 0), c.darkened(0.4), 0.0, 6)
			Toon.sphere(body, 0.035, Vector3(0, 0.56, 0), Color("ff7ad9"), 0.0, 8)
	var hp := Toon.label3d("", 46)
	hp.pixel_size = 0.0055
	root.add_child(hp)
	# Status auras (toggled by the view): purple = recycled from the opponent, cyan = slowed.
	var recycled := Toon.torus(root, 0.2 * s, 0.27 * s, Vector3(0, 0.03, 0), Color("b05cff"), 2.0)
	recycled.visible = false
	var slowed := Toon.torus(root, 0.24 * s, 0.3 * s, Vector3(0, 0.05, 0), Color("8ff0ff"), 1.6)
	slowed.visible = false
	return {"root": root, "body": body, "blob": blob, "scale": s, "hp_label": hp, "recycled": recycled, "slowed": slowed}
