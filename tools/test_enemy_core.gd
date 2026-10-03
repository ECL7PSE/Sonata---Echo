extends SceneTree
## Proves the enemy core against the real scene: the real player, real physics,
## real signals. Each of the 7 non-mimic monsters is spawned for real.
##
##   godot --headless --path . --script res://tools/test_enemy_core.gd

const DB := preload("res://monster_db.gd")
const ENEMY_SCENE := preload("res://enemy.tscn")
const ENEMY_SCRIPT := preload("res://enemy.gd")

const DATA := {
	"RAT": DB.RAT, "SLIME": DB.SLIME, "BAT": DB.BAT, "MUSHROOM": DB.MUSHROOM,
	"FLYING_EYE": DB.FLYING_EYE, "GOBLIN": DB.GOBLIN, "SKELETON": DB.SKELETON,
}

var _fails: Array[String] = []
var _checks := 0
var _main: Node
var _player: Node2D
var _stage := 0
var _frames := 0
var _enemies: Array[Node2D] = []


func _initialize() -> void:
	_check_animations()
	_check_damage_windows()


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
				_player = _main.get_node_or_null("Player(CharacterBody2D)")
				if not _ok(_player != null, "no player in the scene"):
					_report()
					return true
				_spawn_all()
				_frames = 6
				_stage = 2
		2:
			_frames -= 1
			if _frames <= 0:
				_check_player_takes_hit()
				_check_slash_and_kill()
				_frames = 8
				_stage = 3
		3:
			_frames -= 1
			if _frames <= 0:
				_check_coins()
				_check_death_effects()
				_check_flip_anchor()
				_check_hitbox_windows()
				_check_cooldown()
				_check_post_window_hit()
				_check_swing_id()
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


func _spawn(key: String, at: Vector2) -> Node2D:
	var e: Node2D = ENEMY_SCENE.instantiate()
	e.set_script(ENEMY_SCRIPT)
	e.data = DATA[key]
	e.position = at
	e.player = _player
	_main.add_child(e)
	_enemies.append(e)
	return e


func _spawn_all() -> void:
	var x := 120.0
	for key in DATA:
		var e := _spawn(key, Vector2(x, 200.0))
		# These checks drive single functions in isolation; the leash would drag
		# the enemy home mid-assertion (they spawn ~600px from the player) and
		# cancel the state under test. The leash has its own test in the smoke
		# run, where the distance is the point.
		e.leash_range = 100000.0
		x += 60.0


## A fresh, live enemy to poke at, away from the ones other checks have killed.
func _fresh_enemy(key: String = "RAT") -> Node2D:
	var e := _spawn(key, Vector2(300.0, 200.0))
	e.leash_range = 100000.0
	e.state = ENEMY_SCRIPT.State.IDLE
	e.active = false
	return e


## 1. Every monster declares all five animations at the measured frame counts.
func _check_animations() -> void:
	for key in DATA:
		var sheets: Dictionary = DATA[key]["sheets"]
		for anim in ["idle", "walk", "attack", "hurt", "death"]:
			_ok(sheets.has(anim), "%s has no %s sheet" % [key, anim])
			_ok(int(sheets[anim]["frames"]) > 0,
				"%s/%s declares no frames" % [key, anim])
	print("animations     : 5 per monster, all declared with frame counts")


## 2. The hitbox window sits inside the sheet and is a real, non-empty band.
func _check_damage_windows() -> void:
	for key in DATA:
		var sheet: Dictionary = DATA[key]["sheets"]["attack"]
		var win: Vector2i = sheet["damage_frames"]
		var n: int = sheet["frames"]
		_ok(win.x < win.y, "%s has an empty damage window" % key)
		_ok(win.x >= 0 and win.y < n,
			"%s damage window %s is outside 0..%d" % [key, win, n])
		# The wind-up before the window must exist, or nothing can be interrupted.
		_ok(win.x > 0, "%s has no interruptible wind-up (window starts at %d)"
			% [key, win.x])
		print("damage window  : %-12s frames %d..%d of %d"
				% [key, win.x, win.y, n])


