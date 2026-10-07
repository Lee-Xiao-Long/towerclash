class_name MatchmakingScreen
extends CanvasLayer
## "Finding opponent" screen in the baseline style: you vs "?" with pulsing crossed swords, status
## line, elapsed time and Cancel. Stays on top of the arena while the client waits for the second
## player, shows the opponent when found, then fades away at match start.

signal cancel_pressed

var _status: Label
var _detail: Label
var _elapsed: Label
var _cancel: Button
var _swords: Glyph
var _me: Avatar
var _opp: Avatar
var _me_name: Label
var _opp_name: Label
var _t := 0.0
var _root: Control


func _ready() -> void:
	layer = 10
	_root = UiKit.full_rect(Control.new())
	add_child(_root)
	_root.add_child(UiKit.full_rect(UiKit.patterned_bg()))
	var v := UiKit.vbox(18)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.custom_minimum_size = Vector2(470, 0)
	_root.add_child(v)
	v.add_child(UiKit.title("PvP", 44, UiKit.ACCENT))
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var left := UiKit.vbox(6)
	_me = Avatar.make("?", Color("3a8ee6"), 120)
	left.add_child(_me)
	_me_name = UiKit.title("", 20)
	left.add_child(_me_name)
	row.add_child(left)
	_swords = Glyph.make("swords", 96)
	_swords.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_swords)
	var right := UiKit.vbox(6)
	_opp = Avatar.make("?", Color("e24a4a"), 120, Color("c9d2e3"))
	right.add_child(_opp)
	_opp_name = UiKit.title("...", 20)
	right.add_child(_opp_name)
	row.add_child(right)
	v.add_child(row)
	_status = UiKit.title("", 28)
	v.add_child(_status)
	_detail = UiKit.title("", 16, UiKit.TEXT_DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail)
	_elapsed = UiKit.title("0:00", 20, UiKit.TEXT_DIM)
	v.add_child(_elapsed)
	_cancel = UiKit.colored_button("Cancel", Color("d8443a"), Color("8f2a22"), 26, 60)
	_cancel.custom_minimum_size.x = 220
	_cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel.pressed.connect(func(): cancel_pressed.emit())
	v.add_child(_cancel)


func open(me_name := "") -> void:
	_t = 0.0
	_root.modulate.a = 1.0
	_cancel.disabled = false
	visible = true
	set_players(me_name, "")
	set_status("Searching...", "")


## Empty opponent name = still searching ("?").
func set_players(me_name: String, opp_name: String) -> void:
	_me.letter = me_name.substr(0, 1).to_upper() if me_name != "" else "?"
	_me_name.text = me_name
	_opp.letter = opp_name.substr(0, 1).to_upper() if opp_name != "" else "?"
	_opp.fill = Color("ffb38a") if opp_name != "" else Color("c9d2e3")
	_opp_name.text = opp_name if opp_name != "" else "..."
	_me.queue_redraw()
	_opp.queue_redraw()
	if opp_name != "":
		UiKit.pop(_opp, 1.3, 0.4)
		Sfx.play("upgrade", 0.0)


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
	_swords.pivot_offset = _swords.size * 0.5
	var k := 1.0 + 0.08 * sin(_t * 6.0)
	_swords.scale = Vector2(k, k)
	_swords.rotation = sin(_t * 3.0) * 0.08
