class_name CalibView
extends Node3D
## Engine-side check of the sprite importer: renders the Houdini Calib_Box sprite and a real
## 100 cm cube at the same foot point with a 1:1 pixel camera, then compares silhouettes.

var camera: Camera3D
var _box: MeshInstance3D
var _sprite: DirSprite


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	env.environment = e
	add_child(env)

	var sheet := SpriteSheet.get_sheet("Calib_Box")
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = get_viewport().get_visible_rect().size.y * sheet.cm_per_pixel / 100.0
	camera.rotation_degrees = Vector3(-(90.0 - ArenaView.TILT_FROM_VERTICAL_DEG), 0, 0)
	camera.position = camera.basis.z * 30.0
	add_child(camera)

	_sprite = DirSprite.new()
	add_child(_sprite)
	_sprite.setup(sheet, "Still", camera.basis)
	_sprite.set_foot(Vector3.ZERO)

	_box = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color.WHITE
	bm.material = m
	_box.mesh = bm
	_box.position = Vector3(0, 0.5, 0)
	add_child(_box)
	_run.call_deferred()


func _run() -> void:
	var out_dir: String = Net.args.get("out", "user://")
	for i in 3:
		await RenderingServer.frame_post_draw
	_box.visible = false
	_sprite.visible = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var a := get_viewport().get_texture().get_image()
	_sprite.visible = false
	_box.visible = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var b := get_viewport().get_texture().get_image()
	a.save_png(out_dir.path_join("calib_sprite.png"))
	b.save_png(out_dir.path_join("calib_mesh.png"))
	var ra := _bbox(a)
	var rb := _bbox(b)
	var err := maxf(maxf(absf(ra.position.x - rb.position.x), absf(ra.position.y - rb.position.y)),
		maxf(absf(ra.end.x - rb.end.x), absf(ra.end.y - rb.end.y)))
	var res := {
		"viewport": [a.get_width(), a.get_height()],
		"sprite_bbox": [ra.position.x, ra.position.y, ra.size.x, ra.size.y],
		"mesh_bbox": [rb.position.x, rb.position.y, rb.size.x, rb.size.y],
		"expected_width_px": 100.0 / SpriteSheet.get_sheet("Calib_Box").cm_per_pixel,
		"max_edge_error_px": err,
		"pass": err <= 2.0,
	}
	print("CALIB " + JSON.stringify(res))
	get_tree().quit(0 if res.pass else 1)


func _bbox(img: Image) -> Rect2:
	var minx := img.get_width()
	var miny := img.get_height()
	var maxx := -1
	var maxy := -1
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > 0.06:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	return Rect2(minx, miny, maxx - minx + 1, maxy - miny + 1)
