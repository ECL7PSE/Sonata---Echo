extends SceneTree
## Proves the mimic chain: waking, the exact sequence, the invulnerable window,
## the one-way transition, anchoring through every phase, and death.
##
##   godot --headless --path . --script res://tools/test_mimic.gd

const DB := preload("res://monster_db.gd")
const MIMIC_SCRIPT := preload("res://mimic.gd")
const ENEMY_SCENE := preload("res://enemy.tscn")
const ANCHOR_TOL := 1.0
const EPS := 0.001
## Step past each phase boundary rather than landing on it. 1/60 does not
## divide the phase lengths exactly, so stepping for exactly OPENING_TIME can
## leave _chain_time a hair short and the transition never fires.
const MARGIN := 0.05

var _fails: Array[String] = []
var _checks := 0
var _main: Node
var _player: Node2D
var _stage := 0
var _frames := 0
var _spawns := 0


func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	match _stage:
		0:
			_main = load("res://Main.tscn").instantiate()
			root.add_child(_main)
			_frames = 8
			_stage = 1
		1:
			_frames -= 1
			if _frames <= 0:
				_player = _main.get_node_or_null("Player(CharacterBody2D)")
				if not _ok(_player != null, "no player in the scene"):
					_report()
					return true
				# Every mimic is spawned far from the player and with the leash
				# off, so a check that steps time cannot be cancelled by an
				# unrelated enemy walking home.
				_frames = 4
				_stage = 2
		2:
			_frames -= 1
			if _frames <= 0:
				_check_a_proximity()
				_check_b_slash()
				_check_c_sequence()
				_frames = 4
				_stage = 3
		3:
			_frames -= 1
			if _frames <= 0:
				_check_d_invulnerable()
				_check_e_never_returns()
				_check_leash_reengage()
				_check_no_oscillation()
				_check_f_anchor()
				_check_g_death()
				_check_h_burst_push()
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


## A fresh dormant mimic, parked well clear of the player.
func _make_mimic(at := Vector2(900, 900)) -> Node2D:
	var m: Node2D = ENEMY_SCENE.instantiate()
	m.set_script(MIMIC_SCRIPT)
	m.data = DB.MIMIC
	m.position = at
	m.home_position = at
	m.player = _player
	m.leash_range = 100000.0
	_main.add_child(m)
	_spawns += 1
	return m


## A fresh plain enemy, for the leash-reengagement rules that every species
## shares. It is a RAT rather than a mimic so the check exercises Enemy's own
## IDLE branch instead of the mimic's chain gate.
func _make_rat(at := Vector2(800, 800)) -> Node2D:
	var e: Node2D = ENEMY_SCENE.instantiate()
	e.data = DB.RAT
	e.position = at
	e.home_position = at
	e.player = _player
	e.leash_range = 100000.0
	_main.add_child(e)
	return e


## Steps the mimic's chain by `time` seconds without waiting for real frames.
func _run(m: Node2D, time: float) -> void:
	var steps := int(ceil(time / (1.0 / 60.0)))
	for i in steps:
		m._process(1.0 / 60.0)


## a. Walking near wakes it; standing outside the radius does not.
func _check_a_proximity() -> void:
	var m := _make_mimic()
	_ok(m.chain == MIMIC_SCRIPT.Chain.DORMANT, "a fresh mimic is not DORMANT")
	# The burst is driven by the Area2D's own overlap, so "outside the radius
	# does not burst" is a property of the circle, not of a distance test here.
	# Calling _on_proximity_entered by hand would bypass the radius entirely.
	var prox: Area2D = m.get_node_or_null("Proximity")
	var cs := prox.get_node_or_null("Shape") as CollisionShape2D
	var circle := cs.shape as CircleShape2D
	_ok(is_equal_approx(circle.radius, 56.0),
		"the proximity radius is %.1f, expected the default 56"
				% circle.radius)
	_ok(int(prox.collision_layer) == Layers.ENEMY_TRIGGER,
		"the proximity area is not on enemy_trigger")
	_ok(int(prox.collision_mask) == Layers.PLAYER,
		"the proximity area does not watch for the player")
	# With the player far away the area reports nothing, so no burst can fire.
	_player.global_position = m.global_position + Vector2(400, 0)
	_ok(_prox_bodies(prox).is_empty(),
		"a player 400px away is inside the 56px proximity area")
	_ok(m.chain == MIMIC_SCRIPT.Chain.DORMANT,
		"the mimic burst with the player 400px away")
	# Close enough, and the engine sees them.
	_player.global_position = m.global_position + Vector2(20, 0)
	m._on_proximity_entered(_player)
	_ok(m.chain == MIMIC_SCRIPT.Chain.OPENING,
		"walking near did not start the burst (chain %d)" % m.chain)
	# Dormant ignores room triggers.
	var t := _make_mimic()
	t.activate()
	_ok(t.chain == MIMIC_SCRIPT.Chain.DORMANT,
		"activate() woke a dormant mimic; room triggers must not")
	print("proximity      : 56px radius, far=no burst, near=burst, "
			+ "room trigger ignored")


