class_name HomeScreen
extends CanvasLayer
## Main menu in the Rush Royale baseline style (refs/images/IMG_2117.jpeg): blue patterned
## background, profile banner, arena card, wooden deck showcase, big yellow PvP button and a
## bottom tab bar with a raised Battle tab. Pages slide horizontally (tabs or swipe).
## Shows the match summary card on return from a match.

signal play_pressed

const PAGES := ["SHOP", "DECK", "BATTLE", "PROFILE", "SETTINGS"]
const PAGE_ICONS := ["chest", "card", "swords", "person", "gear"]
const BATTLE := 2
## Drag paging: the strip follows the finger with mild resistance (exponential ease-out, scale
## RESIST page widths) and a stiff rubber band past the first/last page. On release it slides
## to the neighbour when dragged past COMMIT_FRAC of a page or flicked faster than FLICK_PAGES
## page widths per second; otherwise it springs back.
const DRAG_START_PX := 14.0
const RESIST := 1.2
const EDGE_RESIST := 0.12
const COMMIT_FRAC := 0.25
const FLICK_PAGES := 1.1
enum Drag { IDLE, PENDING, DRAGGING }
## Placeholder progression derived from real wins (no economy yet): a new arena every 5 wins.
const WINS_PER_ARENA := 5

var profile: Profile
var connection_note := ""

var _root: Control
var _clip: Control
var _strip: Control
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _page := BATTLE
var _summary: Control
var _press_pos := Vector2.ZERO
var _drag := Drag.IDLE
var _raw0 := 0.0
var _vel := 0.0
var _last_x := 0.0
var _last_us := 0
var _cancelling := false
var _tween: Tween
var _deck_pick := 0
var _hero_pick := randi()


func _ready() -> void:
	layer = 2
	_root = UiKit.full_rect(Control.new())
	add_child(_root)
	_root.add_child(UiKit.full_rect(UiKit.patterned_bg()))

	_clip = Control.new()
	_clip.clip_contents = true
	_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clip.offset_bottom = -104
	_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_clip)
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_PASS
	_clip.add_child(_strip)
	for i in PAGES.size():
		var p := MarginContainer.new()
		for side in ["left", "right"]:
			p.add_theme_constant_override("margin_" + side, 18)
		p.add_theme_constant_override("margin_top", 16)
		p.add_theme_constant_override("margin_bottom", 12)
		_strip.add_child(p)
		_pages.append(p)
	_clip.resized.connect(_layout_pages)
	_build_tab_bar()
	refresh()
	_layout_pages()
	show_page(BATTLE, false)


func _build_tab_bar() -> void:
	var bar := PanelContainer.new()
	var bs := UiKit.box(UiKit.BG_DARK, 0)
	bs.border_width_top = 4
	bs.border_color = Color("0f2152")
	bs.content_margin_left = 6
	bs.content_margin_right = 6
	bs.content_margin_top = 8
	bs.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", bs)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -104
	_root.add_child(bar)
	var h := UiKit.hbox(5)
	bar.add_child(h)
	for i in PAGES.size():
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1.5 if i == BATTLE else 1.0
		b.custom_minimum_size = Vector2(0, 86)
		b.pressed.connect(show_page.bind(i))
		b.button_down.connect(func(): UiKit.squish(b))
		b.pressed.connect(func(): Sfx.play("click"))
		var v := UiKit.vbox(0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_bottom = -6
		var g := Glyph.make(PAGE_ICONS[i], 40 if i == BATTLE else 34, Color("c9d2e3"))
		g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(g)
		var l := UiKit.title(PAGES[i].capitalize(), 15)
		l.name = "Caption"
		v.add_child(l)
		b.add_child(v)
		h.add_child(b)
		_tabs.append(b)


func _layout_pages() -> void:
	var w := _clip.size.x
	for i in _pages.size():
		_pages[i].position = Vector2(i * w, 0)
		_pages[i].size = _clip.size
	_strip.position.x = -_page * w


func show_page(i: int, animate := true) -> void:
	_page = clampi(i, 0, PAGES.size() - 1)
	for t in _tabs.size():
		var on := t == _page
		var c := UiKit.ACCENT if on else UiKit.BLUE_BTN
		var e := UiKit.ACCENT_EDGE if on else UiKit.BLUE_EDGE
		UiKit.style_button(_tabs[t], c, e)
		_tabs[t].get_child(0).get_node("Caption").visible = on or t == BATTLE
	var target := -_page * _clip.size.x
	if _tween != null:
		_tween.kill()
	if animate:
		# Duration scales with the distance left, so a release near the target settles quickly.
		var secs := clampf(0.34 * absf(target - _strip.position.x) / maxf(1.0, _clip.size.x), 0.12, 0.34)
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_strip, "position:x", target, secs)
	else:
		_strip.position.x = target


