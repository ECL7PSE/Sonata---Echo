extends Control
## Procedurally drawn note glyphs for the rhythm duel.
## kind: 0 = attack, 1 = rest, 2 = feint, 3 = halo glow

var kind := 0
var accent := Color("#ff5a5a")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5
	var c: Vector2 = size * 0.5
	match kind:
		0:
			_attack(c, r)
		1:
			_rest(c, r)
		2:
			_feint(c, r)
		_:
			_halo(c, r)


func _attack(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.95, -r * 0.85),
		c + Vector2(r * 0.95, -r * 0.85),
		c + Vector2(0.0, r * 0.98),
	])
	draw_colored_polygon(pts, accent.darkened(0.15))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), accent.lightened(0.45), 2.0, false)
	var core := PackedVector2Array([
		c + Vector2(-r * 0.34, -r * 0.45),
		c + Vector2(r * 0.34, -r * 0.45),
		c + Vector2(0.0, r * 0.5),
	])
	draw_colored_polygon(core, accent.lightened(0.62))


func _rest(c: Vector2, r: float) -> void:
	var outer := PackedVector2Array([
		c + Vector2(0.0, -r * 0.95),
		c + Vector2(r * 0.8, 0.0),
		c + Vector2(0.0, r * 0.95),
		c + Vector2(-r * 0.8, 0.0),
	])
	draw_colored_polygon(outer, accent.darkened(0.42))
	draw_polyline(PackedVector2Array([outer[0], outer[1], outer[2], outer[3], outer[0]]), accent.lightened(0.35), 2.0, false)
	var inner := PackedVector2Array([
		c + Vector2(0.0, -r * 0.45),
		c + Vector2(r * 0.38, 0.0),
		c + Vector2(0.0, r * 0.45),
		c + Vector2(-r * 0.38, 0.0),
	])
	draw_colored_polygon(inner, accent.lightened(0.5))


func _feint(c: Vector2, r: float) -> void:
	draw_arc(c, r * 0.78, 0.0, TAU, 28, accent.darkened(0.1), 3.0, false)
	draw_line(c + Vector2(-r * 0.5, r * 0.5), c + Vector2(r * 0.5, -r * 0.5), accent.lightened(0.5), 3.0, false)
	draw_circle(c, r * 0.16, accent.lightened(0.35))


func _halo(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(accent.r, accent.g, accent.b, 0.22))
	draw_circle(c, r * 0.72, Color(accent.r, accent.g, accent.b, 0.3))