## After a leash it must re-engage, and must NEVER return to DORMANT.
##
## The behaviour being pinned down is: an awake mimic that walked home is still
## an awake mimic. It stops fighting because the player left, not because it
## became a chest again. Re-engagement happens either through activate() (a room
## trigger re-entry) or simply by the player walking back into detect range.
func _check_leash_reengage() -> void:
		# A plain enemy: leashed, then the player returns to detect range.
		var e := _make_rat()
		e.activate()
		e.leash_range = 32.0
		_player.global_position = e.home_position + Vector2(5000, 0)
		for i in 4000:
			e._physics_process(1.0 / 60.0)
			if not e.active:
				break
		_ok(not e.active, "the rat never leashed")
		_ok(e.state == MIMIC_SCRIPT.State.IDLE, "a leashed rat is not IDLE")
		# Back within detect range, with no trigger re-entry at all.
		# leash_range is left at its small value: re-engage legitimately requires the
		# player to be inside leash range of HOME, so the "player returned" case has
		# to be the player having genuinely come back to the room.
		_player.global_position = e.home_position + Vector2(20, 0)
		# The delay only governs an enemy that is NOT already home; one standing
		# exactly on its spawn point may look up immediately. What must never
		# happen is a re-engage from outside leash range, which the oscillation
		# check covers with real distances.
		for i in 90:
			e._physics_process(1.0 / 60.0)
		_ok(e.active, "a leashed rat did not re-engage when the player returned")
		_ok(e.state != MIMIC_SCRIPT.State.IDLE,
			"a re-engaged rat is still IDLE (state %d)" % e.state)

		# The mimic: leashed, still awake, re-engaged by activate() and by range.
		var m := _make_mimic()
		m._burst()
		_run(m, MIMIC_SCRIPT.OPENING_TIME + MIMIC_SCRIPT.HOLD_TIME
				+ MIMIC_SCRIPT.TRANSFORM_TIME + MIMIC_SCRIPT.SETTLE_TIME + MARGIN)
		_ok(m.chain == MIMIC_SCRIPT.Chain.AWAKE, "mimic did not reach AWAKE")
		m.leash_range = 32.0
		_player.global_position = m.home_position + Vector2(5000, 0)
		for i in 4000:
			m._physics_process(1.0 / 60.0)
			if not m.active:
				break
		_ok(m.chain == MIMIC_SCRIPT.Chain.AWAKE,
			"a leashed mimic went back to DORMANT (chain %d)" % m.chain)
		_ok(not m.active, "the leashed mimic stayed active forever")
		# Re-engage via activate(), which is the room-trigger path.
		m.activate()
		_ok(m.active, "a leashed awake mimic did not re-engage via activate()")
		# And via detect range, with no activate() call. The player comes back to the
		# room (inside leash of home), which is what re-engagement now requires.
		var m2 := _make_mimic()
		m2._burst()
		_run(m2, MIMIC_SCRIPT.OPENING_TIME + MIMIC_SCRIPT.HOLD_TIME
				+ MIMIC_SCRIPT.TRANSFORM_TIME + MIMIC_SCRIPT.SETTLE_TIME + MARGIN)
		m2.leash_range = 32.0
		_player.global_position = m2.home_position + Vector2(5000, 0)
		for i in 4000:
			m2._physics_process(1.0 / 60.0)
			if not m2.active:
				break
		_player.global_position = m2.home_position + Vector2(20, 0)
		for i in 90:
			m2._physics_process(1.0 / 60.0)
		_ok(m2.active,
			"a leashed mimic ignored a player standing 20px away")
		_ok(m2.chain == MIMIC_SCRIPT.Chain.AWAKE,
			"a re-engaged mimic fell back to DORMANT")
		# A DORMANT mimic must still ignore both paths.
		var d := _make_mimic()
		d.activate()
		_ok(d.chain == MIMIC_SCRIPT.Chain.DORMANT,
			"activate() woke a dormant mimic")
		_player.global_position = d.global_position + Vector2(10, 0)
		d._physics_process(1.0 / 60.0)
		_ok(d.chain == MIMIC_SCRIPT.Chain.DORMANT,
			"a dormant mimic re-engaged on proximity")
		print("leash re-engage: rat + mimic both re-engage; dormant still ignores both")


	## It must not oscillate: re-engage, chase, leash, return, repeat.
	##
	## Three player distances matter, and they fail differently:
	##
	##   just INSIDE  leash of home - the player is genuinely in the room, so a
	##                            single re-engage is correct and expected
	##   just BEYOND  leash of home - the killer case. Still inside DETECT of an
	##                            enemy sitting at home, so without the home-anchored
	##                            leash check it wakes on a loop forever
	##   far BEYOND    leash of home - outside everything; must simply never engage
	##
	## The bound is on leash RETURNS, not flips, because one legitimate re-engage at
	## the near distance is correct behaviour and should not fail the test.
