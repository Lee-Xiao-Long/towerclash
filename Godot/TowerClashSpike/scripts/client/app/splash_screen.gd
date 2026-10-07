class_name SplashScreen
extends CanvasLayer
## Boot screens: studio logo on white (fade in / hold / fade out), then the game title card
## with a status line while the app signs in to EOS in the background.

var _white: ColorRect
var _logo: TextureRect
var _title_root: Control
var _status: Label


func _ready() -> void:
	layer = 20
	_title_root = UiKit.full_rect(Control.new())
	add_child(_title_root)
	_title_root.add_child(UiKit.full_rect(_sky()))
	var v := UiKit.vbox(0)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.offset_top = -120
	_title_root.add_child(v)
	# Chunky two-line logo on a purple shield, like the reference title card.
	var plate := PanelContainer.new()
	var ps := UiKit.chunky(Color("7b3fc4"), Color("4a2080"), 28, false, 10)
	ps.border_width_left = 5
	ps.border_width_right = 5
	ps.border_width_top = 5
	ps.border_color = Color("ffe08a")
	ps.content_margin_left = 30
	ps.content_margin_right = 30
	plate.add_theme_stylebox_override("panel", ps)
	var lv := UiKit.vbox(-18)
	lv.add_child(UiKit.title("TOWER", 72, Color("ffc83a")))
	lv.add_child(UiKit.title("CLASH", 84, Color("ff5fa2")))
	plate.add_child(lv)
	plate.rotation_degrees = -3
	v.add_child(plate)
	var sub := UiKit.title("Godot evaluation spike", 20, Color.WHITE)
	sub.custom_minimum_size.y = 50
	v.add_child(sub)
	_status = UiKit.title("", 22)
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_top = -120
	_status.offset_bottom = -80
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title_root.add_child(_status)
	_title_root.modulate.a = 0.0

	_white = ColorRect.new()
	_white.color = Color.WHITE
	add_child(UiKit.full_rect(_white))
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/ui/Logo_MadLee.png")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.custom_minimum_size = Vector2(380, 380)
	_logo.offset_left = -190
	_logo.offset_right = 190
	_logo.offset_top = -190
	_logo.offset_bottom = 190
	_logo.modulate.a = 0.0
	_white.add_child(_logo)


## Logo sequence; fast=true for bot/test clients.
func run_logo(fast := false) -> void:
	var k := 0.3 if fast else 1.0
	var t := create_tween()
	t.tween_property(_logo, "modulate:a", 1.0, 0.6 * k)
	t.tween_interval(1.4 * k)
	t.tween_property(_logo, "modulate:a", 0.0, 0.4 * k)
	t.tween_property(_white, "modulate:a", 0.0, 0.3 * k)
	t.parallel().tween_property(_title_root, "modulate:a", 1.0, 0.3 * k)
	await t.finished


## Sky gradient with soft cartoon clouds.
func _sky() -> Control:
	var c := ColorRect.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var h := c.size.y
		var steps := 24
		for i in steps:
			var k := float(i) / steps
			c.draw_rect(Rect2(0, h * k, c.size.x, h / steps + 1), Color("3d8fe8").lerp(Color("aee0ff"), k))
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in 9:
			var p := Vector2(rng.randf_range(-40, c.size.x + 40), rng.randf_range(40, h - 40))
			var r := rng.randf_range(40, 80)
			for j in 4:
				c.draw_circle(p + Vector2((j - 1.5) * r * 0.8, -sin(j * 1.3) * r * 0.25), r * (0.75 if j % 3 == 0 else 1.0), Color(1, 1, 1, 0.75)))
	return c


func set_status(text: String) -> void:
	_status.text = text