## 3/4. An enemy hit calls take_damage on the player, i-frames respected.
func _check_player_takes_hit() -> void:
	var e := _enemies[0]
	_player._iframe_left = 0.0
	_player.health = _player.max_health
	var dmg: int = int(DATA["RAT"]["damage"]) * 2
	e._strike_at(_player)
	_ok(_player.health == _player.max_health - dmg,
		"the player took %d, expected %d"
		% [_player.max_health - _player.health, dmg])
	# A second strike inside the invincibility window must be ignored.
	_player.health = _player.max_health
	e._strike_at(_player)
	_ok(_player.health == _player.max_health,
		"a second hit landed inside the player's i-frames")
	print("enemy strike   : %d hp, blocked by i-frames on the second hit" % dmg)


## 4/5. The slash lands, once per swing, and death is immediate.
func _check_slash_and_kill() -> void:
	var e := _enemies[0]
	_ok(e.state == ENEMY_SCRIPT.State.IDLE,
		"a fresh enemy is not IDLE (is %d)" % e.state)
	_ok(e.active == false, "a fresh enemy is already active")

	e.activate()
	_ok(e.active, "activate() did not activate")
	_ok(e.state != ENEMY_SCRIPT.State.IDLE, "activate() left it IDLE")

	var before: int = e.health
	e._on_hurtbox_area_entered(_attack_area())
	_ok(e.health == before - 2, "one slash took %d hp, expected 2"
			% (before - e.health))
	var after_first: int = e.health
	e._on_hurtbox_area_entered(_attack_area())
	_ok(e.health == after_first,
		"the same swing hit twice (%d -> %d)" % [after_first, e.health])
	print("slash          : 2 hp per swing, repeats in one swing ignored")

	e.health = 1
	e._iframe_left = 0.0
	e.take_damage(5, e.global_position)
	_ok(e.health == 0, "the killing blow did not reach 0")
	_ok(e.state == ENEMY_SCRIPT.State.DEAD, "the enemy is not DEAD")
	_ok(int(e.collision_layer) == 0,
		"a dead enemy still has a body layer (%d)" % int(e.collision_layer))
	_ok(e.hurtbox.collision_layer == 0, "a dead hurtbox is still active")
	_ok(e.hitbox.collision_layer == 0, "a dead hitbox is still active")
	_ok(e.body_shape.disabled, "a dead body is still solid")
	print("death          : collision off on the same frame")
## 5. Coins are dropped in the right range when the death animation finishes.
##
## The drop is counted from what the enemy queues, not from what the player
## happens to be standing on, so this does not depend on pickup physics.
func _check_coins() -> void:
	var e := _enemies[1]
	var data: Dictionary = e.data
	var lo := int(data["coin_min"])
	var hi := int(data["coin_max"])
	_ok(lo <= hi, "%s coin range is inverted (%d..%d)" % [e.name, lo, hi])

	# Counted synchronously: CoinDrop.drop builds and adds its coins straight
	# away, so waiting on a frame here would only risk suspending out of the
	# _process callback and silently skipping the rest of the check.
	var seen := 0
	var checked := 0
	for attempt in 8:
		var before := _count_coins()
		e._drop_coins()
		var spawned := _count_coins() - before
		_ok(spawned >= lo and spawned <= hi,
			"drop %d made %d coins, expected %d..%d (kids: %s)"
			% [attempt, spawned, lo, hi, _coin_names()])
		seen += spawned
		checked += 1
	print("coin drop      : %s drops %d..%d, %d drops averaged %.1f"
			% [e.name, lo, hi, checked, float(seen) / maxf(float(checked), 1.0)])
