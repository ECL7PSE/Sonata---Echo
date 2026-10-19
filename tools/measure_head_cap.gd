extends SceneTree
## Measures the head-vs-cap overlap in the REAL running Main scene.
##
## The previous fix set the collider from the sprite's own ink box. That was the
## wrong reference: the ink says where the ART is, not where the wall is. The
## thing the hat has to clear is the bottom of the wall cell, which is generated
## from the GRID - it has nothing to do with the player's texture.
##
## Every number is read off live nodes after the scene has actually run. Nothing
## here re-derives a value that a script already decided.

const BUILDER := preload("res://dungeon_builder.gd")
const FRAME := 4

var _fails: Array[String] = []
var _checks := 0
var _stage := 0
var _frames := 0
var _main: Node
var _player: Node2D
var _icon: Sprite2D
var _shape: CollisionShape2D
var _dungeon: Node2D
var _grid: Array


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


func _initialize() -> void:
	_main = load("res://Main.tscn").instantiate()


func _process(_delta: float) -> bool:
	match _stage:
		0:
			root.add_child(_main)
			_frames = 0
			_stage = 1
		1:
			_frames += 1
			if _frames < 6:
				return false
			if not _grab_nodes():
				return true
			_report()
			return true
	return false


func _grab_nodes() -> bool:
	_dungeon = _main.get_node_or_null("Dungeon")
	_ok(_dungeon != null, "Main.tscn has no Dungeon node")
	if _dungeon == null:
		return false
	_grid = _dungeon.get("_grid")
	for c in _main.get_children():
		if c.has_method("take_damage") and c.has_method("do_attack"):
			_player = c as Node2D
	_ok(_player != null, "no player in the running scene")
	if _player == null:
		return false
	_icon = _player.get_node_or_null("Icon(Sprite2D)") as Sprite2D
	_shape = _player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	_ok(_icon != null, "player has no Icon sprite")
	_ok(_shape != null, "player has no body CollisionShape2D")
	if _icon == null or _shape == null:
		return false
	return true


## Where the player's visible ink actually starts, in WORLD pixels.
func _ink_top_world() -> float:
	var tex: Texture2D = _icon.texture
	if tex == null:
		return _player.global_position.y
	var img: Image = tex.get_image()
	var fw := img.get_width() / maxi(_icon.hframes, 1)
	var fh := img.get_height() / maxi(_icon.vframes, 1)
	var fx := (FRAME % maxi(_icon.hframes, 1)) * fw
	var fy := (FRAME / maxi(_icon.vframes, 1)) * fh
	var miny := 1 << 30
	for y in fh:
		for x in fw:
			if img.get_pixel(x + fx, y + fy).a > 0.02:
				miny = mini(miny, y)
				break
	if miny > (1 << 29):
		return _player.global_position.y
	var local_y := (miny - fh * 0.5) * _icon.scale.y
	return _icon.global_position.y + local_y


## The bottom edge of the nearest wall cell ABOVE the player, in world pixels.
##
## Found from the GRID, because the walls' collision is generated from the grid.
## Asking the TileMap where its art is would measure the drawing, not the
## obstacle.
func _cap_bottom_world() -> float:
	var cell_size := BUILDER.GRID * BUILDER.SCALE
	var px := int(floor(_player.global_position.x / cell_size))
	var py := int(floor(_player.global_position.y / cell_size))
	for dy in range(1, 6):
		if not bool(_dungeon._walkable(_grid, Vector2i(px, py - dy))):
			return float((py - dy + 1) * cell_size)
	return -1e9
## Three places with a wall to the north: a room (hall), a different room
## (vault), and a corridor. The corridor is the interesting one - its north
## wall is the band between the hall and the vault, not a room edge, so it can
## fail where both rooms pass.
const SPOTS := [
	{"name": "hall", "cell": Vector2i(10, 21)},
	{"name": "vault", "cell": Vector2i(27, 21)},
	{"name": "corridor", "cell": Vector2i(18, 24)},
]


func _cell_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * (BUILDER.GRID * BUILDER.SCALE) \
			+ Vector2(BUILDER.GRID, BUILDER.GRID) * 0.5 * BUILDER.SCALE


