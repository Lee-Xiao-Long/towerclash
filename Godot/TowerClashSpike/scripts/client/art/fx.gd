class_name Fx
extends Node3D
## Cosmetic effects for the arena: projectiles per tower "shot" style, impact sparks, kill puffs,
## the recycle orb that flies over the river to the opponent's portal, rings and camera shake.
## Purely client-side; the server already applied the damage when the shot event arrives.

signal projectile_landed(enemy_id: int, kind: String)

const SHOTS := {
	# kind: [colour, radius, flight_s, arc_m, emission]
	"arrow": ["fff1c2", 0.05, 0.12, 0.15, 1.6],
	"bolt": ["7fe6ff", 0.09, 0.1, 0.0, 3.0],
	"dart": ["ffe066", 0.045, 0.08, 0.0, 2.0],
	"bomb": ["3a3340", 0.11, 0.26, 0.9, 0.0],
	"ice": ["a8f4ff", 0.07, 0.12, 0.1, 2.2],
}

var camera: Camera3D
var _shots: Array = []
var _puffs: Array = []
var _orbs: Array = []
var _rings: Array = []
var _shake := 0.0
var _shake_t := 0.0
var _meshes: Dictionary = {}


func _sphere_mesh(r: float) -> SphereMesh:
	var key := snappedf(r, 0.001)
	if not _meshes.has(key):
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 10
		sm.rings = 5
		_meshes[key] = sm
	return _meshes[key]


## target_fn returns the target's current world position (or null when it is gone).
func shoot(kind: String, from: Vector3, target_fn: Callable, enemy_id: int) -> void:
	var spec: Array = SHOTS.get(kind, SHOTS.arrow)
	var c := Color(spec[0])
	var mi := Toon.node(self, _sphere_mesh(spec[1]), Toon.mat(c, 0.0, spec[4]) if spec[4] > 0.0 else Toon.mat(c, 0.01), from, false)
	if kind == "arrow":
		mi.scale = Vector3(0.6, 0.6, 3.0)
	var to = target_fn.call()
	_shots.append({"node": mi, "from": from, "fn": target_fn, "last": to if to != null else from,
		"t": 0.0, "dur": float(spec[2]), "arc": float(spec[3]), "kind": kind, "id": enemy_id, "color": c})


func puff(at: Vector3, c := Color.WHITE, count := 7, size := 0.12) -> void:
	for i in count:
		var a := TAU * i / count + randf() * 0.4
		var dir := Vector3(cos(a), randf_range(0.4, 1.0), sin(a)).normalized()
		var mi := Toon.node(self, _sphere_mesh(size), Toon.mat(c), at + Vector3(0, 0.2, 0), false)
		mi.scale = Vector3.ONE * 0.3
		_puffs.append({"node": mi, "v": dir * randf_range(1.2, 2.2), "t": 0.0, "dur": randf_range(0.3, 0.45)})


func spark(at: Vector3, c: Color) -> void:
	for i in 4:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.0), randf_range(-1, 1)).normalized()
		var mi := Toon.node(self, _sphere_mesh(0.035), Toon.mat(c, 0.0, 2.5), at, false)
		_puffs.append({"node": mi, "v": dir * 2.4, "t": 0.0, "dur": 0.16})


## Flat expanding ring on the ground (summon, merge, splash, frost).
func ring(at: Vector3, c: Color, radius := 0.6, dur := 0.35, emission := 1.5) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 28
	tm.ring_segments = 4
	var mi := Toon.node(self, tm, Toon.mat(c, 0.0, emission), at + Vector3(0, 0.14, 0), false)
	mi.scale = Vector3(0.1, 0.05, 0.1)
	_rings.append({"node": mi, "t": 0.0, "dur": dur, "r": radius})


## Recycled enemy: an orb arcs from the kill spot to the other board's portal.
func recycle_orb(from: Vector3, to: Vector3, on_arrive: Callable) -> void:
	var mi := Toon.node(self, _sphere_mesh(0.12), Toon.mat(Color("c77dff"), 0.0, 3.0), from, false)
	_orbs.append({"node": mi, "from": from + Vector3(0, 0.4, 0), "to": to + Vector3(0, 0.2, 0), "t": 0.0, "dur": 0.75, "cb": on_arrive})


func shake(amount: float, secs := 0.25) -> void:
	_shake = maxf(_shake, amount)
	_shake_t = maxf(_shake_t, secs)


func _process(delta: float) -> void:
	for s in _shots.duplicate():
		s.t += delta
		var to = s.fn.call()
		if to != null:
			s.last = to
		var k := clampf(s.t / s.dur, 0.0, 1.0)
		var p: Vector3 = s.from.lerp(s.last, k)
		p.y += sin(k * PI) * s.arc
		var n: MeshInstance3D = s.node
		if s.kind == "arrow" and n.position.distance_squared_to(p) > 1e-6:
			n.look_at_from_position(n.position, p, Vector3.UP)
			n.scale = Vector3(0.6, 0.6, 3.0)
		n.position = p
		if s.kind == "bomb":
			n.rotation.x += delta * 12.0
		if k >= 1.0:
			_land(s)
			n.queue_free()
			_shots.erase(s)
	for f in _puffs.duplicate():
		f.t += delta
		var k: float = f.t / f.dur
		var n: MeshInstance3D = f.node
		n.position += f.v * delta
		f.v *= 0.9
		n.scale = Vector3.ONE * (sin(minf(k, 1.0) * PI) * 1.0 + 0.05)
		if k >= 1.0:
			n.queue_free()
			_puffs.erase(f)
	for r in _rings.duplicate():
		r.t += delta
		var k: float = r.t / r.dur
		var e := 1.0 - pow(1.0 - minf(k, 1.0), 3.0)
		var n: MeshInstance3D = r.node
		n.scale = Vector3(r.r * e, 0.05, r.r * e)
		if k >= 1.0:
			n.queue_free()
			_rings.erase(r)
	for o in _orbs.duplicate():
		o.t += delta
		var k := clampf(o.t / o.dur, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var p: Vector3 = o.from.lerp(o.to, e)
		p.y += sin(k * PI) * 1.6
		o.node.position = p
		o.node.scale = Vector3.ONE * (1.0 + sin(k * PI * 6.0) * 0.15)
		if k >= 1.0:
			o.node.queue_free()
			_orbs.erase(o)
			o.cb.call()
	if camera != null:
		if _shake_t > 0.0:
			_shake_t -= delta
			camera.h_offset = randf_range(-_shake, _shake)
			camera.v_offset = randf_range(-_shake, _shake)
			_shake *= 0.88
		else:
			camera.h_offset = 0.0
			camera.v_offset = 0.0


func _land(s: Dictionary) -> void:
	var at: Vector3 = s.last
	match s.kind:
		"bomb":
			ring(at, Color("ffb35a"), 1.5, 0.22, 0.8)
			puff(at, Color("ffcf73"), 6, 0.1)
		"ice":
			ring(at, Color("a8f4ff"), 0.6, 0.25, 1.8)
		_:
			spark(at + Vector3(0, 0.25, 0), s.color)
	projectile_landed.emit(int(s.id), str(s.kind))
