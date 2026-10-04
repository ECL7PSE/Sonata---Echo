extends SceneTree
## Proves the dungeon layout is playable and prints it as a picture.
##
## This does not re-implement the rules: it calls the builder's own _build_grid
## and _validate, so what is checked is exactly what gets built. It then boots
## the real Main.tscn and counts the nodes that actually ended up in the tree,
## which catches a layout that validates but never places its props.
##
## It also measures the GENERATED ART, because the art has its own failure modes
## that no cell count can see: a cap tile that renders mostly transparent, a
## collision-only tile that is not actually transparent (which puts the thick
## wall straight back), or a floor that is not darker than the cap.

const BUILDER := preload("res://dungeon_builder.gd")
const SPAWNER := preload("res://enemy_spawner.gd")
const monster_db_preload := preload("res://monster_db.gd")
## Test hook. Set to a room name to drop that room's spawns before checking, so
## the "a room may not ship empty" assertion can be proved to fire instead of
## being assumed to work. Empty in normal runs.
const FORCE_EMPTY_ROOM := ""

var _fails: Array[String] = []
var _builder: Node2D


## Every rule the enemy spawns have to obey, checked against the markers the
## builder actually placed rather than by re-running the planner.
##
## The planner could be self-consistent and still wrong, so nothing here calls
## plan(): it reads the markers, re-derives the geometry from the grid, and
## checks the room/name/count table independently.
func _check_enemy_spawns(builder: Node2D, grid: Array) -> void:
	var spawns: Array = builder._place_enemy_spawns_probe(grid)
	var walkable: Callable = builder._safe_walkable(grid)
	var start: Vector2i = builder._room_centre(builder.ROOM_HALL)

	# Group the markers by room. Read the room from the data, NOT by splitting the
	# marker name: "Spawn_bone_hall_2_35".split("_")[1] is "bone", which silently
	# reported every underscored room as empty.
	var by_room: Dictionary = {}
	for entry in spawns:
		var room := str(entry["room"])
		if FORCE_EMPTY_ROOM != "" and room == FORCE_EMPTY_ROOM:
			continue
		if not by_room.has(room):
			by_room[room] = []
		by_room[room].append(entry)

	print("")
	print("enemy spawns   :")
	var seen_species: Array[String] = []
	for room_name in builder.ROOMS:
		var key := SPAWNER.monster_key(room_name)
		var cells: Array = by_room.get(room_name, [])
		if key == "":
			# The hall and the shaft must be clean.
			if cells.size() != 0:
				_fail("room %s has %d enemies but must have none"
						% [room_name, cells.size()])
			print("  %-11s %-12s %d (expected 0, no trigger)"
					% [room_name, "-", cells.size()])
			continue
		var target := SPAWNER.enemy_count(builder.ROOMS[room_name], room_name)
		if cells.size() < SPAWNER.MIN_ENEMY:
			_fail("room %s placed %d of %d %s - a room may not ship empty. "
					% [room_name, cells.size(), target, key]
					+ "candidates=%s blocked=%s"
					% [str(builder._room_candidates(grid, builder.ROOMS[room_name])),
					str(SPAWNER.props())])
		if cells.size() > SPAWNER.MAX_ENEMY:
			_fail("room %s placed %d enemies, over the cap of %d"
					% [room_name, cells.size(), SPAWNER.MAX_ENEMY])
		# A named override is a deliberate design decision, so it is asserted
		# exactly rather than allowed to drift within the 2..6 band.
		if SPAWNER.COUNT_OVERRIDE.has(room_name):
			var want_exact: int = SPAWNER.COUNT_OVERRIDE[room_name]
			if cells.size() != want_exact:
				_fail("room %s is pinned to exactly %d enemies but placed %d"
						% [room_name, want_exact, cells.size()])
		if not seen_species.has(key):
			seen_species.append(key)

		# Per-spawn rules.
		for entry in cells:
			var cell: Vector2i = entry["cell"]
			if not bool(walkable.call(cell)):
				_fail("spawn %s at %s is not floor" % [room_name, cell])
			var wall := SPAWNER.wall_clearance_px(walkable, cell)
			if wall < SPAWNER.WALL_CLEARANCE_PX:
				_fail("spawn %s at %s is %.0fpx from a wall, need %.0f"
						% [room_name, cell, wall, SPAWNER.WALL_CLEARANCE_PX])
			if not builder.ROOMS[room_name].has_point(cell):
				_fail("spawn %s at %s is outside its room" % [room_name, cell])
			for b in SPAWNER.props():
				var prop := b as Vector2i
				if Vector2(prop - cell).length() * 32.0 \
						< SPAWNER.PROP_CLEARANCE_PX:
					_fail("spawn %s at %s is too close to a prop at %s"
							% [room_name, cell, prop])
			if Vector2(start - cell).length() * 32.0 \
					< SPAWNER.SPAWN_CLEARANCE_PX:
				_fail("spawn %s at %s is within %.0fpx of PlayerStart"
						% [room_name, cell, SPAWNER.SPAWN_CLEARANCE_PX])
		# No two spawns on top of each other.
		for i in cells.size():
			for j in range(i + 1, cells.size()):
				var a: Vector2i = cells[i]["cell"]
				var b: Vector2i = cells[j]["cell"]
				if Vector2(a - b).length() * 32.0 < 32.0:
					_fail("spawns %s at %s and %s overlap"
							% [room_name, a, b])
		print("  %-11s %-12s %d/%d" % [room_name, key, cells.size(), target])

	for want in ["RAT", "SLIME", "BAT", "MUSHROOM", "FLYING_EYE", "GOBLIN",
			"SKELETON"]:
		if not seen_species.has(want):
			_fail("no room spawns a %s" % want)
	print("  species seen : %d/7 (mimic lands in 3B-2b)"
			% seen_species.size())