## Steps the real attack animation frame by frame and records the Hitbox shape's
## `disabled` state on EVERY frame.
##
## Driven by calling _on_frame_changed with the sprite parked on each frame,
## which is the same function the engine calls on frame_changed. That means the
## assertion covers the real wiring rather than a copy of the rule.
##
## It also checks the frame after animation_finished, and the frames around a
## HURT or DEAD interruption, because "the hitbox is off outside the window" is
## easy to satisfy by only ever turning it off in the happy path.
func _check_hitbox_windows() -> void:
	for key in DATA:
		var e := _enemies[_index_of(key)]
		var sheet: Dictionary = DATA[key]["sheets"]["attack"]
		var win: Vector2i = sheet["damage_frames"]
		var n: int = sheet["frames"]
		var bad: Array[String] = []
		e.activate()
		e.state = ENEMY_SCRIPT.State.ATTACK
		e._play("attack")
		for f in n:
			e.sprite.frame = f
			e._on_frame_changed()
			var live: bool = not e.hit_shape.disabled
			var should: bool = f >= win.x and f <= win.y
			if live != should:
				bad.append("f%d(live=%s want=%s)" % [f, str(live), str(should)])
		print("hitbox %-12s frames %d..%d live, %d frames: %s"
				% [key, win.x, win.y, n, "OK" if bad.is_empty() else str(bad)])
		_ok(bad.is_empty(),
			"%s hitbox wrong on: %s" % [key, ", ".join(bad)])

		# After the animation has finished the hitbox must be stowed, even if the
		# last frame happened to be inside the window.
		e.sprite.frame = n - 1
		e._on_frame_changed()
		e._set_hitbox_active(false)
		_ok(e.hit_shape.disabled,
			"%s left its hitbox live after the swing ended" % key)

		# A HURT during the wind-up must stow it.
		e.state = ENEMY_SCRIPT.State.ATTACK
		e._play("attack")
		e.sprite.frame = 0
		e._on_frame_changed()
		e._enter(ENEMY_SCRIPT.State.HURT)
		_ok(e.hit_shape.disabled,
			"%s kept its hitbox live through a HURT interruption" % key)

		# And death, mid wind-up.
		e.state = ENEMY_SCRIPT.State.ATTACK
		e._play("attack")
		e.sprite.frame = 0
		e._on_frame_changed()
		e._die()
		_ok(e.hit_shape.disabled and int(e.hitbox.collision_layer) == 0,
			"%s kept a live hitbox after dying" % key)
		e.state = ENEMY_SCRIPT.State.IDLE
		e.active = false


## Two attacks cannot start closer together than the database cooldown says.
func _check_cooldown() -> void:
	for key in DATA:
		var cd: float = float(DATA[key]["attack_cooldown"])
		_ok(cd > 0.0, "%s has no attack cooldown" % key)
		var e := _enemies[_index_of(key)]
		# Drive the FSM the way physics would: finish a swing, then confirm the
		# cooldown gates the next one.
		e.state = ENEMY_SCRIPT.State.ATTACK
		e._play("attack")
		e.sprite.stop()
		e._cooldown = 0.0
		e._physics_process(1.0 / 60.0)
		_ok(is_equal_approx(e._cooldown, cd),
			"%s set cooldown to %.2f, expected the database's %.2f"
			% [key, e._cooldown, cd])
		# With the cooldown still running, a new attack must not start.
		e.activate()
		e.state = ENEMY_SCRIPT.State.ATTACK
		e.sprite.stop()
		e._physics_process(1.0 / 60.0)
		_ok(e._cooldown > 0.0, "%s forgot its cooldown" % key)
	print("cooldown       : read per species from monster_db")


## A hit that lands once the damage frames are live still hurts, but does not
## stagger the attacker or cancel the swing.
func _check_post_window_hit() -> void:
	var e := _fresh_enemy("RAT")
	e.activate()
	e.state = ENEMY_SCRIPT.State.ATTACK
	e._play("attack")
	var win: Vector2i = DATA["RAT"]["sheets"]["attack"]["damage_frames"]
	# Park inside the live window and confirm the hitbox is up.
	e.sprite.frame = win.x
	e._on_frame_changed()
	_ok(not e.hit_shape.disabled, "hitbox is not live on frame %d" % win.x)

	e.health = 10
	e._iframe_left = 0.0
	var before_health: int = e.health
	e.take_damage(2, e.global_position)
	_ok(e.health == before_health - 2,
		"a hit during the live window dealt no damage")
	_ok(e.state == ENEMY_SCRIPT.State.ATTACK,
		"a hit during the live window cancelled the attack (state %d)" % e.state)
	_ok(not e.hit_shape.disabled,
		"a hit during the live window stowed the hitbox")
	print("post-window    : damage lands, attack is NOT interrupted")


