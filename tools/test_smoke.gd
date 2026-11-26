extends SceneTree
## Smoke test: room triggers wake enemies, but all overworld enemies stay put.
##
##   godot --headless --path . --script res://tools/test_smoke.gd

const BUILDER := preload("res://scripts/world/dungeon_builder.gd")

var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	for _frame in 8:
		await process_frame

	var dungeon := main.get_node_or_null("Dungeon")
	var player := main.get_node_or_null("Player(CharacterBody2D)") as Node2D
	_ok(dungeon != null, "Main has no Dungeon")
	_ok(player != null, "Main has no player")
	if dungeon == null or player == null:
		_report()
		return

	var builder: Node2D = BUILDER.new()
	var grid: Array = builder._build_grid()
	var triggers := dungeon.get_node("RoomTriggers").get_children()
	_ok(not triggers.is_empty(), "no room triggers were built")
	print("triggers       : %d rooms armed" % triggers.size())

	var start_positions := {}
	var enemies: Array = get_nodes_in_group("enemies")
	for enemy in enemies:
		start_positions[enemy.get_instance_id()] = enemy.global_position

	for trigger in triggers:
		var room_name: String = trigger.room_name
		player.global_position = trigger.global_position
		await physics_frame
		await process_frame
		var room_enemies := 0
		for enemy in enemies:
			if str(enemy.name).begins_with("Enemy_%s_" % room_name):
				room_enemies += 1
				_ok(enemy.active, "%s trigger did not activate %s"
						% [room_name, enemy.name])
		_ok(room_enemies == 1, "%s has %d entities, expected exactly one"
				% [room_name, room_enemies])

	var map_width := int(builder.MAP_W) * 32
	var map_height := int(builder.MAP_H) * 32
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var position: Vector2 = enemy.global_position
		_ok(position.is_equal_approx(start_positions[enemy.get_instance_id()]),
				"%s moved after room activation" % enemy.name)
		_ok(position.x >= -32.0 and position.y >= -32.0
				and position.x <= map_width + 32.0
				and position.y <= map_height + 32.0,
				"%s escaped the map at %s" % [enemy.name, position])
		var cell := Vector2i(int(floor(position.x / 32.0)),
				int(floor(position.y / 32.0)))
		var inside: bool = cell.x >= 0 and cell.y >= 0 \
				and cell.y < grid.size() and cell.x < grid[cell.y].size()
		_ok(inside and bool(grid[cell.y][cell.x]),
				"%s is standing in a wall cell %s" % [enemy.name, cell])

	print("stationary     : %d enemies stayed at their spawn positions"
			% enemies.size())
	_report()


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_fails.append(message)


func _report() -> void:
	print("")
	print("assertions     : %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK")
		quit(0)
	else:
		for failure in _fails:
			print("FAIL: " + failure)
		print("RESULT: %d problem(s)" % _fails.size())
		quit(1)