## The dormant Mimics: exact counts, all still DORMANT, and room for the awake
## body they will become.
##
## These read the built dungeon rather than re-running the planner, so a mimic
## that was placed and then woken, moved, or given the wrong species cannot slip
## past.
func _check_mimic_placement(builder: Node2D, grid: Array) -> void:
	var walkable: Callable = builder._safe_walkable(grid)
	var props: Node = null
	if _live_main != null:
		props = _live_main.get_node_or_null("Dungeon/Props")
	print("")
	print("mimic dens     :")
	var mimic_script := preload("res://mimic.gd")
	for room_name in SPAWNER.MIMIC_DENS:
		var spec: Dictionary = SPAWNER.MIMIC_DENS[room_name]
		var want: int = int(spec["count"])
		var chest: Vector2i = spec["chest"]
		var found: Array[Node] = []
		if props != null:
			for child in props.get_children():
				if str(child.name).begins_with("Mimic_%s_" % room_name):
					found.append(child)
		_ok(found.size() == want,
			"%s has %d dormant mimics, expected exactly %d"
					% [room_name, found.size(), want])
		var half := SPAWNER.awake_half_width() / SPAWNER.SCREEN_PX_PER_TILE
		var height := float(monster_db_preload.MIMIC["body"].y) \
				* float(monster_db_preload.MIMIC["scale"]) \
				/ SPAWNER.SCREEN_PX_PER_TILE
		for m in found:
			_ok(m.get_script() == mimic_script,
				"%s is a %s, not a mimic" % [m.name, m.get_script()])
			# DORMANT is what makes it a chest. A mimic that woke during load
			# would be a free 3 hp hit for the player standing in the doorway.
			_ok(m.chain == mimic_script.Chain.DORMANT,
				"%s is not DORMANT at start (chain %d)" % [m.name, m.chain])
			_ok(m.sprite.material == null,
				"%s has a material; a dormant mimic must light like a chest"
						% m.name)
			# Same z as the chests they impersonate.
			_ok(int(m.z_index) == 0,
				"%s has z_index %d, chests are 0" % [m.name, m.z_index])
			var cell := Vector2i(int(floor(m.position.x / 16.0)),
					int(floor(m.position.y / 16.0)))
			_ok(builder.ROOMS[room_name].has_point(cell),
				"%s is outside its room at %s" % [m.name, cell])
			_ok(Vector2(cell - chest).length() <= SPAWNER.MIMIC_NEAR_TILES,
				"%s at %s is %.1f tiles from its chest, max %d"
						% [m.name, cell,
						Vector2(cell - chest).length(), SPAWNER.MIMIC_NEAR_TILES])
			_ok(Vector2(cell - chest).length() * 32.0 >= 32.0,
				"%s is on top of its chest at %s" % [m.name, cell])
			# Room for the awake body, measured against the grid.
			var centre := Vector2(cell) + Vector2(0.5, 0.5)
			var from := Vector2i(floori(centre.x - half),
					floori(centre.y - height))
			var to := Vector2i(floori(centre.x + half - 0.001),
					floori(centre.y - 0.001))
			var clear := true
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					if not bool(walkable.call(Vector2i(x, y))):
						clear = false
			_ok(clear,
				"%s at %s: the awake body overlaps a wall (needs %.1fpx clearance)"
						% [m.name, cell, SPAWNER.mimic_wall_clearance_px()])
		print("  %-11s %d/%d dormant, clearance %.1fpx, chest %s"
				% [room_name, found.size(), want,
				SPAWNER.mimic_wall_clearance_px(), chest])


## Records a failure. check_layout has no assertion counter of its own - it is a
## rule engine that fails loudly - so mimic checks add their own count so the
## run_all_tests summary can still see them.
var _checks := 0
## The instantiated Main.tscn, kept so mimic checks read real placed nodes.
var _live_main: Node = null
## The built grid, kept so the mimic checks can measure awake-body clearance
## against the same floor the dungeon was carved from.
var _grid: Array = []


func _ok(condition: bool, message: String) -> bool:
	_checks += 1
	return _fail_ok(condition, message)


func _fail_ok(condition: bool, message: String) -> bool:
	if not condition:
		_fails.append(message)
	return condition


func _fail(message: String) -> void:
	_fails.append(message)


func _initialize() -> void:
	var builder: Node2D = BUILDER.new()
	_builder = builder
	var grid: Array = builder._build_grid()
	# Kept for the mimic checks, which run at the end and need the same floor.
	_grid = grid

	var problems: Array = builder._validate(grid)
	for p in problems:
		_fails.append(str(p))

	_check_removed_hallway(builder, grid)
	_check_enemy_spawns(builder, grid)
	_print_map(builder, grid)

	# Wall census. The wall:floor ratio decides whether the map reads as rooms
	# or as noise, so it is printed explicitly.
	#
	# cap_cells are visible masonry. block_cells are the transparent
	# collision-only tiles that replaced masonry on the side and bottom edges.
	# The split between them is the whole point of the thin-wall change.
	var floor_cells := 0
	var cap_cells := 0
	var block_cells := 0
	var rim_cells := 0
	var no_collision := 0
	var tileset: TileSet = builder._build_tileset()
	for y in builder.MAP_H:
		for x in builder.MAP_W:
			var cell := Vector2i(x, y)
			if _walkable(grid, cell):
				floor_cells += 1
			elif builder._is_band(grid, cell):
				if builder._is_cap(grid, cell):
					cap_cells += 1
				else:
					block_cells += 1
				# Every band cell must still block, or the player walks out.
				if not _collides(tileset, builder.SRC_WALL,
						Vector2i(builder.WALL_BLOCK, 0)):
					no_collision += 1
			elif builder._is_void(grid, cell):
				rim_cells += 1
				if not _collides(tileset, builder.SRC_WALL,
						Vector2i(builder.WALL_BLOCK, 0)):
					no_collision += 1

	print("\nwalkable cells : %d" % floor_cells)
	print("cap cells      : %d  (visible brick, north edges only)" % cap_cells)
	print("block cells    : %d  (transparent, still solid)" % block_cells)
	print("rim cells      : %d" % rim_cells)
	print("walls per floor: %.2f" % [
		float(cap_cells + block_cells) / maxf(float(floor_cells), 1.0)])

	if no_collision > 0:
		_fails.append(("%d band/rim cell(s) have no collision, so the player can "
			+ "walk out through the invisible edge") % no_collision)
	if cap_cells == 0:
		_fails.append("no cap cells were painted, so the walls have no masonry")
	if floor_cells == 0:
		_fails.append("no floor cells at all")

	_check_torches(builder, grid)
	_check_variant_coverage(builder)
	_check_art(builder, tileset)
	_check_band_inside_grid(builder, grid)
	_check_reachability(builder, grid)
	_check_no_overlap(builder)
	_check_room_parity(builder, grid)
	_check_base_collision(builder, grid)
	_check_prop_placement(builder, grid)
	_check_shaft_width(builder, grid)
	_check_draw_order(builder)
	_check_corridor_passable(builder)
	_check_no_collision_holes(builder, grid)


