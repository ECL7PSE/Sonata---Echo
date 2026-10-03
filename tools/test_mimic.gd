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
			if b.z < 0:
				_ok(false, "mimic %s frame %d is blank" % [anim, f])
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
	var n := 0
	for child in _main.get_children():
		if child.get_script() == preload("res://coin.gd"):
			n += 1
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
