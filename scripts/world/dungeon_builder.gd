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
## The layout is a nine-room serpentine route:
##
##      hall --- cistern --- crypt
##                            |
##      eye_well --- vault --- forge
##         |
##      goblin --- mimic
##                   |
##               bone_hall
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

const PROP_SCRIPT := preload("res://scripts/world/prop_breakable.gd")
const LOOT_SCRIPT := preload("res://scripts/items/loot.gd")
const TORCH_SCRIPT := preload("res://scripts/world/torch.gd")
const TRAP_SCRIPT := preload("res://scripts/world/trap.gd")
const SPAWNER := preload("res://scripts/enemies/enemy_spawner.gd")

const GRID := 16            # tile size in source pixels
const SCALE := 2.0         # the Dungeon node is scaled 2x, see dungeon.tscn
const ROOM_WIDTH := 10
const ROOM_HEIGHT := 8
const CORRIDOR_LENGTH := 4
const CORRIDOR_WIDTH := 3
const BOSS_ROOM_WIDTH_MULTIPLIER := 2
const BOSS_ROOM_HEIGHT_MULTIPLIER := 1.5
const BOSS_ROOM_WIDTH := ROOM_WIDTH * BOSS_ROOM_WIDTH_MULTIPLIER
const BOSS_ROOM_HEIGHT := int(ROOM_HEIGHT * BOSS_ROOM_HEIGHT_MULTIPLIER)
const ROOM_MARGIN := 2
const ROOM_DOOR_OFFSET_X := int((ROOM_WIDTH - CORRIDOR_WIDTH) / 2.0)
const ROOM_DOOR_OFFSET_Y := int((ROOM_HEIGHT - CORRIDOR_WIDTH) / 2.0)
const BOSS_DOOR_OFFSET_X := int((BOSS_ROOM_WIDTH - CORRIDOR_WIDTH) / 2.0)

const ROOM_X_LEFT := ROOM_MARGIN
const ROOM_X_MIDDLE := ROOM_X_LEFT + ROOM_WIDTH + CORRIDOR_LENGTH
const ROOM_X_RIGHT := ROOM_X_MIDDLE + ROOM_WIDTH + CORRIDOR_LENGTH
const ROOM_Y_TOP := ROOM_MARGIN
const ROOM_Y_MIDDLE := ROOM_Y_TOP + ROOM_HEIGHT + CORRIDOR_LENGTH
const ROOM_Y_BOTTOM := ROOM_Y_MIDDLE + ROOM_HEIGHT + CORRIDOR_LENGTH
const BOSS_ROOM_X := ROOM_X_MIDDLE + int((ROOM_WIDTH - BOSS_ROOM_WIDTH) / 2.0)
const BOSS_ROOM_Y := ROOM_Y_BOTTOM + ROOM_HEIGHT + CORRIDOR_LENGTH

# The map bounds follow the layout, including the boss room and its wall margin.
const MAP_W := ROOM_X_RIGHT + ROOM_WIDTH + ROOM_MARGIN
const MAP_H := BOSS_ROOM_Y + BOSS_ROOM_HEIGHT + ROOM_MARGIN

# The player's collider in Main.tscn is 43x67 px, which is 1.4 x 2.1 cells at
# SCALE 2, so a corridor has to be 3 cells (96 px) across to be walkable.
const MIN_CORRIDOR := CORRIDOR_WIDTH

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
# Regular rooms share one size and use the same grid pitch. The oversized boss
# room sits beyond the last regular room, centered on its corridor entrance.
const ROOM_HALL := Rect2i(ROOM_X_LEFT, ROOM_Y_TOP, ROOM_WIDTH, ROOM_HEIGHT)
const ROOM_CISTERN := Rect2i(ROOM_X_MIDDLE, ROOM_Y_TOP, ROOM_WIDTH, ROOM_HEIGHT)
const ROOM_CRYPT := Rect2i(ROOM_X_RIGHT, ROOM_Y_TOP, ROOM_WIDTH, ROOM_HEIGHT)
const ROOM_FORGE := Rect2i(ROOM_X_RIGHT, ROOM_Y_MIDDLE, ROOM_WIDTH, ROOM_HEIGHT)
const ROOM_VAULT := Rect2i(ROOM_X_MIDDLE, ROOM_Y_MIDDLE, ROOM_WIDTH, ROOM_HEIGHT)
const ROOM_EYEWELL := Rect2i(ROOM_X_LEFT, ROOM_Y_MIDDLE, ROOM_WIDTH, ROOM_HEIGHT)
const ROOM_GOBLIN := Rect2i(ROOM_X_LEFT, ROOM_Y_BOTTOM, ROOM_WIDTH, ROOM_HEIGHT)
const ROOM_MIMIC := Rect2i(ROOM_X_MIDDLE, ROOM_Y_BOTTOM, ROOM_WIDTH, ROOM_HEIGHT)
const ROOM_BONE := Rect2i(BOSS_ROOM_X, BOSS_ROOM_Y,
		BOSS_ROOM_WIDTH, BOSS_ROOM_HEIGHT)
