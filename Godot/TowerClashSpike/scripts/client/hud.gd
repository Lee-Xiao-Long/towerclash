class_name Hud
extends CanvasLayer
## Match HUD in the Rush Royale baseline layout (refs/images/gameplay-*.png):
##   top     opponent deck row (with card levels) + opponent avatar
##   river   hearts per side, incoming-recycle counters, wave + timer pill (tracks the 3D river)
##   bottom  mana pill, big yellow summon button with cost, 5-card upgrade bar, own avatar
## plus wave/boss banners, failure toasts and the result ribbon. Built in code like the rest.

signal add_tower_pressed
signal upgrade_pressed(deck_index: int)
signal return_pressed

const PHASES := ["Waiting", "Wave", "Break", "Ended"]
const CARD_W := 80
const CARD_H := 106

var camera: Camera3D

var _root: Control
var _names: Array = ["", ""]
var _decks: Array = [[], []]
var _me := 0
var _snap: Dictionary = {}

var _opp_cards: Array = []      # [{panel, level}]
var _my_cards: Array = []       # [{button, level, cost, cost_row, type}]
var _opp_avatar: Avatar
var _my_avatar: Avatar
var _opp_name: Label
var _river: Control
var _hearts: Array = [[], []]   # [mine, opp] -> Array[Glyph]
var _incoming: Array = [null, null]
var _wave_label: Label
var _timer_label: Label
var _mana_pill: PanelContainer
var _mana_label: Label
var _summon: Button
var _summon_cost: Label
var _toast: Label
var _vignette: ColorRect
var _banner: Control
var _message: Label
var _result: Control
var _last_mana := -1
var _last_hp := [-1, -1]


class Avatar extends Control:
	var letter := "?"
	var ring := Color.WHITE
	var fill := Color("ffcf8a")

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, UiKit.OUTLINE)
		draw_circle(c, r - 3, ring)
		draw_circle(c, r - 9, fill.darkened(0.25))
		draw_circle(c - Vector2(0, 2), r - 11, fill)
		var f := Toon.font()
		var fs := int(r * 1.1)
		var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(f, c + Vector2(-w * 0.5, fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, UiKit.OUTLINE)
		draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _ready() -> void:
	_root = UiKit.full_rect(Control.new())
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_vignette = ColorRect.new()
	_vignette.color = Color(1, 0.1, 0.1, 0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(UiKit.full_rect(_vignette))
	_build_top()
	_build_river()
	_build_bottom()
	_message = UiKit.title("", 30)
	_message.set_anchors_preset(Control.PRESET_CENTER)
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_message)
	_set_decks(Net.decks)


# ---------------------------------------------------------------- build

func _build_top() -> void:
	var bar := ColorRect.new()
	bar.color = Color(0.08, 0.1, 0.2, 0.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 96
	_root.add_child(bar)
	var row := UiKit.hbox(6)
	row.position = Vector2(14, 14)
	bar.add_child(row)
	for i in 5:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(56, 56)
		p.add_theme_stylebox_override("panel", _card_box(Color("8a93a6")))
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(icon)
		var lv := UiKit.title("L.1", 15)
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lv.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		lv.position = Vector2(-10, -14)
		p.add_child(lv)
		row.add_child(p)
		_opp_cards.append({"panel": p, "icon": icon, "level": lv})
	_opp_avatar = Avatar.new()
	_opp_avatar.ring = Color("e24a4a")
	_opp_avatar.fill = Color("ffb38a")
	_opp_avatar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_opp_avatar.offset_left = -88
	_opp_avatar.offset_right = -16
	_opp_avatar.offset_top = 6
	_opp_avatar.offset_bottom = 78
	_opp_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_opp_avatar)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _pill(Color(0.1, 0.08, 0.16, 0.8)))
	plate.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	plate.offset_left = -170
	plate.offset_right = -10
	plate.offset_top = 78
	plate.offset_bottom = 104
	plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(plate)
	_opp_name = UiKit.title("Opponent", 17)
	plate.add_child(_opp_name)


func _pill(c: Color, r := 14) -> StyleBoxFlat:
	var s := UiKit.box(c, r)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