## Uses mouse events only: on iOS/Android touches arrive as emulated mouse events too
## (input_devices/pointing/emulate_mouse_from_touch, on by default), which is also what the
## page buttons see.
func _input(event: InputEvent) -> void:
	if _cancelling:
		return
	if not visible or _summary != null:
		_drag = Drag.IDLE
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _clip.get_global_rect().has_point(event.position):
				return
			_press_pos = event.position
			_last_x = event.position.x
			_last_us = Time.get_ticks_usec()
			_vel = 0.0
			_raw0 = _unresist(_strip.position.x + _page * _clip.size.x)
			_drag = Drag.PENDING
			if _tween != null and _tween.is_running():
				# Catching a sliding page grabs it rather than clicking what is under the finger.
				_tween.kill()
				_drag = Drag.DRAGGING
				get_viewport().set_input_as_handled()
		elif _drag != Drag.IDLE:
			if _drag == Drag.DRAGGING:
				get_viewport().set_input_as_handled()
				_release_drag()
			_drag = Drag.IDLE
	elif event is InputEventMouseMotion and _drag != Drag.IDLE:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_drag = Drag.IDLE
			return
		if _drag == Drag.PENDING:
			var d: Vector2 = event.position - _press_pos
			if maxf(absf(d.x), absf(d.y)) < DRAG_START_PX:
				return
			if absf(d.x) < absf(d.y) * 1.2:
				_drag = Drag.IDLE
				return
			_drag = Drag.DRAGGING
			_press_pos.x = event.position.x
			_cancel_gui_press.call_deferred()
		get_viewport().set_input_as_handled()
		var now := Time.get_ticks_usec()
		var dt := maxf(0.001, (now - _last_us) / 1e6)
		_vel = lerpf(_vel, (event.position.x - _last_x) / dt, 0.5)
		_last_x = event.position.x
		_last_us = now
		var raw: float = _raw0 + event.position.x - _press_pos.x
		_strip.position.x = -_page * _clip.size.x + _resist(raw)


## A drag that started on a button: move the pointer off it and release there, so the button
## drops its pressed state without emitting `pressed`.
func _cancel_gui_press() -> void:
	_cancelling = true
	var far := Vector2(-100000, -100000)
	var mm := InputEventMouseMotion.new()
	mm.position = far
	mm.global_position = far
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(mm)
	var mb := InputEventMouseButton.new()
	mb.position = far
	mb.global_position = far
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = false
	get_viewport().push_input(mb)
	_cancelling = false


func _release_drag() -> void:
	var w := _clip.size.x
	var off := _strip.position.x + _page * w
	if Time.get_ticks_usec() - _last_us > 80000:
		_vel = 0.0  # the finger stopped before lifting: no flick
	var dir := 0
	if absf(_vel) > FLICK_PAGES * w:
		dir = -1 if _vel > 0.0 else 1
	elif absf(off) > COMMIT_FRAC * w:
		dir = -1 if off > 0.0 else 1
	var next := clampi(_page + dir, 0, PAGES.size() - 1)
	if next != _page:
		Sfx.play("click")
	show_page(next)


## Finger offset -> strip offset. Exponential ease-out with scale r page widths: close to 1:1 for
## small drags, increasingly heavy further out; r is small (stiff) where there is no neighbour.
func _resist(raw: float) -> float:
	var w := maxf(1.0, _clip.size.x)
	var r := _resist_scale(raw) * w
	return clampf(signf(raw) * r * (1.0 - exp(-absf(raw) / r)), -w, w)


