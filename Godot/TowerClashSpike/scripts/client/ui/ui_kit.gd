class_name UiKit
extends RefCounted
## Code-built UI helpers shared by the app screens and the match HUD (no .tscn/theme assets
## in the spike). Look follows the Rush Royale baseline (Docs/Art_Baseline.md): deep blue
## backgrounds, lighter blue panels, chunky buttons with a darker bottom lip, white text with a
## dark outline, yellow primary actions. The font (Lilita One) is the project theme font.

const BG := Color("1f3f8f")
const BG_DARK := Color("162f6e")
const PANEL := Color("2f5cc0")
const PANEL_LIGHT := Color("4a7be0")
const PANEL_EDGE := Color("6f9cff")
const WOOD := Color("9a6136")
const WOOD_DARK := Color("6e3f1f")
const ACCENT := Color("ffc83a")          # primary yellow
const ACCENT_EDGE := Color("d98a1e")
const BLUE_BTN := Color("3f8ff0")
const BLUE_EDGE := Color("2558b5")
const GREEN_BTN := Color("5ccf4a")
const GREEN_EDGE := Color("2f8f2a")
const GREY_BTN := Color("8a93a6")
const GREY_EDGE := Color("5b6274")
const TEXT := Color(1, 1, 1)
const TEXT_DIM := Color("c6d6ff")
const OUTLINE := Color("1b1630")
const MANA := Color("4fc3ff")
const WIN := Color("6ee36a")
const LOSS := Color("ff6a5c")
const DRAW := Color("ffd84a")
const BRAND := Color(1.0, 0.0, 0.42)     # Mad Lee logo pink #FF006A


static func box(c: Color, radius := 14, border := 0, border_c := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_c
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	return s


## Chunky "3D" box: darker lip at the bottom. pressed shrinks the lip and nudges content down.
static func chunky(c: Color, edge: Color, radius := 16, pressed := false, lip := 6) -> StyleBoxFlat:
	var s := box(c, radius, 0, edge)
	var l := 2 if pressed else lip
	s.border_width_bottom = l
	s.border_width_top = 0
	s.border_color = edge
	s.content_margin_top = 8 + (lip - l)
	s.content_margin_bottom = 8 + l
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 0 if pressed else 3
	s.shadow_offset = Vector2(0, 3)
	return s


static func label(text: String, size := 20, c := TEXT, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func outlined(l: Label, outline := 6) -> Label:
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	return l


## White outlined text, the default for anything on top of art.
static func title(text: String, size := 28, c := TEXT) -> Label:
	return outlined(label(text, size, c), maxi(4, size / 5))


static func button(text: String, size := 24, primary := true, min_h := 64) -> Button:
	return colored_button(text, ACCENT if primary else BLUE_BTN, ACCENT_EDGE if primary else BLUE_EDGE, size, min_h)


static func colored_button(text: String, c: Color, edge: Color, size := 24, min_h := 64) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", size)
	style_button(b, c, edge)
	b.add_theme_constant_override("outline_size", maxi(4, size / 5))
	b.add_theme_color_override("font_outline_color", OUTLINE)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, TEXT)
	b.add_theme_color_override("font_disabled_color", Color(0.85, 0.87, 0.92))
	b.button_down.connect(func(): squish(b))
	b.pressed.connect(func(): Sfx.play("click"))
	return b


static func style_button(b: Button, c: Color, edge: Color) -> void:
	b.add_theme_stylebox_override("normal", chunky(c, edge))
	b.add_theme_stylebox_override("hover", chunky(c.lightened(0.08), edge))
	b.add_theme_stylebox_override("pressed", chunky(c.darkened(0.06), edge, 16, true))
	b.add_theme_stylebox_override("hover_pressed", chunky(c.darkened(0.06), edge, 16, true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", chunky(GREY_BTN, GREY_EDGE))


## Quick press squash for any control (pivot centred).
static func squish(c: Control, amount := 0.92) -> void:
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2(2.0 - amount, amount), 0.05)
	t.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Scale pop (counters, cards, banners).
static func pop(c: Control, peak := 1.25, secs := 0.3) -> void:
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2.ONE * peak, secs * 0.3).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE, secs * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func shake_x(c: Control, px := 8.0) -> void:
	var x0 := c.position.x
	var t := c.create_tween()
	for i in 4:
		t.tween_property(c, "position:x", x0 + (px if i % 2 == 0 else -px) * (1.0 - i * 0.2), 0.04)
	t.tween_property(c, "position:x", x0, 0.04)


static func panel(c := PANEL, radius := 18, edge := PANEL_EDGE, border := 3) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(c, radius, border, edge))
	return p


static func wood_panel(radius := 18) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(WOOD, radius, 4, WOOD_DARK)
	s.border_width_bottom = 8
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 4)
	p.add_theme_stylebox_override("panel", s)
	return p


static func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c


## Deep blue background with a faint diagonal pattern of rounded tiles (menus).
static func patterned_bg() -> Control:
	var c := ColorRect.new()
	c.color = BG
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var step := 70.0
		var col := Color(1, 1, 1, 0.045)
		var y := -step
		var row := 0
		while y < c.size.y + step:
			var x := -step + (step * 0.5 if row % 2 == 1 else 0.0)
			while x < c.size.x + step:
				c.draw_circle(Vector2(x, y), 16.0, col)
				c.draw_circle(Vector2(x - 9, y - 4), 4.0, Color(1, 1, 1, 0.03))
				x += step
			y += step * 0.6
			row += 1)
	return c


static func result_word(winner: int, me: int) -> String:
	return "DRAW" if winner < 0 else ("VICTORY" if winner == me else "DEFEAT")


static func result_color(winner: int, me: int) -> Color:
	return DRAW if winner < 0 else (WIN if winner == me else LOSS)


static func reason_text(reason: String, won: bool) -> String:
	match reason:
		"base_destroyed":
			return "Enemy base destroyed" if won else "Your base was destroyed"
		"both_bases_destroyed":
			return "Both bases fell - decided on score"
		"final_round":
			return "Final round - decided on base HP, then mana"
		"opponent_left":
			return "Opponent left the match" if won else "You left the match"
	return reason


static func mmss(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