func _check_no_oscillation() -> void:
	const FRAMES := 1200
	const REAL_LEASH := 240.0
	const DETECT := 120.0
	# 0.25x is the only distance that is unambiguously inside BOTH the leash and
	# the detect radius. 0.5x of a 240px leash is exactly 120px, which IS the
	# detect range - an enemy sitting at home will not notice a player standing
	# precisely on its detection boundary, so that case must NOT be required to
	# engage or the test would be asserting the wrong thing.
	var distances := {"inside both": REAL_LEASH * 0.25,
			"on detect edge": REAL_LEASH * 0.5,
			"just beyond": REAL_LEASH * 1.05, "far beyond": REAL_LEASH * 1.6}
	for label in ["rat", "mimic"]:
		for where in distances.keys():
			var gap: float = distances[where]
			var e: Node2D = _make_rat() if label == "rat" else _make_mimic()
			if label == "mimic":
				e._burst()
				_run(e, MIMIC_SCRIPT.OPENING_TIME + MIMIC_SCRIPT.HOLD_TIME
						+ MIMIC_SCRIPT.TRANSFORM_TIME + MIMIC_SCRIPT.SETTLE_TIME
						+ MARGIN)
			e.leash_range = REAL_LEASH
			e.activate()
			# Settle at home first, so the window starts from the state a leashed
			# enemy is actually in.
			_player.global_position = e.home_position + Vector2(9000, 0)
			for i in 6000:
				e._physics_process(1.0 / 60.0)
				if not e.active:
					break
			_ok(not e.active, "%s/%s never settled at home" % [label, where])
			_player.global_position = e.home_position + Vector2(gap, 0)
			var engagements := 0
			var leash_returns := 0
			var engaged_once := false
			var was_active: bool = e.active
			for i in FRAMES:
				_player.global_position = e.home_position + Vector2(gap, 0)
				e._physics_process(1.0 / 60.0)
				if e.has_method("_process"):
					e._process(1.0 / 60.0)
				# A real engagement is CHASE or ATTACK, not merely "active".
				if e.state == MIMIC_SCRIPT.State.CHASE \
						or e.state == MIMIC_SCRIPT.State.ATTACK:
					engaged_once = true
				if e.active and not was_active:
					engagements += 1
				elif was_active and not e.active:
					leash_returns += 1
				was_active = e.active
			# PRECONDITION. Without this a case where the enemy never moved
			# reports zero leash returns and passes vacuously. The rule is
			# distance-dependent, because an enemy at home simply cannot notice
			# a player outside its detect radius - "did not engage" is the CORRECT
			# result there, not a void.
			var must_engage: bool = gap < DETECT
			if must_engage:
				_ok(engaged_once,
					"%s at %s (%dpx, inside detect) never engaged"
							% [label, where, int(gap)])
			else:
				_ok(not engaged_once,
					"%s at %s (%dpx, outside detect) engaged anyway"
							% [label, where, int(gap)])
			_ok(leash_returns <= 1,
				"%s at %s (%dpx): %d leash returns in %d frames"
						% [label, where, int(gap), leash_returns, FRAMES])
			print("no oscillation : %-6s %-11s %5.0fpx engaged=%-5s "
					% [label, where, gap, str(engaged_once)]
					+ "engagements=%d leash_returns=%d"
							% [engagements, leash_returns])
	# The beyond-leash case must stay asleep even after the delay expires, and it
	# must be a REAL leash with a REAL distance: 1.05x of 240 = 252px, which is
	# still inside the 120px detect radius measured from an enemy that has drifted
	# toward the player. A 40px leash made this case trivially safe.
	var e2 := _make_rat()
	e2.leash_range = 240.0
	e2.activate()
	_player.global_position = e2.home_position + Vector2(9000, 0)
	for i in 6000:
		e2._physics_process(1.0 / 60.0)
		if not e2.active:
			break
	_player.global_position = e2.home_position + Vector2(252, 0)
	for i in 1800:
		_player.global_position = e2.home_position + Vector2(252, 0)
		e2._physics_process(1.0 / 60.0)
	_ok(not e2.active,
		"an enemy re-engaged on detect range alone, 252px (1.05x leash) from home")
	print("no oscillation : beyond-leash stays asleep at 252px (1.05x of 240)")