const ROOMS := {
	"hall": ROOM_HALL,
	"cistern": ROOM_CISTERN,
	"crypt": ROOM_CRYPT,
	"forge": ROOM_FORGE,
	"vault": ROOM_VAULT,
	"eye_well": ROOM_EYEWELL,
	"goblin_den": ROOM_GOBLIN,
	"mimic_den": ROOM_MIMIC,
	"bone_hall": ROOM_BONE,
}
const ROOM_START := ROOM_HALL

# Corridors occupy the fixed gap between rooms and are centered on their
# entrances; each is CORRIDOR_LENGTH long and CORRIDOR_WIDTH cells wide.
const CORRIDORS := [
	Rect2i(ROOM_X_LEFT + ROOM_WIDTH, ROOM_Y_TOP + ROOM_DOOR_OFFSET_Y,
			CORRIDOR_LENGTH, CORRIDOR_WIDTH), # hall -> cistern
	Rect2i(ROOM_X_MIDDLE + ROOM_WIDTH, ROOM_Y_TOP + ROOM_DOOR_OFFSET_Y,
			CORRIDOR_LENGTH, CORRIDOR_WIDTH), # cistern -> crypt
	Rect2i(ROOM_X_RIGHT + ROOM_DOOR_OFFSET_X,
			ROOM_Y_TOP + ROOM_HEIGHT, CORRIDOR_WIDTH, CORRIDOR_LENGTH), # crypt -> forge
	Rect2i(ROOM_X_MIDDLE + ROOM_WIDTH, ROOM_Y_MIDDLE + ROOM_DOOR_OFFSET_Y,
			CORRIDOR_LENGTH, CORRIDOR_WIDTH), # forge -> vault
	Rect2i(ROOM_X_LEFT + ROOM_WIDTH, ROOM_Y_MIDDLE + ROOM_DOOR_OFFSET_Y,
			CORRIDOR_LENGTH, CORRIDOR_WIDTH), # vault -> eye_well
	Rect2i(ROOM_X_LEFT + ROOM_DOOR_OFFSET_X,
			ROOM_Y_MIDDLE + ROOM_HEIGHT, CORRIDOR_WIDTH, CORRIDOR_LENGTH), # eye_well -> goblin
	Rect2i(ROOM_X_LEFT + ROOM_WIDTH, ROOM_Y_BOTTOM + ROOM_DOOR_OFFSET_Y,
			CORRIDOR_LENGTH, CORRIDOR_WIDTH), # goblin -> mimic
	Rect2i(BOSS_ROOM_X + BOSS_DOOR_OFFSET_X,
			ROOM_Y_BOTTOM + ROOM_HEIGHT, CORRIDOR_WIDTH, CORRIDOR_LENGTH), # mimic -> boss
]

## Minimum lights for rooms that need guaranteed illumination.
##
## the global TORCH_MIN_PER_ROOM is 0, which means an unlisted room can be handed
## zero torches and render as an unlit black box. Listed rooms are guaranteed a
## floor; rooms absent from this table keep the random behaviour.
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
		# Rooms in ROOM_MIN_TORCH get that minimum in addition to the random draw;
		# all other rooms retain the original global range.
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
	for room_name in SPAWNER.ROOM_MONSTER:
		var centre := _room_centre(ROOMS[room_name])
		if absi(cell.x - centre.x) <= 1 \
				and absi(cell.y - centre.y) <= 1:
			return false
	for room_name in SPAWNER.MIMIC_DENS:
		var centre := _room_centre(ROOMS[room_name])
		if absi(cell.x - centre.x) <= 1 \
				and absi(cell.y - centre.y) <= 1:
			return false
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


