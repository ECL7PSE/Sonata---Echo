extends SceneTree
## Audits the Walls layer: every non-walkable cell that has NO collision.
##
## _paint_walls only tiles a cell when _is_band or _is_void says so. A cell that
## is neither falls through every branch and is drawn as nothing at all - which
## is a hole in the dungeon the player can walk out of. _is_band scans dy from
## 0 upwards, so it never looks NORTH of a cell, and that is where the misses
## come from.

const BUILDER := preload("res://dungeon_builder.gd")

var _builder: Node2D
var _grid: Array
var _stage := 0
var _frames := 0


func _initialize() -> void:
	_builder = load("res://dungeon.tscn").instantiate()


func _process(_delta: float) -> bool:
	match _stage:
		0:
			root.add_child(_builder)
			_frames = 0
			_stage = 1
		1:
			_frames += 1
			if _frames < 3:
				return false
			_grid = _builder.get("_grid")
			if _grid.is_empty():
				print("RESULT: the builder's _grid is empty - the scene did not build")
				return true
			print("grid: %d rows, %d cols" % [_grid.size(), (_grid[0] as Array).size()])
			_audit()
			return true
	return false


## Bounds-safe walkable. The builder's own _walkable indexes grid[y][x]
## directly, so probing a neighbour one cell outside the map crashes - which is
## exactly what _is_band and _is_void do from the edge.
func _walk(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= BUILDER.MAP_W or cell.y >= BUILDER.MAP_H:
		return false
	return bool(_builder._walkable(_grid, cell))


## _is_band, with the out-of-bounds probes clamped instead of crashing.
func _is_band(cell: Vector2i) -> bool:
	if _walk(cell):
		return false
	for dy in range(0, BUILDER.WALL_RING + 1):
		for dx in range(-BUILDER.WALL_RING, BUILDER.WALL_RING + 1):
			if _walk(Vector2i(cell.x + dx, cell.y + dy)):
				return true
	return false


func _is_void(cell: Vector2i) -> bool:
	if _walk(cell) or _is_band(cell):
		return false
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if _is_band(cell + d):
			return true
	return false


## Would _paint_walls put a collision tile here? Mirrors its branches exactly.
func _has_collision(cell: Vector2i) -> bool:
	if _walk(cell):
		return false
	return _is_band(cell) or _is_void(cell)


func _audit() -> void:
	var holes: Array[Vector2i] = []
	var adjacent_holes: Array[Vector2i] = []
	for y in BUILDER.MAP_H:
		for x in BUILDER.MAP_W:
			var cell := Vector2i(x, y)
			if _walk(cell) or _has_collision(cell):
				continue
			holes.append(cell)
			var reachable := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if _walk(cell + Vector2i(dx, dy)):
						reachable = true
						break
				if reachable:
					break
			if reachable:
				adjacent_holes.append(cell)

	print("non-walkable cells with NO collision : %d" % holes.size())
	print("  of those, adjacent to floor        : %d" % adjacent_holes.size())
	for c in adjacent_holes.slice(0, 30):
		print("    hole at %s" % c)
	if adjacent_holes.size() > 30:
		print("    ... and %d more" % (adjacent_holes.size() - 30))
	print("RESULT: OK")