func _build_river() -> void:
	_river = Control.new()
	_river.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_river.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_root.add_child(_river)
	# Opponent hearts sit just above the river on the left, ours just below on the right.
	for side in 2:
		var h := UiKit.hbox(2)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in int(GameData.rules.base_hp):
			var g := Glyph.make("heart", 30)
			h.add_child(g)
			_hearts[side].append(g)
		var inc := PanelContainer.new()
		inc.add_theme_stylebox_override("panel", _pill(Color("7b3fc4"), 12))
		var il := UiKit.title("+0", 15)
		inc.add_child(il)
		inc.visible = false
		_incoming[side] = {"panel": inc, "label": il}
		if side == 1:
			h.position = Vector2(12, -40)
			h.add_child(inc)
		else:
			h.position = Vector2(540 - 12 - 3 * 32, 8)
			h.add_child(inc)
			h.move_child(inc, 0)
		h.set_meta("side", side)
		_river.add_child(h)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _pill(Color(0.1, 0.08, 0.16, 0.78), 18))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := UiKit.hbox(10)
	pill.add_child(hb)
	_wave_label = UiKit.title("Wave 1", 20)
	hb.add_child(_wave_label)
	_timer_label = UiKit.title("00:00", 20, Color("ffe066"))
	hb.add_child(_timer_label)
	_river.add_child(pill)
	pill.set_meta("centre", true)


func _build_bottom() -> void:
	# Wooden tray behind the deck bar, like the reference.
	var tray := PanelContainer.new()
	var ts := UiKit.box(Color("5a3a24"), 0, 0)
	ts.border_width_top = 6
	ts.border_color = Color("3c2416")
	tray.add_theme_stylebox_override("panel", ts)
	tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tray.offset_top = -134
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tray)

	var cards := UiKit.hbox(6)
	cards.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cards.offset_left = 12
	cards.offset_top = -124
	cards.offset_bottom = -14
	_root.add_child(cards)
	for i in 5:
		var b := Button.new()
		b.custom_minimum_size = Vector2(CARD_W, CARD_H)
		UiKit.style_button(b, Color("8a93a6"), Color("5b6274"))
		b.pressed.connect(_on_card.bind(i))
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 4
		icon.offset_right = -4
		icon.offset_top = 6
		icon.offset_bottom = -30
		b.add_child(icon)
		var lv := UiKit.title("L.1", 17)
		lv.position = Vector2(6, 0)
		b.add_child(lv)
		var cost_row := UiKit.hbox(2)
		cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
		cost_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		cost_row.offset_top = -32
		cost_row.offset_bottom = -6
		cost_row.add_child(Glyph.make("mana", 20))
		var cost := UiKit.title("100", 17)
		cost_row.add_child(cost)
		b.add_child(cost_row)
		cards.add_child(b)
		_my_cards.append({"button": b, "icon": icon, "level": lv, "cost": cost, "cost_row": cost_row, "type": ""})

	_my_avatar = Avatar.new()
	_my_avatar.ring = Color("3a8ee6")
	_my_avatar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_my_avatar.offset_left = -90
	_my_avatar.offset_right = -12
	_my_avatar.offset_top = -108
	_my_avatar.offset_bottom = -30
	_my_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_my_avatar)

	_mana_pill = PanelContainer.new()
	_mana_pill.add_theme_stylebox_override("panel", _pill(Color(0.1, 0.08, 0.16, 0.82), 18))
	_mana_pill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_mana_pill.offset_left = 14
	_mana_pill.offset_right = 150
	_mana_pill.offset_top = -184
	_mana_pill.offset_bottom = -146
	_mana_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mh := UiKit.hbox(6)
	_mana_pill.add_child(mh)
	mh.add_child(Glyph.make("mana", 32))
	_mana_label = UiKit.title("0", 26)
	_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mh.add_child(_mana_label)
	_root.add_child(_mana_pill)

	_summon = UiKit.button("", 24, true, 76)
	_summon.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_summon.offset_left = -92
	_summon.offset_right = 92
	_summon.offset_top = -214
	_summon.offset_bottom = -138
	_summon.pressed.connect(func(): add_tower_pressed.emit())
	var sh := UiKit.hbox(8)
	sh.alignment = BoxContainer.ALIGNMENT_CENTER
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	sh.offset_bottom = -6
	sh.add_child(Glyph.make("card", 44))
	sh.add_child(Glyph.make("mana", 26))
	_summon_cost = UiKit.title("10", 28)
	sh.add_child(_summon_cost)
	_summon.add_child(sh)
	_root.add_child(_summon)

	_toast = UiKit.title("", 20, Color("ffd84a"))
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_top = -258
	_toast.offset_bottom = -222
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.modulate.a = 0.0
	_root.add_child(_toast)


func _on_card(i: int) -> void:
	upgrade_pressed.emit(i)


# ---------------------------------------------------------------- data

func set_names(names: Array, me: int) -> void:
	if names.size() == 2:
		_names = names
	_me = maxi(me, 0)
	_opp_name.text = _opp_display_name()
	_opp_avatar.letter = _initial(_opp_display_name())
	_my_avatar.letter = _initial(str(_names[_me]) if str(_names[_me]) != "" else "You")
	_opp_avatar.queue_redraw()
	_my_avatar.queue_redraw()
	_set_decks(Net.decks)


func _initial(n: String) -> String:
	return n.substr(0, 1).to_upper() if n != "" else "?"


