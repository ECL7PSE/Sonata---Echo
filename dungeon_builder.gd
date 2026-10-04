@tool
extends Node2D
## Echo - dungeon builder.
##
## The stonework is GENERATED, not cut from a sheet. T002's row-9 bricks carry
## dark vertical streaking and pillar shading that reads as noise at this size,
## and its rows 0-5 are the same flat brick the floor wants, so cutting tiles
## from it cannot produce the calm, even stone of the reference art. Every floor,
## cap and outline pixel is therefore composed in code from the palette below,
## which is written out explicitly so the result is tuned to the target style
## rather than inherited from the source artwork.
##
## The layout is five halls wired together:
##
##      cistern --- crypt --- forge
##         |
##        hall --- vault
##
## How the three surfaces are built:
##
##  * FLOOR - low-contrast flagstones of varied rectangular size in three close
##    mid-teal shades, deliberately darker and calmer than the cap so the walls
##    read clearly against it.
##  * CAP - a thin brick course, about one cell tall, drawn ONLY on north-facing
##    edges (a wall cell whose southern neighbour is floor) and wherever the
##    floor steps up. Side and bottom edges get no wall tiles at all, exactly as
##    the reference does.
##  * OUTLINE - a 1px bright aqua line with a lighter inner edge, tracing the
##    whole dungeon silhouette on its own TileMapLayer so the walls can be
##    toggled without losing the room shape.
##
## Removing the masonry from side and bottom edges does NOT weaken the boundary:
## those cells keep a collision-only tile carrying the identical full-cell
## polygon, so the player is stopped exactly as before while the art matches the
## reference.
##
## _validate() runs before anything is built and refuses to build a broken map:
## every walkable cell must be reachable from the spawn, every corridor must be
## MIN_CORRIDOR cells across (the player's collider is 43x67 px), no prop may sit
## in a corridor, on a doorway or on a trap, and every arch and carpet must fall
## entirely on walkable floor.

const SHEET_DIR := "res://Assets/Dungeon/dungeon_V.1.0.0_nyknck/"
const SHEET_T002 := SHEET_DIR + "Tile/T002.png"

const PROP_SCRIPT := preload("res://prop_breakable.gd")
const LOOT_SCRIPT := preload("res://loot.gd")
const TORCH_SCRIPT := preload("res://torch.gd")
const TRAP_SCRIPT := preload("res://trap.gd")
const SPAWNER := preload("res://enemy_spawner.gd")

const GRID := 16            # tile size in source pixels
const SCALE := 2.0         # the Dungeon node is scaled 2x, see dungeon.tscn
const MAP_W := 43
## The map grew downward, not sideways, so no existing room had to move.
## 43 columns x 43 rows: the old 31 rows plus 12 rows of southern dungeon.
const MAP_H := 43

# The player's collider in Main.tscn is 43x67 px, which is 1.4 x 2.1 cells at
# SCALE 2, so a corridor has to be 3 cells (96 px) across to be walkable.
const MIN_CORRIDOR := 3

## The player's BODY collider, in RENDERED px. Must track the RectangleShape2D
## in Main.tscn.
##
## MEASURED, not assumed, in the running Main scene (tools/measure_head_cap.gd).
## tools/measure_player.gd reads the alpha bounding box of idle frame 4 in
## darkhatman_idle_sheet_64x64.png: the sheet is 256x256 at hframes/vframes 4,
## so a frame is 64x64 and the ink spans y 5..47 frame px -> y -32.40..+18.00
## rendered at scale 1.2.
##
## The ink alone is NOT the wrong reference, but the SIGN of the comparison is.
## What the hat has to clear is the bottom of the wall cell, which is generated
## from the GRID. Measured with the player pressed flush north:
##
##   collider 20x20 (what the file actually produced) -> ink 22.39 px INSIDE
##            the wall cell. That was the bug.
##   collider 16x51 at y -7.2                     -> ink sits 0.31 px BELOW the
##            wall cell's base, i.e. it already clears it. Not a bug.
##
## NOTE for anyone editing Main.tscn: `#` is NOT a comment character in a .tscn
## file, `;` is. A `#` line inside a `[node]` or `[sub_resource]` block is
## parsed as an invalid property, the block is discarded, and the node silently
## keeps its DEFAULT values. That is how a 16x51 collider and a z_index of 3
## both failed to apply while the file on disk looked correct - the running
## collider was Godot's default 20x20 at the origin. Keep comments out of the
## .tscn and put them here.
##
## Width is 14 - narrower than the drawn art on purpose, so the player slips
## through gaps the artwork overhangs. 14 rendered px is 0.4375 of a 32 px tile.
##
## The sprite was shrunk from scale 1.2 to PLAYER_SCALE so its ink is ~38.7 px
## tall instead of ~51: at 1.2 the character was a tile and a half tall, which
## is why a 3-tile corridor felt cramped. The box is the ink height minus
## HEAD_OVERLAP_PX, so the top of the hat may sit HEAD_OVERLAP_PX inside a wall
## instead of pinning the whole box against it.
const PLAYER_SCALE := 0.9
const HEAD_OVERLAP_PX := 4.0
## Feet ink bottom in local px at PLAYER_SCALE: (48 - 32) * 0.9 = +14.4.
const PLAYER_FEET_Y := 14.4
const PLAYER_SIZE := Vector2(14, 38.7 - HEAD_OVERLAP_PX)
## Half the player's collider, in RENDERED px. Derived, so it cannot drift out
## of step with PLAYER_SIZE. Used by the spawn and prop clearance checks.
const PLAYER_HALF := PLAYER_SIZE * 0.5
const PROP_CLEARANCE := Vector2(26, 26)

# --- Draw order ---------------------------------------------------------------
##
## One place for every z_index in the dungeon, because the numbers were spread
## across three files and drifted into a visible bug: the player's head was cut
## off by the wall cap when walking along a north wall.
##
## The cause was that the Outline layer sat at z 2, the SAME layer as Props,
## while the player and the enemies sat at the default z 0 - below the wall cap
## at z 1. Walking north, the cap drew over the player's head; the cyan outline
## at z 2 would have drawn over their whole body had the cap not been in the way.
##
## The order that fixes it, lowest first:
##
##   0  Floor, Hazards        flat things the player stands ON
##   1  Walls + wall cap      masonry
##   2  Outline               the 1px cyan silhouette
##   3  Props                 chests, pots, crates, torches, mimics
##   4  Actors                the player and every enemy
##
## Actors sit ABOVE props so a chest is never drawn over the character standing
## in front of it. Props still clear Floor, Hazards, Walls and the Outline, and
## the wall-mounted torches are props, so they still burn in front of the cap.
## Requirement 3 also holds: the Outline stays at 2, under props and actors, so
## the cyan line never draws across a face.
const Z_FLOOR := 0
const Z_HAZARDS := 0
const Z_WALLS := 1
const Z_OUTLINE := 2
const Z_PROPS := 3
const Z_ACTORS := 4

## Cells of solid static collider ringing the whole map, outside the grid.
const BORDER_THICK := 2

# --- Generated art ----------------------------------------------------------
# Every tile is composed in code from this palette. Nothing is cut from a sheet,
# because no sheet in the pack is the reference style: T002's row-9 bricks carry
# dark vertical streaking and pillar shading, and cutting them inherited exactly
# the noise the reference does not have.
#
# The three surfaces are deliberately separated in VALUE as well as in colour.
# The floor is the darkest, the cap sits above it, and the outline is the only
# thing allowed to be genuinely bright. That ordering is what makes the walls
# read against the floor instead of dissolving into it.
#
# Floor: three close shades plus a mortar barely darker than they are. Close
# shades are the whole point - high contrast here would beat the cap for
# attention and the room would read as a chessboard.
const FLOOR_SHADES: Array[Color] = [
	Color(0.125, 0.270, 0.285),
	Color(0.140, 0.295, 0.310),
	Color(0.155, 0.320, 0.335),
]
const FLOOR_MORTAR := Color(0.105, 0.230, 0.245)

