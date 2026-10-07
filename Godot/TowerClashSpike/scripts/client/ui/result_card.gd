class_name ResultCard
extends RefCounted
## Victory/defeat card shared by the match HUD and the home-screen summary: a ribbon banner with
## the result word over a wooden stats panel (Rush Royale baseline, refs/images/round-end-*).


## rows: [[label, mine, theirs], ...]; the first row is the header (names).
static func build(word: String, ribbon_color: Color, reason: String, rows: Array, footer: String) -> VBoxContainer:
	var v := UiKit.vbox(18)
	v.custom_minimum_size = Vector2(470, 0)
	var ribbon := PanelContainer.new()
	ribbon.name = "Ribbon"
	var rs := UiKit.chunky(ribbon_color, ribbon_color.darkened(0.45), 10, false, 8)
	rs.border_width_top = 4
	rs.border_width_left = 4
	rs.border_width_right = 4
	rs.border_color = Color("ffe08a")
	rs.content_margin_top = 10
	rs.content_margin_bottom = 16
	ribbon.add_theme_stylebox_override("panel", rs)
	ribbon.add_child(UiKit.title(word, 54))
	v.add_child(ribbon)

	var wood := UiKit.wood_panel()
	var wv := UiKit.vbox(8)
	wood.add_child(wv)
	wv.add_child(UiKit.title(reason, 20, Color("ffe7b8")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	for r in rows.size():
		var row: Array = rows[r]
		for i in 3:
			var header := i == 0 or r == 0
			var l := UiKit.title(str(row[i]), 22 if not header or (r == 0 and i > 0) else 18, Color("ffe7b8") if i == 0 else Color.WHITE)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
			grid.add_child(l)
	wv.add_child(grid)
	wv.add_child(UiKit.title(footer, 18, Color("ffe7b8")))
	v.add_child(wood)
	return v


static func ribbon_color(winner: int, me: int) -> Color:
	if winner < 0:
		return Color("e0a42a")
	return Color("3f8ff0") if winner == me else Color("d8443a")


## Pops the ribbon in once the card has a size (call after adding it to the tree).
static func animate_in(card: Control) -> void:
	var ribbon := card.get_node_or_null("Ribbon") as Control
	if ribbon == null:
		return
	await card.get_tree().process_frame
	ribbon.pivot_offset = ribbon.size * 0.5
	ribbon.scale = Vector2(0.3, 0.3)
	ribbon.create_tween().tween_property(ribbon, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
