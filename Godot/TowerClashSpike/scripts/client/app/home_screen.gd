class_name HomeScreen
extends CanvasLayer
## Main menu: horizontally sliding sections (Play / Deck / Profile / Settings) with a bottom
## tab bar and swipe, mirroring the GDD home layout. Shows a match summary on return.

signal play_pressed

const PAGES := ["PLAY", "DECK", "PROFILE", "SETTINGS"]
const SWIPE_PX := 90.0

var profile: Profile
var connection_note := ""

var _root: Control
var _clip: Control
var _strip: Control
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _page := 0
var _name_chip: Label
var _summary: Control
var _press_pos := Vector2.INF


func _ready() -> void:
	layer = 2
	_root = UiKit.full_rect(Control.new())
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(UiKit.full_rect(bg))

	var header := UiKit.hbox()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 24
	header.offset_right = -24
	header.offset_top = 24
	header.offset_bottom = 100
	_root.add_child(header)
	var titles := UiKit.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UiKit.label("TOWER CLASH", 40, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
	titles.add_child(UiKit.label("Godot spike", 16, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	header.add_child(titles)
	var chip := UiKit.panel(UiKit.PANEL_LIGHT, 22)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_chip = UiKit.label("", 18)
	chip.add_child(_name_chip)
	header.add_child(chip)

	_clip = Control.new()
	_clip.clip_contents = true
	_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clip.offset_top = 112
	_clip.offset_bottom = -96
	_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_clip)
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_PASS
	_clip.add_child(_strip)
	for i in PAGES.size():
		var p := MarginContainer.new()
		for side in ["left", "right"]:
			p.add_theme_constant_override("margin_" + side, 24)
		p.add_theme_constant_override("margin_top", 8)
		p.add_theme_constant_override("margin_bottom", 8)
		_strip.add_child(p)
		_pages.append(p)
	_clip.resized.connect(_layout_pages)

	var bar := UiKit.hbox(6)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -88
	bar.offset_bottom = -12
	bar.offset_left = 12
	bar.offset_right = -12
	_root.add_child(bar)
	for i in PAGES.size():
		var b := UiKit.button(PAGES[i], 17, false, 70)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(show_page.bind(i))
		bar.add_child(b)
		_tabs.append(b)

	refresh()
	_layout_pages()
	show_page(0, false)


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
		var base := UiKit.ACCENT if on else UiKit.PANEL_LIGHT
		_tabs[t].add_theme_stylebox_override("normal", UiKit.box(base))
		_tabs[t].add_theme_stylebox_override("hover", UiKit.box(base.lightened(0.12)))
	var target := -_page * _clip.size.x
	if animate:
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
				.tween_property(_strip, "position:x", target, 0.25)
	else:
		_strip.position.x = target


func _input(event: InputEvent) -> void:
	if not visible or _summary != null:
		return
	var press: bool = event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	if not press:
		return
	if event.pressed:
		_press_pos = event.position if _clip.get_global_rect().has_point(event.position) else Vector2.INF
	elif _press_pos != Vector2.INF:
		var d: Vector2 = event.position - _press_pos
		_press_pos = Vector2.INF
		if absf(d.x) > SWIPE_PX and absf(d.x) > absf(d.y) * 1.5:
			show_page(_page + (1 if d.x < 0 else -1))


func refresh() -> void:
	if profile == null:
		return
	_name_chip.text = str(profile.data.name)
	_build_play(_pages[0])
	_build_deck(_pages[1])
	_build_profile(_pages[2])
	_build_settings(_pages[3])


func _clear(page: Control) -> VBoxContainer:
	for c in page.get_children():
		c.queue_free()
	var v := UiKit.vbox(14)
	page.add_child(v)
	return v


# ---------------------------------------------------------------- pages

func _build_play(page: Control) -> void:
	var v := _clear(page)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var qm := UiKit.button("QUICK MATCH", 36, true, 120)
	qm.pressed.connect(func(): play_pressed.emit())
	v.add_child(qm)
	v.add_child(UiKit.label(connection_note, 16, UiKit.TEXT_DIM))
	for t in ["RANKED  (coming soon)", "PRACTICE VS BOT  (coming soon)"]:
		var b := UiKit.button(t, 20, false, 60)
		b.disabled = true
		v.add_child(b)
	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer2)
	if not profile.data.history.is_empty():
		var h: Dictionary = profile.data.history[0]
		var card := UiKit.panel()
		var l := UiKit.label("Last match: %s vs %s  -  round %d, %s" % [
			str(h.result).to_upper(), h.opponent, int(h.round), UiKit.mmss(float(h.time))], 17, _entry_color(h))
		card.add_child(l)
		v.add_child(card)


func _build_deck(page: Control) -> void:
	var v := _clear(page)
	v.add_child(UiKit.label("BATTLE DECK", 26))
	var sheet := SpriteSheet.get_sheet("StandIn_Blocky")
	for type in profile.data.deck:
		var def: Dictionary = GameData.towers[type]
		var row := UiKit.panel()
		var h := UiKit.hbox(16)
		row.add_child(h)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(72, 72)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if sheet != null:
			var fr := sheet.frame("Idle", sheet.direction_for_heading(Vector2(0, 1)), 0)
			var at := AtlasTexture.new()
			at.atlas = fr.texture
			at.region = fr.region
			icon.texture = at
		var c: Array = def.tint
		icon.modulate = Color(c[0], c[1], c[2])
		h.add_child(icon)
		var info := UiKit.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.label(type, 24, Color(c[0], c[1], c[2]), HORIZONTAL_ALIGNMENT_LEFT))
		var extra := ""
		if def.has("splash_radius"):
			extra = "  splash %d" % int(def.splash_radius)
		if def.has("slow_factor"):
			extra = "  slow %d%% %ss" % [int(100 * (1.0 - float(def.slow_factor))), def.slow_time]
		info.add_child(UiKit.label("DMG %d   RNG %d   %s/s%s" % [int(def.damage), int(def.range), def.rate, extra],
				16, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
		info.add_child(UiKit.label("Targets: " + str(def.targeting).capitalize(), 15, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
		h.add_child(info)
		v.add_child(row)
	v.add_child(UiKit.label("Deck editing arrives with the collection screen.", 15, UiKit.TEXT_DIM))


func _build_profile(page: Control) -> void:
	var v := _clear(page)
	var d := profile.data
	v.add_child(UiKit.label(str(d.name), 30))
	var m := int(d.matches)
	var rate := 0 if m == 0 else int(round(100.0 * float(d.wins) / m))
	v.add_child(UiKit.label("%d W  -  %d L  -  %d D     (%d%% wins)" % [int(d.wins), int(d.losses), int(d.draws), rate], 20, UiKit.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for pair in [["Matches", m], ["Kills", int(d.kills)], ["Best round", int(d.best_round)]]:
		var cell := UiKit.panel()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := UiKit.vbox(0)
		cv.add_child(UiKit.label(str(pair[1]), 28))
		cv.add_child(UiKit.label(pair[0], 14, UiKit.TEXT_DIM))
		cell.add_child(cv)
		grid.add_child(cell)
	v.add_child(grid)
	v.add_child(UiKit.label("RECENT MATCHES", 18, UiKit.TEXT_DIM))
	if d.history.is_empty():
		v.add_child(UiKit.label("No matches yet - hit Quick Match.", 17, UiKit.TEXT_DIM))
	for i in mini(6, d.history.size()):
		var h: Dictionary = d.history[i]
		var row := UiKit.panel(UiKit.PANEL, 12)
		var hb := UiKit.hbox()
		row.add_child(hb)
		var w := UiKit.label(str(h.result).to_upper(), 18, _entry_color(h), HORIZONTAL_ALIGNMENT_LEFT)
		w.custom_minimum_size.x = 70
		hb.add_child(w)
		var mid := UiKit.label("vs %s" % h.opponent, 17, UiKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(mid)
		hb.add_child(UiKit.label("R%d  %s" % [int(h.round), UiKit.mmss(float(h.time))], 16, UiKit.TEXT_DIM))
		v.add_child(row)


func _build_settings(page: Control) -> void:
	var v := _clear(page)
	v.add_child(UiKit.label("SETTINGS", 26))
	v.add_child(UiKit.label("Player name", 16, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	var name_edit := LineEdit.new()
	name_edit.text = str(profile.data.name)
	name_edit.max_length = 20
	name_edit.add_theme_font_size_override("font_size", 22)
	name_edit.text_changed.connect(func(t: String):
		if t.strip_edges() != "":
			profile.data.name = t.strip_edges()
			profile.save()
			_name_chip.text = profile.data.name)
	v.add_child(name_edit)

	v.add_child(UiKit.label("Matchmaking", 16, UiKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	var conn := OptionButton.new()
	conn.add_theme_font_size_override("font_size", 20)
	conn.add_item("Online - EOS session search", 0)
	conn.add_item("Local server (direct address)", 1)
	conn.selected = 0 if profile.setting("connection") == "online" else 1
	v.add_child(conn)
	var addr := LineEdit.new()
	addr.text = str(profile.setting("local_address"))
	addr.add_theme_font_size_override("font_size", 20)
	addr.editable = conn.selected == 1
	addr.text_changed.connect(func(t: String): profile.set_setting("local_address", t.strip_edges()))
	v.add_child(addr)
	conn.item_selected.connect(func(i: int):
		profile.set_setting("connection", "online" if i == 0 else "local")
		addr.editable = i == 1
		_build_play(_pages[0]))

	var auto := CheckButton.new()
	auto.text = "Auto-play (bot plays for me)"
	auto.add_theme_font_size_override("font_size", 20)
	auto.button_pressed = bool(profile.setting("autoplay"))
	auto.toggled.connect(func(on: bool): profile.set_setting("autoplay", on))
	v.add_child(auto)

	var reset := UiKit.button("Reset stats", 18, false, 50)
	reset.pressed.connect(func():
		profile.reset_stats()
		refresh())
	v.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var creds := "found" if Online.has_credentials() else "missing"
	var info := UiKit.label("Profile: %s\nEOS credentials: %s\nGodot %s" % [
		ProjectSettings.globalize_path(profile.path), creds, Engine.get_version_info().string], 13, UiKit.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(info)


func _entry_color(h: Dictionary) -> Color:
	return UiKit.WIN if h.result == "win" else (UiKit.LOSS if h.result == "loss" else UiKit.DRAW)


# ---------------------------------------------------------------- match summary

## Overlay shown when returning from a match (GDD 6.1 results). auto_close for bots.
func show_summary(entry: Dictionary, auto_close := 0.0) -> void:
	close_summary()
	_summary = UiKit.full_rect(Control.new())
	_root.add_child(_summary)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	_summary.add_child(UiKit.full_rect(dim))
	var p := UiKit.panel(UiKit.PANEL, 24)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(440, 0)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	_summary.add_child(p)
	var v := UiKit.vbox(12)
	p.add_child(v)
	if entry.is_empty():
		v.add_child(UiKit.label("MATCH ABANDONED", 34, UiKit.DRAW))
		v.add_child(UiKit.label("The connection to the server was lost.", 18, UiKit.TEXT_DIM))
	else:
		var won: bool = entry.result == "win"
		v.add_child(UiKit.outlined(UiKit.label(str(entry.result).to_upper().replace("WIN", "VICTORY").replace("LOSS", "DEFEAT"), 50, _entry_color(entry))))
		v.add_child(UiKit.label(UiKit.reason_text(str(entry.reason), won), 18, UiKit.TEXT_DIM))
		v.add_child(UiKit.label("vs %s" % entry.opponent, 22))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 18)
		for row in [["", "You", "Them"], ["Base HP", entry.base_hp[0], entry.base_hp[1]], ["Kills", entry.kills[0], entry.kills[1]]]:
			for cell in row:
				var l := UiKit.label(str(cell), 20, UiKit.TEXT if row[0] != "" else UiKit.TEXT_DIM)
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(l)
		v.add_child(grid)
		v.add_child(UiKit.label("Round %d   -   %s" % [int(entry.round), UiKit.mmss(float(entry.time))], 18, UiKit.TEXT_DIM))
	var ok := UiKit.button("CONTINUE", 24)
	ok.pressed.connect(close_summary)
	v.add_child(ok)
	_summary.modulate.a = 0.0
	create_tween().tween_property(_summary, "modulate:a", 1.0, 0.25)
	if auto_close > 0.0:
		get_tree().create_timer(auto_close).timeout.connect(close_summary)


func close_summary() -> void:
	if _summary != null:
		_summary.queue_free()
		_summary = null
