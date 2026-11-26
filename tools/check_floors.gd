extends SceneTree

## Enemy placement is independent of floor index and run seed.
##
## Each populated room must retain exactly one centre spawn on every floor.

const SPAWNER := preload("res://scripts/enemies/enemy_spawner.gd")
const BUILDER := preload("res://scripts/world/dungeon_builder.gd")

var _fails: Array[String] = []


func _initialize() -> void:
	var builder = BUILDER.new()
	var rooms: Dictionary = builder.ROOMS
	var names: Array = rooms.keys()

	var actual := _fingerprint(names, rooms)
	var expected: Array[String] = []
	for room_name in names:
		var room: Rect2i = rooms[room_name]
		if SPAWNER.is_enemy_room(room_name):
			expected.append("%s:1@%s"
					% [room_name, SPAWNER.room_center_cell(room)])
	print("enemy plan: ", actual)
	_check(actual == " ".join(expected),
			"populated rooms must each have one fixed centre spawn")

	for room_name in names:
		var room: Rect2i = rooms[room_name]
		if not SPAWNER.is_enemy_room(room_name):
			continue
		var n := SPAWNER.enemy_count(room, room_name)
		_check(n == SPAWNER.ENEMIES_PER_ROOM,
			"%s asked for %d entities" % [room_name, n])

	builder.free()

	if _fails.is_empty():
		print("RESULT: OK - one fixed centre spawn per populated room")
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL")
	quit()


## Counts and centre cells for every populated room.
func _fingerprint(names: Array, rooms: Dictionary) -> String:
	var parts: Array[String] = []
	for room_name in names:
		var room: Rect2i = rooms[room_name]
		if not SPAWNER.is_enemy_room(room_name):
			continue
		var cells := SPAWNER.plan(_all_walkable(room), room, room_name,
			[] as Array[Vector2i], Vector2i(-999, -999))
		var first := "-"
		if not cells.is_empty():
			first = str(cells[0])
		parts.append("%s:%d@%s" % [room_name, cells.size(), first])
	return " ".join(parts)


## A room rectangle is entirely floor for this purpose; the point is the scatter,
## not the walls.
func _all_walkable(room: Rect2i) -> Callable:
	return func(c: Vector2i) -> bool:
		return room.has_point(c)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)