## Every band cell within WALL_RING of a walkable cell must land INSIDE the grid.
##
## A room hugging the edge (x=1, or y=1) makes its two-cell band need cells at
## -1, which do not exist. _is_band silently returns false for out-of-bounds
## neighbours, so that room ends up with a ONE-cell wall on that side: the wall
## and the cyan outline that traces it get clipped against the edge of the map.
## Nothing else notices, because the player is still stopped - the wall is just
## half the thickness it is everywhere else. That is exactly the bug that put
## bone_hall at x=1 before it was moved to x=2.
func _check_band_inside_grid(builder: Node2D, grid: Array) -> void:
	var clipped: Array[String] = []
	for y in builder.MAP_H:
		for x in builder.MAP_W:
			var cell := Vector2i(x, y)
			if not _walkable(grid, cell):
				continue
			for dy in range(-builder.WALL_RING, builder.WALL_RING + 1):
				for dx in range(-builder.WALL_RING, builder.WALL_RING + 1):
					var n := cell + Vector2i(dx, dy)
					if n.x < 0 or n.y < 0 or n.x >= builder.MAP_W \
							or n.y >= builder.MAP_H:
						clipped.append("%s (wall runs off the grid at %s)" % [cell, n])
	print("band in grid  : %s" % ["OK" if clipped.is_empty()
		else "%d walkable cell(s) with a clipped band" % clipped.size()])
	for c in clipped:
		_fails.append(c)


## Flood fills from the spawn and requires every room to be reachable.
##
## _validate already checks that every walkable cell is reachable, but this
## additionally proves it ROOM BY ROOM, which is what catches a new room added to
## ROOMS but never wired to a corridor: it would be a sealed box that the
## room-level check names precisely.
func _check_reachability(builder: Node2D, grid: Array) -> void:
	var origin: Vector2i = builder._room_centre(builder.ROOM_START)
	var seen: Dictionary = builder._flood(grid, origin)
	var unreachable: Array[String] = []
	for room_name in builder.ROOMS.keys():
		var centre: Vector2i = builder._room_centre(builder.ROOMS[room_name])
		var found := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if seen.has(centre + Vector2i(dx, dy)):
					found = true
					break
			if found:
				break
		if not found:
			unreachable.append(room_name)
	print("reachability  : %d/%d rooms reachable from spawn %s" % [
		builder.ROOMS.size() - unreachable.size(), builder.ROOMS.size(), origin])
	for r in unreachable:
		_fails.append("room '%s' cannot be walked to from the spawn" % r)


## No two rooms may overlap. Overlapping rooms silently merge into one bigger
## room, which breaks the one-monster-per-room plan and corrupts the torch
## per-room tally below.
func _check_no_overlap(builder: Node2D) -> void:
	var names: Array = builder.ROOMS.keys()
	var clashes: Array[String] = []
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2i = builder.ROOMS[names[i]]
			var b: Rect2i = builder.ROOMS[names[j]]
			if a.intersects(b):
				clashes.append("rooms '%s' %s and '%s' %s overlap" % [
					names[i], a, names[j], b])
	print("room overlap  : %s" % ["none" if clashes.is_empty()
		else "%d overlapping pair(s)" % clashes.size()])
	for c in clashes:
		_fails.append(c)


## Every room must have visible masonry on a north-facing edge, and the four
## APPENDED rooms must also have at least two lights.
##
## The cap rule applies everywhere: a room with zero caps reads as a hole in the
## world. The torch rule deliberately applies ONLY to the new rooms. The global
## TORCH_MIN_PER_ROOM is 0 and the original five have always been allowed to
## render with zero or one light - that is existing, tuned lighting, and the brief
## forbids changing it. So cistern (0) and hall/vault (1) are reported as-is and
## only the appended rooms are held to the minimum.
func _check_room_parity(builder: Node2D, grid: Array) -> void:
	var torches: Array = builder._build_torches(grid)
	var per_room := {}
	for t in torches:
		var owner := ""
		for room_name in builder.ROOMS.keys():
			if builder.ROOMS[room_name].has_point(t):
				owner = room_name
				break
		per_room[owner] = int(per_room.get(owner, 0)) + 1
	var bad: Array[String] = []
	for room_name in builder.ROOMS.keys():
		var rect: Rect2i = builder.ROOMS[room_name]
		var caps := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if builder._is_cap(grid, Vector2i(x, y)):
					caps += 1
		var lights := int(per_room.get(room_name, 0))
		var is_new: bool = builder.ROOM_MIN_TORCH.has(room_name)
		print("  %-11s cap %3d   torches %d%s" % [room_name, caps, lights,
			"   (appended)" if is_new else "   (original)"])
		if caps == 0:
			bad.append("room '%s' has no visible wall cap" % room_name)
		if is_new and lights < 2:
			bad.append("appended room '%s' has only %d torch(es), needs 2"
				% [room_name, lights])
	# The shaft lights are listed rather than generated, so they are not in the
	# per-room tally above; check they are on real floor and clear of traps.
	for s in builder.SHAFT_LIGHTS:
		if not _walkable(grid, s):
			bad.append("shaft light %s is not on walkable floor" % s)
		elif builder.TRAPS.has(s):
			bad.append("shaft light %s sits on a trap" % s)
	for b in bad:
		_fails.append(b)