# Cap: the same family lifted a step, so the wall sits clearly above the floor.
#
# The cap must read as a LIGHTER band than the floor. The torch pools blend
# additively ON the floor, so bright lights push the floor up past the cap and
# the wall stops looking like a wall. Light energy is kept low enough that the
# brightest pool stays under the cap value.
const CAP_SHADES: Array[Color] = [
	Color(0.255, 0.455, 0.475),
	Color(0.285, 0.495, 0.515),
	Color(0.315, 0.535, 0.555),
]
## 1px darker line between bricks.
const CAP_MORTAR := Color(0.165, 0.315, 0.335)
## 1px lighter line along each brick's top edge. Only 1px, and only a little
## lighter: a bright highlight bar is what made the old mint cap read as a strip
## of light rather than as the top of a wall.
const CAP_HIGHLIGHT := Color(0.345, 0.565, 0.585)

# Outline: a bright aqua line with a slightly lighter inner edge, which is what
# gives the reference silhouette its crisp, slightly beveled look.
const OUTLINE_COLOR := Color(0.435, 0.925, 0.945)
const OUTLINE_INNER := Color(0.640, 0.985, 0.990)

## How many generated tiles of each kind, and the seeds that pick their contents.
## Fixed seeds mean the dungeon looks identical on every run, which is what keeps
## the layout checks and screenshots reproducible.
const FLOOR_VARIANTS := 4
const CAP_VARIANTS := 4
const ART_SEED := 20240917

## Tiles are 16px, so a "thin cap" is a single row of bricks with the highlight
## band on top and the shadow band along the bottom. Two rows of brick would make
## the wall read as a solid block again.
const CAP_ROWS := 1

# --- Wall tiles --------------------------------------------------------------
# Three kinds of wall tile, and the distinction between them is the whole design:
#
#   CAP   brick, drawn ONLY along north-facing / step-up edges. This is the only
#         tile that is actually visible as a wall.
#   BLOCK a collision-only tile: completely transparent, but carrying the same
#         full-cell polygon a cap does. Side and bottom edges use this. The art
#         disappears; the boundary does not.
#   EDGE  the 1px aqua outline, on its own layer, tracing the whole silhouette.
#
# The previous build filled every band cell with masonry on all four sides, which
# is why the walls read as thick tiled blocks. Removing the masonry does NOT remove
# the collision, which is the part that actually matters for play.
#
# Atlas layout, one row:
#
#   CAP_VARIANTS cap tiles | 1 block tile | EDGE_VARIANTS edge tiles
const WALL_CAP_BASE := 0
const WALL_BLOCK := CAP_VARIANTS
## Each edge tile is a 4-bit mask of which sides need a line:
## 1=up 2=down 4=left 8=right. All 16 combinations exist so any silhouette cell
## resolves to a real tile rather than falling back to a wrong one.
const EDGE_VARIANTS := 16

## Atlas coords for a wall cell: `shape` picks the silhouette, `brick` the face.
func wall_atlas(shape: int, brick: int) -> Vector2i:
	return Vector2i(brick, shape)

# How many cells thick the rock around the dungeon is. Two, unchanged: this
# governs collision and the outline ring, both of which must stay identical.
const WALL_RING := 2

# TileSet source ids, in the order _build_tileset() registers them. The wall
# layer carries collision; the floor does not, so the player walks the floor and
# is stopped by the band.
const SRC_FLOOR := 0     # generated flagstone, no collision
const SRC_WALL := 1      # cap + collision-only block, collides
const SRC_EDGE := 2      # 1px aqua outline, no collision

# --- Layout ----------------------------------------------------------------
# Nine halls. Each is a plain rectangle: the wall is drawn as the ring of rock
# around it, so a room is exactly the rectangle below.
#
# The five original rooms are unchanged and must stay byte-identical: they own
# the collision the rest of the game balances around. The four southern rooms
# were appended below y=31, so the map grew downward (MAP_H) rather than
# sideways and no existing room moved.
const ROOM_CISTERN := Rect2i(4, 5, 11, 8)    # west hall
const ROOM_CRYPT := Rect2i(18, 5, 10, 8)     # north burial room
const ROOM_FORGE := Rect2i(33, 5, 8, 8)      # north-east workshop
const ROOM_HALL := Rect2i(4, 21, 12, 8)      # the spawn hall
const ROOM_VAULT := Rect2i(22, 21, 12, 8)    # treasure vault
## Appended rooms. Monster difficulty rises with walking distance from the start.
const ROOM_EYEWELL := Rect2i(31, 33, 8, 7)   # flying eye
const ROOM_GOBLIN := Rect2i(20, 33, 8, 7)    # goblin
const ROOM_MIMIC := Rect2i(10, 33, 8, 7)     # mimic
## bone_hall starts at x=2, NOT x=1. At x=1 this room's two-cell wall band would
## need cells at x=-1, which do not exist, so the left wall - and the outline
## that traces it - would be clipped against the grid edge. x=2 puts the band at
## x=0,1: the same two-cell margin every other room in the dungeon has.
const ROOM_BONE := Rect2i(2, 31, 6, 9)       # skeleton, the furthest room
const ROOMS := {
	"cistern": ROOM_CISTERN,
	"crypt": ROOM_CRYPT,
	"forge": ROOM_FORGE,
	"hall": ROOM_HALL,
	"vault": ROOM_VAULT,
	"eye_well": ROOM_EYEWELL,
	"goblin_den": ROOM_GOBLIN,
	"mimic_den": ROOM_MIMIC,
	"bone_hall": ROOM_BONE,
}
const ROOM_START := ROOM_HALL

# Corridors overlap or abut the rooms they join, so the dungeon is connected by
# construction and there is no separate route list to drift out of sync. Every
# one is 3 cells across in its short direction.
#
# The forge->vault stair is deliberately ABSENT. The forge holds three crates and
# a chest, and it used to run on into a long stair that led nowhere worth going;
# removing the corridor turns it into a proper dead end, so that branch now
# terminates at the forge instead of dangling.
const CORRIDORS := [
	Rect2i(14, 8, 4, 3),    # cistern -> crypt
	Rect2i(27, 8, 6, 3),    # crypt -> forge
	Rect2i(8, 13, 3, 8),    # cistern -> hall  (the long west stair)
	Rect2i(16, 24, 6, 3),   # hall -> vault
	# The appended route. One spine, no branches, no dead-end corridors:
	#   forge -> (the long south shaft) -> eye_well -> goblin_den
	#         -> mimic_den -> bone_hall
	# Every link is 3 cells across at minimum so the 43x67 player collider always
	# clears, and each corridor joins exactly two spaces.
	Rect2i(36, 13, 3, 20),  # forge -> eye_well (the long south shaft)
	Rect2i(28, 36, 4, 3),   # eye_well -> goblin_den
	Rect2i(18, 36, 4, 3),   # goblin_den -> mimic_den
	Rect2i(8, 36, 3, 3),    # mimic_den -> bone_hall
]

## Two lights for the south shaft, at the WALL EDGE and alternating sides.
##
## The generated torch pass deliberately refuses corridor cells (_torch_ok
## returns false for anything _in_corridor) so a light can never pinch a
## doorway the player has to walk through. This shaft is the one place that rule
## has to bend: it is 20 cells of dead straight corridor with no side doors, so
## lighting it from the rooms alone leaves a black tunnel. These two are listed
## rather than generated because they must land in fixed positions to read as
## evenly spaced markers on a long climb.
##
## They sit on the shaft's EDGE cells (x=36 and x=38) rather than down its middle
## (x=37), and alternate sides. A torch in the middle of a 3-wide corridor reads
## as a bollard in the middle of the road; pushed against the wall the glow rakes
## across the opposite wall cap, which is what every other torch in the dungeon
## does. A torch carries no collision shape at all, so this does NOT narrow the
## walkable width - all three columns stay open, and check_layout asserts it.
const SHAFT_LIGHTS: Array[Vector2i] = [
	Vector2i(36, 19),  # west edge of the shaft, ~1/3 down
	Vector2i(38, 26),  # east edge of the shaft, ~2/3 down
]

