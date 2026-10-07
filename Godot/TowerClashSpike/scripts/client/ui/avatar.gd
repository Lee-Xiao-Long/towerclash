class_name Avatar
extends Control
## Round player portrait placeholder: coloured ring, face-tone fill and the name's initial.

var letter := "?"
var ring := Color.WHITE
var fill := Color("ffcf8a")


static func make(name_text: String, ring_color: Color, px := 72.0, fill_color := Color("ffcf8a")) -> Avatar:
	var a := Avatar.new()
	a.letter = name_text.substr(0, 1).to_upper() if name_text != "" else "?"
	a.ring = ring_color
	a.fill = fill_color
	a.custom_minimum_size = Vector2(px, px)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return a


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