func _opp_display_name() -> String:
	var n: String = _names[1 - _me]
	return n if n != "" else "Opponent"


func _set_decks(decks: Array) -> void:
	if decks.size() != 2 or (decks[0] as Array).is_empty():
		return
	_decks = decks
	var mine: Array = decks[_me]
	var theirs: Array = decks[1 - _me]
	for i in mini(5, theirs.size()):
		var t: String = theirs[i]
		_opp_cards[i].icon.texture = FigureIcons.icon(t)
		_opp_cards[i].panel.add_theme_stylebox_override("panel", _card_box(_card_bg(t)))
	for i in mini(5, mine.size()):
		var t: String = mine[i]
		var c: Dictionary = _my_cards[i]
		c.type = t
		c.icon.texture = FigureIcons.icon(t)
		UiKit.style_button(c.button, _card_bg(t), _card_bg(t).darkened(0.35))


func _card_box(c: Color) -> StyleBoxFlat:
	var s := UiKit.box(c, 10, 3, UiKit.OUTLINE)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_content_margin(side, 2)
	return s


func _card_bg(type: String) -> Color:
	return Figures.look_color(GameData.towers[type]).lerp(Color("c9d2e3"), 0.45)


func update_from(snap: Dictionary, me: int) -> void:
	if me < 0:
		return
	_me = me
	_snap = snap
	var p: Array = snap.p[me]
	var o: Array = snap.p[1 - me]
	var mana := int(p[0])
	if _last_mana >= 0 and mana > _last_mana:
		UiKit.pop(_mana_pill, 1.08, 0.2)
		if mana - _last_mana >= 25:
			Sfx.play("coin")
	_last_mana = mana
	_mana_label.text = str(mana)
	var cost := int(p[2])
	_summon_cost.text = str(cost)
	var full: bool = snap.tw[me].size() >= GameData.slot_count()
	_summon.modulate = Color.WHITE if mana >= cost and not full else Color(0.75, 0.75, 0.8)
	_wave_label.text = "Wave %d/%d" % [int(snap.r) + 1, int(snap.rn)] if int(snap.ph) != MatchSim.Phase.INTERMISSION else "Break"
	_timer_label.text = UiKit.mmss(float(snap.tl)).lpad(5, "0")
	_set_hearts(0, int(p[1]))
	_set_hearts(1, int(o[1]))
	_set_incoming(0, int(p[3]))
	_set_incoming(1, int(o[3]))
	var costs: Array = GameData.rules.card_upgrade_costs
	for side in 2:
		var levels: Array = (snap.p[me] if side == 0 else snap.p[1 - me])[5]
		for i in mini(5, levels.size()):
			var lvl := int(levels[i])
			if side == 1:
				_opp_cards[i].level.text = "L.%d" % lvl
				continue
			var c: Dictionary = _my_cards[i]
			if lvl > int(c.get("lvl", lvl)):
				UiKit.pop(c.button, 1.15, 0.3)
				Sfx.play("upgrade", 0.0)
			c.lvl = lvl
			c.level.text = "L.%d" % lvl
			var up := -1 if lvl > costs.size() else int(costs[lvl - 1])
			c.cost.text = "MAX" if up < 0 else str(up)
			c.button.modulate = Color.WHITE if up >= 0 and mana >= up else Color(0.72, 0.72, 0.78)


func _set_hearts(side: int, hp: int) -> void:
	var hs: Array = _hearts[side]
	if _last_hp[side] >= 0 and hp < _last_hp[side]:
		for i in range(maxi(hp, 0), mini(_last_hp[side], hs.size())):
			UiKit.pop(hs[i], 1.6, 0.4)
	_last_hp[side] = hp
	for i in hs.size():
		hs[i].set_kind("heart" if i < hp else "heart_empty")


func _set_incoming(side: int, n: int) -> void:
	var d: Dictionary = _incoming[side]
	d.panel.visible = n > 0
	d.label.text = "+%d" % n


func _process(_delta: float) -> void:
	if camera == null:
		return
	# Keep the river widgets glued to the 3D river even with different aspect ratios.
	var vp := get_viewport().get_visible_rect().size
	var ry := camera.unproject_position(Vector3(0, 0, 0)).y
	_river.position.y = ry
	for ch in _river.get_children():
		if ch.has_meta("centre"):
			ch.position = Vector2((vp.x - ch.size.x) * 0.5, -ch.size.y * 0.5)
		elif ch.has_meta("side") and int(ch.get_meta("side")) == 0:
			ch.position.x = vp.x - 12 - ch.size.x


# ---------------------------------------------------------------- moments