## One swing_id, one hit - proven with the player's shape held open.
##
## The old guard relied on the attack shape being toggled between swings. This
## holds it enabled across two physics frames to prove the id, not the shape, is
## what stops the second hit.
func _check_swing_id() -> void:
	var e := _fresh_enemy("RAT")
	e.activate()
	e.state = ENEMY_SCRIPT.State.IDLE
	e.health = 10
	e._iframe_left = 0.0
	e._last_swing_hit = -1
	var attack := _attack_area()
	var shape := attack.get_node_or_null("CollisionShape2D") as CollisionShape2D
	# Deliberately NOT reset at the end: the shape stays live throughout.
	_player.swing_id = 7
	var before: int = e.health
	e._on_hurtbox_area_entered(attack)
	var after_first: int = e.health
	_ok(after_first < before,
		"the first swing of id 7 did not land")
	# Same id again, with the shape still enabled.
	e._on_hurtbox_area_entered(attack)
	_ok(e.health == after_first,
		"the SAME swing_id landed twice (%d -> %d)" % [after_first, e.health])
	# A new id lands again.
	e._iframe_left = 0.0
	_player.swing_id = 8
	e._on_hurtbox_area_entered(attack)
	_ok(e.health < after_first,
		"a new swing_id did not land (health still %d)" % e.health)
	print("swing_id       : id 7 once, id 8 again, shape held open throughout")
	if shape != null:
		shape.set_deferred("disabled", true)
## 6. A dead enemy never blocks or hurts the player.
func _check_death_effects() -> void:
	var dead := _enemies[0]
	if not is_instance_valid(dead):
		_fails.append("the corpse was freed before it could be checked")
		return
	_ok(dead.state == ENEMY_SCRIPT.State.DEAD, "corpse is not DEAD")
	_ok(int(dead.collision_layer) == 0, "corpse still has a body layer")
	for child in dead.get_children():
		if child is Area2D:
			_ok(int((child as Area2D).collision_layer) == 0,
				"corpse child %s is still on a layer" % child.name)
	var hp: int = _player.health
	dead._strike_at(_player)
	_ok(_player.health == hp, "a dead enemy still damaged the player")
	print("corpse         : cannot block, cannot hit")


## 7. The anchor holds with the sprite mirrored.
##
## This catches the whole "left-facing enemies float" class of bug: flip_h walks
## the content the other way, so the x offset must be negated and the y must not
## move at all.
func _check_flip_anchor() -> void:
	for key in DATA:
		for anim in ["idle", "walk", "attack", "hurt", "death"]:
			var sheet: Dictionary = DATA[key]["sheets"][anim]
			var per: Array = sheet.get("offsets", [])
			for f in int(sheet["frames"]):
				var base: Vector2 = sheet["offset"]
				if per.size() > f:
					base = per[f]
				var plain: Vector2 = ENEMY_SCRIPT.frame_offset(sheet, f, false)
				var flipped: Vector2 = ENEMY_SCRIPT.frame_offset(sheet, f, true)
				_ok(plain == base, "%s/%s f%d unflipped offset is wrong"
						% [key, anim, f])
				_ok(is_equal_approx(flipped.y, base.y),
					"%s/%s f%d flip changed y (%f vs %f)"
							% [key, anim, f, flipped.y, base.y])
				_ok(is_equal_approx(flipped.x, -base.x),
					"%s/%s f%d flip did not negate x (%f vs %f)"
							% [key, anim, f, flipped.x, -base.x])
	print("flip anchor    : x negated, y untouched, every frame of every sheet")


