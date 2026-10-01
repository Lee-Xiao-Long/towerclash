class_name BoardLayout
extends RefCounted
## Logical board geometry in board-local cm (x = right, y = toward the board owner's camera).
## Identical for both players. The server uses it only for range math; clients map it to
## world space (own board at the bottom, opponent's rotated 180 degrees at the top).

const PATH_X := 460.0
const PATH_Y := 330.0

static var _path: PackedVector2Array = PackedVector2Array([
	Vector2(-PATH_X, PATH_Y),   # spawn: owner's lower-left
	Vector2(-PATH_X, -PATH_Y),
	Vector2(PATH_X, -PATH_Y),
	Vector2(PATH_X, PATH_Y),    # gate: owner's lower-right
])
static var _cum: PackedFloat32Array = PackedFloat32Array()


static func _ensure() -> void:
	if _cum.size() == _path.size():
		return
	_cum.resize(_path.size())
	_cum[0] = 0.0
	for i in range(1, _path.size()):
		_cum[i] = _cum[i - 1] + _path[i - 1].distance_to(_path[i])


static func path_points() -> PackedVector2Array:
	return _path


static func path_length() -> float:
	_ensure()
	return _cum[_cum.size() - 1]


## Point on the path at distance d from the spawn.
static func path_point(d: float) -> Vector2:
	_ensure()
	d = clampf(d, 0.0, path_length())
	for i in range(1, _path.size()):
		if d <= _cum[i]:
			var seg := _cum[i] - _cum[i - 1]
			var t := 0.0 if seg <= 0.0 else (d - _cum[i - 1]) / seg
			return _path[i - 1].lerp(_path[i], t)
	return _path[_path.size() - 1]


static func slot_pos(slot: int) -> Vector2:
	var cols := int(GameData.rules.slot_cols)
	var rows := int(GameData.rules.slot_rows)
	var pitch := float(GameData.rules.slot_pitch_cm)
	var c := slot % cols
	var r := slot / cols  # row 0 = far side (away from owner)
	return Vector2((c - (cols - 1) * 0.5) * pitch, (r - (rows - 1) * 0.5) * pitch)
