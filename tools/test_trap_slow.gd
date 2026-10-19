extends SceneTree
## Functional test for the spike-trap slow, run against the REAL Main.tscn.
##
## It does not simulate input: it moves the player onto each trap and steps the
## physics server, then checks the speed the player would actually move at. That
## catches the things a static layout check cannot - a trap that never fires, a
## slow that never lifts, and traps whose hitboxes silently overlap so the player
## is slowed by three traps at once without any way to tell.

const MAIN := "res://Main.tscn"
## Fail if the player drops below this fraction of base speed on one trap.
const MIN_SINGLE := 0.2
## Fail if one trap leaves the player slower than this fraction of base.
const MAX_SINGLE := 0.95
## Fail if the player ends a run still slowed after leaving every trap.
const RESTORED := 0.999
## Mirrors trap.gd's Phase enum: 0 = safe window, 1 = spikes out.
const PHASE_SAFE := 0
const PHASE_TRAVEL := 1

var _failures := 0

## Step the simulation until `predicate` is true or the budget runs out. The spike
## traps are on a timer now - they only bite while the spikes are out - so any
## check that expects a slow has to wait for the cycle rather than assume it is
## already in that phase.
func _await_until(predicate: Callable, budget := 400) -> bool:
	for _i in budget:
		await physics_frame
		if predicate.call():
			return true
	return false


## Stands the player on a trap and waits until that trap is actually applying its
## slow. Returns the speed ratio measured at that moment.
func _speed_while_active(player: Node, base: float, trap: Node) -> float:
	player.global_position = trap.global_position
	await physics_frame
	var t := trap
	var active := func() -> bool:
		var biting: bool = int(t.get("_phase")) == PHASE_TRAVEL
		return biting and not t.get_overlapping_bodies().is_empty()
	if not await _await_until(active):
		return -1.0
	await physics_frame
	return player.current_speed() / base


func _initialize() -> void:
	var game: Node = load(MAIN).instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame

	var player: Node = game.get_node("Player(CharacterBody2D)")
	var dungeon: Node = game.get_node("Dungeon")
	var traps := _collect_traps(dungeon)
	if traps.is_empty():
		_fail("no trap nodes were built")
		_finish()
		return

	var base: float = player.current_speed()
	print("base speed          : %.1f px/s" % base)
	print("traps built         : %d" % traps.size())

	# Every trap must actually slow the player, and only while they stand on it.
	for trap in traps:
		var cell := _cell_of(trap)
		var on_it := await _speed_while_active(player, base, trap)
		var hits := _traps_touching(traps, player)
		if on_it < 0.0:
			_fail("trap %s never became active" % cell)
		elif on_it > MAX_SINGLE:
			_fail("trap %s barely slowed the player (%.2fx)" % [cell, on_it])
		elif on_it < MIN_SINGLE:
			_fail("trap %s slowed the player far too much (%.2fx, %d traps overlap: %s)" % [
				cell, on_it, hits.size(), hits])
	print("checked %d traps individually" % traps.size())

	# Step well clear of every trap: the speed must come back exactly.
	player.global_position = Vector2(-4000, -4000)
	await physics_frame
	await physics_frame
	var restored: float = player.current_speed() / base
	if restored < RESTORED:
		_fail("speed did not return after leaving the traps (%.2fx)" % restored)
	else:
		print("restored after exit : %.2fx  OK" % restored)

	# Overlapping traps must NOT stack into a freeze. The player's collider is
	# wider than a tile, so a spike strip always overlaps several traps at once;
	# the strongest active slow has to win so the penalty stays bounded.
	var pair := _closest_traps(traps)
	if pair.size() == 2:
		var mid: Vector2 = (pair[0].global_position + pair[1].global_position) / 2.0
		player.global_position = mid
		await physics_frame
		var both := -1.0
		# Named local rather than an inline lambda: GDScript does not accept a
		# multi-line lambda as a call argument.
		var p0: Node = pair[0]
		var p1: Node = pair[1]
		var both_active := func() -> bool:
			var a: bool = int(p0.get("_phase")) == PHASE_TRAVEL
			var b: bool = int(p1.get("_phase")) == PHASE_TRAVEL
			return a and b
		if await _await_until(both_active):
			await physics_frame
			both = player.current_speed() / base
		var one: float = float(pair[0].get("slow_factor"))
		var hits := _traps_touching(traps, player)
		print("overlapping traps   : %.2fx while %d traps overlap (one is %.2fx)" % [
			both, hits.size(), one])
		if both < one - 0.001:
			_fail("overlapping traps stacked into %.2fx, worse than one trap (%.2fx)" % [
				both, one])
		elif both > one + 0.05:
			_fail("overlapping traps did not apply the slow (%.2fx vs %.2fx)" % [both, one])
	else:
		print("no overlapping pair found - skipping the overlap check")

	# And leaving the pair must still restore full speed.
	player.global_position = Vector2(-4000, -4000)
	await physics_frame
	await physics_frame
	var final: float = player.current_speed() / base
	if final < RESTORED:
		_fail("speed did not return after leaving a trap pair (%.2fx)" % final)

	# The cycle must repeat: every trap must go safe again after being active.
	var t0: Node = traps[0]
	var back_to_safe := func() -> bool:
		return int(t0.get("_phase")) == PHASE_SAFE
	var repeat_ok := await _await_until(back_to_safe)
	if repeat_ok:
		print("cycle repeats       : trap returned to its safe window  OK")
	else:
		_fail("trap never returned to the safe phase - the cycle does not repeat")

	_finish()

## Which traps currently report the player inside them. This is the ground truth
## the speed number is derived from, so a mismatch points straight at the cause.
func _traps_touching(traps: Array[Node2D], player: Node) -> Array:
	var out: Array = []
	for t in traps:
		if not t.get_overlapping_bodies().has(player):
			continue
		out.append(_cell_of(t))
	return out


## The builder names every trap "Trap_<x>_<y>", so the grid cell can be read back
## for the failure messages without the builder having to carry extra metadata.
func _cell_of(trap: Node) -> Vector2i:
	var parts := String(trap.name).split("_")
	if parts.size() < 3:
		return Vector2i.ZERO
	return Vector2i(int(parts[1]), int(parts[2]))


## Traps live in their own "Hazards" layer, flat on the floor so the player walks
## over them, rather than up in "Props" where they drew above the player.
func _collect_traps(dungeon: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var hazards: Node = dungeon.get_node_or_null("Hazards")
	if hazards == null:
		return out
	for child in hazards.get_children():
		if child.name.begins_with("Trap_"):
			out.append(child)
	return out

## The two traps closest together, used to prove overlapping slows stay bounded.
func _closest_traps(traps: Array[Node2D]) -> Array[Node2D]:
	var best: Array[Node2D] = []
	var best_dist := INF
	for i in traps.size():
		for j in range(i + 1, traps.size()):
			var d: float = traps[i].global_position.distance_to(traps[j].global_position)
			if d < best_dist:
				best_dist = d
				best = [traps[i], traps[j]]
	return best

func _fail(msg: String) -> void:
	_failures += 1
	print("FAIL: ", msg)

func _finish() -> void:
	if _failures == 0:
		print("\nRESULT: OK - traps slow the player and always let go")
		quit(0)
		return
	print("\nRESULT: %d FAILURE(S)" % _failures)
	quit(1)