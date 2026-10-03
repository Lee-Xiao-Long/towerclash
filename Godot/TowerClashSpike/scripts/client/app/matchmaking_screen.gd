class_name MatchmakingScreen
extends CanvasLayer
## "Finding opponent" screen: spinner, status line, elapsed time and Cancel. Stays on top of
## the arena while the client waits for the second player, then fades away at match start.

signal cancel_pressed

var _status: Label
var _detail: Label
var _elapsed: Label
var _cancel: Button
var _spinner: Control
var _t := 0.0
var _root: Control


func _ready() -> void:
	layer = 10
	_root = UiKit.full_rect(Control.new())
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	_root.add_child(UiKit.full_rect(bg))
	var v := UiKit.vbox(18)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.custom_minimum_size = Vector2(460, 0)
	_root.add_child(v)
	v.add_child(UiKit.label("QUICK MATCH", 30, UiKit.ACCENT))
	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(120, 120)
	_spinner.draw.connect(_draw_spinner)
	v.add_child(_spinner)
	_status = UiKit.label("", 24)
	v.add_child(_status)
	_detail = UiKit.label("", 16, UiKit.TEXT_DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail)
	_elapsed = UiKit.label("0:00", 18, UiKit.TEXT_DIM)
	v.add_child(_elapsed)
	_cancel = UiKit.button("CANCEL", 22, false, 58)
	_cancel.pressed.connect(func(): cancel_pressed.emit())
	v.add_child(_cancel)


func open() -> void:
	_t = 0.0
	_root.modulate.a = 1.0
	_cancel.disabled = false
	visible = true
	set_status("Searching...", "")


func set_status(text: String, detail := "") -> void:
	_status.text = text
	_detail.text = detail


func lock_cancel() -> void:
	_cancel.disabled = true


func fade_out() -> void:
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.35)
	await t.finished
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_elapsed.text = UiKit.mmss(_t)
	_spinner.queue_redraw()


func _draw_spinner() -> void:
	var c := _spinner.size * 0.5
	var r := minf(c.x, c.y) - 8.0
	_spinner.draw_arc(c, r, 0.0, TAU, 48, UiKit.PANEL_LIGHT, 8.0, true)
	var a := _t * 4.0
	_spinner.draw_arc(c, r, a, a + 1.6, 24, UiKit.ACCENT, 8.0, true)
