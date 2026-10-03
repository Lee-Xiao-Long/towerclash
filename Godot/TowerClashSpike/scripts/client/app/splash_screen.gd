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
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	add_child(UiKit.full_rect(bg))

	_title_root = UiKit.full_rect(Control.new())
	add_child(_title_root)
	var v := UiKit.vbox(10)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	_title_root.add_child(v)
	v.add_child(UiKit.outlined(UiKit.label("TOWER CLASH", 56, UiKit.ACCENT), 8))
	v.add_child(UiKit.label("Godot evaluation spike", 20, UiKit.TEXT_DIM))
	_status = UiKit.label("", 20, UiKit.TEXT_DIM)
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


func set_status(text: String) -> void:
	_status.text = text