func _unresist(off: float) -> float:
	var w := maxf(1.0, _clip.size.x)
	var r := _resist_scale(off) * w
	return signf(off) * -r * log(1.0 - minf(absf(off) / r, 0.999))


func _resist_scale(offset: float) -> float:
	var neighbour := _page - int(signf(offset))
	return RESIST if neighbour >= 0 and neighbour < PAGES.size() else EDGE_RESIST


func refresh() -> void:
	if profile == null:
		return
	_hero_pick += 1
	_build_shop(_pages[0])
	_build_deck(_pages[1])
	_build_battle(_pages[2])
	_build_profile(_pages[3])
	_build_settings(_pages[4])


func _clear(page: Control, sep := 14) -> VBoxContainer:
	for c in page.get_children():
		c.queue_free()
	var v := UiKit.vbox(sep)
	page.add_child(v)
	return v


func _spacer(v: Container) -> void:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(s)


func _section_title(text: String) -> Control:
	return UiKit.title(text, 26)


# ---------------------------------------------------------------- pages

func _profile_banner() -> Control:
	var d := profile.data
	var p := PanelContainer.new()
	var s := UiKit.chunky(UiKit.PANEL_LIGHT, UiKit.BLUE_EDGE, 16)
	s.border_width_left = 3
	s.border_width_right = 3
	s.border_width_top = 3
	s.content_margin_left = 10
	p.add_theme_stylebox_override("panel", s)
	var h := UiKit.hbox(12)
	p.add_child(h)
	h.add_child(Avatar.make(str(d.name), Color("3a8ee6"), 64))
	var v := UiKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := UiKit.title(str(d.name), 24)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(n)
	var rec := UiKit.title("%d W  %d L  %d D" % [int(d.wins), int(d.losses), int(d.draws)], 16, UiKit.TEXT_DIM)
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(rec)
	h.add_child(v)
	var tro := UiKit.hbox(4)
	tro.add_child(Glyph.make("trophy", 34))
	tro.add_child(UiKit.title(str(int(d.wins)), 26))
	h.add_child(tro)
	return p


func _build_battle(page: Control) -> void:
	var v := _clear(page, 16)
	v.add_child(_profile_banner())

	# Arena card: shield + name + progress toward the next arena.
	var wins := int(profile.data.wins)
	var arena := 1 + wins / WINS_PER_ARENA
	var arena_row := UiKit.hbox(14)
	arena_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var sh := Glyph.make("shield", 96, Color("b0702a"))
	arena_row.add_child(sh)
	var av := UiKit.vbox(6)
	av.alignment = BoxContainer.ALIGNMENT_CENTER
	av.add_child(UiKit.title("Arena %d" % arena, 32))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(190, 24)
	bar.max_value = WINS_PER_ARENA
	bar.value = wins % WINS_PER_ARENA
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UiKit.box(Color("142a63"), 10, 3, UiKit.OUTLINE))
	bar.add_theme_stylebox_override("fill", UiKit.box(UiKit.ACCENT, 10))
	av.add_child(bar)
	av.add_child(UiKit.title("%d / %d wins" % [wins % WINS_PER_ARENA, WINS_PER_ARENA], 15, UiKit.TEXT_DIM))
	arena_row.add_child(av)
	v.add_child(arena_row)

	# Deck showcase on a wooden board.
	var wood := UiKit.wood_panel()
	var wv := UiKit.vbox(8)
	wood.add_child(wv)
	wv.add_child(UiKit.title("Battle Deck", 22, Color("ffe7b8")))
	var cards := UiKit.hbox(6)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	for t in profile.data.deck:
		cards.add_child(_unit_card(t, 78, "Lvl 1"))
	wv.add_child(cards)
	v.add_child(wood)
	v.add_child(_hero(profile.data.deck[_hero_pick % profile.data.deck.size()]))

	var row := UiKit.hbox(12)
	var pvp := UiKit.button("", 36, true, 104)
	pvp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pvp.size_flags_stretch_ratio = 1.3
	pvp.pressed.connect(func(): play_pressed.emit())
	_icon_caption(pvp, "swords", "PvP")
	row.add_child(pvp)
	var coop := UiKit.colored_button("", UiKit.BLUE_BTN, UiKit.BLUE_EDGE, 30, 104)
	coop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coop.disabled = true
	_icon_caption(coop, "lock", "Co-Op")
	row.add_child(coop)
	v.add_child(row)
	v.add_child(UiKit.title(connection_note, 15, UiKit.TEXT_DIM))
	if not profile.data.history.is_empty():
		var h: Dictionary = profile.data.history[0]
		v.add_child(UiKit.title("Last match: %s vs %s  -  wave %d, %s" % [
			str(h.result).to_upper(), h.opponent, int(h.round), UiKit.mmss(float(h.time))], 16, _entry_color(h)))


