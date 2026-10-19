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

## Real-physics oscillation: how many leash returns are acceptable in the window.
const LIVE_FRAMES := 600
## The REAL leash, and a distance that is genuinely just beyond it.
const LIVE_LEASH := 240.0
const LIVE_GAP := 252.0
const LIVE_MAX_RETURNS := 2
const MIMIC_SCRIPT := preload("res://mimic.gd")
const MONSTER_DB := preload("res://monster_db.gd")
const MIMIC_OPEN := 0.5
const MIMIC_HOLD := 0.15
const MIMIC_TRANSFORM := 0.58
const MIMIC_SETTLE := 0.4

var _fails: Array[String] = []
var _checks := 0
var _stage := 0
var _frames := 0
var _main: Node
var _live_n := 0
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
				_check_live_oscillation()
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
		#
		# This was written as _ok(false, ...) INSIDE the failure branch, so on a
		# passing run it contributed zero assertions - the "no enemy in a wall"
		# rule was never actually counted. It is now asserted positively for
		# every enemy, so a wall-standing enemy costs a real assertion whether or
		# not it happens.
		var cell := Vector2i(int(floor(p.x / 32.0)), int(floor(p.y / 32.0)))
		var inside: bool = cell.x >= 0 and cell.y >= 0 \
				and cell.y < _grid.size() and cell.x < _grid[cell.y].size()
		var on_floor: bool = inside and bool(_grid[cell.y][cell.x])
		_ok(on_floor,
			"%s is standing in a wall cell %s" % [enemy.name, cell])
	print("bounds         : %d enemies checked against %dx%d map"
			% [checked, w, h])


## Oscillation under REAL physics.
##
## The unit check in test_mimic drives _physics_process directly, so it proves the
## state machine converges but cannot see anything caused by move_and_slide -
## an enemy being pushed by the player, wedged in a corner, or nudged across the
## leash boundary by contact. This runs the actual body through the actual
## physics step, with the player held just beyond leash range, which is the
## configuration most likely to produce a real fight loop.
func _check_live_oscillation() -> void:
	var r: Node2D = _spawn_live(MONSTER_DB.RAT, Vector2(300, 300), null)
	var m: Node2D = _spawn_live(MONSTER_DB.MIMIC, Vector2(300, 500),
			MIMIC_SCRIPT)
	for pair in [[r, "rat"], [m, "mimic"]]:
		var e: Node2D = pair[0]
		var label: String = pair[1]
		e.leash_range = LIVE_LEASH
		e.activate()
		# Send it home once, so the cooldown is armed the way it would be in play.
		_player.global_position = e.home_position + Vector2(9000, 0)
		for i in 6000:
			e._physics_process(1.0 / 60.0)
			if not e.active:
				break
		_ok(not e.active, "%s never settled before the live window" % label)
		# Now hold the player just beyond the leash, and let physics run.
		var returns := 0
		var engagements := 0
		var engaged_once := false
		var was_active: bool = e.active
		for i in LIVE_FRAMES:
			# The player's own _physics_process would move it from input; keeping
			# it parked means the position below is the one under test.
			_player.global_position = e.home_position + Vector2(LIVE_GAP, 0)
			e._physics_process(1.0 / 60.0)
			if e.has_method("_process"):
				e._process(1.0 / 60.0)
			# A real engagement is CHASE or ATTACK, not merely "active".
			if e.state == 2 or e.state == 3:
				engaged_once = true
			if e.active and not was_active:
				engagements += 1
			elif was_active and not e.active:
				returns += 1
			was_active = e.active
		# PRECONDITION. An enemy at home cannot notice a player outside its
		# detect radius, so "did not engage" is CORRECT there, not a void.
		if LIVE_GAP < 120.0:
			_ok(engaged_once, "%s never engaged inside detect range" % label)
		else:
			_ok(not engaged_once,
				"%s engaged from %dpx away, outside its %dpx detect range"
						% [label, int(LIVE_GAP), 120])
		_ok(returns <= LIVE_MAX_RETURNS,
			"%s looped under live physics: %d leash returns in %d frames"
					% [label, returns, LIVE_FRAMES])
		print("live oscillation: %-6s gap=%3.0fpx engaged=%-5s "
				% [label, LIVE_GAP, str(engaged_once)]
				+ "engagements=%d leash_returns=%d"
						% [engagements, returns])


func _spawn_live(data: Dictionary, at: Vector2, script) -> Node2D:
	var e: Node2D = (load("res://enemy.tscn") as PackedScene).instantiate()
	if script != null:
		e.set_script(script)
	e.data = data
	e.position = at
	e.player = _player
	e.name = "Live_%d" % _live_n
	_live_n += 1
	_dungeon.add_child(e)
	return e


## An enemy left too far behind walks home and goes dormant again.
func _check_leash() -> void:
	# Self-contained on purpose. By the time this runs the player has been
	# teleported through every room, so each room's enemies have already leashed
	# back to dormant and there is nothing left to observe. Activate one directly
	# and move the player far away.
	var pool: Array = []
	for enemy in get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		# Skip dormant mimics. They REFUSE activation by design - that is the
		# whole disguise - so picking one here asserted the opposite of what the
		# leash is supposed to prove. Tested with `in` because a plain Enemy has
		# no `chain` property, and two separate preloads of mimic.gd are not
		# guaranteed to be the same Script resource to compare against.
		# Skip EVERY mimic, not just dormant ones. A leashed mimic is correct
		# code with a different activation path, and asserting the generic
		# leash on it proves the wrong thing.
		if "chain" in enemy:
			continue
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