# Enemy-room chests sit toward the lower-right wall with a two-cell wall margin,
# leaving the centred enemy and its interaction area clear.
const CHEST_MARGIN := 2
const CHEST_OFFSET := Vector2i(
		int(ROOM_WIDTH / 2.0) - CHEST_MARGIN,
		int(ROOM_HEIGHT / 2.0) - CHEST_MARGIN)
const CHEST_ENEMY_CLEARANCE := 32.0
const CHEST_VISIBLE_SIZE := Vector2(24.0, 24.0)
const CHEST_HALL := Vector2i(ROOM_X_LEFT + 2,
		ROOM_Y_TOP + ROOM_HEIGHT - 2)
const CHEST_CRYPT := Vector2i(
		ROOM_X_RIGHT + int(ROOM_WIDTH / 2.0) + CHEST_OFFSET.x,
		ROOM_Y_TOP + int(ROOM_HEIGHT / 2.0) + CHEST_OFFSET.y)
const CHEST_FORGE := Vector2i(
		ROOM_X_RIGHT + int(ROOM_WIDTH / 2.0) + CHEST_OFFSET.x,
		ROOM_Y_MIDDLE + int(ROOM_HEIGHT / 2.0) + CHEST_OFFSET.y)
const CHEST_VAULT := Vector2i(
		ROOM_X_MIDDLE + int(ROOM_WIDTH / 2.0) + CHEST_OFFSET.x,
		ROOM_Y_MIDDLE + int(ROOM_HEIGHT / 2.0) + CHEST_OFFSET.y)
const CHEST_GOBLIN_DEN := Vector2i(
		ROOM_X_LEFT + int(ROOM_WIDTH / 2.0) + CHEST_OFFSET.x,
		ROOM_Y_BOTTOM + int(ROOM_HEIGHT / 2.0) + CHEST_OFFSET.y)
const CHEST_MIMIC_DEN := Vector2i(
		ROOM_X_MIDDLE + int(ROOM_WIDTH / 2.0) + CHEST_OFFSET.x,
		ROOM_Y_BOTTOM + int(ROOM_HEIGHT / 2.0) + CHEST_OFFSET.y)
const BOSS_CHEST_MARGIN := 4
const FINAL_CHEST := Vector2i(BOSS_ROOM_X + BOSS_ROOM_WIDTH - BOSS_CHEST_MARGIN,
		BOSS_ROOM_Y + int(BOSS_ROOM_HEIGHT / 2.0))
const CHEST_BY_ROOM := {
	"crypt": CHEST_CRYPT,
	"forge": CHEST_FORGE,
	"vault": CHEST_VAULT,
	"goblin_den": CHEST_GOBLIN_DEN,
	"mimic_den": CHEST_MIMIC_DEN,
	"bone_hall": FINAL_CHEST,
}
# One chest per reward room plus one in the spawn hall; loot behavior is unchanged.
const CHESTS: Array[Vector2i] = [
	CHEST_HALL,
	CHEST_CRYPT,
	CHEST_FORGE,
	CHEST_VAULT,
	# eye_well stays the empty reward room.
	CHEST_GOBLIN_DEN,
	CHEST_MIMIC_DEN,
	FINAL_CHEST,
]
const POTS: Array[Vector2i] = [
	Vector2i(ROOM_X_MIDDLE + 2, ROOM_Y_TOP + 2),
	Vector2i(ROOM_X_MIDDLE + 3, ROOM_Y_TOP + 2),
	Vector2i(ROOM_X_MIDDLE + 2, ROOM_Y_TOP + 3),
]
const CRATES: Array[Vector2i] = [
	Vector2i(ROOM_X_RIGHT + 2, ROOM_Y_MIDDLE + 2),
	Vector2i(ROOM_X_RIGHT + 3, ROOM_Y_MIDDLE + 2),
	Vector2i(ROOM_X_RIGHT + 2, ROOM_Y_MIDDLE + 3),
]