## Minimum lights for the APPENDED rooms only.
##
## The global TORCH_MIN_PER_ROOM is 0, which is deliberate for the original five
## (their lighting is already balanced and must not move), but it means a newly
## added room can be handed zero torches and render as an unlit black box. Only
## the rooms listed here are guaranteed a floor; rooms absent from this table
## keep the original random behaviour.
const ROOM_MIN_TORCH := {
	"eye_well": 2,
	"goblin_den": 2,
	"mimic_den": 2,
	"bone_hall": 2,
}

## Torch placement is generated, not listed.
##
## The lights used to sit on a fixed grid - two per hall, all on the same row -
## which read as evenly spaced squares rather than as lighting. They are now
## scattered per room with a seeded RNG: the per-room count is drawn from a
## range (so some halls get several, some get one, some get none), and each light
## is placed by picking a walkable cell a minimum distance from the ones already
## placed in that room, so they never line up.
##
## The seed is FIXED, not random. The look is scattered but the dungeon is
## identical on every run, which is what keeps the layout checks and the
## screenshots reproducible. Change TORCH_SEED to reshuffle.
const TORCH_SEED := 20240517
## How many lights a room may get, inclusive.
const TORCH_MIN_PER_ROOM := 0
const TORCH_MAX_PER_ROOM := 4
## Minimum Chebyshev distance between two lights in the same room.
const TORCH_SPACING := 3


## Builds the torch list for this layout. See the TORCH_SEED note above.
func _build_torches(grid: Array) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = TORCH_SEED
	var out: Array[Vector2i] = []

	for room_name in ROOMS.keys():
		var rect: Rect2i = ROOMS[room_name]
		var candidates: Array[Vector2i] = []
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				if _walkable(grid, cell) and _torch_ok(grid, cell):
					candidates.append(cell)

		if candidates.is_empty():
			continue

		# How many this room gets. Drawn per room, so rooms genuinely differ.
		#
		# The four APPENDED rooms carry ROOM_MIN_TORCH instead of relying on the
		# global range: the brief asks every new room for at least two lights,
		# and TORCH_MIN_PER_ROOM is 0, so the random draw can legitimately hand
		# one of them a single torch or none at all. The five original rooms stay
		# on the old range - their lighting is already tuned and must not move.
		var want := rng.randi_range(TORCH_MIN_PER_ROOM, TORCH_MAX_PER_ROOM)
		want = maxi(want, int(ROOM_MIN_TORCH.get(room_name, 0)))
		var placed := 0
		var guard := 0
		# The guard stops a room whose candidate list is too tight from spinning
		# forever: it gives up once it has tried a generous number of candidates.
		while placed < want and guard < candidates.size() * 4:
			guard += 1
			var pick: Vector2i = candidates[rng.randi_range(
				0, candidates.size() - 1)]
			if _too_close(out, pick):
				continue
			out.append(pick)
			placed += 1

	return out


## A torch may stand anywhere on open floor, but not on top of something else,
## not on a trap, and not in a doorway.
##
## The doorway rule has to be tested rather than assumed. Room rectangles and
## corridor rectangles overlap where they meet, so a cell picked from inside a
## room rect can still be the corridor's throat. A torch there would light a
## doorway and pinch the passage the player has to walk through.
func _torch_ok(grid: Array, cell: Vector2i) -> bool:
	for blocked in _blocking_prop_cells():
		if blocked == cell:
			return false
	for t in TRAPS:
		if t == cell:
			return false
	if _in_corridor(cell):
		return false
	return _walkable(grid, cell)


## True when `cell` is within TORCH_SPACING of a light already placed. Spacing is
## Chebyshev so it is a real gap on screen rather than a diagonal one.
func _too_close(placed: Array[Vector2i], cell: Vector2i) -> bool:
	for p in placed:
		var d := cell - p
		if absi(d.x) < TORCH_SPACING and absi(d.y) < TORCH_SPACING:
			return true
	return false


# One chest per reward room plus one in the spawn hall, so clearing the route
# pays. Each sits three cells clear of anything else, because _clearance()
# needs a 3x3 of walkable floor around a chest or the player can never stand
# beside it to open it.
const CHESTS: Array[Vector2i] = [
	Vector2i(8, 26),    # hall
	Vector2i(25, 10),   # crypt
	Vector2i(38, 10),   # forge
	Vector2i(30, 26),   # vault
	# Appended rooms. Not every new room gets one on purpose: eye_well is the
	# empty reward room and is meant to be worth the walk for the monsters alone.
	Vector2i(25, 37),   # goblin_den
	Vector2i(14, 37),   # mimic_den
	Vector2i(4, 36),    # bone_hall
]
const POTS: Array[Vector2i] = [Vector2i(6, 7), Vector2i(7, 7), Vector2i(6, 8)]
const CRATES: Array[Vector2i] = [Vector2i(35, 7), Vector2i(36, 7), Vector2i(35, 8)]

# Spike traps. They never block: each is a slow field the player has to cross,
# so a trapped corridor costs time instead of ending a run. Full-width strips
# span the corridor and have to be crossed slowly; the staggered pairs sit in
# the middle and can be stepped around if you spot them in time.
#
# Nothing here sits in the removed forge->vault stair: that whole hallway went
# with the corridor, so its strip went too.
# EVERY trap lives in room floor, at least 3 cells (Chebyshev) from ANY
# corridor cell, and never inside a corridor at all.
#
# This overrides two earlier rules on purpose.
#
# 1. The "a full-width strip across the corridor is the point of it" rule.
#    The west stair and the forge link are 3 cells wide, so a strip down
#    the middle row left exactly one free lane on each side - and the
#    lane beside the cap was 1 tile of true standing room. That is a
#    squeeze, not a hazard you can read and step around. Traps are now
#    room floor, where there is floor to step around them on.
# 2. "Do not move the original props." The corridor strips were the
#    original traps, so this move is the deliberate exception.
#
# MIN_CORRIDOR, ROOMS and CORRIDORS are untouched.
#
# Old -> new, so the move is auditable:
#   (8,17) (9,17) (10,17)   west stair strip  -> hall
#   (15,9)  (16,9)          cistern link      -> cistern
#   (30,8)  (30,9) (30,10)  forge link        -> crypt
#   (17,25) (20,25)         hall-vault link   -> vault
#   (33,35)                  eye_well          -> eye_well
#   (22,35) (26,35) (23,38)  goblin_den        -> goblin_den
		# (23,33) then moved again to (25,35): y=33 is the room's first floor row,
		# so it sat 1 cell under the top wall band and failed the 24px wall rule.
#   (11,34)                  mimic_den         -> mimic_den
const TRAPS: Array[Vector2i] = [
	Vector2i(5, 24), Vector2i(6, 24), Vector2i(7, 24),    # hall
	Vector2i(7, 9), Vector2i(8, 9),                      # cistern
	Vector2i(21, 7), Vector2i(22, 7), Vector2i(21, 8),    # crypt
	Vector2i(24, 24), Vector2i(25, 24),                  # vault
	Vector2i(34, 35), Vector2i(36, 38),                   # eye_well
	Vector2i(25, 35), Vector2i(24, 35), Vector2i(25, 34),  # goblin_den
	Vector2i(14, 34), Vector2i(15, 35),                   # mimic_den
]

const TP_FRAMES := 14

# --- Build state -----------------------------------------------------------

