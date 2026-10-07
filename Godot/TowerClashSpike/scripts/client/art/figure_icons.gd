class_name FigureIcons
extends RefCounted
## Card/portrait icons rendered from the same procedural tower figures used on the board, so the
## deck bar, opponent deck row and menus always match the arena. icon() returns an ImageTexture
## at once; it is filled in after one offscreen render (a few frames later).

const SIZE := 160

static var _cache: Dictionary = {}


static func icon(type: String) -> Texture2D:
	if _cache.has(type):
		return _cache[type]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_cache[type] = tex
	if DisplayServer.get_name() != "headless" and GameData.towers.has(type):
		_render(type, tex)
	return tex


static func _render(type: String, tex: ImageTexture) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child.call_deferred(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.92, 1.0)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.9
	world.add_child(sun)
	var f := Figures.tower(type, 1)
	world.add_child(f.root)
	f.pad.visible = false
	f.ring.visible = false
	f.pips.visible = false
	f.body.rotation.y = deg_to_rad(-20)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.25
	cam.rotation_degrees = Vector3(-18, 0, 0)
	cam.position = Vector3(0, 0.62, 0) + cam.basis.z * 5.0
	world.add_child(cam)
	await tree.process_frame
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img != null:
		tex.set_image(img)
	vp.queue_free()
