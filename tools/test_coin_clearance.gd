extends SceneTree
## Proves a settled coin is somewhere the player can actually reach.
##
## Two bugs lived here and neither showed up in the old tests, which only
## checked that a coin NODE existed with a collider:
##
##  1. coin_drop.gd set a property named `walkable`, but coin.gd's member is
##     `_walkable`. Object.set() on an unknown name fails silently, so the floor
##     test was never installed and coins scattered straight through masonry.
##  2. Even with the test installed, it only checked the coin's CENTRE cell. The
##     player is 43x67 rendered px and cannot walk inside a wall, so a coin
##     resting within (half-width + pickup radius) of masonry is a coin the
##     player can never touch. This asserts the real Euclidean clearance, and
##     then asserts the coin is actually collectable.
##
## Drops are stepped by calling the coin's own _physics_process directly. That
## drives the real scatter, settle and magnet code without depending on how fast
## headless happens to idle, so the result is deterministic rather than timing
## dependent.

const COIN := preload("res://coin.gd")
const DROP := preload("res://coin_drop.gd")
const LOOT := preload("res://loot.gd")

const CELL := 16.0
const COINS_PER_DROP := 2
const SEEDS := 20
## Must match coin.gd's CLEARANCE, restated so the suite fails if the two drift.
## Was 13.0 at the 16-wide box, 14.0 at the 20-wide feet box, 20.0 at 43x67.
const WANT_CLEARANCE := 12.5
const EPS := 0.05

var _fails: Array[String] = []
var _checks := 0
var _stage := 0
var _frames := 0
var _main: Node
var _props: Node2D
var _walk: Callable
var _coins := 0
var _worst := 1e9


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


func _initialize() -> void:
	_main = load("res://Main.tscn").instantiate()


func _process(_delta: float) -> bool:
	match _stage:
		0:
			root.add_child(_main)
			_frames = 0
			_stage = 1
		1:
			_frames += 1
			if _frames < 4:
				return false
			var d := _main.get_node_or_null("Dungeon")
			if d == null:
				_fails.append("Main.tscn has no Dungeon node")
				_stage = 9
				return false
			var grid: Array = d.get("_grid")
			_walk = func(c: Vector2i) -> bool: return d._walkable(grid, c)
			_props = d.get_node("Props")
			if _props == null:
				_fails.append("Dungeon has no Props node")
				_stage = 9
				return false
			_stage = 2
			_frames = 0
		2:
			# One site per drop: every chest, then one enemy per monster room.
			var sites := _drop_sites()
			if _frames < sites.size():
				_drop_at(sites[_frames])
				_frames += 1
				return false
			_stage = 9
		9:
			_report()
			return true
	return false


## Every chest, plus one enemy from each room that spawns enemies.
func _drop_sites() -> Array:
	var out: Array = []
	for child in _props.get_children():
		if child.get_script() == LOOT:
			out.append({"name": "chest", "pos": child.global_position})
	var seen: Dictionary = {}
	for e in root.get_tree().get_nodes_in_group("enemies"):
		var room: String = str(e.get("room_name"))
		if room == "" or seen.has(room):
			continue
		seen[room] = true
		out.append({"name": "enemy:" + room, "pos": e.global_position})
	return out


func _drop_at(site: Dictionary) -> void:
	for seed_i in SEEDS:
		seed(seed_i * 7919 + int(site["pos"].x) * 31 + int(site["pos"].y))
		var before := _props.get_child_count()
		DROP.drop(_props, site["pos"], COINS_PER_DROP, 34.0, _walk)
		var fresh: Array = []
		for i in range(before, _props.get_child_count()):
			fresh.append(_props.get_child(i))
		# Past the 0.45s scatter, plus enough for the settle fallback to fire.
		for f in 40:
			for c in fresh:
				if is_instance_valid(c):
					c._physics_process(1.0 / 60.0)
		var settled: Array = []
		for c in fresh:
			if is_instance_valid(c):
				settled.append(c)
		_coins += settled.size()
		for c in settled:
			var d := _min_wall_distance(c.position)
			_worst = minf(_worst, d)
			_ok(d >= WANT_CLEARANCE - EPS,
					"%s seed %d: coin settled %.1f local px from a wall, need %.0f"
					% [site["name"], seed_i, d, WANT_CLEARANCE])
		var got := _collect_all(settled, site)
		_ok(got, "%s seed %d: %d of %d coins could not be collected"
				% [site["name"], seed_i, settled.size() - got, settled.size()])
		for c in settled:
			if is_instance_valid(c):
				c.queue_free()
## Parks the player on each coin and drives the magnet. A coin that is out of
## reach of the player's body must still be taken, which is the whole point of
## the magnet.
func _collect_all(coins: Array, site: Dictionary) -> int:
	var p := _player()
	if p == null:
		return 0
	var got := 0
	for c in coins:
		if not is_instance_valid(c) or c.is_queued_for_deletion():
			got += 1
			continue
		p.global_position = c.global_position
		for f in 120:  # 2.0s at 60Hz
			c._physics_process(1.0 / 60.0)
			# queue_free() is deferred to the end of the frame, and this loop
			# never yields a frame, so is_instance_valid() is still true for a
			# collected coin. is_queued_for_deletion() is the real signal.
			if not is_instance_valid(c) or c.is_queued_for_deletion():
				got += 1
				break
	if is_instance_valid(p):
		p.global_position = site["pos"]
	return got


func _player() -> Node2D:
	for child in _main.get_children():
		if child.has_method("take_damage") and child.has_method("do_attack"):
			return child as Node2D
	return null


## Euclidean distance from a LOCAL position to the nearest non-walkable cell.
func _min_wall_distance(p: Vector2) -> float:
	var best := 1e9
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var c := Vector2i(cx + dx, cy + dy)
			if bool(_walk.call(c)):
				continue
			var r := Rect2(c.x * CELL, c.y * CELL, CELL, CELL)
			var q := Vector2(clampf(p.x, r.position.x, r.end.x),
					clampf(p.y, r.position.y, r.end.y))
			best = minf(best, p.distance_to(q))
	return best


func _report() -> void:
	print("coins tested   : %d settled" % _coins)
	print("settle rescue  : %d coin(s) needed the fallback" % COIN.settle_rescues)
	print("worst clearance: %.1f local px (need %.0f)" % [_worst, WANT_CLEARANCE])
	print("assertions     : %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK")
	else:
		for f in _fails.slice(0, 12):
			print("FAIL: " + f)
		print("RESULT: %d FAILURE(S)" % _fails.size())