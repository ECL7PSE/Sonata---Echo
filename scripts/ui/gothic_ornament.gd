extends Control
## Code-drawn gothic flourishes.
##
## One node, one _draw(), a handful of motifs, so frames and title blocks keep
## their ornate read with no sprite-sheet art behind them. Every motif is drawn
## from lines and arcs at the node's real size, so it stays sharp at any scale.

enum Kind { CORNERS, DIVIDER, GEAR, CROSS }

@export var kind: int = Kind.CORNERS
@export var line_color := Color("#6f1420")
@export var accent := Color("#b81422")
@export var thickness := 2.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	match kind:
		Kind.DIVIDER:
			_divider()
		Kind.GEAR:
			_gear()
		Kind.CROSS:
			_cross()
		_:
			_corners()


## Four quiet inward arcs with a dot at each corner - a panel's stone flourishes.
## Deliberately just an arc and a dot: an inner arc or a diagonal stem turns the
## motif into something that reads as an arrowhead rather than ornament.
func _corners() -> void:
	var inset := 6.0
	var r := 11.0
	_corner(Vector2(inset + r, inset + r), PI, PI * 1.5, Vector2(inset, inset), r)
	_corner(Vector2(size.x - inset - r, inset + r), PI * 1.5, TAU,
			Vector2(size.x - inset, inset), r)
	_corner(Vector2(size.x - inset - r, size.y - inset - r), 0.0, PI * 0.5,
			Vector2(size.x - inset, size.y - inset), r)
	_corner(Vector2(inset + r, size.y - inset - r), PI * 0.5, PI,
			Vector2(inset, size.y - inset), r)


func _corner(center: Vector2, a0: float, a1: float, tip: Vector2, r: float) -> void:
	draw_arc(center, r, a0, a1, 10, line_color, thickness, false)
	draw_circle(tip, 1.5, accent)


## A horizontal rule broken by a thorn diamond - a heading flourish.
func _divider() -> void:
	var y := size.y * 0.5
	var mid := size.x * 0.5
	draw_line(Vector2(0.0, y), Vector2(mid - 18.0, y), line_color, thickness, false)
	draw_line(Vector2(mid + 18.0, y), Vector2(size.x, y), line_color, thickness, false)
	var d := 7.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(mid, y - d), Vector2(mid + d, y),
		Vector2(mid, y + d), Vector2(mid - d, y)]), accent)
	draw_circle(Vector2(2.0, y), 2.0, accent)
	draw_circle(Vector2(size.x - 2.0, y), 2.0, accent)


## A cog, for the settings entry: a hub ring plus eight teeth.
func _gear() -> void:
	var c := size * 0.5
	var R := minf(size.x, size.y) * 0.5 - 4.0
	for i in 8:
		draw_set_transform(c, float(i) * TAU / 8.0, Vector2.ONE)
		draw_rect(Rect2(-2.5, -R, 5.0, R * 0.34), line_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_arc(c, R * 0.66, 0.0, TAU, 28, line_color, thickness, false)
	draw_circle(c, R * 0.24, accent)


## An X, for a close button.
func _cross() -> void:
	var m := minf(size.x, size.y) * 0.30
	var far := minf(size.x, size.y) - m
	draw_line(Vector2(m, m), Vector2(far, far), accent, 3.0, false)
	draw_line(Vector2(far, m), Vector2(m, far), accent, 3.0, false)
