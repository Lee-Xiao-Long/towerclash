class_name Hud
extends CanvasLayer
## Minimal match HUD built in code. Opponent info at the top, own info and the
## one-tap Add Tower button at the bottom.

signal add_tower_pressed

const PHASES := ["Waiting", "Wave", "Intermission", "Ended"]

var _top: Label
var _mid: Label
var _bottom: Label
var _button: Button
var _result: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_top = _label(root, Control.PRESET_TOP_WIDE, 20)
	_top.text = "Connecting..."
	_mid = _label(root, Control.PRESET_CENTER, 24)
	_bottom = _label(root, Control.PRESET_BOTTOM_WIDE, 20)
	_bottom.offset_top = -110
	_bottom.offset_bottom = -70
	_button = Button.new()
	_button.text = "Add Tower"
	_button.add_theme_font_size_override("font_size", 26)
	_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_button.offset_left = -130
	_button.offset_right = 130
	_button.offset_top = -64
	_button.offset_bottom = -10
	_button.pressed.connect(func(): add_tower_pressed.emit())
	root.add_child(_button)
	_result = _label(root, Control.PRESET_CENTER, 44)
	_result.visible = false


func _label(parent: Control, preset: int, size: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func update_from(snap: Dictionary, me: int) -> void:
	if me < 0:
		return
	var p: Array = snap.p[me]
	var o: Array = snap.p[1 - me]
	_top.text = "Opponent  HP %d   Gold %d   Towers %d   Incoming %d" % [o[1], o[0], snap.tw[1 - me].size(), o[3]]
	_mid.text = "Round %d/%d  %s  %ds" % [int(snap.r) + 1, int(snap.rn), PHASES[int(snap.ph)], int(snap.tl)]
	_bottom.text = "You  HP %d   Gold %d   Towers %d   Incoming %d" % [p[1], p[0], snap.tw[me].size(), p[3]]
	_button.text = "Add Tower (%d)" % int(p[2])
	_button.disabled = int(p[0]) < int(p[2])


func show_result(res: Dictionary, me: int) -> void:
	var w := int(res.winner)
	_result.text = "DRAW" if w < 0 else ("VICTORY" if w == me else "DEFEAT")
	_result.text += "\n(%s)" % res.reason
	_result.visible = true
	_mid.visible = false
