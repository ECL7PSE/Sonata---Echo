extends Control
## Tiny hand-drawn charm glyph, one per echo.
##
## Drawn with primitives so the shop and the inventory show the same mark
## without any art files. Give it the echo id and a size; it centres itself.

const GothUI := preload("res://scripts/ui/gothic_ui.gd")

var kind := ""


func _init(id := "") -> void:
	kind = id
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	if s < 6.0:
		return
	var o := (size - Vector2(s, s)) * 0.5
	var gold := Color("#ffd166")
	var cream := Color("#f3e6c4")
	var stone := Color("#8d7f9c")
	match kind:
		"hollow_note":
			draw_arc(o + Vector2(0.34, 0.72) * s, s * 0.15, 0.0, TAU, 22, gold, 2.0)
			draw_line(o + Vector2(0.49, 0.72) * s, o + Vector2(0.49, 0.20) * s, gold, 2.0)
			draw_line(o + Vector2(0.49, 0.20) * s, o + Vector2(0.72, 0.30) * s, GothUI.CYAN, 2.0)
		"metronome":
			var tri := PackedVector2Array([
				o + Vector2(0.30, 0.80) * s,
				o + Vector2(0.70, 0.80) * s,
				o + Vector2(0.50, 0.18) * s,
			])
			draw_colored_polygon(tri, Color("#3a2e46"))
			draw_polyline(PackedVector2Array([tri[0], tri[2], tri[1]]), GothUI.CYAN, 2.0)
			draw_line(o + Vector2(0.50, 0.74) * s, o + Vector2(0.68, 0.30) * s, gold, 2.0)
		"grubsong":
			draw_circle(o + Vector2(0.36, 0.34) * s, s * 0.11, cream)
			draw_circle(o + Vector2(0.50, 0.50) * s, s * 0.13, cream)
			draw_circle(o + Vector2(0.56, 0.68) * s, s * 0.12, cream)
			draw_circle(o + Vector2(0.58, 0.32) * s, s * 0.07, GothUI.CYAN)
			draw_line(o + Vector2(0.65, 0.32) * s, o + Vector2(0.65, 0.14) * s, GothUI.CYAN, 2.0)
		"candle_stub":
			draw_rect(Rect2(o + Vector2(0.37, 0.44) * s, Vector2(0.26, 0.40) * s), cream)
			draw_rect(Rect2(o + Vector2(0.37, 0.44) * s, Vector2(0.26, 0.06) * s), Color("#d9c9a0"))
			draw_circle(o + Vector2(0.50, 0.31) * s, s * 0.11, gold)
			draw_arc(o + Vector2(0.50, 0.31) * s, s * 0.18, 0.0, TAU, 20, Color(1.0, 0.72, 0.3, 0.35), 2.0)
		"dead_mans_toll":
			draw_rect(Rect2(o + Vector2(0.30, 0.30) * s, Vector2(0.40, 0.52) * s), stone)
			draw_arc(o + Vector2(0.50, 0.30) * s, s * 0.20, PI, TAU, 18, stone, 6.0)
			draw_circle(o + Vector2(0.50, 0.56) * s, s * 0.12, gold)
			draw_line(o + Vector2(0.50, 0.48) * s, o + Vector2(0.50, 0.64) * s, Color("#8a6b1f"), 2.0)
		"grave_bell":
			var bell := PackedVector2Array([
				o + Vector2(0.50, 0.16) * s,
				o + Vector2(0.66, 0.62) * s,
				o + Vector2(0.34, 0.62) * s,
			])
			draw_colored_polygon(bell, gold)
			draw_rect(Rect2(o + Vector2(0.28, 0.62) * s, Vector2(0.44, 0.08) * s), Color("#d9b45a"))
			draw_circle(o + Vector2(0.50, 0.78) * s, s * 0.07, GothUI.CRIMSON)
		_:
			draw_arc(size * 0.5, s * 0.32, 0.0, TAU, 24, GothUI.DIM, 2.0)
