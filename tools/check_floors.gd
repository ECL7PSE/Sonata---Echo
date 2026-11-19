extends SceneTree

## Procedural floors: the same rooms must lay out differently on each descent.
##
## The dungeon seeds the spawner with (run seed, depth). This proves that two
## different floors give different head counts and different spawn scatter,
## while every count still sits inside the spawner's own limits.

const SPAWNER := preload("res://scripts/enemies/enemy_spawner.gd")
const BUILDER := preload("res://scripts/world/dungeon_builder.gd")

var _fails: Array[String] = []


func _initialize() -> void:
	var builder = BUILDER.new()
	var rooms: Dictionary = builder.ROOMS
	var names: Array = rooms.keys()

	var a := _fingerprint(names, rooms, 12345, 1)
	var b := _fingerprint(names, rooms, 12345, 2)
	var c := _fingerprint(names, rooms, 999, 1)
	print("floor 1 : ", a)
	print("floor 2 : ", b)
	print("other   : ", c)

	_check(a != b, "the same run must lay out floor 2 differently from floor 1")
	_check(a != c, "a different run must lay out floor 1 differently")

	for d in [1, 2, 3, 7]:
		SPAWNER.set_floor(4242, d)
		for room_name in names:
			var room: Rect2i = rooms[room_name]
			if not SPAWNER.is_enemy_room(room_name):
				continue
			var n := SPAWNER.enemy_count(room, room_name)
			_check(n >= SPAWNER.MIN_ENEMY and n <= SPAWNER.MAX_ENEMY,
				"%s on floor %d asked for %d heads" % [room_name, d, n])

	builder.free()
	SPAWNER.set_floor(1, 1)

	if _fails.is_empty():
		print("RESULT: OK - every floor reshuffles")
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL")
	quit()


## Counts plus the first spawn cell of every room, for one floor.
func _fingerprint(names: Array, rooms: Dictionary, run_seed: int, depth: int) -> String:
	SPAWNER.set_floor(run_seed, depth)
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
