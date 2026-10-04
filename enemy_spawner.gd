extends RefCounted
class_name EnemySpawner
## Decides WHERE enemies stand, and builds the room trigger that wakes them.
##
## Placement is generated from a fixed seed per room, so the dungeon is the same
## every run and a spawn that clips a wall is caught by a test rather than by a
## player discovering it. Nothing here reads randf(): an unseeded spawn is a bug.
##
## The rules, and why each exists:
##
##   on floor              an enemy in a wall is invisible but still solid
##   inset from walls>=1 tile clear of the band, comfortably over the 24px floor
##   clear of traps        an enemy standing on spikes is being punished for the
##                         spawn, not for a mistake it made
##   clear of chests/torch both are props the player walks up to
##   >150px from spawn     nobody should be hit before they have moved
##   not overlapping       two enemies in one cell is one sprite and two hitboxes

const ENEMY_SCENE := preload("res://enemy.tscn")
const ENEMY_SCRIPT := preload("res://enemy.gd")
const DB := preload("res://monster_db.gd")
const MIMIC_SCRIPT := preload("res://mimic.gd")

## Room name -> the monster that lives there. The hall and shaft are absent on
## purpose: those are the safe route and they must stay empty.
const ROOM_MONSTER := {
	"vault": "RAT",
	"cistern": "SLIME",
	"crypt": "MUSHROOM",
	"forge": "BAT",
	"eye_well": "FLYING_EYE",
	"goblin_den": "GOBLIN",
	"bone_hall": "SKELETON",
}
## Rooms that must never hold an enemy, and must never get a trigger.
const EMPTY_ROOMS: Array[String] = ["hall", "shaft"]

## Tiles of clearance kept around every spawn.
const INSET := 1
## One enemy per this many screen pixels of room width, then clamped.
const PER_ENEMY_PX := 70.0
const MIN_ENEMY := 2
const MAX_ENEMY := 6
## Screen pixels an enemy must sit from traps, chests and crates.
##
## Torches and pots are NOT in this list. Torches are wall-mounted decoration
## with no collision, so "stay away from the torch" was reserving floor nothing
## could ever occupy.
const PROP_CLEARANCE_PX := 32.0
## Screen pixels of clear floor between a spawn and the nearest wall.
const WALL_CLEARANCE_PX := 24.0
## Screen pixels from the player's spawn.
const SPAWN_CLEARANCE_PX := 150.0
## Measured from the real chest: C001_01 is a 24x24 image with a 16x15 visible
## chest, and it is drawn 1:1. Both figures come from measure_sheets.gd's own
## pixel scan, not from this comment.
const MIMIC_CHEST_W := 16
const MIMIC_CHEST_H := 15

## Traps, chests and crates. Built once so the planner and check_layout read the
## same list.
static var PROPS: Array[Vector2i] = []
## The Dungeon node is scaled 2x, so one source tile is 32 screen pixels.
const SCREEN_PX_PER_TILE := 32.0


## Rooms that get dormant Mimics, and the real chest each one hides beside.
##
## The mimic is placed relative to a chest on purpose: a dormant mimic IS a
## chest, so a player who has learned to loot this dungeon should be reading the
## room as "three chests here", not "three enemies here".
const MIMIC_DENS: Dictionary = {
	"mimic_den": {"chest": Vector2i(14, 37), "count": 3},
	"crypt": {"chest": Vector2i(25, 10), "count": 1},
}
## How close to its chest a mimic may stand, in tiles. Four reads as a group.
const MIMIC_NEAR_TILES := 4


## The awake mimic's half-width, on screen, from monster_db.
static func awake_half_width() -> float:
	var body: Vector2i = DB.MIMIC.get("body", Vector2i(16, 15))
	return float(body.x) * float(DB.MIMIC["scale"]) * 0.5


## Wall clearance a mimic needs, computed rather than hardcoded.
##
## max(24px, awake half-width + 4px). The awake body is the binding constraint
## and it is much bigger than the 16x15 chest it starts as: at scale 1.6 the
## mimic is 67.2px wide, so a placement that only clears the 24px floor rule
## would stand the creature's shoulder inside a wall the moment it wakes.
static func mimic_wall_clearance_px() -> float:
	return maxf(WALL_CLEARANCE_PX, awake_half_width() + 4.0)