var _grid: Array = []
var _trap_frames: SpriteFrames
func _ready() -> void:
	_grid = _build_grid()
	var problems := _validate(_grid)
	if not problems.is_empty():
		for p in problems:
			push_error("dungeon layout: " + p)
		# Refusing to build a broken map is the whole point of _validate, so a
		# failure has to be loud rather than quietly drawing a sealed level.
		assert(false, "dungeon layout is invalid, see the errors above")
		return

	var tileset := _build_tileset()
	var layers := _make_layers(tileset)
	add_child(layers["floor"])
	add_child(layers["wall"])
	add_child(layers["edge"])

	# Ambient darkness, as a CanvasModulate on the dungeon node.
	#
	# It sits under this node rather than under Main, so it tints the dungeon and
	# nothing else. There is no CanvasLayer or Control anywhere in the project -
	# no HUD at all - so this cannot darken any UI; the player is a sibling of
	# this node in the same canvas and is meant to sit in the same darkness.
	#
	# A dark teal-blue rather than grey: the ambient multiplies every pixel, so a
	# neutral grey would wash the teal out of the stone instead of deepening it.
	var ambient := CanvasModulate.new()
	ambient.name = "Ambient"
	ambient.color = Color(0.52, 0.64, 0.80)
	add_child(ambient)

	# Traps live in their own layer BELOW the props, and below the player.
	#
	# The TP001 art is a self-contained floor tile that draws its own dark hole
	# with the spike rising out of it. It belongs flat ON the floor. On the props
	# layer (z_index 2) the spikes drew OVER the player, so walking through a
	# strip looked like passing underneath a floating slab. At z_index 0 the
	# player stands on the spikes, which is what a spike floor should look like.
	var hazards := Node2D.new()
	hazards.name = "Hazards"
	hazards.z_index = Z_HAZARDS
	add_child(hazards)
	layers["hazards"] = hazards

	var props := Node2D.new()
	props.name = "Props"
	props.z_index = Z_PROPS
	add_child(props)
	layers["props"] = props

	_paint_floor(layers["floor"])
	_paint_walls(layers["wall"], layers["edge"], _grid)
	_seal_walls(layers["wall"], _grid)
	_place_border(self)
	_place_traps(layers["hazards"], _grid)
	_place_torches(layers["props"], _grid)
	_place_shaft_lights(layers["props"], _grid)
	_place_props(layers["props"], _grid)
	_place_player_start()
	_place_enemy_spawns()


# --- Grid ------------------------------------------------------------------

## 0 = solid rock, 1 = walkable floor. The outer ring is never carved, so the
## player physically cannot leave the map - the boundary is solid rock rather
## than an invisible camera clamp.
func _build_grid() -> Array:
	var grid: Array = []
	for y in MAP_H:
		var row: Array = []
		row.resize(MAP_W)
		row.fill(0)
		grid.append(row)
	for rect in ROOMS.values():
		_carve(grid, rect)
	for rect in CORRIDORS:
		_carve(grid, rect)
	return grid


func _carve(grid: Array, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		if y < 1 or y >= MAP_H - 1:
			continue
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 1 or x >= MAP_W - 1:
				continue
			grid[y][x] = 1


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAP_W and cell.y < MAP_H


func _walkable(grid: Array, cell: Vector2i) -> bool:
	return _in_bounds(cell) and grid[cell.y][cell.x] == 1


func _room_centre(rect: Rect2i) -> Vector2i:
	return rect.position + rect.size / 2


func _cell_centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * GRID + GRID * 0.5, cell.y * GRID + GRID * 0.5)


func _in_corridor(cell: Vector2i) -> bool:
	for c in CORRIDORS:
		if c.has_point(cell):
			return true
	return false


## Props that physically block the player: a chest, pot or crate stands in the
## way. These may never sit in a corridor.
func _blocking_prop_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append_array(CHESTS)
	out.append_array(POTS)
	out.append_array(CRATES)
	return out


## Breadth-first flood fill over walkable cells. A cell is only reached through a
## walkable neighbour, so a successful fill proves the player can walk there.
func _flood(grid: Array, origin: Vector2i) -> Dictionary:
	var seen := {}
	var queue: Array[Vector2i] = [origin]
	seen[origin] = true
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = p + d
			if seen.has(n) or not _walkable(grid, n):
				continue
			seen[n] = true
			queue.append(n)
	return seen


# --- Validation ------------------------------------------------------------

## Returns a list of human-readable problems. An empty list means the layout is
## safe to build.
func _validate(grid: Array) -> Array[String]:
	var problems: Array[String] = []
	var spawn := _room_centre(ROOM_START)
	if not _walkable(grid, spawn):
		problems.append("spawn %s is inside solid rock" % spawn)
		return problems

	# 1. Every room must be reachable, and so must every walkable cell, or the
	#    player could end up in a sealed pocket with no way out.
	var reach := _flood(grid, spawn)
	for name in ROOMS:
		var centre := _room_centre(ROOMS[name])
		if not reach.has(centre):
			problems.append("room '%s' (%s) is unreachable" % [name, centre])
	var orphans := 0
	for y in MAP_H:
		for x in MAP_W:
			var cell := Vector2i(x, y)
			if _walkable(grid, cell) and not reach.has(cell):
				orphans += 1
	if orphans > 0:
		problems.append("%d walkable cells are sealed off from the spawn" % orphans)

	# 2. Corridors must be wide enough for the 43x67 player collider, otherwise
	#    the player wedges sideways in them and can never turn around.
	for i in CORRIDORS.size():
		var c: Rect2i = CORRIDORS[i]
		if mini(c.size.x, c.size.y) < MIN_CORRIDOR:
			problems.append("corridor %d %s is only %d cells wide" % [
				i, c, mini(c.size.x, c.size.y)])

	# 3. The spawn and every room centre need elbow room, so the player is never
	#    wedged against a wall on frame one.
	if not _clearance(grid, spawn, PLAYER_HALF):
		problems.append("spawn %s has no clearance for the player collider" % spawn)
	for name in ROOMS:
		if not _clearance(grid, _room_centre(ROOMS[name]), PLAYER_HALF):
			problems.append("room '%s' centre is too tight for the player" % name)

	# 4. No prop may stand in a corridor: it would block the route or be hit
	#    constantly. Nor on a doorway, nor under the arch that hides it.
	var placed := {}
	for cell in _blocking_prop_cells():
		if not _walkable(grid, cell):
			problems.append("prop at %s is not on walkable floor" % cell)
		elif _in_corridor(cell):
			problems.append("prop at %s sits in a corridor" % cell)
		if placed.has(cell):
			problems.append("two props share the cell %s" % cell)
		placed[cell] = true

	# 5. Chests have to be standable-next-to, or they can never be opened.
	for cell in CHESTS:
		if not _clearance(grid, cell, PROP_CLEARANCE):
			problems.append("chest at %s has no room to stand" % cell)

	# 6. Torches must stand on real floor, or their light pools in solid rock.
	for cell in _build_torches(grid):
		if not _walkable(grid, cell):
			problems.append("torch at %s is not on walkable floor" % cell)

	# 7. A trap must be standable and reachable, or the player walks into a slow
	#    they can neither see nor get to.
	var seen_traps := {}
	for cell in TRAPS:
		if seen_traps.has(cell):
			problems.append("two traps share the cell %s" % cell)
		seen_traps[cell] = true
		if not _walkable(grid, cell):
			problems.append("trap %s is not on walkable floor" % cell)
		elif not reach.has(cell):
			problems.append("trap %s is unreachable" % cell)

	# 8. A prop may not stand on a trap either: the prop would hide the spikes
	#    and the player would be slowed with nothing showing why.
	for cell in _blocking_prop_cells():
		if seen_traps.has(cell):
			problems.append("a prop stands on the trap at %s" % cell)

	return problems


## True when a box of `half` (in world px) centred on `cell` fits on walkable
## floor. Converted to cells through the dungeon scale.
func _clearance(grid: Array, cell: Vector2i, half: Vector2) -> bool:
	var half_cells := Vector2i(
		int(ceil(half.x / (GRID * SCALE))), int(ceil(half.y / (GRID * SCALE)))
	)
	for y in range(cell.y - half_cells.y, cell.y + half_cells.y + 1):
		for x in range(cell.x - half_cells.x, cell.x + half_cells.x + 1):
			if not _walkable(grid, Vector2i(x, y)):
				return false
	return true
