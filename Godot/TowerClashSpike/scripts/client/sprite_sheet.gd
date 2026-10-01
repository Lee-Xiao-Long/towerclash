class_name SpriteSheet
extends RefCounted
## Importer for Houdini sprite_gen output (schema towerclash.sprite_sheet/1).
## Reads <Asset>_Sheet.json next to its PNG sheets and answers frame/region queries.

const SCHEMA := "towerclash.sprite_sheet/1"

static var _cache: Dictionary = {}

var asset := ""
var cell := Vector2i(128, 128)
var pivot := Vector2(64, 100)          # px, cell top-left, y down
var cm_per_pixel := 0.75
var textures: Array[Texture2D] = []
var sheet_cols: Array[int] = []
var animations: Dictionary = {}       # name -> {fps, loop, frames, sheet, rows{dir: row}}
var directions: Array = []            # [{name, yaw_deg, source, flip_x}] sorted by yaw
var content_rect := Rect2()           # union of opaque pixels over all frames (cell px)


static func get_sheet(asset_name: String) -> SpriteSheet:
	if _cache.has(asset_name):
		return _cache[asset_name]
	var s := SpriteSheet.new()
	if not s._load("res://assets/sprites/%s_Sheet.json" % asset_name):
		return null
	_cache[asset_name] = s
	return s


func _load(json_path: String) -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(data) != TYPE_DICTIONARY or data.get("schema", "") != SCHEMA:
		push_error("SpriteSheet: %s is not %s" % [json_path, SCHEMA])
		return false
	asset = data.asset
	cell = Vector2i(int(data.cell.w), int(data.cell.h))
	pivot = Vector2(float(data.pivot_px.x), float(data.pivot_px.y))
	cm_per_pixel = float(data.cm_per_pixel)
	var cr: Dictionary = data.get("content_rect", {"x": 0, "y": 0, "w": cell.x, "h": cell.y})
	content_rect = Rect2(float(cr.x), float(cr.y), float(cr.w), float(cr.h))
	var dir := json_path.get_base_dir()
	for sh in data.sheets:
		var tex: Texture2D = load(dir.path_join(sh.file))
		if tex == null:
			push_error("SpriteSheet: missing texture %s" % sh.file)
			return false
		textures.append(tex)
		sheet_cols.append(int(sh.cols))
	for a in data.animations:
		animations[a.name] = a
	directions = data.directions.duplicate()
	directions.sort_custom(func(x, y): return float(x.yaw_deg) < float(y.yaw_deg))
	return true


## Direction whose yaw is closest to a ground-plane heading (x = east, z = south/toward camera).
## Yaw convention matches Canonical.json: 0 = S (+Z), 90 = E (+X).
func direction_for_heading(heading_xz: Vector2) -> Dictionary:
	if heading_xz.length_squared() < 1e-8:
		return directions[0]
	var yaw := fposmod(rad_to_deg(atan2(heading_xz.x, heading_xz.y)), 360.0)
	var best: Dictionary = directions[0]
	var best_d := 1e9
	for d in directions:
		var diff := absf(fposmod(yaw - float(d.yaw_deg) + 180.0, 360.0) - 180.0)
		if diff < best_d:
			best_d = diff
			best = d
	return best


## Region (in sheet pixels), texture and horizontal flip for one frame.
func frame(anim_name: String, dir: Dictionary, index: int) -> Dictionary:
	var a: Dictionary = animations[anim_name]
	var src: String = dir.get("source", dir.name)
	var row := int(a.rows[src])
	var sheet := int(a.get("sheet", 0))
	var col := index % int(a.frames)
	return {
		"texture": textures[sheet],
		"region": Rect2(col * cell.x, row * cell.y, cell.x, cell.y),
		"flip": bool(dir.get("flip_x", false)),
	}
