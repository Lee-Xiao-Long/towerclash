class_name Glyph
extends Control
## Small vector icons drawn in code (no image assets): mana potion, heart, broken heart, skull,
## crossed swords, card. Size follows the control rect.

var kind := "mana"
var color := Color.WHITE


static func make(p_kind: String, px := 32.0, c := Color.WHITE) -> Glyph:
	var g := Glyph.new()
	g.kind = p_kind
	g.color = c
	g.custom_minimum_size = Vector2(px, px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func set_kind(k: String) -> void:
	kind = k
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var ol := UiKit.OUTLINE
	match kind:
		"mana":
			# Round flask with a neck and cork, blue liquid with a highlight.
			var c := o + Vector2(s * 0.5, s * 0.6)
			draw_rect(Rect2(o + Vector2(s * 0.36, s * 0.06), Vector2(s * 0.28, s * 0.3)), ol)
			draw_rect(Rect2(o + Vector2(s * 0.41, s * 0.1), Vector2(s * 0.18, s * 0.26)), Color("d9ecff"))
			draw_rect(Rect2(o + Vector2(s * 0.39, s * 0.02), Vector2(s * 0.22, s * 0.1)), Color("b07a4a"))
			draw_circle(c, s * 0.38, ol)
			draw_circle(c, s * 0.33, Color("d9ecff"))
			draw_circle(c + Vector2(0, s * 0.04), s * 0.29, UiKit.MANA)
			draw_circle(c + Vector2(-s * 0.12, -s * 0.06), s * 0.07, Color(1, 1, 1, 0.85))
		"heart", "heart_empty":
			var col := Color("ff4d5e") if kind == "heart" else Color("4a3440")
			_heart(o, s, ol, 1.0)
			_heart(o, s, col, 0.8)
			if kind == "heart":
				draw_circle(o + Vector2(s * 0.33, s * 0.33), s * 0.08, Color(1, 1, 1, 0.7))
		"skull":
			var c := o + Vector2(s * 0.5, s * 0.45)
			draw_circle(c, s * 0.36, ol)
			draw_circle(c, s * 0.3, color)
			draw_rect(Rect2(o + Vector2(s * 0.3, s * 0.6), Vector2(s * 0.4, s * 0.25)), color)
			draw_circle(c + Vector2(-s * 0.12, 0), s * 0.09, ol)
			draw_circle(c + Vector2(s * 0.12, 0), s * 0.09, ol)
		"card":
			var r := Rect2(o + Vector2(s * 0.18, s * 0.08), Vector2(s * 0.64, s * 0.84))
			draw_rect(r.grow(s * 0.05), ol)
			draw_rect(r, Color("3f8ff0"))
			draw_rect(r.grow(-s * 0.1), Color("6fb0ff"))
			draw_circle(r.get_center(), s * 0.13, Color("1f3f8f"))
		"swords":
			for sx in [-1.0, 1.0]:
				var a := o + Vector2(s * (0.5 - 0.32 * sx), s * 0.85)
				var b := o + Vector2(s * (0.5 + 0.3 * sx), s * 0.12)
				draw_line(a, b, ol, s * 0.18)
				draw_line(a, b, Color("e8eef2"), s * 0.1)
				var m := a.lerp(b, 0.25)
				var perp := (b - a).orthogonal().normalized() * s * 0.15
				draw_line(m - perp, m + perp, ol, s * 0.12)
				draw_line(m - perp, m + perp, Color("ffc83a"), s * 0.07)


func _heart(o: Vector2, s: float, c: Color, k: float) -> void:
	var cx := o.x + s * 0.5
	var r := s * 0.24 * k
	var top := o.y + s * 0.38
	draw_circle(Vector2(cx - r * 0.95, top), r, c)
	draw_circle(Vector2(cx + r * 0.95, top), r, c)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - r * 1.9, top + r * 0.25), Vector2(cx + r * 1.9, top + r * 0.25), Vector2(cx, o.y + s * (0.5 + 0.42 * k))]), c)