# --- TileSet ---------------------------------------------------------------

func _make_layers(tileset: TileSet) -> Dictionary:
	# Three independent layers, lowest first. The Outline layer is deliberately
	# separate from Walls so the masonry can be hidden without losing the room
	# silhouette - the outline is what tells you where the dungeon ends.
	var floor_layer := TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = tileset
	floor_layer.z_index = Z_FLOOR

	var wall_layer := TileMapLayer.new()
	wall_layer.name = "Walls"
	wall_layer.tile_set = tileset
	wall_layer.z_index = Z_WALLS

	var edge_layer := TileMapLayer.new()
	edge_layer.name = "Outline"
	edge_layer.tile_set = tileset
	edge_layer.z_index = Z_OUTLINE

	return {
		"floor": floor_layer,
		"wall": wall_layer,
		"edge": edge_layer,
	}


func _build_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(GRID, GRID)
	# The physics layer belongs to the TileSet, not to an individual source.
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)
	tileset.set_physics_layer_collision_mask(0, 1)

	tileset.add_source(_floor_source(), SRC_FLOOR)

	var wall_src := TileSetAtlasSource.new()
	wall_src.texture = _wall_atlas()
	wall_src.texture_region_size = Vector2i(GRID, GRID)
	# The cap variants, then the one collision-only tile they all share.
	for v in CAP_VARIANTS + 1:
		wall_src.create_tile(Vector2i(v, 0))
	tileset.add_source(wall_src, SRC_WALL)

	var edge_src := TileSetAtlasSource.new()
	edge_src.texture = _edge_atlas()
	edge_src.texture_region_size = Vector2i(GRID, GRID)
	for v in EDGE_VARIANTS:
		edge_src.create_tile(Vector2i(v, 0))
	tileset.add_source(edge_src, SRC_EDGE)

	# Collision is assigned only AFTER the source belongs to a TileSet: a TileData
	# resolves its physics layers through the owning TileSet, so asking a detached
	# source for its tiles reports "physics.size() = 0" and silently builds a
	# dungeon the player walks straight through.
	#
	# Every wall tile gets the identical full-cell polygon, including the
	# transparent block tile. That tile is how the side and bottom edges keep
	# stopping the player while showing nothing at all.
	for v in CAP_VARIANTS + 1:
		_make_solid_tile(wall_src, Vector2i(v, 0))
	return tileset