## Every chest and trap must be on real floor and clear of the lights.
##
## The STRICT rules - a clear cell on every side, and 5+ cells from PlayerStart -
## apply only to props in the APPENDED rooms. The original props deliberately
## break them and must not be moved:
##
##   * the hall chest (8,26) sits 2 cells from the spawn because it is the start
##     room's reward chest, and the start room is meant to be walkable and safe.
##
## No trap is exempt any more: every trap is room floor and at least 3 cells
## from any corridor cell, so the STRICT rules now cover all of them.
##
## Appending rooms get the stricter treatment so a new chest can never be placed
## somewhere the player cannot stand beside, and a new trap can never land on
## top of the player as the run starts.
func _check_prop_placement(builder: Node2D, grid: Array) -> void:
	var torches: Array = builder._build_torches(grid)
	for s in builder.SHAFT_LIGHTS:
		torches.append(s)
	var start_cell: Vector2i = builder._room_centre(builder.ROOM_START)
	var bad: Array[String] = []
	var strict := 0
	var loose := 0
	for kind_name in [["chest", builder.CHESTS], ["trap", builder.TRAPS]]:
		var kind: String = kind_name[0]
		for cell in kind_name[1]:
			# Corridor clearance is absolute and applies to EVERY trap, on top of
			# whichever placement rule the room it sits in would otherwise use.
			if kind == "trap":
				bad.append_array(_trap_corridor_problems(builder, cell))
			var is_new: bool = _in_appended_room(builder, cell)
			if is_new:
				strict += 1
				bad.append_array(_prop_problems(builder, grid, torches,
					start_cell, cell, kind))
			else:
				loose += 1
				bad.append_array(_prop_problems_loose(builder, grid, cell, kind))
	print("prop placement: %d appended (strict), %d original (as-is), %s" % [
		strict, loose, "all valid" if bad.is_empty()
		else "%d PROBLEM(S)" % bad.size()])
	for b in bad:
		_fails.append(b)


## The absolute trap rule, checked for every trap regardless of its room.
##
## A trap may not occupy a corridor cell, and may not sit within 2 cells of one
## (Chebyshev). A 3-wide corridor is exactly the player's half-width plus its
## own width, so a trap a cell off the centre line leaves a single 1-tile lane
## on the far side - often underneath the wall cap - and the crossing becomes a
## squeeze rather than a readable hazard.
func _trap_corridor_problems(builder: Node2D, cell: Vector2i) -> Array[String]:
	var out: Array[String] = []
	if builder._in_corridor(cell):
		out.append("trap at %s sits IN a corridor" % cell)
		return out
	for c in builder.CORRIDORS:
		# Both the loop var and the derived rect are typed explicitly: CORRIDORS
		# is an untyped Array, so `c` is a Variant and GDScript will not infer
		# anything from `c.position + c.size` (that is a parse error, not a
		# warning). Naming it `end` additionally shadows Rect2i.end.
		var rect: Rect2i = c
		var far: Vector2i = rect.position + rect.size
		for y in range(rect.position.y, far.y):
			for x in range(rect.position.x, far.x):
				var near := Vector2i(x, y)
				var d := Vector2i(absi(near.x - cell.x), absi(near.y - cell.y))
				if d.x <= 2 and d.y <= 2:
					out.append("trap at %s is %d cells from the corridor at %s"
							% [cell, maxi(d.x, d.y), near])
					return out
	return out


## Draw order: actors in front of the masonry, outline behind them.
##
## This is a regression guard for a visible bug, not a style rule. The player
## and the enemies both used to sit at the default z 0 while the wall cap was at
## z 1, so walking north along a wall drew the cap straight across the head and
## tall monsters were cut off at the neck. It also pins requirement 3: the 1px
## cyan Outline must stay UNDER the player and the enemies, or it draws across
## their faces.
##
## Everything here is asserted against the CONSTANTS and against a freshly made
## layer set, not against the live tree: check_layout probes the builder before
## _ready() has run, so the real Walls/Outline/Props nodes do not exist yet. The
## player is a static property of Main.tscn, so its z is read from the scene
## file's parsed value via the constant it must agree with.
func _check_draw_order(builder: Node2D) -> void:
	var z_actors: int = builder.Z_ACTORS
	var z_walls: int = builder.Z_WALLS
	var z_outline: int = builder.Z_OUTLINE
	var z_props: int = builder.Z_PROPS

	# The core of it: actors must be strictly above the cap AND the outline.
	_ok(z_actors > z_walls,
			"Z_ACTORS (%d) must be above Z_WALLS (%d), or the wall cap cuts the "
			% [z_actors, z_walls] + "player's head off")
	_ok(z_actors > z_outline,
			"Z_ACTORS (%d) must be above Z_OUTLINE (%d), or the cyan line draws "
			% [z_actors, z_outline] + "across the player's face")
	# Actors now draw ABOVE props, so a chest is never drawn over the player.
	# This inverts the old rule, which asserted props above actors.
	_ok(z_actors > z_props,
			"Z_ACTORS (%d) must be above Z_PROPS (%d), or a chest draws over the "
			% [z_actors, z_props] + "player standing in front of it")
	# ...but props still have to clear everything they used to clear.
	_ok(z_props > z_walls,
			"Z_PROPS (%d) must stay above Z_WALLS (%d), or torches draw behind "
			% [z_props, z_walls] + "the wall cap they are mounted on")
	_ok(z_props > z_outline,
			"Z_PROPS (%d) must stay above Z_OUTLINE (%d)" % [z_props, z_outline])
	# Flat things the player stands ON must stay under everything.
	_ok(builder.Z_HAZARDS < z_actors,
			"Z_HAZARDS (%d) must stay under Z_ACTORS (%d), or the spikes draw "
			% [builder.Z_HAZARDS, z_actors] + "over the player again")
	_ok(builder.Z_FLOOR < z_walls,
			"Z_FLOOR (%d) must stay under Z_WALLS (%d)"
			% [builder.Z_FLOOR, z_walls])

	# The layers the builder actually builds must use those constants, so a
	# later edit cannot leave the constant right and the node wrong.
	var made: Dictionary = builder._make_layers(_tileset_for_check())
	_ok(made.has("wall") and int(made["wall"].z_index) == z_walls,
			"the Walls layer is not built at Z_WALLS")
	_ok(made.has("edge") and int(made["edge"].z_index) == z_outline,
			"the Outline layer is not built at Z_OUTLINE")
	_ok(made.has("floor") and int(made["floor"].z_index) == builder.Z_FLOOR,
			"the Floor layer is not built at Z_FLOOR")
	for k in made.keys():
		var c: CanvasItem = made[k]
		# y_sort would silently defeat every z comparison above.
		_ok(not c.y_sort_enabled,
				"%s has y_sort enabled, which reorders it against fixed z" % c.name)
		if is_instance_valid(c):
			c.free()