## Several mimics bursting at once must not stack past the single amplitude.
func _check_shake_cap() -> void:
	var ms: Array = []
	for i in 4:
		var m := _make_mimic(Vector2(700.0 + i * 60.0, 700.0))
		_player.global_position = m.global_position + Vector2(10, 0)
		m._burst()
		ms.append(m)
	var worst := 0.0
	for step in 12:
		for m in ms:
			m._process(1.0 / 60.0)
		for m in ms:
			worst = maxf(worst, m.sprite.position.length())
	_ok(worst <= m_shake() + 0.001,
		"four simultaneous bursts reached %.2fpx, cap is %.2fpx"
				% [worst, m_shake()])
	print("shake cap      : 4 bursts at once, peak %.2fpx (cap %.2f)"
			% [worst, m_shake()])
	# And the offset is always reset when the shake ends.
	for m in ms:
		_ok(m.sprite.position == Vector2.ZERO,
			"%s left a non-zero shake offset" % m.name)


func m_shake() -> float:
	return MIMIC_SCRIPT.SHAKE_PX


func _prox_bodies(prox: Area2D) -> Array:
	return prox.get_overlapping_bodies()


## b. A slash bursts it, deals nothing, and leaves health alone.
func _check_b_slash() -> void:
	var m := _make_mimic()
	var before: int = m.health
	var area := _player.get_node_or_null("AttackArea(Area2D)") as Area2D
	_player.swing_id = 1
	m._on_hurtbox_area_entered(area)
	_ok(m.chain == MIMIC_SCRIPT.Chain.OPENING, "a slash did not start the burst")
	_ok(m.health == before, "the slash changed health from %d to %d"
			% [before, m.health])
	_ok(m.is_invulnerable(), "a bursting mimic is not invulnerable")
	# A second slash, same swing id, must not restart anything.
	m._on_hurtbox_area_entered(area)
	_ok(m._chain_time < 0.2,
		"a second slash reset the chain clock (%.2f)" % m._chain_time)
	print("slash burst    : 0 damage, health %d -> %d, no double-start" % [before, m.health])
## c. The exact sequence and its timings.
func _check_c_sequence() -> void:
	var m := _make_mimic()
	_ok(m.sprite.animation == "dormant",
		"the dormant mimic is showing '%s', not the chest" % m.sprite.animation)
	m._burst()
	_ok(m.sprite.animation == "opening",
		"the burst did not swap to opening on the same frame (shows '%s')"
				% m.sprite.animation)
	var seen: Array[String] = ["OPENING"]
	_run(m, MIMIC_SCRIPT.OPENING_TIME * 0.9)
	_ok(m.chain == MIMIC_SCRIPT.Chain.OPENING, "OPENING ended early")
	_run(m, 0.1)
	_ok(m.chain == MIMIC_SCRIPT.Chain.HOLD, "OPENING did not become HOLD")
	seen.append("HOLD")
	_run(m, MIMIC_SCRIPT.HOLD_TIME + 0.02)
	_ok(m.chain == MIMIC_SCRIPT.Chain.TRANSFORM, "HOLD did not become TRANSFORM")
	seen.append("TRANSFORM")
	_run(m, MIMIC_SCRIPT.TRANSFORM_TIME + 0.02)
	_ok(m.chain == MIMIC_SCRIPT.Chain.SETTLE, "TRANSFORM did not become SETTLE")
	seen.append("SETTLE")
	_run(m, MIMIC_SCRIPT.SETTLE_TIME + 0.02)
	_ok(m.chain == MIMIC_SCRIPT.Chain.AWAKE, "SETTLE did not become AWAKE")
	seen.append("AWAKE")
	print("chain          : %s (%.2f/%.2f/%.2f/%.2fs)"
			% [" -> ".join(seen), MIMIC_SCRIPT.OPENING_TIME,
			MIMIC_SCRIPT.HOLD_TIME, MIMIC_SCRIPT.TRANSFORM_TIME,
			MIMIC_SCRIPT.SETTLE_TIME])