## Big portrait of one deck unit on a soft spotlight (fills the space the reference uses for its
## hero banner). Changes each time home is shown.
func _hero(type: String) -> Control:
	var area := Control.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.custom_minimum_size = Vector2(0, 200)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Figures.look_color(GameData.towers[type])
	area.draw.connect(func():
		var c := area.size * 0.5 + Vector2(0, 10)
		var r := minf(area.size.x, area.size.y) * 0.48
		for i in 10:
			var k := 1.0 - i / 10.0
			area.draw_circle(c, r * k, Color(col.lightened(0.5), 0.05 + 0.03 * i))
		area.draw_set_transform(c + Vector2(0, r * 0.62), 0.0, Vector2(1.0, 0.25))
		area.draw_circle(Vector2.ZERO, r * 0.55, Color(0, 0, 0, 0.25))
		area.draw_set_transform(Vector2.ZERO))
	var tex := TextureRect.new()
	tex.texture = FigureIcons.icon(type, 320, 1.6)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(UiKit.full_rect(tex))
	var cap := UiKit.title(type, 26)
	cap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cap.offset_top = -30
	area.add_child(cap)
	return area


func _icon_caption(b: Button, glyph: String, text: String) -> void:
	var h := UiKit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_bottom = -6
	h.add_child(Glyph.make(glyph, 52))
	h.add_child(UiKit.title(text, 38))
	b.add_child(h)


## Tall unit card: coloured frame, rendered portrait, caption strip.
func _unit_card(type: String, w: float, caption: String, selected := false) -> Control:
	var col := Figures.look_color(GameData.towers[type])
	var p := PanelContainer.new()
	var s := UiKit.box(col.lerp(Color("c9d2e3"), 0.45), 12, 4 if not selected else 6, UiKit.OUTLINE if not selected else UiKit.ACCENT)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_content_margin(side, 3)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(w, w * 1.3)
	var v := UiKit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var icon := TextureRect.new()
	icon.texture = FigureIcons.icon(type)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon)
	var cap := PanelContainer.new()
	var cs := UiKit.box(col.darkened(0.35), 8)
	cs.content_margin_top = 0
	cs.content_margin_bottom = 0
	cs.content_margin_left = 2
	cs.content_margin_right = 2
	cap.add_theme_stylebox_override("panel", cs)
	cap.add_child(UiKit.title(caption, 15))
	v.add_child(cap)
	return p


func _build_deck(page: Control) -> void:
	var v := _clear(page, 12)
	v.add_child(_section_title("Battle Deck"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var center := CenterContainer.new()
	center.add_child(grid)
	v.add_child(center)
	var deck: Array = profile.data.deck
	_deck_pick = clampi(_deck_pick, 0, deck.size() - 1)
	for i in deck.size():
		var card := _unit_card(deck[i], 128, deck[i], i == _deck_pick)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_deck_pick = i
				Sfx.play("click")
				_build_deck(_pages[1]))
		grid.add_child(card)
	var t: String = deck[_deck_pick]
	var def: Dictionary = GameData.towers[t]
	var info := UiKit.panel()
	var iv := UiKit.vbox(4)
	info.add_child(iv)
	iv.add_child(UiKit.title(t, 26, Figures.look_color(def).lightened(0.3)))
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 20)
	var rows := [["Damage", str(int(def.damage))], ["Range", str(int(def.range))], ["Attack speed", "%s / s" % def.rate],
		["Targets", str(def.targeting).capitalize()]]
	if def.has("splash_radius"):
		rows.append(["Splash", str(int(def.splash_radius))])
	if def.has("slow_factor"):
		rows.append(["Slow", "%d%% for %ss" % [int(100 * (1.0 - float(def.slow_factor))), def.slow_time]])
	for r in rows:
		var a := UiKit.title(r[0], 18, UiKit.TEXT_DIM)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(a)
		var b := UiKit.title(r[1], 18)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats.add_child(b)
	iv.add_child(stats)
	v.add_child(info)
	_spacer(v)
	v.add_child(UiKit.title("Deck editing arrives with the collection screen.", 15, UiKit.TEXT_DIM))