## A throwaway TileSet. _make_layers only stores the reference on each layer, so
## the contents never matter here and none of this reaches the screen.
func _tileset_for_check() -> TileSet:
	return TileSet.new()


## The player must still fit through a MIN_CORRIDOR-wide gap.
##
## The collider is now 16x51 rather than 20x16. It got much TALLER, and a tall
## box is what can wedge in a doorway, so this is checked explicitly rather than
## assumed: the box has to fit inside MIN_CORRIDOR cells across BOTH axes, and
## the width has to stay under the 0.6-tile rule so the art can overhang.
func _check_corridor_passable(builder: Node2D) -> void:
	var size: Vector2 = builder.PLAYER_SIZE
	var cell_px: float = builder.GRID * builder.SCALE
	var gap: float = builder.MIN_CORRIDOR * cell_px

	_ok(size.x <= gap,
			"player collider is %.0f px wide, a %d-cell gap is only %.0f px"
			% [size.x, builder.MIN_CORRIDOR, gap])
	_ok(size.y <= gap,
			"player collider is %.0f px tall, a %d-cell gap is only %.0f px - "
			% [size.y, builder.MIN_CORRIDOR, gap]
			+ "it would wedge in a doorway")
	# The stated design rule: the collider stays narrower than 0.6 of a tile so
	# corridors stay easy even though the drawn sprite is wider than the box.
	_ok(size.x < cell_px * 0.6,
			"player collider is %.1f px wide, over the 0.6-tile limit of %.1f px"
			% [size.x, cell_px * 0.6])

	# The lane height is what the player can actually walk through: the corridor
	# minus the feet box. The brief asks for at least 1.75 tiles (56 px).
	var lane: float = gap - size.y
	_ok(lane >= MIN_LANE_PX,
			"lane in a %d-cell corridor is %.1f px, need %.0f (%.2f tiles)"
			% [builder.MIN_CORRIDOR, lane, MIN_LANE_PX, lane / cell_px])
	print("corridor lane : %.1f px in a %d-cell gap (box %.1f tall), need %.0f"
			% [lane, builder.MIN_CORRIDOR, size.y, MIN_LANE_PX])

	# And the real thing: every declared corridor must actually be wide enough.
	for c in builder.CORRIDORS:
		var rect: Rect2i = c
		var across: int = mini(rect.size.x, rect.size.y)
		_ok(across >= builder.MIN_CORRIDOR,
				"corridor %s is only %d cell(s) across, need %d"
				% [rect, across, builder.MIN_CORRIDOR])


## Minimum clear lane the player must have in a MIN_CORRIDOR corridor: 1.75
## tiles, so the feet own most of the corridor's height.
const MIN_LANE_PX := 56.0


## No non-walkable cell that touches floor may lack collision.
##
## This is the assertion the "player walks out of the map" bug needed and never
## had. _is_band scans dy from 0 and so never looks north of a cell, which left
## 385 cells with neither art nor collision - 58 of them touching floor, in
## unbroken runs along y=13, y=29 and y=40. Checking every 8-neighbour of every
## walkable cell catches exactly the holes a player can reach.
##
## The layers are BUILT here rather than read from the live tree: check_layout
## probes the builder before _ready(), so the real Walls layer does not exist
## yet. _paint_walls + _seal_walls is the same pair the game runs, so this is a
## check of what ships, not of a reimplementation.
func _check_no_collision_holes(builder: Node2D, grid: Array) -> void:
	var layers: Dictionary = builder._make_layers(_tileset_for_check())
	builder._paint_walls(layers["wall"], layers["edge"], grid)
	builder._seal_walls(layers["wall"], grid)
	var wall_layer: TileMapLayer = layers["wall"]
	var holes: Array[String] = []
	for y in builder.MAP_H:
		for x in builder.MAP_W:
			var cell := Vector2i(x, y)
			if builder._walkable(grid, cell):
				continue
			var touches := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if builder._walkable(grid, cell + Vector2i(dx, dy)):
						touches = true
						break
				if touches:
					break
			if not touches:
				continue
			if wall_layer.get_cell_source_id(cell) == -1:
				holes.append(str(cell))
	_ok(holes.is_empty(),
			"%d non-walkable cell(s) beside floor have no collision: %s"
			% [holes.size(), ", ".join(holes.slice(0, 8))])
	print("collision seal: %d hole(s) beside floor" % holes.size())
	for k in layers.keys():
		var c: CanvasItem = layers[k]
		if is_instance_valid(c):
			c.free()


## True when `cell` lies inside one of the rooms appended in this feature pass.
func _in_appended_room(builder: Node2D, cell: Vector2i) -> bool:
	for room_name in builder.ROOM_MIN_TORCH.keys():
		if builder.ROOMS[room_name].has_point(cell):
			return true
	return false


## The floor and torch checks that apply to EVERY prop, original or appended.
func _prop_problems_loose(builder: Node2D, grid: Array, cell: Vector2i,
		kind: String) -> Array[String]:
	var out: Array[String] = []
	if not _walkable(grid, cell):
		out.append("%s at %s is not on walkable floor" % [kind, cell])
	elif builder._build_torches(grid).has(cell):
		out.append("%s at %s sits on a generated torch" % [kind, cell])
	elif builder.SHAFT_LIGHTS.has(cell):
		out.append("%s at %s sits on a shaft torch" % [kind, cell])
	return out