# Room-floor traps slow the player without blocking a narrow corridor. Their
# positions follow the room grid so resizing or moving a row does not strand
# them in rock or in a passage.
const TRAPS: Array[Vector2i] = [
	Vector2i(ROOM_X_LEFT + 1, ROOM_Y_TOP + 5),
	Vector2i(ROOM_X_LEFT + 2, ROOM_Y_TOP + 5),
	Vector2i(ROOM_X_LEFT + 3, ROOM_Y_TOP + 5), # hall
	Vector2i(ROOM_X_MIDDLE + 5, ROOM_Y_TOP + 5),
	Vector2i(ROOM_X_MIDDLE + 6, ROOM_Y_TOP + 5), # cistern
	Vector2i(ROOM_X_RIGHT + 2, ROOM_Y_TOP + 5),
	Vector2i(ROOM_X_RIGHT + 3, ROOM_Y_TOP + 5),
	Vector2i(ROOM_X_RIGHT + 2, ROOM_Y_TOP + 6), # crypt
	Vector2i(ROOM_X_MIDDLE + 2, ROOM_Y_MIDDLE + 5),
	Vector2i(ROOM_X_MIDDLE + 3, ROOM_Y_MIDDLE + 5), # vault
	Vector2i(ROOM_X_LEFT + 2, ROOM_Y_MIDDLE + 2),
	Vector2i(ROOM_X_LEFT + 4, ROOM_Y_MIDDLE + 5), # eye_well
	Vector2i(ROOM_X_LEFT + 2, ROOM_Y_BOTTOM + 2),
	Vector2i(ROOM_X_LEFT + 3, ROOM_Y_BOTTOM + 2),
	Vector2i(ROOM_X_LEFT + 4, ROOM_Y_BOTTOM + 2), # goblin_den
	Vector2i(ROOM_X_MIDDLE + 2, ROOM_Y_BOTTOM + 2),
	Vector2i(ROOM_X_MIDDLE + 3, ROOM_Y_BOTTOM + 3), # mimic_den
]

const TP_FRAMES := 14

# --- Build state -----------------------------------------------------------

var _grid: Array = []
var _trap_frames: SpriteFrames
## The door taken on the way down, read once in _ready().
var _choice := ""
## The chest cell that bites on this floor. Seeded, so the same floor always
## has the same cursed chest and the next floor moves it.
var _cursed_cell := Vector2i(-1, -1)
func _ready() -> void:
	# Looked up through the tree, not by identifier: tools preload this script
	# outside the running game, where autoload names do not resolve.
	var state := get_node_or_null("/root/GameState")
	var run_seed := 0
	if state != null:
		run_seed = int(state.get("run_seed"))
	if run_seed == 0:
		run_seed = randi()
		if state != null:
			state.set("run_seed", run_seed)
	var depth := 1
	if state != null:
		depth = int(state.get("depth"))
	# One chest per floor bites. The pick is seeded from the floor, so the same
	# floor always has the same cursed chest and descending moves the curse.
	_cursed_cell = _pick_cursed_chest(run_seed, depth)
	# The door taken on the way down shapes this floor, then is cleared so it
	# only ever applies to one descent.
	if state != null:
		_choice = str(state.get("floor_choice"))
		state.set("coin_value", 2 if _choice == "combat" else 1)
		state.set("floor_choice", "")

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
	return rect.position + Vector2i(int(float(rect.size.x) * 0.5), int(float(rect.size.y) * 0.5))


func _cell_centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * GRID + GRID * 0.5, cell.y * GRID + GRID * 0.5)


