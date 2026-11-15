extends RefCounted
class_name RunReset
## Sends the player back to the start and puts the dungeon back to sleep.
##
## Triggered by the LAST chest, so the run loops rather than ends: you open the
## chest at the end of the map, wake up in the start hall at full health, and
## every enemy - including every dormant mimic - is back where it began.
##
## Deferred by one frame from the caller, because it runs from inside an
## area_entered callback, which is a physics query flush.

static func reset(tree: SceneTree) -> void:
	if tree == null:
		return
	var player: Node2D = _find_player(tree)
	if player == null:
		return
	# Back to the marker and full health.
	if player.has_method("snap_to_player_start"):
		player.snap_to_player_start()
	if player.has_method("reset_health"):
		player.reset_health()
	if player.has_method("set_velocity"):
		player.set_velocity(Vector2.ZERO)
	else:
		player.set("velocity", Vector2.ZERO)
	_reset_enemies(tree)
	print("run reset      : back to PlayerStart, enemies respawned")


## Floor complete: drop one floor deeper.
##
## The next floor is rebuilt from GameState.run_seed + depth, so it is a new
## layout. The bench is the only thing that makes the depth stick - dying or
## quitting sends you back to the last rest, which is the checkpoint rule.
static func descend(tree: SceneTree) -> void:
	if tree == null:
		return
	# Looked up through the tree rather than by name: this script is a
	# class_name RefCounted, and autoload identifiers do not resolve at compile
	# time in that context (they do at runtime, via /root).
	var gs := tree.root.get_node_or_null("GameState")
	if gs == null:
		return
	gs.set("depth", int(gs.get("depth")) + 1)
	print("descent        : floor %d" % int(gs.get("depth")))
	tree.call_deferred("reload_current_scene")


## Every enemy goes home and dormant. A mimic that woke is put back to sleep,
## which is the only way its disguise can re-form.
static func _reset_enemies(tree: SceneTree) -> void:
	for enemy in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		enemy.global_position = enemy.home_position
		enemy.set("velocity", Vector2.ZERO)
		if enemy.has_method("activate"):
			enemy.deactivate()
		enemy.set("active", false)
		if enemy.has_method("_enter"):
			enemy._enter(0)   # State.IDLE
		if enemy.has_method("_enter_chain"):
			enemy.dormant_reset()


static func _find_player(tree: SceneTree) -> Node2D:
	var root := tree.current_scene
	if root == null:
		root = tree.root
	if root == null:
		return null
	for child in root.get_children():
		if child.has_method("snap_to_player_start"):
			return child as Node2D
	return null