## The strict per-cell rules for a prop in an appended room.
##
## "24px from a wall" is enforced as a whole cell of clearance: a cell whose
## four neighbours are ALL walkable sits at least one full tile (32px) from any
## wall, which is more than the 24px asked for. A chest flush against a wall
## cannot be opened, because the player has nowhere to stand on that side.
func _prop_problems(builder: Node2D, grid: Array, torches: Array,
		start_cell: Vector2i, cell: Vector2i, kind: String) -> Array[String]:
	var out := _prop_problems_loose(builder, grid, cell, kind)
	if not out.is_empty():
		return out
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if not _walkable(grid, cell + d):
			out.append("%s at %s has a wall within one cell (less than 24px)"
				% [kind, cell])
			break
	if torches.has(cell):
		out.append("%s at %s sits on a torch" % [kind, cell])
	# 150px at 32px per cell is 4.7 cells, so 5 cells of Chebyshev distance.
	var dx: int = absi(cell.x - start_cell.x)
	var dy: int = absi(cell.y - start_cell.y)
	if maxi(dx, dy) < 5:
		out.append("%s at %s is only %d cells from PlayerStart, must be 5+"
			% [kind, cell, maxi(dx, dy)])
	# A chest needs a 3x5 of clear floor so the player can stand beside it.
	if kind == "chest":
		var half: Vector2 = builder.PLAYER_HALF
		var hc := Vector2i(int(ceil(half.x / (builder.GRID * builder.SCALE))),
			int(ceil(half.y / (builder.GRID * builder.SCALE))))
		for y in range(cell.y - hc.y, cell.y + hc.y + 1):
			for x in range(cell.x - hc.x, cell.x + hc.x + 1):
				if not _walkable(grid, Vector2i(x, y)):
					out.append("%s at %s has no clear floor to stand beside "
						% [kind, cell] + "it at (%d,%d)" % [x, y])
	return out


## The shaft must stay fully walkable across its width at both light rows.
##
## The shaft lights were moved onto the edge columns specifically so the light
## does not sit in the middle of the road. This asserts the torches really do
## carry no collision: if one ever grew a CollisionShape2D, the corridor would
## silently become 2 wide there and the 43px player collider would scrape.
func _check_shaft_width(builder: Node2D, grid: Array) -> void:
	var bad: Array[String] = []
	for s in builder.SHAFT_LIGHTS:
		for x in range(36, 39):
			if not _walkable(grid, Vector2i(x, s.y)):
				bad.append("shaft is only 2 wide at y=%d (torch row)" % s.y)
	if bad.is_empty():
		print("shaft width   : 3 cells open at both torch rows")
	for b in bad:
		_fails.append(b)
		_fails.append(b)


## The five original rooms and four original corridors are the collision the
## whole game already balances around, and they must not move.
##
## This asserts the OLD rectangles are still walkable in the NEW grid rather
## than comparing totals. Totals cannot prove this: the map grew from 43x31 to
## 43x43, so the wall and rim counts are EXPECTED to rise. What must hold is that
## no cell that was walkable before has stopped being walkable. Every other
## number in this file is allowed to change.
const BASE_ROOMS := {
	"cistern": Rect2i(4, 5, 11, 8),
	"crypt": Rect2i(18, 5, 10, 8),
	"forge": Rect2i(33, 5, 8, 8),
	"hall": Rect2i(4, 21, 12, 8),
	"vault": Rect2i(22, 21, 12, 8),
}
const BASE_CORRIDORS := [
	Rect2i(14, 8, 4, 3),
	Rect2i(27, 8, 6, 3),
	Rect2i(8, 13, 3, 8),
	Rect2i(16, 24, 6, 3),
]


func _check_base_collision(builder: Node2D, grid: Array) -> void:
	var missing: Array[String] = []
	var base_cells := 0
	for name in BASE_ROOMS.keys():
		var rect: Rect2i = BASE_ROOMS[name]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				base_cells += 1
				if not _walkable(grid, Vector2i(x, y)):
					missing.append("room '%s' cell (%d,%d)" % [name, x, y])
	for c in BASE_CORRIDORS:
		for y in range(c.position.y, c.end.y):
			for x in range(c.position.x, c.end.x):
				base_cells += 1
				if not _walkable(grid, Vector2i(x, y)):
					missing.append("corridor %s cell (%d,%d)" % [c, x, y])
	# Also confirm the builder still DECLARES them unchanged, not merely that the
	# grid happens to be walkable there.
	for name in BASE_ROOMS.keys():
		if builder.ROOMS[name] != BASE_ROOMS[name]:
			missing.append("room '%s' is now %s, was %s" % [
				name, builder.ROOMS[name], BASE_ROOMS[name]])
	if builder.CORRIDORS.size() < BASE_CORRIDORS.size():
		missing.append("a base corridor was removed")
	else:
		for i in BASE_CORRIDORS.size():
			if builder.CORRIDORS[i] != BASE_CORRIDORS[i]:
				missing.append("corridor %d is now %s, was %s" % [
					i, builder.CORRIDORS[i], BASE_CORRIDORS[i]])
	print("base collision : %d original cells checked, %s" % [
		base_cells, "all still walkable" if missing.is_empty()
		else "%d PROBLEM(S)" % missing.size()])
	for m in missing:
		_fails.append("base collision changed - " + m)


## The forge-to-vault hallway was removed on purpose. It must stay removed: any
## floor or trap left in that rectangle means a partial deletion.
func _check_removed_hallway(builder: Node2D, grid: Array) -> void:
	var gone := Rect2i(33, 13, 3, 8)
	var leftover: Array[String] = []
	for y in range(gone.position.y, gone.end.y):
		for x in range(gone.position.x, gone.end.x):
			if _walkable(grid, Vector2i(x, y)):
				leftover.append("floor at (%d,%d)" % [x, y])
	for c in builder.TRAPS:
		if gone.has_point(c):
			leftover.append("a trap at %s" % c)
			break
	if leftover.is_empty():
		print("removed hallway: %s is clear" % gone)
	else:
		for s in leftover:
			_fails.append("removed hallway still has " + s)


