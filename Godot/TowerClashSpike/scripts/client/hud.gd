class_name Hud
extends CanvasLayer
## Match HUD built in code. Opponent info at the top, own info and the one-tap Add Tower
## button at the bottom, result panel (with Return Home in the app flow) in the middle.

signal add_tower_pressed
signal return_pressed

const PHASES := ["Waiting", "Wave", "Intermission", "Ended"]

var _top: Label
var _mid: Label
var _bottom: Label
var _button: Button
var _result_panel: PanelContainer
var _result_title: Label
var _result_body: Label
var _return: Button
var _names: Array = ["", ""]
var _me := 0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_top = _label(root, Control.PRESET_TOP_WIDE, 20)
	_top.text = "Waiting for match..."
	_mid = _label(root, Control.PRESET_CENTER, 24)
	_bottom = _label(root, Control.PRESET_BOTTOM_WIDE, 20)
	_bottom.offset_top = -110
	_bottom.offset_bottom = -70
	_button = UiKit.button("Add Tower", 26, true, 54)
	_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_button.offset_left = -130
	_button.offset_right = 130
	_button.offset_top = -64
	_button.offset_bottom = -10
	_button.pressed.connect(func(): add_tower_pressed.emit())
	root.add_child(_button)

	_result_panel = UiKit.panel(Color(0.08, 0.09, 0.13, 0.92), 22)
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.custom_minimum_size = Vector2(420, 0)
	_result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_panel.visible = false
	root.add_child(_result_panel)
	var v := UiKit.vbox(14)
	_result_panel.add_child(v)
	_result_title = UiKit.outlined(UiKit.label("", 52))
	v.add_child(_result_title)
	_result_body = UiKit.label("", 20, UiKit.TEXT_DIM)
	_result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_result_body)
	_return = UiKit.button("Return Home", 26)
	_return.pressed.connect(func(): return_pressed.emit())
	_return.visible = false
	v.add_child(_return)


func _label(parent: Control, preset: int, size: int) -> Label:
	var l := UiKit.outlined(UiKit.label("", size))
	l.set_anchors_preset(preset)
	parent.add_child(l)
	return l


func set_names(names: Array, me: int) -> void:
	if names.size() == 2:
		_names = names
	_me = maxi(me, 0)


func _opp_name() -> String:
	var n: String = _names[1 - _me]
	return n if n != "" else "Opponent"


func update_from(snap: Dictionary, me: int) -> void:
	if me < 0:
		return
	_me = me
	var p: Array = snap.p[me]
	var o: Array = snap.p[1 - me]
	_top.text = "%s  HP %d   Gold %d   Towers %d   Incoming %d" % [_opp_name(), o[1], o[0], snap.tw[1 - me].size(), o[3]]
	_mid.text = "Round %d/%d  %s  %ds" % [int(snap.r) + 1, int(snap.rn), PHASES[int(snap.ph)], int(snap.tl)]
	_bottom.text = "You  HP %d   Gold %d   Towers %d   Incoming %d" % [p[1], p[0], snap.tw[me].size(), p[3]]
	_button.text = "Add Tower (%d)" % int(p[2])
	_button.disabled = int(p[0]) < int(p[2])


func show_message(text: String) -> void:
	_mid.text = text
	_mid.visible = true


func show_result(res: Dictionary, me: int, with_return := false) -> void:
	var w := int(res.winner)
	var won := w == me
	_result_title.text = UiKit.result_word(w, me)
	_result_title.add_theme_color_override("font_color", UiKit.result_color(w, me))
	var kills: Array = res.get("kills", [0, 0])
	var hp: Array = res.get("base_hp", [0, 0])
	var o := 1 - maxi(me, 0)
	var m := maxi(me, 0)
	_result_body.text = "%s\nvs %s\nRound %d   %s\nBase HP %d - %d   Kills %d - %d" % [
		UiKit.reason_text(str(res.reason), won), _opp_name(), int(res.get("round", 0)),
		UiKit.mmss(float(res.get("time", 0.0))), int(hp[m]), int(hp[o]), int(kills[m]), int(kills[o])]
	_return.visible = with_return
	_result_panel.visible = true
	_mid.visible = false
	_button.disabled = true
