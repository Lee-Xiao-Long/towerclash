class_name UiKit
extends RefCounted
## Code-built UI helpers shared by the app screens and the match HUD (no .tscn/theme assets
## in the spike). Colours follow the Mad Lee logo pink on a dark navy base.

const BG := Color(0.07, 0.08, 0.12)
const PANEL := Color(0.12, 0.14, 0.2)
const PANEL_LIGHT := Color(0.18, 0.2, 0.28)
const ACCENT := Color(1.0, 0.0, 0.42)          # logo pink #FF006A
const TEXT := Color(0.94, 0.95, 0.98)
const TEXT_DIM := Color(0.62, 0.66, 0.76)
const WIN := Color(0.35, 0.9, 0.5)
const LOSS := Color(1.0, 0.4, 0.4)
const DRAW := Color(0.95, 0.85, 0.4)


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
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	return l


static func button(text: String, size := 24, primary := true, min_h := 64) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", size)
	var base := ACCENT if primary else PANEL_LIGHT
	b.add_theme_stylebox_override("normal", box(base))
	b.add_theme_stylebox_override("hover", box(base.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", box(base.darkened(0.2)))
	b.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, 14, 2, TEXT))
	b.add_theme_stylebox_override("disabled", box(PANEL.lightened(0.04)))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM.darkened(0.3))
	return b


static func panel(c := PANEL, radius := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(c, radius))
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
			return "Final round - decided on base HP, then gold"
		"opponent_left":
			return "Opponent left the match" if won else "You left the match"
	return reason


static func mmss(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