func _room_world_centre(rect: Rect2i) -> Vector2:
	return Vector2(rect.position) * GRID + Vector2(rect.size) * GRID * 0.5


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

	# Room sizes and margins are part of the layout contract; catch accidental
	# per-room shrinking or a boss room pushed beyond its reserved map bounds.
	for room_name in ROOMS:
		var room: Rect2i = ROOMS[room_name]
		var expected_size := Vector2i(BOSS_ROOM_WIDTH, BOSS_ROOM_HEIGHT) \
				if room_name == "bone_hall" else Vector2i(ROOM_WIDTH, ROOM_HEIGHT)
		if room.size != expected_size:
			problems.append("room '%s' has size %s, expected %s"
					% [room_name, room.size, expected_size])
		if room.position.x < ROOM_MARGIN or room.position.y < ROOM_MARGIN \
				or room.end.x > MAP_W - ROOM_MARGIN \
				or room.end.y > MAP_H - ROOM_MARGIN:
			problems.append("room '%s' at %s exceeds the reserved map bounds"
					% [room_name, room])
	var room_names: Array = ROOMS.keys()
	for i in range(room_names.size()):
		var first: Rect2i = ROOMS[room_names[i]]
		for j in range(i + 1, room_names.size()):
			var second: Rect2i = ROOMS[room_names[j]]
			if first.intersects(second):
				problems.append("rooms '%s' and '%s' overlap"
						% [room_names[i], room_names[j]])

	# 1. Every room must be reachable, and so must every walkable cell, or the
	#    player could end up in a sealed pocket with no way out.
	var reach := _flood(grid, spawn)
	for room_name in ROOMS:
		var centre := _room_centre(ROOMS[room_name])
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
		var horizontal := c.size == Vector2i(CORRIDOR_LENGTH, CORRIDOR_WIDTH)
		var vertical := c.size == Vector2i(CORRIDOR_WIDTH, CORRIDOR_LENGTH)
		if not horizontal and not vertical:
			problems.append("corridor %d %s does not match the fixed dimensions" % [i, c])
		if mini(c.size.x, c.size.y) < MIN_CORRIDOR:
			problems.append("corridor %d %s is only %d cells wide" % [
				i, c, mini(c.size.x, c.size.y)])

	# 3. The spawn and every room centre need elbow room, so the player is never
	#    wedged against a wall on frame one.
	if not _clearance(grid, spawn, PLAYER_HALF):
		problems.append("spawn %s has no clearance for the player collider" % spawn)
	for room_name in ROOMS:
		if not _clearance(grid, _room_centre(ROOMS[room_name]), PLAYER_HALF):
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


## Populates EnemySpawns with one Marker2D and one enemy per populated room,
## plus one trigger per regular monster room.
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
		if cells.size() != SPAWNER.ENEMIES_PER_ROOM:
			push_error("Room %s planned %d enemies; expected exactly one"
					% [room_name, cells.size()])
			continue
		var cell: Vector2i = cells[0]
		var spawn_position := _room_world_centre(ROOMS[room_name])
		var marker := Marker2D.new()
		marker.name = "Spawn_%s_%d_%d" % [room_name, cell.x, cell.y]
		marker.position = spawn_position
		spawns.add_child(marker)
		var is_boss: bool = room_name == "bone_hall"
		var enemy := SPAWNER.make_enemy(key, spawn_position, room_name,
				null, is_boss)
		if is_boss:
			enemy.name = "Enemy_%s_%d_%d_boss" % [room_name, cell.x, cell.y]
			_mark_boss_room(room_name)
		spawns.add_child(enemy)
		triggers.add_child(SPAWNER.make_trigger(ROOMS[room_name], room_name))
		var chest_cell: Vector2i = CHEST_BY_ROOM.get(
				room_name, Vector2i(-1, -1))
		var chest_report := "none"
		if chest_cell.x >= 0:
			var clearance := _enemy_chest_clearance_px(enemy, chest_cell)
			chest_report = "%s (%.1fpx clear)" % [str(chest_cell), clearance]
			if clearance < CHEST_ENEMY_CLEARANCE:
				push_error("%s chest clearance is %.1fpx; need %.1fpx"
						% [room_name, clearance, CHEST_ENEMY_CLEARANCE])
		print("spawn %-11s species=%-12s entities=1 sprites=%d scale=%.2f chest=%s"
				% [room_name, key, int(enemy.get("_sprite_count")),
				float(enemy.get("_scale")), chest_report])
# --- Node factories --------------------------------------------------------