## Picks `count` dormant-mimic cells hugging a wall beside `chest`.
##
## "Beside a chest and against a wall" is the whole disguise, so the wall
## constraint is inverted from the normal spawn rule: instead of being pushed
## away from walls, these MUST have one nearby, while still having enough clear
## floor for the awake body. The cell is floor, all four neighbours are floor
## (a corner is fine, a gap is not), and the body rectangle is checked cell by
## cell.
static func plan_mimic(walkable: Callable, room: Rect2i, chest: Vector2i,
		count: int, blocked: Array[Vector2i],
		player_start: Vector2i) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = room_seed("mimic_" + str(chest))
	# Convert the awake body to TILES, which is the grid's unit.
	var half_tiles := awake_half_width() / SCREEN_PX_PER_TILE
	var height_tiles := float(DB.MIMIC.get("body", Vector2i(16, 15)).y) \
			* float(DB.MIMIC["scale"]) / SCREEN_PX_PER_TILE
	var out: Array[Vector2i] = []
	for _attempt in 800:
		if out.size() >= count:
			break
		var cell := chest + Vector2i(
			rng.randi_range(-MIMIC_NEAR_TILES, MIMIC_NEAR_TILES),
			rng.randi_range(-MIMIC_NEAR_TILES, MIMIC_NEAR_TILES))
		if not room.has_point(cell):
			continue
		if Vector2(cell - chest).length() > MIMIC_NEAR_TILES:
			continue
		if not bool(walkable.call(cell)):
			continue
		# Near a wall: at least one orthogonal neighbour is not floor.
		var against := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not bool(walkable.call(cell + d)):
				against = true
		if not against:
			continue
		# But the AWAKE body must still fit, measured against the grid rather
		# than assumed from the clearance number.
		if not _body_fits(walkable, cell, half_tiles, height_tiles):
			continue
		if _screen_distance(cell, player_start) < SPAWN_CLEARANCE_PX:
			continue
		if _near_any(cell, blocked, PROP_CLEARANCE_PX):
			continue
		if _near_any(cell, out, SCREEN_PX_PER_TILE):
			continue
		out.append(cell)
	return out


## True when the awake body rectangle standing on `cell` covers only floor.
##
## The node origin is the body's bottom-centre, so the rect runs from
## (centre - half, centre - height) to (centre + half, centre).
##
## The halves arrive in TILES, not pixels. The grid is indexed by cell and the
## first version passed the awake half-width (33.6px) straight into a tile
## space, so the rect spanned 67 TILES and could never fit - which is why both
## rooms silently placed zero mimics while the run still went green.
static func _body_fits(walkable: Callable, cell: Vector2i, half: float,
		height: float) -> bool:
	var centre := Vector2(cell) + Vector2(0.5, 0.5)
	var left := centre.x - half
	var top := centre.y - height
	var right := centre.x + half
	var bottom := centre.y
	# Every cell the rectangle touches, including partial ones at the edges.
	var from := Vector2i(floori(left), floori(top))
	var to := Vector2i(floori(right - 0.001), floori(bottom - 0.001))
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			if not bool(walkable.call(Vector2i(x, y))):
				return false
	return true


static func set_props(cells: Array[Vector2i]) -> void:
	PROPS = cells


static func props() -> Array[Vector2i]:
	return PROPS


static func monster_key(room_name: String) -> String:
	return ROOM_MONSTER.get(room_name, "")


static func is_enemy_room(room_name: String) -> bool:
	return ROOM_MONSTER.has(room_name)


## Per-room count overrides, where the width rule would disagree with a
## deliberate design decision.
##
## bone_hall is 6 tiles wide, which the width rule rounds to 3. The room is
## meant to hold 2 skeletons, one of them the boss, so the override caps it. The
## override is NAMED and lives here rather than as a magic number at the call
## site, and check_layout asserts the exact figure so a cap cannot silently drift
## into "however many fit".
const COUNT_OVERRIDE := {
	"bone_hall": 2,
}