func announce_wave(n: int, boss: bool) -> void:
	if _banner != null:
		_banner.queue_free()
	var v := UiKit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ribbon := PanelContainer.new()
	var c := Color("d8443a") if boss else Color("3f8ff0")
	var s := UiKit.chunky(c, c.darkened(0.4), 12)
	s.content_margin_left = 40
	s.content_margin_right = 40
	ribbon.add_theme_stylebox_override("panel", s)
	ribbon.add_child(UiKit.title("BOSS WAVE" if boss else "Wave %d" % n, 40))
	v.add_child(ribbon)
	_banner = v
	_root.add_child(v)
	await get_tree().process_frame
	if _banner != v:
		return
	var vp := get_viewport().get_visible_rect().size
	v.position = Vector2((vp.x - v.size.x) * 0.5, _river.position.y - v.size.y * 0.5)
	v.pivot_offset = v.size * 0.5
	v.scale = Vector2(0.2, 0.2)
	Sfx.play("boss" if boss else "horn", 0.0)
	var t := v.create_tween()
	t.tween_property(v, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.9)
	t.tween_property(v, "modulate:a", 0.0, 0.3)
	t.tween_callback(v.queue_free)


func base_hit(mine: bool) -> void:
	Sfx.play("base_hit", 0.05, 0.0 if mine else -8.0)
	if mine:
		_vignette.color.a = 0.3
		create_tween().tween_property(_vignette, "color:a", 0.0, 0.45)


func action_failed(action: String, reason: String) -> void:
	var text := ""
	match reason:
		"gold":
			text = "Not enough mana!"
		"full":
			text = "Board is full!"
		"mismatch":
			text = "Merge needs the same unit and rank"
		"max":
			text = "Already max level"
		_:
			return
	Sfx.play("fail", 0.0)
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast.position.y = _summon.position.y - 44
	var t := create_tween()
	t.tween_property(_toast, "position:y", _toast.position.y - 24, 0.8)
	t.parallel().tween_property(_toast, "modulate:a", 0.0, 0.8).set_delay(0.4)
	if action == "place":
		UiKit.shake_x(_summon)


func show_message(text: String) -> void:
	_message.text = text
	_message.visible = true


func show_result(res: Dictionary, me: int, with_return := false) -> void:
	var w := int(res.winner)
	var won := w == me
	var m := maxi(me, 0)
	var o := 1 - m
	_summon.disabled = true
	_message.visible = false
	Sfx.play("victory" if won else ("defeat" if w >= 0 else "horn"), 0.0)
	_result = UiKit.full_rect(Control.new())
	_root.add_child(_result)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.16, 0.7)
	_result.add_child(UiKit.full_rect(dim))
	var v := UiKit.vbox(18)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.custom_minimum_size = Vector2(470, 0)
	_result.add_child(v)

	var ribbon := PanelContainer.new()
	var rc := Color("3f8ff0") if won else (Color("d8443a") if w >= 0 else Color("e0a42a"))
	var rs := UiKit.chunky(rc, rc.darkened(0.45), 10, false, 8)
	rs.border_width_top = 4
	rs.border_width_left = 4
	rs.border_width_right = 4
	rs.border_color = Color("ffe08a")
	rs.content_margin_top = 10
	rs.content_margin_bottom = 16
	ribbon.add_theme_stylebox_override("panel", rs)
	ribbon.add_child(UiKit.title(UiKit.result_word(w, me), 54))
	v.add_child(ribbon)

	var wood := UiKit.wood_panel()
	var wv := UiKit.vbox(8)
	wood.add_child(wv)
	wv.add_child(UiKit.title(UiKit.reason_text(str(res.reason), won), 20, Color("ffe7b8")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	var kills: Array = res.get("kills", [0, 0])
	var hp: Array = res.get("base_hp", [0, 0])
	var my_name := str(_names[m]) if str(_names[m]) != "" else "You"
	for row in [["", my_name, _opp_display_name()], ["Hearts", hp[m], hp[o]], ["Kills", kills[m], kills[o]]]:
		for i in 3:
			var l := UiKit.title(str(row[i]), 22 if i > 0 else 18, Color.WHITE if i > 0 else Color("ffe7b8"))
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
			grid.add_child(l)
	wv.add_child(grid)
	wv.add_child(UiKit.title("Wave %d   -   %s" % [int(res.get("round", 0)), UiKit.mmss(float(res.get("time", 0.0)))], 18, Color("ffe7b8")))
	v.add_child(wood)
	if with_return:
		var b := UiKit.colored_button("Continue", UiKit.BLUE_BTN, UiKit.BLUE_EDGE, 28, 64)
		b.custom_minimum_size.x = 220
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func(): return_pressed.emit())
		v.add_child(b)
	_result.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_result, "modulate:a", 1.0, 0.25)
	await get_tree().process_frame
	ribbon.pivot_offset = ribbon.size * 0.5
	ribbon.scale = Vector2(0.3, 0.3)
	create_tween().tween_property(ribbon, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