func _build_shop(page: Control) -> void:
	var v := _clear(page, 14)
	v.add_child(_section_title("Shop"))
	_spacer(v)
	var g := Glyph.make("chest", 140)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(g)
	v.add_child(UiKit.title("Coming soon", 30))
	v.add_child(UiKit.title("Commerce backend not chosen yet.", 16, UiKit.TEXT_DIM))
	_spacer(v)


func _build_profile(page: Control) -> void:
	var v := _clear(page, 12)
	var d := profile.data
	v.add_child(_profile_banner())
	var m := int(d.matches)
	var rate := 0 if m == 0 else int(round(100.0 * float(d.wins) / m))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for pair in [["Matches", m], ["Win rate", "%d%%" % rate], ["Kills", int(d.kills)], ["Best wave", int(d.best_round)]]:
		var cell := UiKit.panel()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := UiKit.vbox(0)
		cv.add_child(UiKit.title(str(pair[1]), 30))
		cv.add_child(UiKit.title(pair[0], 15, UiKit.TEXT_DIM))
		cell.add_child(cv)
		grid.add_child(cell)
	v.add_child(grid)
	v.add_child(UiKit.title("Recent matches", 20, UiKit.TEXT_DIM))
	if d.history.is_empty():
		v.add_child(UiKit.title("No matches yet - tap PvP.", 17, UiKit.TEXT_DIM))
	for i in mini(6, d.history.size()):
		var h: Dictionary = d.history[i]
		var row := UiKit.panel(UiKit.PANEL, 12)
		var hb := UiKit.hbox()
		row.add_child(hb)
		var w := UiKit.title(str(h.result).to_upper(), 18, _entry_color(h))
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		w.custom_minimum_size.x = 70
		hb.add_child(w)
		var mid := UiKit.title("vs %s" % h.opponent, 17)
		mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(mid)
		hb.add_child(UiKit.title("W%d  %s" % [int(h.round), UiKit.mmss(float(h.time))], 16, UiKit.TEXT_DIM))
		v.add_child(row)


func _field_style(c: Control) -> void:
	var s := UiKit.box(Color("142a63"), 10, 3, UiKit.PANEL_EDGE)
	c.add_theme_stylebox_override("normal", s)
	c.add_theme_stylebox_override("focus", UiKit.box(Color("142a63"), 10, 3, UiKit.ACCENT))
	c.add_theme_stylebox_override("read_only", UiKit.box(Color("1b336f"), 10, 3, UiKit.PANEL))
	c.add_theme_color_override("font_color", UiKit.TEXT)