## How many enemies a room holds: one per ~70px of width, floored and capped.
##
## Width, not area, because a long thin corridor fights very differently from a
## square room with the same floor count.
static func enemy_count(room: Rect2i, room_name: String = "") -> int:
	if room_name != "" and COUNT_OVERRIDE.has(room_name):
		return int(COUNT_OVERRIDE[room_name])
	var px := float(room.size.x) * SCREEN_PX_PER_TILE
	return clampi(int(round(px / PER_ENEMY_PX)), MIN_ENEMY, MAX_ENEMY)


## A stable seed per room. Named, not hashed, so the same room always lays out
## the same way even if Godot changes its string hash between versions.
##
## The mixing step is not decoration. A raw FNV-style hash handed straight to
## RandomNumberGenerator produced a DEGENERATE stream for "eye_well": the first
## randi_range call returned the same value 600 times, so every candidate cell
## was identical and the room spawned zero enemies. Feeding the seed through a
## 32-bit finaliser and discarding one draw makes every room lay out properly.
static func room_seed(room_name: String) -> int:
	var h := 2166136261
	for i in room_name.length():
		h = (h ^ room_name.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	# Finaliser (murmur3-style), then keep it positive and odd.
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	h = (h * 0x85EBCA6B) & 0xFFFFFFFF
	h = (h ^ (h >> 13)) & 0xFFFFFFFF
	h = (h * 0xC2B2AE35) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return h | 1


## The cells enemies occupy, in order. `blocked` holds traps, chests and torches;
## `walkable` is the builder's OWN test, passed in rather than reimplemented.
##
## Taking it as a Callable is deliberate: the spawner used to index the grid
## itself and silently produced ZERO enemies for every room, because its idea of
## the grid layout did not match the builder's. One test, owned by one file.
static func plan(walkable: Callable, room: Rect2i, room_name: String,
		blocked: Array[Vector2i], player_start: Vector2i) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = room_seed(room_name)
	# Discard the first draw: the initial state of a freshly seeded PCG can still
	# correlate with the seed, and one throwaway draw is cheap insurance.
	rng.randi()
	var want := enemy_count(room, room_name)
	var out: Array[Vector2i] = []
	var why := {"room": 0, "blocked": 0, "spawnfar": 0, "overlap": 0}
	# Bounded so a rule change that makes placement impossible fails the test
	# instead of hanging the build.
	for _attempt in 600:
		if out.size() >= want:
			break
		var cell := room.position + Vector2i(
			rng.randi_range(INSET, room.size.x - 1 - INSET),
			rng.randi_range(INSET, room.size.y - 1 - INSET))
		if not _fits(walkable, cell, room):
			why["room"] += 1
			continue
		if _near_any(cell, blocked, PROP_CLEARANCE_PX):
			why["blocked"] += 1
			continue
		if _screen_distance(cell, player_start) < SPAWN_CLEARANCE_PX:
			why["spawnfar"] += 1
			continue
		if _near_any(cell, out, SCREEN_PX_PER_TILE):
			why["overlap"] += 1
			continue
		out.append(cell)
	print("   plan %-11s want=%d got=%d rejected %s"
			% [room_name, want, out.size(), str(why)])
	return out


## Is this cell floor, with the given clearance from the nearest wall?
##
## The rule is the literal spec - "the spawn cell is floor and at least 24px from
## any wall" - rather than the old blanket "the whole 3x3 ring must be inside
## the room and walkable". The ring rule was stricter in two ways the spec never
## asked for: it demanded room-rect membership as well as walkability, and it
## cost 8 of the 9 cells around a spawn in the small appended rooms.
##
## Clearance is measured, not assumed: the smallest Chebyshev ring containing a
## non-floor cell, times the screen size of a tile.
static func _fits(walkable: Callable, cell: Vector2i, room: Rect2i) -> bool:
	if not room.has_point(cell):
		return false
	if not bool(walkable.call(cell)):
		return false
	var clearance := wall_clearance_px(walkable, cell)
	return clearance >= WALL_CLEARANCE_PX


## Distance in screen pixels from `cell` to the nearest non-floor cell.
static func wall_clearance_px(walkable: Callable, cell: Vector2i) -> float:
	for ring in range(0, 4):
		var on_ring := false
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				# only the square's border
				if absi(dx) != ring and absi(dy) != ring:
					continue
				on_ring = true
				if not bool(walkable.call(cell + Vector2i(dx, dy))):
					return float(ring) * SCREEN_PX_PER_TILE
		if not on_ring:
			break
	return 4.0 * SCREEN_PX_PER_TILE


## True when `cell` is within `min_px` of anything in `others`.
##
## Name and return value agree on purpose. It was originally inverted - returning
## true when FAR - and because the call sites read "if near: skip", every
## candidate was rejected as overlapping and every room spawned zero enemies.
static func _near_any(cell: Vector2i, others: Array, min_px: float) -> bool:
	var tiles := min_px / SCREEN_PX_PER_TILE
	for o in others:
		var other := o as Vector2i
		if absi(other.x - cell.x) <= tiles and absi(other.y - cell.y) <= tiles:
			return true
	return false


static func _screen_distance(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length() * SCREEN_PX_PER_TILE


static func _walkable(grid: Array, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= grid[0].size() \
			or cell.y >= grid.size():
		return false
	return grid[cell.y][cell.x]
## Builds a dormant Mimic at a cell centre, parented by the caller.
##
## The player is left null on purpose: a mimic resolves it itself, and passing
## it here would hand every mimic a reference to a node the builder does not own.
static func make_mimic(cell_centre: Vector2, room_name: String,
		suffix: String) -> Node2D:
	var e: Node2D = ENEMY_SCENE.instantiate()
	e.set_script(MIMIC_SCRIPT)
	e.data = DB.MIMIC
# The audio map is keyed on the species, so a Mimic needs to say so.
	e.species = "mimic"
	e.position = cell_centre
	e.home_position = cell_centre
	e.name = "Mimic_%s_%s" % [room_name, suffix]
	# Default material, like a real chest: a CanvasItemMaterial would opt the
	# sprite out of the dungeon's PointLight2D lights and it would read as
	# unlit stone next to a glowing chest.
	var sprite := e.get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.material = null
	return e


## Builds one enemy at `cell_centre`, already anchored on its ground contact point.
static func make_enemy(key: String, cell_centre: Vector2, room_name: String,
		player: Node2D, is_boss := false) -> Node2D:
	var e: Node2D = ENEMY_SCENE.instantiate()
	e.set_script(ENEMY_SCRIPT)
	# BY_KEY is keyed by the lowercase species name ("rat"), while ROOM_MONSTER
	# uses the UPPER const name ("RAT"). Normalise here rather than making every
	# caller remember which is which.
	e.data = DB.BY_KEY[key.to_lower()]
# The audio map is keyed on the lowercase species name.
	e.species = key.to_lower()
	e.position = cell_centre
	e.home_position = cell_centre
	e.boss = is_boss
	e.player = player
	e.name = "Enemy_%s_%d_%d" % [room_name,
			int(cell_centre.x), int(cell_centre.y)]
	return e


## The Area2D that wakes a room.
##
## It covers the room's walkable interior, inset by the same INSET as the spawns,
## so walking into a doorway does not start the fight before the player is
## actually in the room. Once a room is woken it stays woken: the trigger does
## not toggle, the leash decides when an enemy gives up.
static func make_trigger(room: Rect2i, room_name: String) -> Area2D:
	var area := Area2D.new()
	area.name = "Trigger_%s" % room_name
	area.collision_layer = Layers.ENEMY_TRIGGER
	area.collision_mask = Layers.trigger_mask()
	var from := room.position + Vector2i.ONE * INSET
	var span := room.size - Vector2i.ONE * INSET * 2
	var shape := RectangleShape2D.new()
	shape.size = Vector2(span) * 16.0
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	cs.shape = shape
	area.add_child(cs)
	area.position = Vector2(from) * 16.0 + shape.size * 0.5
	area.set_script(preload("res://room_trigger.gd"))
	area.set("room_name", room_name)
	return area