## Every torch must be off the corridors. The generated positions are the ones the
## scene actually uses, so this catches a doorway light even though the placement
## is randomised.
func _check_torches(builder: Node2D, grid: Array) -> void:
	var torches: Array = builder._build_torches(grid)
	var in_doorway := 0
	for cell in torches:
		if builder._in_corridor(cell):
			in_doorway += 1
			_fails.append("torch at %s sits in a corridor doorway" % cell)
	if not torches.is_empty():
		print("torch placement: %d torches, %d in a doorway" % [
			torches.size(), in_doorway])


## Every generated floor and cap variant must actually reach the map.
##
## Variants are chosen by a hash, so one that renders as an empty or blank cell
## is invisible in a layout check and shows up only as a hole or a bald patch.
func _check_variant_coverage(builder: Node2D) -> void:
	var caps := {}
	var floors := {}
	for y in builder.MAP_H:
		for x in builder.MAP_W:
			caps[builder._cap_variant(x, y)] = true
			floors[builder._floor_variant(x, y)] = true
	print("cap variants   : %d of %d used" % [
		caps.size(), builder.CAP_VARIANTS])
	print("floor variants : %d of %d used" % [
		floors.size(), builder.FLOOR_VARIANTS])
	if caps.size() < builder.CAP_VARIANTS:
		_fails.append("not every cap variant appears in the dungeon")
	if floors.size() < builder.FLOOR_VARIANTS:
		_fails.append("not every floor variant appears in the dungeon")


## Checks the generated art itself, measured off the built textures.
##
## These are pixel facts, not layout facts: whether the cap tile is actually full
## of brick, whether the collision-only tile is actually transparent, and whether
## the floor is genuinely darker than the cap.
func _check_art(builder: Node2D, tileset: TileSet) -> void:
	var size := Vector2i(builder.GRID, builder.GRID)
	var cap_img := _tile_image(tileset, builder.SRC_WALL, Vector2i(0, 0), size)
	var block_img := _tile_image(tileset, builder.SRC_WALL,
		Vector2i(builder.WALL_BLOCK, 0), size)
	var floor_img := _tile_image(tileset, builder.SRC_FLOOR,
		Vector2i(0, 0), size)
	# Mask 15 draws a line on all four sides, so it is the one tile guaranteed to
	# contain outline pixels. Mask 0 is legitimately empty, and sampling it would
	# make this check pass no matter what the outline looked like.
	var edge_img := _tile_image(tileset, builder.SRC_EDGE, Vector2i(15, 0), size)
	if cap_img == null or block_img == null:
		_fails.append("could not read a generated tile back from the TileSet")
		return
	if floor_img == null or edge_img == null:
		_fails.append("could not read a generated tile back from the TileSet")
		return

	var cap_fill := _opaque(cap_img)
	var block_fill := _opaque(block_img)
	var floor_fill := _opaque(floor_img)
	var edge_fill := _opaque(edge_img)
	print("cap fill       : %d px (a full cap is 256)" % cap_fill)
	print("block fill     : %d px (collision-only tile must be 0)" % block_fill)
	print("floor fill     : %d px" % floor_fill)
	print("edge fill      : %d px (an outline is a thin line)" % edge_fill)

	if cap_fill < 200:
		_fails.append(("cap tile is only %d px filled, so the wall cap is "
			+ "mostly transparent and punches holes in the masonry") % cap_fill)
	if block_fill > 0:
		_fails.append(("the collision-only tile has %d opaque px, so the side "
			+ "and bottom edges still draw masonry and the wall stays a thick "
			+ "band") % block_fill)
	if floor_fill != 256:
		_fails.append(("floor tile is only %d px filled, so the flagstones "
			+ "leave gaps") % floor_fill)
	# Mask 15 is the worst case: a line on all four sides is
	# 4 * 16 (outer) + 4 * 14 (inner) = 112 px. A thicker band than that would
	# mean the outline stopped being 1px, so this is an upper bound, not a guess.
	if edge_fill > 120:
		_fails.append(("outline tile has %d opaque px, so the silhouette is a "
			+ "thick band rather than a 1px line") % edge_fill)

	# The floor must sit clearly BELOW the cap in brightness, or the walls do
	# not read as walls. Both are mid-teal, so this compares luminance directly.
	var cap_lum := _luminance(cap_img)
	var floor_lum := _luminance(floor_img)
	print("cap luminance  : %.3f" % cap_lum)
	print("floor luminance: %.3f" % floor_lum)
	if cap_lum <= floor_lum:
		_fails.append(("floor luminance %.3f is not below cap luminance %.3f, "
			+ "so the walls do not read against the floor")
			% [floor_lum, cap_lum])


## The pixels of one tile, read back out of a TileSet atlas source.
func _tile_image(tileset: TileSet, source_id: int, coords: Vector2i,
		size: Vector2i) -> Image:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null or src.texture == null:
		return null
	var full: Image = src.texture.get_image()
	var at := Vector2i(coords.x * size.x, coords.y * size.y)
	return full.get_region(Rect2i(at, size))


