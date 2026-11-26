extends RefCounted
class_name EnemySpawner
## Decides WHERE enemies stand, and builds the room trigger that wakes them.
##
## Every populated room gets one enemy at its centre.
##
## The rules, and why each exists:
##
##   on floor              an enemy in a wall is invisible but still solid
##   room centre           room size or floor index cannot scatter the spawn

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const ENEMY_SCRIPT := preload("res://scripts/enemies/enemy.gd")
const DB := preload("res://scripts/enemies/monster_db.gd")
const MIMIC_SCRIPT := preload("res://scripts/enemies/mimic.gd")

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

## Tiles kept between a room trigger and its doorways.
const INSET := 1
const ENEMIES_PER_ROOM := 1
## Screen-pixel spacing checked by the layout tests for nearby props.
const PROP_CLEARANCE_PX := 32.0
## Screen pixels of clear floor between a spawn and the nearest wall.
const WALL_CLEARANCE_PX := 24.0
## Screen pixels from the player's spawn.
const SPAWN_CLEARANCE_PX := 150.0
## Traps, chests and crates. Built once so the planner and check_layout read the
## same list.
static var PROPS: Array[Vector2i] = []
## The Dungeon node is scaled 2x, so one source tile is 32 screen pixels.
const SCREEN_PX_PER_TILE := 32.0


## Rooms that get one dormant Mimic instead of a regular room enemy.
const MIMIC_DENS: Dictionary = {
	"mimic_den": {"count": 1},
}


## The awake mimic's half-width in rendered pixels, including dungeon scaling.
static func awake_half_width() -> float:
	var body: Vector2i = DB.MIMIC.get("body", Vector2i(16, 15))
	return float(body.x) * float(DB.MIMIC["scale"]) \
			* float(ENEMY_SCRIPT.SCALE_BY_SPRITE_COUNT[1]) \
			* float(DB.DUNGEON_SCALE) * 0.5


## Wall clearance a mimic needs, computed from the scaled awake body.
## The awake art is about 78px wide, so it needs more than the 24px floor rule.
static func mimic_wall_clearance_px() -> float:
	return maxf(WALL_CLEARANCE_PX, awake_half_width() + 4.0)


## Places the one dormant Mimic at the room centre, like every other enemy.
static func plan_mimic(walkable: Callable, room: Rect2i,
		blocked: Array[Vector2i],
		player_start: Vector2i) -> Array[Vector2i]:
	var cell := room_center_cell(room)
	if cell == player_start or blocked.has(cell) or not _fits(walkable, cell, room):
		return []
	# The dormant body must have room to grow into its final centred size.
	var half_tiles := awake_half_width() / SCREEN_PX_PER_TILE
	var height_tiles := float(DB.MIMIC.get("body", Vector2i(16, 15)).y) \
			* float(DB.MIMIC["scale"]) \
			* float(ENEMY_SCRIPT.SCALE_BY_SPRITE_COUNT[1]) \
			* float(DB.DUNGEON_SCALE) / SCREEN_PX_PER_TILE
	if not _body_fits(walkable, cell, half_tiles, height_tiles):
		return []
	return [cell]


## True when the awake body rectangle standing on `cell` covers only floor.
##
## The node origin is the body's bottom-centre, so the rect runs from
## (centre - half, centre - height) to (centre + half, centre).
##
## The halves arrive in TILES, not pixels. The grid is indexed by cell, so
## converting the scaled pixel bounds here keeps the awake body inside the room.
static func _body_fits(walkable: Callable, cell: Vector2i, half: float,
		height: float) -> bool:
	var centre := Vector2(cell) + Vector2(0.5, 0.5)
	var left := centre.x - half
	var top := centre.y - height
	var right := centre.x + half
	var bottom := centre.y
	# Every cell the rectangle touches, including partial ones at the edges.
	var start_cell := Vector2i(floori(left), floori(top))
	var to := Vector2i(floori(right - 0.001), floori(bottom - 0.001))
	for y in range(start_cell.y, to.y + 1):
		for x in range(start_cell.x, to.x + 1):
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


static func enemy_count(_room: Rect2i, _room_name: String = "") -> int:
	return ENEMIES_PER_ROOM


static func room_center_cell(room: Rect2i) -> Vector2i:
	return room.position + Vector2i(int(room.size.x / 2.0),
			int(room.size.y / 2.0))


## One centre cell per populated room; `walkable` remains owned by the builder.
static func plan(walkable: Callable, room: Rect2i, _room_name: String,
		blocked: Array[Vector2i], _player_start: Vector2i) -> Array[Vector2i]:
	var center := room_center_cell(room)
	if not _fits(walkable, center, room) or blocked.has(center):
		return []
	return [center]


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
## so walking into a doorway does not wake enemies before the player is actually
## in the room. Activation never moves the stationary enemies.
static func make_trigger(room: Rect2i, room_name: String) -> Area2D:
	var area := Area2D.new()
	area.name = "Trigger_%s" % room_name
	area.collision_layer = Layers.ENEMY_TRIGGER
	area.collision_mask = Layers.trigger_mask()
	var origin := room.position + Vector2i.ONE * INSET
	var span := room.size - Vector2i.ONE * INSET * 2
	var shape := RectangleShape2D.new()
	shape.size = Vector2(span) * 16.0
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	cs.shape = shape
	area.add_child(cs)
	area.position = Vector2(origin) * 16.0 + shape.size * 0.5
	area.set_script(preload("res://scripts/world/room_trigger.gd"))
	area.set("room_name", room_name)
	return area