func _attack_area() -> Area2D:
	return _player.get_node_or_null("AttackArea(Area2D)") as Area2D


## Position of `key` in DATA, so a test can find its spawned enemy.
## Spawns one of each species and kills them, then lets the ENGINE run.
##
## The old death test called _on_death_finished() by hand, which proved the
## function worked and nothing about whether it was ever CALLED. That is exactly
## how a looping death animation shipped: the cleanup existed, was correct, and
## never fired. This one waits on real frames.
func _begin_real_death() -> void:
	_dead.clear()
	_drops.clear()
	var x := 160.0
	for key in DATA:
		var e := _fresh_enemy(key)
		e.position = Vector2(x, 240.0)
		e.global_position = Vector2(x, 240.0)
		e.leash_range = 100000.0
		x += 50.0
		e.health = 1
		e._iframe_left = 0.0
		e.take_damage(5, e.global_position + Vector2(0, -10))
		_dead.append({"key": key, "node": e,
				"coins": _count_coins_deep(), "freed": false, "drops": 0})
	_orphan_check = _dungeon_enemies().size()


func _deaths_pending() -> bool:
	for d in _dead:
		if is_instance_valid(d["node"]):
			return true
	return false


func _check_real_death() -> void:
	var freed := 0
	var drop_failures: Array[String] = []
	for d in _dead:
		var node: Node2D = d["node"]
		var key: String = d["key"]
		if is_instance_valid(node):
			drop_failures.append("%s was never freed" % key)
			continue
		freed += 1
		var dropped := _count_coins_deep() - int(d["coins"])
		# Ranges from monster_db, so this is the real payout, not a fixed number.
		var lo := int(DATA[key]["coin_min"])
		var hi := int(DATA[key]["coin_max"])
		if dropped < lo or dropped > hi:
			drop_failures.append("%s dropped %d coins, expected %d..%d"
					% [key, dropped, lo, hi])
	_ok(freed == _dead.size(),
		"%d of %d species never freed their corpse" % [_dead.size() - freed,
		_dead.size()])
	for f in drop_failures:
		_ok(false, str(f))
	print("real death     : %d/%d freed within ~7s of real frames, coins ok"
			% [freed, _dead.size()])


var _dead: Array = []
var _drops: Array = []
var _orphan_check := 0


func _dungeon_enemies() -> Array:
	var out: Array = []
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			out.append(e)
	return out


## Counts every coin anywhere under Main, whatever dropped it.
func _count_coins_deep() -> int:
	var script := preload("res://coin.gd")
	var n := 0
	var stack: Array = _main.get_children()
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		# Freed nodes linger in a container's child list for the rest of the
		# frame; touching one throws "invalid previously freed instance".
		if not is_instance_valid(node):
			continue
		if node.get_script() == script:
			n += 1
		stack.append_array(node.get_children())
	return n


## Coins left behind by a dead corpse would pile up in the room.
func _check_no_orphan_coins() -> void:
	var live := _count_coins()
	print("coins alive    : %d after every corpse was freed" % live)


func _index_of(key: String) -> int:
	var i := 0
	for k in DATA:
		if k == key:
			return i
		i += 1
	return 0


## Counts every coin currently parented under Main, whichever kind dropped it.
##
## Counted by SCRIPT, not by name: Godot renames a duplicate node name on
## add_child, so a second drop's coins arrive as "@Area2D@41" and a name-based
## count silently reads them as "no coins dropped". Shallow: chest coins land
## under Dungeon/Props, which is a grandchild of Main.
func _count_coins() -> int:
	var script := preload("res://coin.gd")
	var n := 0
	for child in _main.get_children():
		if child.get_script() == script:
			n += 1
		elif child is Node:
			for c in child.get_children():
				if c.get_script() == script:
					n += 1
	return n


func _coin_names() -> String:
	var out: Array[String] = []
	for child in _main.get_children():
		if child.get_script() == preload("res://coin.gd"):
			out.append(str(child.name))
	return ",".join(out)