## How many pixels of `img` are visibly opaque.
func _opaque(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.15:
				n += 1
	return n


## Mean luminance of the opaque pixels, so "darker" can be checked.
func _luminance(img: Image) -> float:
	var total := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.15:
				total += c.get_luminance()
				n += 1
	if n == 0:
		return 0.0
	return total / float(n)


## The scene is instantiated from _process rather than _initialize because `root` is
## not inside the tree yet during initialize: _ready would never fire, the
## dungeon would silently build nothing, and the check would pass on an empty
## scene. _process only runs once the tree is actually live.
func _process(_delta: float) -> bool:
	_check_live_scene(_builder)
	# After the live scene: the mimic checks read the nodes that were really
	# placed, not a plan.
	_check_mimic_placement(_builder, _grid)
	print("")
	print("assertions     : %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK")
		quit(0)
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: %d problem(s)" % _fails.size())
		quit(1)
	return true


## Boots the real scene and checks that the player spawns on carved floor and
## that every declared prop, trap and torch actually became a node.
func _check_live_scene(builder: Node2D) -> void:
	var packed: PackedScene = load("res://Main.tscn")
	if packed == null:
		_fails.append("Main.tscn could not be loaded")
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	# Kept so the mimic checks can read the REAL placed nodes. The bare builder
	# has no Dungeon child, so reading it there finds nothing at all.
	_live_main = main

	var dungeon: Node2D = main.get_node_or_null("Dungeon")
	if dungeon == null:
		_fails.append("Main.tscn has no Dungeon node")
		main.queue_free()
		return

	var grid: Array = dungeon._build_grid()
	var player := main.get_node_or_null("Player(CharacterBody2D)") as Node2D
	if player == null:
		_fails.append("Main.tscn has no player")
		main.queue_free()
		return

	# The dungeon node is scaled 2x, so world position / (GRID * SCALE) is the cell.
	var cell := Vector2i(
		int(floor(player.position.x / (builder.GRID * builder.SCALE))),
		int(floor(player.position.y / (builder.GRID * builder.SCALE)))
	)
	if not _walkable(grid, cell):
		_fails.append("player spawns at cell %s, which is not walkable floor" % cell)
	else:
		print("player spawn   : cell %s, on carved floor" % cell)

	# The CanvasModulate must exist and be scoped to the dungeon, or the
	# ambient darkness is either missing or leaking onto UI.
	var ambient := dungeon.get_node_or_null("Ambient")
	if ambient == null:
		_fails.append("Dungeon has no CanvasModulate named Ambient")
	elif not ambient is CanvasModulate:
		_fails.append("Dungeon/Ambient is a %s, not a CanvasModulate" % ambient.get_class())
	else:
		print("ambient        : ColorModulate on the dungeon only")

	# The three layers must all exist, and the outline must be independent.
	var walls := dungeon.get_node_or_null("Walls")
	var outline := dungeon.get_node_or_null("Outline")
	if walls == null:
		_fails.append("Dungeon has no Walls layer")
	if outline == null:
		_fails.append("Dungeon has no Outline layer (the silhouette must be "
			+ "an independent layer so the walls can be toggled)")
	elif walls != null and outline.get_parent() != walls.get_parent():
		_fails.append("Outline is not a sibling of Walls; it must be its own layer")

	var counts := {"chest": 0, "pot": 0, "crate": 0, "trap": 0, "torch": 0}
	var props: Node = dungeon.get_node_or_null("Props")
	if props != null:
		for child in props.get_children():
			var n := String(child.name).to_lower()
			for key in counts.keys():
				if n.begins_with(key):
					counts[key] += 1
					break
	# Traps sit in their own layer, not in Props, so they are counted there.
	var hazards: Node = dungeon.get_node_or_null("Hazards")
	if hazards != null:
		counts["trap"] = hazards.get_child_count()
	print("built in tree  : %s" % counts)

	var want := {"chest": builder.CHESTS.size(), "pot": builder.POTS.size(),
		"crate": builder.CRATES.size(), "trap": builder.TRAPS.size(),
		# Torches are generated rather than listed, so the declared count comes
		# from the same function that places them. The two shaft lights are placed
		# by a separate pass and are NOT in that list, so they are added here -
		# otherwise the scene legitimately holds two more torch nodes than
		# _build_torches reports and the count check fails for the wrong reason.
		"torch": builder._build_torches(grid).size() + builder.SHAFT_LIGHTS.size()}
	for key in want.keys():
		if int(counts[key]) != int(want[key]):
			_fails.append("%s: layout declares %d but the scene built %d" % [
				key, int(want[key]), int(counts[key])])
	main.queue_free()


func _walkable(grid: Array, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0:
		return false
	if cell.x >= grid[0].size() or cell.y >= grid.size():
		return false
	return grid[cell.y][cell.x] == 1


## The map as a picture. '#' wall, '.' floor, and a letter for everything the
## player has to interact with - a layout bug is obvious here and invisible in
## a table of numbers.
##
## '#' is a visible brick cap, ',' is the transparent collision-only tile that
## replaced masonry on side and bottom edges, and ':' is the rim outside the
## band. The comma cells are the ones that must not be drawing anything.
func _print_map(builder: Node2D, grid: Array) -> void:
	var marks := {}
	for c in builder.TRAPS:
		marks[c] = "T"
	for c in builder.CHESTS:
		marks[c] = "C"
	for c in builder._build_torches(grid):
		marks[c] = "o"
	for c in builder.POTS:
		marks[c] = "p"
	for c in builder.CRATES:
		marks[c] = "b"
	marks[builder._room_centre(builder.ROOM_START)] = "@"

	print("    " + _digits(builder.MAP_W))
	for y in builder.MAP_H:
		var line := ""
		for x in builder.MAP_W:
			var cell := Vector2i(x, y)
			if marks.has(cell) and _walkable(grid, cell):
				line += marks[cell]
			elif _walkable(grid, cell):
				line += "."
			elif builder._is_band(grid, cell):
				if builder._is_cap(grid, cell):
					line += "#"
				else:
					line += ","
			elif builder._is_void(grid, cell):
				line += ":"
			else:
				line += " "
		print("%3d %s" % [y, line])
	print("\n  @ spawn  T trap  C chest  o torch  p pot  b crate")
	print("  # brick cap (visible)   , collision-only (invisible)   : rim")


func _digits(n: int) -> String:
	var s := ""
	for i in n:
		s += str(i % 10)
	return s
## Whether the given tile in `source_id` carries collision.
##
## Read straight off the TileSet source: a TileMapLayer has no get_tile_data of
## its own, and a detached source reports zero physics layers for every tile.
func _collides(tileset: TileSet, source_id: int, coords: Vector2i) -> bool:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null:
		return false
	var data: TileData = src.get_tile_data(coords, 0)
	return data != null and data.get_collision_polygons_count(0) > 0