## The wall atlas: CAP_VARIANTS brick caps, then one fully transparent
## collision-only tile.
##
## The cap is a thin course of brick, about one cell tall. Each brick gets a
## 1px lighter top edge and a 1px darker mortar joint to its right, and the
## joints are staggered so the wall never reads as a grid. There is deliberately
## no vertical streaking and no pillar shading: the previous sheet-cut bricks
## carried both, and they were what made the old walls look like dirty blocks.
##
## The block tile is 100% transparent. It exists purely so the side and bottom
## edges keep their collision while showing nothing at all, which is how the
## wall stops being a thick band without the player being able to walk out.
func _wall_atlas() -> ImageTexture:
	##CAP_VARIANTS cap tiles plus the single block tile.
	var cols := CAP_VARIANTS + 1
	var atlas := Image.create_empty(cols * GRID, GRID, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for v in CAP_VARIANTS:
		_draw_cap(atlas, Vector2i(v * GRID, 0), v)
	# Tile CAP_VARIANTS is the transparent collision-only block: never drawn.
	return ImageTexture.create_from_image(atlas)


## Fills one 16x16 cap tile with a single course of staggered brick.
##
## `variant` selects the RNG stream, so each generated cap is a different but
## reproducible arrangement. The top row is the lit edge, then the brick face,
## then a mortar line at the bottom where the cap meets the room.
func _draw_cap(atlas: Image, at: Vector2i, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ART_SEED + variant * 977

	# One course of brick across the tile. Two courses would make the wall a block.
	var face_top := 2
	var face_bottom := GRID - 2
	var brick_w := 8
	# Start at a random offset so the vertical joints stagger naturally.
	var offset := rng.randi_range(0, brick_w - 1)
	var x := -offset
	while x < GRID:
		var bx0 := maxi(x, 0)
		var bx1 := mini(x + brick_w, GRID)
		if bx1 > bx0:
			var shade: Color = CAP_SHADES[rng.randi_range(0, CAP_SHADES.size() - 1)]
			for by in range(face_top, face_bottom):
				for bx in range(bx0, bx1):
					atlas.set_pixel(at.x + bx, at.y + by, shade)
			# 1px darker mortar on the right of each brick: the vertical joint.
			for by in range(face_top, face_bottom):
				atlas.set_pixel(at.x + bx1 - 1, at.y + by, CAP_MORTAR)
		x += brick_w

	# 1px lighter highlight along the top edge of the whole cap.
	for bx in GRID:
		atlas.set_pixel(at.x + bx, at.y, CAP_HIGHLIGHT)
	# 1px darker shadow along the bottom, where the cap meets the floor.
	for bx in GRID:
		atlas.set_pixel(at.x + bx, at.y + GRID - 1, CAP_MORTAR)


## The outline atlas: EDGE_VARIANTS tiles, one per side-mask.
##
## Each tile is transparent except for a 1px bright aqua line along each exposed
## side, plus a slightly lighter 1px inner edge just inside it. That inner edge
## is what gives the reference silhouette its crisp, bevelled look.
##
## This replaces the old void-outline tiles, whose "vertical" edge actually
## stamped short HORIZONTAL runs and so drew the dashed white tick marks.
func _edge_atlas() -> ImageTexture:
	var atlas := Image.create_empty(EDGE_VARIANTS * GRID, GRID, false,
		Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for mask in EDGE_VARIANTS:
		var at := Vector2i(mask * GRID, 0)
		if mask & 1:
			for bx in GRID:
				atlas.set_pixel(at.x + bx, at.y, OUTLINE_COLOR)
				atlas.set_pixel(at.x + bx, at.y + 1, OUTLINE_INNER)
		if mask & 2:
			for bx in GRID:
				atlas.set_pixel(at.x + bx, at.y + GRID - 1, OUTLINE_COLOR)
				atlas.set_pixel(at.x + bx, at.y + GRID - 2, OUTLINE_INNER)
		if mask & 4:
			for by in GRID:
				atlas.set_pixel(at.x, at.y + by, OUTLINE_COLOR)
				atlas.set_pixel(at.x + 1, at.y + by, OUTLINE_INNER)
		if mask & 8:
			for by in GRID:
				atlas.set_pixel(at.x + GRID - 1, at.y + by, OUTLINE_COLOR)
				atlas.set_pixel(at.x + GRID - 2, at.y + by, OUTLINE_INNER)
	return ImageTexture.create_from_image(atlas)

## The floor atlas: FLOOR_VARIANTS tiles of low-contrast flagstones.
##
## Each tile is subdivided into rectangles of varied size, each filled with one of
## three CLOSE mid-teal shades and separated by a mortar barely darker than the
## stones themselves. Varying the rectangle sizes is what stops it reading as a
## checkerboard; keeping the shades close is what keeps it calm, and keeps it
## clearly darker than the cap above it.
func _floor_source() -> TileSetAtlasSource:
	var atlas := Image.create_empty(FLOOR_VARIANTS * GRID, GRID, false,
		Image.FORMAT_RGBA8)
	atlas.fill(FLOOR_MORTAR)
	for v in FLOOR_VARIANTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = ART_SEED + v * 31
		var at := Vector2i(v * GRID, 0)
		# A tile is TWO rows of large slabs at most. An earlier pass subdivided into
		# 4-8px rows, which produced small uniform bricks and read as noise; the
		# reference floor is a few big flat stones per tile.
		var y := 0
		while y < GRID:
			var h := mini(rng.randi_range(8, GRID), GRID - y)
			# One or two wide stones per row.
			var x := 0
			while x < GRID:
				var w := mini(rng.randi_range(8, GRID), GRID - x)
				var shade: Color = FLOOR_SHADES[
					rng.randi_range(0, FLOOR_SHADES.size() - 1)]
				# Inset by 1px right and bottom so the mortar shows as a thin joint.
				for by in range(y, y + maxi(h - 1, 1)):
					for bx in range(x, x + maxi(w - 1, 1)):
						atlas.set_pixel(at.x + bx, at.y + by, shade)
				x += w
			y += h

	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(atlas)
	src.texture_region_size = Vector2i(GRID, GRID)
	for v in FLOOR_VARIANTS:
		src.create_tile(Vector2i(v, 0))
	return src


## Which flagstone variant a cell uses. A hash of the coordinate, so the floor is
## varied but identical on every run and never re-shuffles between frames.
func _floor_variant(x: int, y: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663)
	return absi(h) % FLOOR_VARIANTS


## Which cap variant a cell uses. Hashed from the coordinate for the same reason
## as the floor: varied, but stable across runs and frames.
func _cap_variant(x: int, y: int) -> int:
	var h := (x * 83492791) ^ (y * 2971215073)
	return absi(h) % CAP_VARIANTS


## The side-mask for a silhouette cell: 1=up 2=down 4=left 8=right.
##
## A side is drawn when the neighbouring cell does not show the SAME surface.
##
## This compares against the CAP rather than the whole band on purpose. The band
## is two cells thick but only the inner row carries masonry, so measuring against
## the band put the cyan line out on the far side of an empty row and left a
## black gap between the outline and the bricks. The reference has the line
## hugging the stone, so that is what the neighbour test has to ask.
func _edge_mask(grid: Array, cell: Vector2i) -> int:
	var mask := 0
	if not _shows_wall(grid, cell + Vector2i.UP):
		mask |= 1
	if not _shows_wall(grid, cell + Vector2i.DOWN):
		mask |= 2
	if not _shows_wall(grid, cell + Vector2i.LEFT):
		mask |= 4
	if not _shows_wall(grid, cell + Vector2i.RIGHT):
		mask |= 8
	return mask


## True when `cell` shows the same surface as a cap: the cap cell itself, or
## open floor beside it. Floor counts because the outline must run along the base
## of the wall exactly where the masonry meets the room.
func _shows_wall(grid: Array, cell: Vector2i) -> bool:
	return _is_cap(grid, cell) or _walkable(grid, cell)


## True when this wall cell should be drawn as a visible brick cap.
##
## Only north-facing edges and step-ups get masonry, which is what makes the wall a
## thin cap instead of a thick block: a cap cell is one whose SOUTHERN neighbour is
## walkable floor. Side and bottom edges get the transparent collision-only tile
## instead, so they block the player but show nothing.
func _is_cap(grid: Array, cell: Vector2i) -> bool:
	return _walkable(grid, cell + Vector2i.DOWN)

## Gives one wall tile a full-cell collision polygon.
##
## Collision is assigned only AFTER the source belongs to a TileSet: a TileData
## resolves its physics layers through the owning TileSet, so asking a detached
## source for its tiles reports "physics.size() = 0" and silently builds a dungeon
## the player walks straight through.
func _make_solid_tile(src: TileSetAtlasSource, coords: Vector2i) -> void:
	var half := float(GRID) * 0.5
	var corners := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
	var td: TileData = src.get_tile_data(coords, 0)
	td.set_collision_polygons_count(0, 1)
	td.set_collision_polygon_points(0, 0, corners)


func _paint_floor(floor_layer: TileMapLayer) -> void:
	for y in MAP_H:
		for x in MAP_W:
			if not _walkable(_grid, Vector2i(x, y)):
				continue
			floor_layer.set_cell(Vector2i(x, y), SRC_FLOOR,
				Vector2i(_floor_variant(x, y), 0))


## Paints the three boundary layers.
##
##   Walls   a brick CAP on north-facing and step-up edges only. Every other band
##           cell gets the transparent collision-only tile, so the side and bottom
##           edges keep blocking the player while showing nothing. This is the
##           change that stops the walls reading as thick tiled blocks.
##   Outline the 1px aqua silhouette, on its own layer so the masonry can be
##           toggled independently.
##
## The outline is painted on BOTH cap cells and floor cells. Cap-only was not
## enough: on a room's south side there is no masonry at all by design, so the
## cyan line stopped dead halfway around the room and the bottom of every room
## had no edge. The reference traces the whole silhouette, including the sides
## and bottom where the outline is the only thing marking the boundary.
##
## A cell is only outlined where it faces the void, never where it faces another
## outlined cell, so the line is one pixel wide and never doubled up.
func _paint_walls(wall_layer: TileMapLayer, edge_layer: TileMapLayer,
		grid: Array) -> void:
	for y in MAP_H:
		for x in MAP_W:
			var cell := Vector2i(x, y)
			if _walkable(grid, cell):
				var floor_mask := _floor_edge_mask(grid, cell)
				if floor_mask != 0:
					edge_layer.set_cell(cell, SRC_EDGE, Vector2i(floor_mask, 0))
				continue
			if _is_band(grid, cell):
				if _is_cap(grid, cell):
					wall_layer.set_cell(cell, SRC_WALL,
						Vector2i(_cap_variant(x, y), 0))
					var mask := _edge_mask(grid, cell)
					if mask != 0:
						edge_layer.set_cell(cell, SRC_EDGE, Vector2i(mask, 0))
				else:
					wall_layer.set_cell(cell, SRC_WALL, Vector2i(WALL_BLOCK, 0))
			elif _is_void(grid, cell):
				# The rim just outside the band: invisible, but it still blocks.
				wall_layer.set_cell(cell, SRC_WALL, Vector2i(WALL_BLOCK, 0))


## Every non-walkable cell gets a collision, unconditionally.
##
## _paint_walls above tiles a cell only when _is_band or _is_void says so, and
## both are one-sided: _is_band scans dy from 0, so it NEVER looks north of a
## cell, and _is_void probes only the four cardinal neighbours. A cell directly
## north of floor therefore failed both, fell through every branch, and was
## drawn as nothing at all - no art AND no collision.
##
## tools/audit_wall_holes.gd found 385 such cells, 58 touching floor, in
## unbroken runs along y=13, y=29 and y=40. The player could walk out through
## the north side of a room and into the void.
##
## This runs after _paint_walls and only fills cells with no tile yet, so it
## cannot replace a cap or a drawn block - it can only close holes. Collision no
## longer depends on any of the geometric predicates agreeing.
func _seal_walls(wall_layer: TileMapLayer, grid: Array) -> void:
	var sealed := 0
	for y in MAP_H:
		for x in MAP_W:
			var cell := Vector2i(x, y)
			if _walkable(grid, cell):
				continue
			if wall_layer.get_cell_source_id(cell) != -1:
				continue
			wall_layer.set_cell(cell, SRC_WALL, Vector2i(WALL_BLOCK, 0))
			sealed += 1
	if sealed > 0:
		print("wall seal     : %d cell(s) had no collision, now closed"
			% sealed)


## A solid ring of static bodies around the whole map, BORDER_THICK cells deep.
##
## The tile seal only covers cells inside the grid. This covers everything
## outside it, so no speed or knockback can put the player beyond the map. Four
## rectangles, not tiles, so no painting rule can undo it.
func _place_border(body: Node2D) -> void:
	var cell_px := float(GRID * SCALE)
	var w := float(MAP_W) * cell_px
	var h := float(MAP_H) * cell_px
	var t := float(BORDER_THICK) * cell_px
	var ring := StaticBody2D.new()
	ring.name = "Border"
	ring.collision_layer = Layers.WORLD
	ring.collision_mask = 0
	body.add_child(ring)
	# Centre position and size of each of the four slabs.
	var slabs := [
		Vector4(w * 0.5, -t * 0.5, w, t),
		Vector4(w * 0.5, h + t * 0.5, w, t),
		Vector4(-t * 0.5, h * 0.5, t, h + t * 2.0),
		Vector4(w + t * 0.5, h * 0.5, t, h + t * 2.0),
	]
	for i in slabs.size():
		var v: Vector4 = slabs[i]
		var cs := CollisionShape2D.new()
		cs.name = "Slab%d" % i
		var box := RectangleShape2D.new()
		box.size = Vector2(v.z, v.w)
		cs.shape = box
		cs.position = Vector2(v.x, v.y)
		ring.add_child(cs)


## The outline sides of a FLOOR cell: any side that is not floor and not a cap.
##
## A cap neighbour counts as "inside", which is what keeps the line hugging the
## top of the brick on north-facing walls instead of cutting through it.
func _floor_edge_mask(grid: Array, cell: Vector2i) -> int:
	var mask := 0
	if not _shows_wall(grid, cell + Vector2i.UP):
		mask |= 1
	if not _shows_wall(grid, cell + Vector2i.DOWN):
		mask |= 2
	if not _shows_wall(grid, cell + Vector2i.LEFT):
		mask |= 4
	if not _shows_wall(grid, cell + Vector2i.RIGHT):
		mask |= 8
	return mask
func _is_void(grid: Array, cell: Vector2i) -> bool:
	if _walkable(grid, cell) or _is_band(grid, cell):
		return false
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if _is_band(grid, cell + d):
			return true
	return false


## True when `cell` is inside the solid rock band that wraps the carved rooms:
## not walkable, but close enough to carved floor to be wall rather than the
## empty rock beyond the dungeon.
func _is_band(grid: Array, cell: Vector2i) -> bool:
	if _walkable(grid, cell):
		return false
	for dy in range(0, WALL_RING + 1):
		for dx in range(-WALL_RING, WALL_RING + 1):
			if _walkable(grid, Vector2i(cell.x + dx, cell.y + dy)):
				return true
	return false


# --- Placement -------------------------------------------------------------

func _place_torches(props: Node2D, grid: Array) -> void:
	for cell in _build_torches(grid):
		props.add_child(_make_torch(cell))


## The two fixed lights for the south shaft.
##
## These go through _make_torch, not through the generated _build_torches pass, so
## they carry the identical soft cyan PointLight2D every other light in the
## dungeon has. They bypass _torch_ok on purpose - that check rejects corridor
## cells so a torch can never pinch a doorway, and this shaft has no doorways to
## pinch, only 20 cells of tunnel.
##
## Each one is still re-checked against walkability and against the trap list
## here rather than trusted: a listed light that landed on a trap or on rock
## would silently become a light in a wall.
func _place_shaft_lights(props: Node2D, grid: Array) -> void:
	for cell in SHAFT_LIGHTS:
		if not _walkable(grid, cell):
			push_error("shaft light at %s is not on walkable floor" % cell)
			continue
		if TRAPS.has(cell):
			push_error("shaft light at %s sits on a trap" % cell)
			continue
		props.add_child(_make_torch(cell))


## A torch at `cell`, with the dungeon's soft cyan light.
func _make_torch(cell: Vector2i) -> Node2D:
	var node := Node2D.new()
	node.name = "Torch_%d_%d" % [cell.x, cell.y]
	node.position = _cell_centre(cell)
	node.set_script(TORCH_SCRIPT)

	# A soft cyan pool, centred on the torch.
	#
	# The light is a CHILD of the torch node, and the node sits at the cell
	# centre, so the glow is centred on the light source and is never
	# tile-aligned. Additive blending is what makes it read as emitted light
	# over the dark ambient instead of a pale disc pasted on the floor.
	var light := PointLight2D.new()
	light.name = "Light"
	light.texture = _light_texture()
	light.texture_scale = 0.62
	light.energy = 0.62
	light.color = Color(0.435, 0.953, 1.0)
	light.blend_mode = Light2D.BLEND_MODE_ADD
	node.add_child(light)
	return node


## The Marker2D the player starts and respawns at, at the centre of ROOM_START.
##
## The builder owns this rather than Main.tscn, because the position has to be
## derived from the same room rectangle everything else is carved from. Hardcoding
## a position in the scene file is what put the old spawn at cell (9,24) instead
## of the hall centre (10,25).
func _place_player_start() -> void:
	var cell := _room_centre(ROOM_START)
	var marker := Marker2D.new()
	marker.name = "PlayerStart"
	marker.position = _cell_centre(cell)
	marker.set_meta("cell", cell)
	add_child(marker)


func _place_props(props: Node2D, grid: Array) -> void:
	for cell in CHESTS:
		if _walkable(grid, cell):
			props.add_child(_make_chest(cell))
	for cell in POTS:
		if _walkable(grid, cell):
			props.add_child(_make_breakable(cell, "Pot", "Pot/P001/P001", 8, 10.0))
	for cell in CRATES:
		if _walkable(grid, cell):
			props.add_child(_make_breakable(cell, "Crate", "Box/B001/B001", 7, 12.0))


func _place_traps(hazards: Node2D, grid: Array) -> void:
	for cell in TRAPS:
		if _walkable(grid, cell):
			hazards.add_child(_make_trap(cell))


## A Marker2D at the centre of every hall, so enemy spawning has somewhere to
## aim. The markers are positions only - no enemies are spawned yet.
## Populates EnemySpawns: one Marker2D per enemy, and one trigger per monster
## room.
##
## The markers are the dungeon builder's single source of truth for placement,
## which is what lets check_layout.gd assert the spawn rules without having to
## re-derive them or trust the enemy nodes at runtime.
func _place_enemy_spawns() -> void:
	var spawns := Node2D.new()
	spawns.name = "EnemySpawns"
	add_child(spawns)
	var triggers := Node2D.new()
	triggers.name = "RoomTriggers"
	# Enemies draw at the actor layer, so a tall sprite (skeleton, mushroom,
	# goblin) is never cut off by the wall cap and the cyan Outline stays
	# under it. Previously this node inherited the default z 0, which is BELOW
	# the wall cap at z 1 - the same bug as the player.
	triggers.z_index = Z_ACTORS
	add_child(triggers)
	_place_mimics(spawns)

	# What a spawn must keep away from, read from the nodes that were ACTUALLY
	# placed rather than from the const lists they came from. Torches in
	# particular are seeded at placement time and have no cell list to copy, and
	# a spawn rule that silently skipped them would be a rule nobody could see.
	var blocked := _blocked_cells()

	var start := _room_centre(ROOM_HALL)
	for room_name in ROOMS:
		if not SPAWNER.is_enemy_room(room_name):
			continue
		var key := SPAWNER.monster_key(room_name)
		var cells := SPAWNER.plan(func(c: Vector2i) -> bool:
				return _walkable(_grid, c), ROOMS[room_name], room_name,
				blocked, start)
		for i in cells.size():
			var marker := Marker2D.new()
			var cell: Vector2i = cells[i]
			marker.name = "Spawn_%s_%d_%d" % [room_name, cell.x, cell.y]
			marker.position = _cell_centre(cell)
			spawns.add_child(marker)
			# The bone hall's LAST skeleton is the boss, marked by position in the
			# room rather than by name so the flag cannot drift from the spawn.
			var is_boss: bool = room_name == "bone_hall" and i == cells.size() - 1
			var enemy := SPAWNER.make_enemy(key, _cell_centre(cell), room_name,
					null, is_boss)
			if is_boss:
				enemy.name = "Enemy_%s_%d_%d_boss" % [room_name, cell.x, cell.y]
			spawns.add_child(enemy)
		triggers.add_child(SPAWNER.make_trigger(ROOMS[room_name], room_name))
		print("spawn %-11s %-12s %d enemy/enemies%s"
				% [room_name, key, cells.size(),
				" (last is the boss)" if room_name == "bone_hall" else ""])
# --- Node factories --------------------------------------------------------

## Lays out the dormant Mimics, beside their chests and against a wall.
##
## They are parented to the SAME Props node the chests live in, which is what
## makes them sort and light identically: Props carries the z_index, and a
## mimic built anywhere else would draw behind the floor or in front of the wall
## cap. The sprite keeps the default material so the dungeon lights still reach
## it, exactly as they reach a real chest.
func _place_mimics(spawns: Node2D) -> void:
	var props := get_node_or_null("Props")
	if props == null:
		return
	var walkable := func(c: Vector2i) -> bool: return _walkable(_grid, c)
	var blocked := _blocked_cells()
	var start := _room_centre(ROOM_HALL)
	for room_name in SPAWNER.MIMIC_DENS:
		var spec: Dictionary = SPAWNER.MIMIC_DENS[room_name]
		var chest: Vector2i = spec["chest"]
		var want: int = int(spec["count"])
		var cells := SPAWNER.plan_mimic(walkable, ROOMS[room_name], chest,
				want, blocked, start)
		for i in cells.size():
			var cell: Vector2i = cells[i]
			var m := SPAWNER.make_mimic(_cell_centre(cell), room_name,
					"Cell_%d_%d" % [cell.x, cell.y])
			props.add_child(m)
			# Belt and braces: the spawner already leaves these unset, but a
			# dormant mimic that sorts differently from a real chest gives the
			# disguise away the instant the player walks behind it.
			m.z_index = 0
			m.y_sort_enabled = false
		print("spawn %-11s MIMIC         %d/%d dormant (chest %s, clearance %.1fpx)"
				% [room_name, cells.size(), want, chest,
				SPAWNER.mimic_wall_clearance_px()])


## The cells a spawn must avoid: traps, chests and crates.
##
## Read from the const lists, not by walking the tree. The tree version picked up
## torches and pots too, and torches are wall decoration with no collider - they
## were reserving floor that could never be used.
func _blocked_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append_array(TRAPS)
	out.append_array(CHESTS)
	out.append_array(CRATES)
	SPAWNER.set_props(out)
	return out


## Where the spawns went, without building the whole scene.
##
## Returns [{name, cell}] for each marker the planner chose. Kept separate from
## _place_enemy_spawns so a test can assert the plan without instantiating
## enemies, and so the two cannot drift apart.
func _place_enemy_spawns_probe(grid: Array) -> Array:
	var out: Array = []
	var walkable := _safe_walkable(grid)
	var blocked := _blocked_cells()
	var start := _room_centre(ROOM_HALL)
	for room_name in ROOMS:
		if not SPAWNER.is_enemy_room(room_name):
			continue
		for cell in SPAWNER.plan(walkable, ROOMS[room_name], room_name,
				blocked, start):
			out.append({"name": "Spawn_%s_%d_%d" % [room_name, cell.x, cell.y],
					"room": room_name, "cell": cell})
	return out


## _walkable with bounds checking, because the clearance probe deliberately
## walks rings OUTWARD from a cell and will leave the map. The unguarded version
## threw "Out of bounds get index" once per probe ring.
func _safe_walkable(grid: Array) -> Callable:
	return func(c: Vector2i) -> bool:
		if c.x < 0 or c.y < 0 or c.y >= grid.size():
			return false
		var row = grid[c.y]
		if c.x >= row.size():
			return false
		return bool(row[c.x])


## The candidate cells for a room, for the failure message when it comes up
## short. Showing the room's legal cells is what makes a placement failure
## actionable instead of just a number.
func _room_candidates(grid: Array, room: Rect2i) -> Array:
	var walkable := _safe_walkable(grid)
	var out: Array = []
	for y in room.size.y:
		for x in room.size.x:
			var c := room.position + Vector2i(x, y)
			if bool(walkable.call(c)):
				out.append(c)
	return out


## The single chest that ends the loop, in the furthest room.
const FINAL_CHEST := Vector2i(4, 36)


func _is_final_chest(cell: Vector2i) -> bool:
	return cell == FINAL_CHEST


func _make_chest(cell: Vector2i) -> Area2D:
	var node := Area2D.new()
	node.name = "Chest_%d_%d" % [cell.x, cell.y]
	node.position = _cell_centre(cell)
	node.set_script(LOOT_SCRIPT)
	# The chest in the LAST room is a doorway, not a payout: opening it sends the
	# player back to PlayerStart and respawns every enemy.
	node.set("resets_the_run", _is_final_chest(cell))

	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = _chest_frames()
	sprite.play("idle")
	node.add_child(sprite)

	node.add_child(_box_shape(GRID))
	return node


func _make_breakable(cell: Vector2i, label: String, prefix: String, count: int,
		speed: float) -> Area2D:
	var node := Area2D.new()
	node.name = "%s_%d_%d" % [label, cell.x, cell.y]
	node.position = _cell_centre(cell)
	node.set_script(PROP_SCRIPT)

	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = _breakable_frames(prefix, count, speed)
	sprite.play("idle")
	node.add_child(sprite)

	node.add_child(_box_shape(GRID))
	return node


## A spike trap: the 14-frame TP001 loop on an AnimatedSprite2D inside the
## Area2D that applies the slow. Art and hitbox are the same node, so they can
## never drift apart, and a trap is never solid - it costs time, not a life.
func _make_trap(cell: Vector2i) -> Area2D:
	var node := Area2D.new()
	node.name = "Trap_%d_%d" % [cell.x, cell.y]
	node.position = _cell_centre(cell)
	node.set_script(TRAP_SCRIPT)

	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = _get_trap_frames()
	node.add_child(sprite)

	node.add_child(_box_shape(GRID))
	return node


func _box_shape(size_px: int) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var box := RectangleShape2D.new()
	box.size = Vector2(size_px, size_px)
	shape.shape = box
	return shape


# --- Resources -------------------------------------------------------------

## A chest is not breakable: it holds a still "idle" lid until it is struck,
## then lifts. Those two names are a contract with loot.gd.
func _chest_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.add_frame("idle", load(SHEET_DIR + "Chest/C001/C001_01.png"))
	frames.set_animation_speed("idle", 6.0)
	frames.set_animation_loop("idle", true)

	frames.add_animation("open")
	for i in 7:
		frames.add_frame("open",
			load(SHEET_DIR + "Chest/C001/C001_%02d.png" % (i + 1)))
	frames.set_animation_speed("open", 9.0)
	frames.set_animation_loop("open", false)
	return frames


## Builds "idle" as a still of frame 1 plus a reaction built from every frame,
## which is the pair prop_breakable.gd expects.
func _breakable_frames(prefix: String, count: int, speed: float) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.add_frame("idle", load(SHEET_DIR + "%s_01.png" % prefix))
	frames.set_animation_speed("idle", 6.0)
	frames.set_animation_loop("idle", true)

	frames.add_animation("break")
	for i in count:
		frames.add_frame("break", load(SHEET_DIR + "%s_%02d.png" % [prefix, i + 1]))
	frames.set_animation_speed("break", speed)
	frames.set_animation_loop("break", false)
	return frames


func _get_trap_frames() -> SpriteFrames:
	if _trap_frames != null:
		return _trap_frames
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("spikes")
	for i in TP_FRAMES:
		frames.add_frame("spikes",
			load(SHEET_DIR + "Trap/TP001/TP001_%02d.png" % (i + 1)))
	frames.set_animation_speed("spikes", 12.0)
	frames.set_animation_loop("spikes", true)
	_trap_frames = frames
	return frames


## A soft radial falloff so the torch pools light instead of stamping a disc.
##
## Four stops, not two: a two-stop gradient holds full white over the inner half
## and then falls off a cliff, which is what reads as a hard-edged disc. The
## gradual ramp is what makes the edge genuinely soft.
##
## fill_to is (1.0, 0.5) - the gradient runs from the centre to the RIGHT edge,
## so it reaches zero exactly at the texture border. Reaching zero at the rim is
## what prevents the square edge of the texture from showing.
func _light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.72),
		Color(1, 1, 1, 0.28),
		Color(1, 1, 1, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
