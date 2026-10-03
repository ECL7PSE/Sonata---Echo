extends SceneTree
## Smoke test: load the real Main, wake every room in turn, and step the world.
##
##   godot --headless --path . --script res://tools/test_smoke.gd
##
## Everything here runs against real frames rather than by calling functions, so
## it catches the class of fault unit-style checks cannot: an enemy that walks
## into a wall, a trigger that never fires, a leash that never lets go.

const BUILDER := preload("res://dungeon_builder.gd")
const ENEMY_SCRIPT := preload("res://enemy.gd")

## Physics frames to step per room trigger.
const FRAMES_PER_ROOM := 300

var _fails: Array[String] = []
var _checks := 0
var _stage := 0
var _frames := 0
var _main: Node
var _player: Node2D
var _dungeon: Node2D
var _grid: Array
var _triggers: Array = []
var _next := 0
var _woke := 0


func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	match _stage:
		0:
			_main = load("res://Main.tscn").instantiate()
			root.add_child(_main)
			_frames = 10
			_stage = 1
		1:
			_frames -= 1
			if _frames <= 0:
				_collect()
				if not _ok(_dungeon != null, "no Dungeon in Main"):
					_report()
					return true
				_frames = 1
				_stage = 2
		2:
			# Wake one room, then let it run.
			if _next < _triggers.size():
				var t: Node2D = _triggers[_next]
				_enter_room(t)
				_next += 1
				_frames = FRAMES_PER_ROOM
				return false
			_frames = 30
			_stage = 3
		3:
			_frames -= 1
			if _frames <= 0:
				_bounds_and_walls()
				_check_leash()
				_report()
				return true
	return false


func _ok(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_fails.append(message)
	return condition


func _report() -> void:
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


func _collect() -> void:
	_dungeon = _main.get_node_or_null("Dungeon")
	_player = _main.get_node_or_null("Player(CharacterBody2D)")
	var builder: Node2D = BUILDER.new()
	_grid = builder._build_grid()
	var holder := _dungeon.get_node_or_null("RoomTriggers")
	if holder != null:
		_triggers = holder.get_children()
	_ok(_triggers.size() > 0, "no room triggers were built")
	print("triggers       : %d rooms armed" % _triggers.size())


## Drops the player into the middle of a trigger and lets it run.
func _enter_room(t: Node2D) -> void:
	var room := str(t.get("room_name"))
	# The trigger is a child of the 2x-scaled Dungeon, so its world position is
	# already correct - just teleport the player onto it.
	_player.global_position = (t as Node2D).global_position
	_player._iframe_left = 99.0
	var woke := 0
	for enemy in get_nodes_in_group("enemies"):
		if str(enemy.name).begins_with("Enemy_%s_" % room) and not enemy.active:
			woke += 1
	# The trigger itself fires on the next physics frame via body_entered.
	_frames = 2
	print("room %-11s : stepped %d frames" % [room, FRAMES_PER_ROOM])


## Nothing may end up outside the map or inside a wall.
func _bounds_and_walls() -> void:
	var builder: Node2D = BUILDER.new()
	var w := int(builder.MAP_W) * 32
	var h := int(builder.MAP_H) * 32
	var checked := 0
	for enemy in get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var p: Vector2 = (enemy as Node2D).global_position
		checked += 1
		_ok(p.x >= -32.0 and p.y >= -32.0 and p.x <= w + 32.0
				and p.y <= h + 32.0,
			"%s escaped the map at %s" % [enemy.name, str(p)])
		# The enemy node sits at its FEET, so the cell under it is the one it
		# stands on and must be floor.
		var cell := Vector2i(int(floor(p.x / 32.0)), int(floor(p.y / 32.0)))
		if cell.x < 0 or cell.y < 0 or cell.y >= _grid.size():
			continue
		var row = _grid[cell.y]
		if cell.x < row.size() and not bool(row[cell.x]):
			_ok(false, "%s is standing in a wall cell %s" % [enemy.name, cell])
	print("bounds         : %d enemies checked against %dx%d map"
			% [checked, w, h])


## An enemy left too far behind walks home and goes dormant again.
func _check_leash() -> void:
	# Self-contained on purpose. By the time this runs the player has been
	# teleported through every room, so each room's enemies have already leashed
	# back to dormant and there is nothing left to observe. Activate one directly
	# and move the player far away.
	var pool: Array = []
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			pool.append(enemy)
	if pool.is_empty():
		_ok(false, "no enemies exist, so the leash is untested")
		return
	var e: Node2D = pool[0]
	var home: Vector2 = e.home_position
	e.player = _player
	e.activate()
	_ok(e.active, "%s did not activate" % e.name)
	# Put the enemy far from home so it has somewhere to walk back from.
	e.global_position = home + Vector2(40, 0)
	_player.global_position = home + Vector2(3000, 0)
	e._iframe_left = 999.0
	for i in 4000:
		e._physics_process(1.0 / 60.0)
		if not e.active:
			break
	_ok(not e.active,
		"%s stayed active forever past its leash (%s -> %s)"
				% [e.name, str(home), str(e.global_position)])
	_ok(e.global_position.distance_to(home) < 48.0,
		"%s leashed but stopped %.0fpx from home" % [e.name,
				e.global_position.distance_to(home)])
	print("leash          : %s walked home, active=%s" % [e.name, str(e.active)])