func _setting_label(text: String) -> Label:
	var l := UiKit.title(text, 17, UiKit.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _build_settings(page: Control) -> void:
	var v := _clear(page, 10)
	v.add_child(_section_title("Settings"))
	v.add_child(_setting_label("Player name"))
	var name_edit := LineEdit.new()
	name_edit.text = str(profile.data.name)
	name_edit.max_length = 20
	name_edit.add_theme_font_size_override("font_size", 22)
	_field_style(name_edit)
	name_edit.text_changed.connect(func(t: String):
		if t.strip_edges() != "":
			profile.data.name = t.strip_edges()
			profile.save())
	name_edit.text_submitted.connect(func(_t: String): refresh())
	v.add_child(name_edit)

	v.add_child(_setting_label("Matchmaking"))
	var conn := OptionButton.new()
	conn.add_theme_font_size_override("font_size", 20)
	conn.add_item("Online - EOS session search", 0)
	conn.add_item("Local server (direct address)", 1)
	conn.selected = 0 if profile.setting("connection") == "online" else 1
	UiKit.style_button(conn, UiKit.BLUE_BTN, UiKit.BLUE_EDGE)
	v.add_child(conn)
	var addr := LineEdit.new()
	addr.text = str(profile.setting("local_address"))
	addr.add_theme_font_size_override("font_size", 20)
	addr.editable = conn.selected == 1
	_field_style(addr)
	addr.text_changed.connect(func(t: String): profile.set_setting("local_address", t.strip_edges()))
	v.add_child(addr)
	conn.item_selected.connect(func(i: int):
		profile.set_setting("connection", "online" if i == 0 else "local")
		addr.editable = i == 1
		_build_battle(_pages[BATTLE]))

	for opt in [["sound", "Sound effects"], ["autoplay", "Auto-play (bot plays for me)"]]:
		var cb := CheckButton.new()
		cb.text = opt[1]
		cb.add_theme_font_size_override("font_size", 20)
		cb.add_theme_constant_override("outline_size", 4)
		cb.add_theme_color_override("font_outline_color", UiKit.OUTLINE)
		cb.button_pressed = bool(profile.setting(opt[0]))
		var key: String = opt[0]
		cb.toggled.connect(func(on: bool):
			profile.set_setting(key, on)
			if key == "sound":
				Sfx.set_enabled(on))
		v.add_child(cb)

	var reset := UiKit.colored_button("Reset stats", Color("d8443a"), Color("8f2a22"), 20, 54)
	reset.pressed.connect(func():
		profile.reset_stats()
		refresh())
	v.add_child(reset)
	_spacer(v)
	var creds := "found" if Online.has_credentials() else "missing"
	var info := UiKit.label("Profile: %s\nEOS credentials: %s\nGodot %s" % [
		ProjectSettings.globalize_path(profile.path), creds, Engine.get_version_info().string], 13, UiKit.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(info)


func _entry_color(h: Dictionary) -> Color:
	return UiKit.WIN if h.result == "win" else (UiKit.LOSS if h.result == "loss" else UiKit.DRAW)


# ---------------------------------------------------------------- match summary

## Card shown when returning from a match (GDD 6.1 results). auto_close for bots.
func show_summary(entry: Dictionary, auto_close := 0.0) -> void:
	close_summary()
	_summary = UiKit.full_rect(Control.new())
	_root.add_child(_summary)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.16, 0.75)
	_summary.add_child(UiKit.full_rect(dim))
	var card: VBoxContainer
	if entry.is_empty():
		card = ResultCard.build("ABANDONED", Color("8a93a6"), "The connection to the server was lost.", [["", "", ""]], "")
	else:
		var won: bool = entry.result == "win"
		var word: String = {"win": "VICTORY", "loss": "DEFEAT"}.get(entry.result, "DRAW")
		var col := Color("3f8ff0") if won else (Color("d8443a") if entry.result == "loss" else Color("e0a42a"))
		card = ResultCard.build(word, col, UiKit.reason_text(str(entry.reason), won),
				[["", str(profile.data.name), str(entry.opponent)], ["Hearts", entry.base_hp[0], entry.base_hp[1]], ["Kills", entry.kills[0], entry.kills[1]]],
				"Wave %d   -   %s" % [int(entry.round), UiKit.mmss(float(entry.time))])
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var ok := UiKit.colored_button("Continue", UiKit.BLUE_BTN, UiKit.BLUE_EDGE, 28, 64)
	ok.custom_minimum_size.x = 220
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(close_summary)
	card.add_child(ok)
	_summary.add_child(card)
	_summary.modulate.a = 0.0
	create_tween().tween_property(_summary, "modulate:a", 1.0, 0.25)
	ResultCard.animate_in(card)
	if auto_close > 0.0:
		get_tree().create_timer(auto_close).timeout.connect(close_summary)


func close_summary() -> void:
	if _summary != null:
		_summary.queue_free()
		_summary = null
		refresh()