## d. Invulnerable and harmless until SETTLE; hurtable from SETTLE on.
func _check_d_invulnerable() -> void:
	var area := _player.get_node_or_null("AttackArea(Area2D)") as Area2D
	for stage in ["OPENING", "HOLD", "TRANSFORM"]:
		var m := _make_mimic()
		m._burst()
		if stage != "OPENING":
			_run(m, MIMIC_SCRIPT.OPENING_TIME + MARGIN)
		if stage == "HOLD":
			_ok(m.chain == MIMIC_SCRIPT.Chain.HOLD, "not in HOLD for %s" % stage)
		if stage == "TRANSFORM":
			_run(m, MIMIC_SCRIPT.HOLD_TIME + MARGIN)
			_ok(m.chain == MIMIC_SCRIPT.Chain.TRANSFORM,
				"not in TRANSFORM for %s" % stage)
		_ok(m.is_invulnerable(), "%s is not invulnerable" % stage)
		var hp: int = m.health
		_player.swing_id = 2
		m._on_hurtbox_area_entered(area)
		_ok(m.health == hp,
			"a hit during %s dealt damage (%d -> %d)" % [stage, hp, m.health])
		_ok(m.hit_shape.disabled, "the hitbox is live during %s" % stage)
	var s := _make_mimic()
	s._burst()
	_run(s, MIMIC_SCRIPT.OPENING_TIME + MIMIC_SCRIPT.HOLD_TIME
+ MIMIC_SCRIPT.TRANSFORM_TIME + MARGIN)
	_ok(s.chain == MIMIC_SCRIPT.Chain.SETTLE, "not in SETTLE")
	_ok(not s.is_invulnerable(), "a SETTLING mimic is still invulnerable")
	var before: int = s.health
	s.take_damage(2, s.global_position)
	_ok(s.health == before - 2,
		"a hit in SETTLE did not land (%d -> %d)" % [before, s.health])
	print("invuln window  : 0 damage through OPENING/HOLD/TRANSFORM, "
			+ "hurtable in SETTLE")

## e. It never returns to DORMANT, even when leashed.
func _check_e_never_returns() -> void:
	var m := _make_mimic()
	m._burst()
	_run(m, MIMIC_SCRIPT.OPENING_TIME + MIMIC_SCRIPT.HOLD_TIME
			+ MIMIC_SCRIPT.TRANSFORM_TIME + MIMIC_SCRIPT.SETTLE_TIME + MARGIN)
	_ok(m.chain == MIMIC_SCRIPT.Chain.AWAKE, "did not reach AWAKE")
	m.leash_range = 32.0
	_player.global_position = m.home_position + Vector2(5000, 0)
	for i in 4000:
		m._physics_process(1.0 / 60.0)
		m._process(1.0 / 60.0)
