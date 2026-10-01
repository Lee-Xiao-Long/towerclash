class_name DirSprite
extends Sprite3D
## Unlit, camera-facing directional sprite driven by a SpriteSheet.
## Node origin = the asset's foot point on the ground. The sprite plane is parallel to the
## (orthographic) image plane and pushed toward the camera, which keeps its screen position
## and stops the ground from clipping the feet.

const CAMERA_PUSH_M := 3.0

var sheet: SpriteSheet
var anim := ""
var fps := 8.0
var loop := true
var heading := Vector2(0, 1)
var _t := 0.0
var _dir: Dictionary = {}
var _foot := Vector3.ZERO


func setup(p_sheet: SpriteSheet, p_anim: String, camera_basis: Basis) -> void:
	sheet = p_sheet
	region_enabled = true
	centered = true
	pixel_size = sheet.cm_per_pixel / 100.0
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	shaded = false
	double_sided = true
	basis = camera_basis
	play(p_anim)


func play(p_anim: String) -> void:
	if anim == p_anim or not sheet.animations.has(p_anim):
		return
	anim = p_anim
	var a: Dictionary = sheet.animations[anim]
	fps = float(a.fps)
	loop = bool(a.loop)
	_t = 0.0
	_apply()


## Ground position in world metres.
func set_foot(p: Vector3) -> void:
	_foot = p
	position = p + basis.z * CAMERA_PUSH_M


func set_heading(h: Vector2) -> void:
	if h.length_squared() > 1e-8:
		heading = h


func _process(delta: float) -> void:
	if sheet == null:
		return
	_t += delta
	_apply()


func _apply() -> void:
	var a: Dictionary = sheet.animations[anim]
	var n := int(a.frames)
	var idx := int(_t * fps)
	idx = idx % n if loop else min(idx, n - 1)
	_dir = sheet.direction_for_heading(heading)
	var f := sheet.frame(anim, _dir, idx)
	texture = f.texture
	region_rect = f.region
	flip_h = f.flip
	var px := sheet.pivot.x
	if flip_h:
		px = sheet.cell.x - px
	# centered: cell centre at origin; shift so the pivot pixel lands on the origin (offset is y-up).
	offset = Vector2(sheet.cell.x * 0.5 - px, sheet.pivot.y - sheet.cell.y * 0.5)