func _sweep_boundaries() -> void:
	var cell_px := float(BUILDER.GRID * BUILDER.SCALE)
	var grid: Array = _dungeon.get("_grid")
	# Inline bounds: _in_bounds is an instance method, so it cannot be called on
	# the preloaded class from a --script harness.
	var in_map := func(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 \
				and c.x < BUILDER.MAP_W and c.y < BUILDER.MAP_H
	var is_floor := func(c: Vector2i) -> bool:
		return in_map.call(c) and bool(grid[c.y][c.x] == 1)
	var spots: Array[Vector2i] = []
	# Every boundary cell of every room, every corridor, and every corner.
	for name in BUILDER.ROOMS.keys():
		var r: Rect2i = BUILDER.ROOMS[name]
		for x in range(r.position.x, r.end.x):
			spots.append(Vector2i(x, r.position.y))
			spots.append(Vector2i(x, r.end.y - 1))
		for y in range(r.position.y, r.end.y):
			spots.append(Vector2i(r.position.x, y))
			spots.append(Vector2i(r.end.x - 1, y))
	for c in BUILDER.CORRIDORS:
		var rect: Rect2i = c
		for y in range(rect.position.y, rect.end.y):
			spots.append(Vector2i(rect.position.x, y))
			spots.append(Vector2i(rect.end.x - 1, y))
		for x in range(rect.position.x, rect.end.x):
			spots.append(Vector2i(x, rect.position.y))
			spots.append(Vector2i(x, rect.end.y - 1))
	# The four outer corners of the map.
	spots.append(Vector2i(0, 0))
	spots.append(Vector2i(BUILDER.MAP_W - 1, 0))
	spots.append(Vector2i(0, BUILDER.MAP_H - 1))
	spots.append(Vector2i(BUILDER.MAP_W - 1, BUILDER.MAP_H - 1))

	# Eight directions, so a diagonal escape cannot hide behind an axis one.
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
			Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]
	var escapes: Array[String] = []
	var tried := 0
	for spot in spots:
		if not in_map.call(spot):
			continue
		if not bool(grid[spot.y][spot.x] == 1):
			continue
		for d in dirs:
			tried += 1
			_player.global_position = Vector2(spot) * cell_px \
					+ Vector2(cell_px, cell_px) * 0.5
			_player.set("velocity", Vector2.ZERO)
			var push := Vector2(d) * 4000.0
			for f in 60:
				_player.set("velocity", push)
				_player.call("move_and_slide")
				var cp := _player.global_position
				var cell := Vector2i(int(floor(cp.x / cell_px)), int(floor(cp.y / cell_px)))
				var ok: bool = is_floor.call(cell)
				if not ok:
					escapes.append("%s pushed %s left the floor at %s"
							% [spot, str(d), str(cell)])
					f = 60
	print("boundary sweep: %d boundary cells, %d pushes, %d escape(s)"
			% [spots.size(), tried, escapes.size()])
	for e in escapes.slice(0, 6):
		_ok(false, e)
	_ok(escapes.is_empty(), "%d escape(s) out of the dungeon" % escapes.size())


func _report() -> void:
	var rect: RectangleShape2D = _shape.shape as RectangleShape2D
	print("shape in scene : size %s, node pos %s"
			% [str(rect.size), str(_shape.position)])
	print("player z_index : %d (z_as_relative %s)"
			% [_player.z_index, str(_player.z_as_relative)])
	_ok(rect.size.is_equal_approx(BUILDER.PLAYER_SIZE),
			"the running collider is %s, PLAYER_SIZE says %s - Main.tscn did not apply"
			% [str(rect.size), str(BUILDER.PLAYER_SIZE)])
	_ok(_player.z_index == BUILDER.Z_ACTORS and not _player.z_as_relative,
			"the player draws at z %d (relative %s), expected %d absolute"
			% [_player.z_index, str(_player.z_as_relative), BUILDER.Z_ACTORS])

	var worst := -1e9
	for spot in SPOTS:
		_player.global_position = _cell_world(spot["cell"])
		_player.set("velocity", Vector2.ZERO)
		for i in 30:
			_player.set("velocity", Vector2(0, -4000))
			_player.call("move_and_slide")
		var ink := _ink_top_world()
		var base := _cap_bottom_world()
		# SIGN. y grows DOWNWARD, so ink_top < wall_base means the hat reaches
		# ABOVE the wall cell's floor line, i.e. inside the masonry. That is the
		# overlap, and POSITIVE is bad. Subtracting the other way round reports
		# more clearance as more overlap, which is how an earlier draft of this
		# file "fixed" a box that was never broken.
		var overlap := base - ink
		# The box is deliberately ink height MINUS HEAD_OVERLAP_PX, so the hat is
		# allowed to sit that far inside the wall - that slack is what stops the
		# whole character being pinned a cell back from every north wall. So the
		# budget is HEAD_OVERLAP_PX, not zero.
		var budget: float = BUILDER.HEAD_OVERLAP_PX + 0.25
		print("  %-10s cell %-10s ink_top %8.2f  wall_base %8.2f  overlap %6.2f"
				% [spot["name"], str(spot["cell"]), ink, base, overlap])
		worst = maxf(worst, overlap)
		_ok(base > 0.0, "%s: no wall found north of the player" % spot["name"])
		_ok(overlap <= budget,
				"%s: the hat overlaps the cap by %.2f px, budget %.2f"
				% [spot["name"], overlap, budget])
	_sweep_boundaries()
	print("worst overlap : %.2f px" % worst)
	print("assertions    : %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK")
	else:
		for f in _fails.slice(0, 10):
			print("FAIL: " + f)
		print("RESULT: %d FAILURE(S)" % _fails.size())