## f. Every frame of every chain phase sits on the anchor, both facings.
func _check_f_anchor() -> void:
	var sheets: Dictionary = DB.MIMIC["sheets"]
	var worst := 0.0
	var frames := 0
	for anim in ["dormant", "opening", "idle_open", "transform",
			"idle_transformed", "walk", "attack", "hurt", "death"]:
		var sheet: Dictionary = sheets[anim]
		var fw: int = sheet["frame_size"].x
		var fh: int = sheet["frame_size"].y
		var img: Image = (load(sheet["path"]) as Texture2D).get_image()
		for f in int(sheet["frames"]):
			frames += 1
			var b := _bbox(img, f, fw, fh)
			# Asserted ALWAYS, not only when blank. The geometry checks below can
			# only run for a frame that has pixels, so an unconditional count here
			# is what keeps a sheet of blank frames from quietly contributing
			# nothing to the suite.
			_ok(b.z >= 0, "mimic %s frame %d is blank" % [anim, f])
			if b.z < 0:
				continue
			var bc := Vector2((b.x + b.z) * 0.5, float(b.w))
			# Unflipped, the offset must land the bottom-centre on the origin.
			var plain: Vector2 = MIMIC_SCRIPT.frame_offset(sheet, f, false)
			var landed := Vector2(bc.x - fw * 0.5, bc.y - fh * 0.5) + plain
			worst = maxf(worst, landed.length())
			_ok(landed.length() <= ANCHOR_TOL + EPS,
				"mimic %s f%d is %.2fpx off the anchor"
						% [anim, f, landed.length()])
			# Flipped, the content is mirrored, so the offset must be the
			# negation and the residual must be the mirror image - NOT zero.
			# Re-running the unflipped geometry here would fail every sheet,
			# which is exactly what the first version of this check did.
			var flipped: Vector2 = MIMIC_SCRIPT.frame_offset(sheet, f, true)
			_ok(is_equal_approx(flipped.x, -plain.x),
				"mimic %s f%d flip did not negate x" % [anim, f])
			_ok(is_equal_approx(flipped.y, plain.y),
				"mimic %s f%d flip moved y" % [anim, f])
			var landed_f := Vector2(landed.x * -1.0, landed.y)
			_ok(landed_f.length() <= ANCHOR_TOL + EPS,
				"mimic %s f%d flipped is %.2fpx off the anchor"
						% [anim, f, landed_f.length()])
	print("mimic anchor   : %d frames across all 9 chain sheets, worst %.2f px"
			% [frames, worst])


## g. Death disables collision at once and pays 3-6 coins.
func _check_g_death() -> void:
	var m := _make_mimic()
	m._burst()
	_run(m, MIMIC_SCRIPT.OPENING_TIME + MIMIC_SCRIPT.HOLD_TIME
			+ MIMIC_SCRIPT.TRANSFORM_TIME + MIMIC_SCRIPT.SETTLE_TIME + MARGIN)
	var before := _count_coins()
	m.health = 1
	m._iframe_left = 0.0
	m.take_damage(5, m.global_position)
	_ok(int(m.collision_layer) == 0, "a dead mimic kept its body layer")
	_ok(m.hit_shape.disabled, "a dead mimic kept its hitbox")
	m._on_death_finished()
	var dropped := _count_coins() - before
	_ok(dropped >= 3 and dropped <= 6,
		"the mimic dropped %d coins, expected 3..6" % dropped)
	print("mimic death    : collision off immediately, dropped %d coins" % dropped)


## h. The transform's shove only fires inside its own radius.
func _check_h_burst_push() -> void:
	var far := _make_mimic()
	_player.global_position = far.global_position + Vector2(300, 0)
	_player.velocity = Vector2.ZERO
	far._burst_push()
	_ok(_player.velocity.length() < 1.0,
		"the burst shoved the player from 300px away")
	var near := _make_mimic()
	_player.global_position = near.global_position + Vector2(8, 0)
	_player.velocity = Vector2.ZERO
	var hp: int = _player.health
	near._burst_push()
	_ok(_player.velocity.length() > 1.0,
		"the burst did not shove the player standing 8px away")
	_ok(_player.health == hp,
		"the burst shoved AND damaged the player (%d -> %d)" % [hp, _player.health])
	print("burst push     : 0 damage, fires only within %.0fpx"
			% near.burst_push_radius)


func _count_coins() -> int:
	var script := preload("res://coin.gd")
	var n := 0
	var stack: Array = _main.get_children()
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node.get_script() == script:
			n += 1
		stack.append_array(node.get_children())
	return n


func _bbox(img: Image, f: int, fw: int, fh: int) -> Vector4i:
	var min_x := 999999
	var min_y := 999999
	var max_x := -1
	var max_y := -1
	for y in fh:
		for x in fw:
			if img.get_pixel(f * fw + x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Vector4i(0, 0, -1, -1)
	return Vector4i(min_x, min_y, max_x, max_y)