## Places one dormant Mimic at the centre of its room.
##
## They are parented to the SAME Props node the chests live in, which is what
## makes them sort and light identically: Props carries the z_index, and a
## mimic built anywhere else would draw behind the floor or in front of the wall
## cap. The sprite keeps the default material so the dungeon lights still reach
## it, exactly as they reach a real chest.
func _place_mimics(_spawns: Node2D) -> void:
	var props := get_node_or_null("Props")
	if props == null:
		return
	var walkable := func(c: Vector2i) -> bool: return _walkable(_grid, c)
	var blocked := _blocked_cells()
	var start := _room_centre(ROOM_HALL)
	for room_name in SPAWNER.MIMIC_DENS:
		var spec: Dictionary = SPAWNER.MIMIC_DENS[room_name]
		var want: int = int(spec["count"])
		var cells := SPAWNER.plan_mimic(walkable, ROOMS[room_name],
				blocked, start)
		if cells.size() != want:
			push_error("Room %s planned %d Mimics; expected exactly %d"
					% [room_name, cells.size(), want])
			continue
		for i in cells.size():
			var cell: Vector2i = cells[i]
			var m := SPAWNER.make_mimic(_room_world_centre(ROOMS[room_name]), room_name,
					"Cell_%d_%d" % [cell.x, cell.y])
			props.add_child(m)
			# Belt and braces: the spawner already leaves these unset, but a
			# dormant mimic that sorts differently from a real chest gives the
			# disguise away the instant the player walks behind it.
			m.z_index = 0
			m.y_sort_enabled = false
			var chest_cell: Vector2i = CHEST_BY_ROOM[room_name]
			var clearance := _enemy_chest_clearance_px(m, chest_cell)
			if clearance < CHEST_ENEMY_CLEARANCE:
				push_error("%s Mimic chest clearance is %.1fpx; need %.1fpx"
						% [room_name, clearance, CHEST_ENEMY_CLEARANCE])
			print("spawn %-11s species=MIMIC       entities=1 sprites=%d scale=%.2f chest=%s (%.1fpx clear)"
					% [room_name, int(m.get("_sprite_count")),
					float(m.get("_scale")),
					str(chest_cell), clearance])


func _enemy_chest_clearance_px(enemy: Node2D, chest_cell: Vector2i) -> float:
	var shape_node := enemy.get_node("InteractionArea/CollisionShape2D") \
			as CollisionShape2D
	var shape := shape_node.shape
	var area_center := enemy.position + shape_node.position
	var chest_center := _cell_centre(chest_cell)
	var delta := (chest_center - area_center).abs()
	var chest_half := CHEST_VISIBLE_SIZE * 0.5
	var clearance := 0.0
	if shape is RectangleShape2D:
		var half := (shape as RectangleShape2D).size * 0.5
		var gap := Vector2(maxf(delta.x - half.x - chest_half.x, 0.0),
				maxf(delta.y - half.y - chest_half.y, 0.0))
		clearance = gap.length()
	elif shape is CircleShape2D:
		var nearest := Vector2(maxf(delta.x - chest_half.x, 0.0),
				maxf(delta.y - chest_half.y, 0.0))
		clearance = maxf(nearest.length() - (shape as CircleShape2D).radius,
				0.0)
	else:
		push_error("%s has an unsupported interaction shape for clearance"
				% enemy.name)
	return clearance * SCALE


## The cells a spawn must avoid: traps, props, and the deterministic torch plan.
## Torches have no collider, but enemies still should not cover their light.
func _blocked_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append_array(TRAPS)
	out.append_array(CHESTS)
	out.append_array(POTS)
	out.append_array(CRATES)
	out.append_array(_build_torches(_grid))
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


func _is_final_chest(cell: Vector2i) -> bool:
	return cell == FINAL_CHEST


## The chest cell that bites on this floor.
##
## Seeded from the floor seed and depth, so the same floor always produces the
## same cursed chest. Never the final chest: that one is a doorway, not a payout.
func _pick_cursed_chest(run_seed: int, depth: int) -> Vector2i:
	var pool: Array[Vector2i] = []
	for cell in CHESTS:
		if not _is_final_chest(cell):
			pool.append(cell)
	if pool.is_empty():
		return Vector2i(-1, -1)
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 31 + depth * 7919
	return pool[rng.randi_range(0, pool.size() - 1)]


## Tells the map which room the boss is in, so the fight is marked before it
## starts rather than remembered afterwards.
func _mark_boss_room(room_name: String) -> void:
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.call("mark_boss_room", room_name)


func _make_chest(cell: Vector2i) -> Area2D:
	var node := Area2D.new()
	node.name = "Chest_%d_%d" % [cell.x, cell.y]
	node.position = _cell_centre(cell)
	node.set_script(LOOT_SCRIPT)
	# The chest in the LAST room is a doorway, not a payout: opening it sends the
	# player back to PlayerStart and respawns every enemy.
	node.set("resets_the_run", _is_final_chest(cell))
	# One chest per floor bites: a heart, but double the gold.
	node.set("cursed", cell == _cursed_cell)
	# HOARD floors pay double at every chest.
	if _choice == "hoard" and not _is_final_chest(cell):
		node.set("coin_count", int(node.get("coin_count")) * 2)

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
