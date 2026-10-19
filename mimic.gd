extends "res://enemy.gd"
class_name Mimic
## The mimic: a chest that becomes a monster, and only ever does so once.
##
## The chain is deliberately NOT folded into Enemy's State enum. A mimic spends
## the first moments of its life in a phase that has no meaning for any other
## species, and putting DORMANT in the shared enum would give every enemy five
## states it can never be in. This file keeps its own chain and defers to the
## inherited FSM only once the burst is over.
##
##   DORMANT -> OPENING -> HOLD -> TRANSFORM -> SETTLE -> the normal FSM
##
## Once it leaves DORMANT it never returns. The leash still applies afterwards -
## an awake mimic that is outrun walks home and dozes - but "home" for an awake
## mimic is a dormant-looking chest it cannot turn back into, so it simply stops.
##
## Two things make the disguise work, and both are easy to break:
##
##   the dormant sprite is the REAL C001_01 chest art at 1:1, and
##   the dormant hitbox is chest-sized, not creature-sized.
##
## Sizing the dormant hitbox off the awake body would give a closed chest a
## creature-sized target and make the trap unreadable.

enum Chain { DORMANT, OPENING, HOLD, TRANSFORM, SETTLE, AWAKE }

## Pixels at which the player wakes a dormant mimic by walking near.
@export var wake_radius := 56.0
## Pixels at which the transform's first frame shoves the player away.
@export var burst_push_radius := 24.0
@export var burst_push := 220.0
## Shake on the frame the lid comes off.
const SHAKE_PX := 2.0
@export var shake_time := 0.15

## Phase lengths. Each is the sheet's own length at the fps set in _ready, so the
## timings and the art cannot disagree.
const OPENING_TIME := 0.50      # opening.png, 6 frames @ 12fps
const HOLD_TIME := 0.15         # idle_open, held
const TRANSFORM_TIME := 0.58    # transform.png, 7 frames @ 12fps
const SETTLE_TIME := 0.40       # idle_transformed, held
const OPENING_FPS := 12.0
const TRANSFORM_FPS := 12.0

var chain: int = Chain.DORMANT
var _chain_time := 0.0
var _prox: Area2D
var _shake_left := 0.0
var _scale_tween: Tween
## Set once the burst has begun, so nothing can start it a second time.
var _has_burst := false
## Puts an awake mimic back to being a chest.
##
## The run reset is the only way a mimic ever returns to DORMANT: once woken it
## stays a monster, which is what makes it a threat. The exception is a full run
## reset, where the whole dungeon is put back exactly as it was built.
func dormant_reset() -> void:
	chain = Chain.DORMANT
	_has_burst = false
	_dead_handled = false
	_coins_dropped = false
	_shake_left = 0.0
	_scale_tween = null
	sprite.modulate = Color(1, 1, 1, 1)
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2(data.get("dormant_scale", 1.0), data.get("dormant_scale", 1.0))
	_apply_dormant_profile()
	if player != null:
		var dist := player.global_position.distance_to(global_position)
		if dist <= wake_radius:
			_burst()


func _ready() -> void:
	super._ready()
	_build_proximity()
	_apply_dormant_profile()
	set_physics_process(true)


## The area that wakes this mimic when the player walks close.
##
## Built in code rather than in a second scene so the mimic shares enemy.tscn
## and there is exactly one enemy scene to keep correct.
func _build_proximity() -> void:
	_prox = Area2D.new()
	_prox.name = "Proximity"
	_prox.collision_layer = Layers.ENEMY_TRIGGER
	_prox.collision_mask = Layers.trigger_mask()
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var circle := CircleShape2D.new()
	circle.radius = wake_radius
	shape.shape = circle
	_prox.add_child(shape)
	add_child(_prox)
	_prox.body_entered.connect(_on_proximity_entered)


## Swaps in the chest art, at 1:1, with a chest-sized hurtbox.
func _apply_dormant_profile() -> void:
	var dscale := float(data.get("dormant_scale", 1.0))
	var dbody: Vector2i = data.get("dormant_body", Vector2i(16, 15))
	sprite.scale = Vector2(dscale, dscale)
	var dw := float(dbody.x) * dscale
	var dh := float(dbody.y) * dscale
	hurt_shape.shape = _rect(1.15 * dw, 1.15 * dh)
	hurt_shape.position = Vector2(0, -0.5 * dh)
	body_shape.shape = _rect(dw, dh)
	body_shape.position = Vector2(0, -0.5 * dh)
	_set_hitbox_active(false)
	_play("dormant")


## Phases during which the mimic cannot be hurt at all.
##
## SETTLE is deliberately NOT in this list. The brief is invulnerable from the
## trigger until TRANSFORM finishes, and damage accepted from SETTLE onward -
## so SETTLE is the first moment a player can actually land a hit on the thing
## they just woke up. Gating the whole chain off until AWAKE made the mimic
## briefly unkillable during a phase it is plainly visible and stationary.
const ARMED_CHAINS: Array[int] = [Chain.DORMANT, Chain.OPENING, Chain.HOLD,
		Chain.TRANSFORM]


## True whenever the mimic must ignore damage.
##
## Overriding the PREDICATE rather than setting a huge invincibility timer means
## "can this be hurt" is one honest question with one answer, and a damage number
## is never spent on a phase that cannot be interrupted.
func is_invulnerable() -> bool:
	if state == State.DEAD:
		return true
	if ARMED_CHAINS.has(chain):
		return true
	return super.is_invulnerable()


## No floating numbers while it is only a chest.
func _spawn_damage_number(_amount: int, _source: Vector2) -> void:
	if ARMED_CHAINS.has(chain):
		return
	super._spawn_damage_number(_amount, _source)


## Room triggers must NOT start a dormant mimic. Activating is how the rest of the
## game wakes an enemy, so this is the single gate a trigger cannot pass.
func activate() -> void:
	if chain != Chain.AWAKE:
		return
	super.activate()


## Wakes on proximity, but only if it has not woken already.
func _on_proximity_entered(body: Node2D) -> void:
	if body == null or not body.has_method("take_damage"):
		return
	_burst()


## A slash on a dormant mimic wakes it and does nothing else.
func _on_hurtbox_area_entered(area: Area2D) -> void:
	if chain == Chain.DORMANT:
		_burst()
		return
	super._on_hurtbox_area_entered(area)


## The lid comes off.
func _burst() -> void:
	if _has_burst or chain != Chain.DORMANT:
		return
	_has_burst = true
# The burst is the one-off with no matching "action" in the map: it is the
	# chest splitting open, not a hit. The guard above already makes it
	# once-only, so a re-burst cannot double up.
	_sfx_enemy("burst")
	_chain_time = 0.0
	chain = Chain.OPENING
	# The swap, the flash and the shake all happen on THIS frame. Deferring the
	# flash by one frame would leave a dead-looking chest flashing for a tick.
	_play("opening")
	sprite.modulate = Color(4, 4, 4, 1)
	var flash := create_tween()
	flash.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.18)
	_shake_left = shake_time
	_set_hitbox_active_deferred(false)
	_start_scale_tween()
	# NO extra frame_changed connection here: Enemy._ready already connects
	# _on_frame_changed, and connecting the same callable twice is an engine error
	# (and would double-apply the anchor on every frame of the burst).


## Grows the sprite from the chest profile to the awake one.
## _set_hitbox_active for use from inside an Area2D callback.
##
## A burst can be triggered by area_entered, which runs during a physics query
## flush; toggling a CollisionShape2D there makes the engine throw "Can't change
## this state while flushing queries". The same problem and the same reason
## loot.gd defers its coin spawns.
func _set_hitbox_active_deferred(on: bool) -> void:
	var reach := 0.0
	if on:
		reach = _facing_x() * 0.45 * _body_w
	hit_shape.set_deferred("disabled", not on)
	hit_shape.position = Vector2(reach, -0.35 * _body_h)


## Swaps the hitboxes over to the awake profile once the growth is done.
func _apply_awake_shapes() -> void:
	_size_shapes()


## The chain, ticked here so it can be stepped deterministically by a test.
##
## Deliberately does NOT call super: Enemy defines no _process, and invoking a
## virtual the parent does not implement is at best noise and at worst an error.
func _process(delta: float) -> void:
	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - delta, 0.0)
		# Decaying jitter. A constant offset would read as the sprite being
		# misplaced rather than the chest juddering.
		#
		# Clamped to a hard RADIUS, not a per-axis box: randf_range on both axes
		# can land at +/-2 on each, a 2.83px diagonal, which breaks the "2px"
		# promise the burst makes. Several mimics bursting together must never
		# read as a bigger shake than one, and clamping is what guarantees that.
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		var strength := SHAKE_PX * (_shake_left / shake_time)
		sprite.position = offset * strength
	elif sprite.position != Vector2.ZERO:
		sprite.position = Vector2.ZERO

	if chain == Chain.DORMANT or chain == Chain.AWAKE \
			or state == State.DEAD:
		return
	_chain_time += delta
	match chain:
		Chain.OPENING:
			if _chain_time >= OPENING_TIME:
				_enter_chain(Chain.HOLD)
		Chain.HOLD:
			if _chain_time >= HOLD_TIME:
				_enter_chain(Chain.TRANSFORM)
		Chain.TRANSFORM:
			if _chain_time >= TRANSFORM_TIME:
				_enter_chain(Chain.SETTLE)
		Chain.SETTLE:
			if _chain_time >= SETTLE_TIME:
				_awaken()


func _enter_chain(next: int) -> void:
	chain = next
	_chain_time = 0.0
	match next:
		Chain.HOLD:
			_play("idle_open")
		Chain.TRANSFORM:
			_play("transform")
			sprite.frame = 0
			# The shove lands on the FIRST frame of the transform, which is the
			# frame the creature becomes tall enough to be pushing at.
			_burst_push()
		Chain.SETTLE:
			_play("idle_transformed")


## Knocks the player away with NO damage.
##
## The point is to buy a beat of space, not to punish approach: taking a hit for
## standing next to a chest you have not attacked yet is the one thing that would
## make the disguise feel unfair. Applied straight to velocity rather than
## through take_damage, which correctly refuses a zero-damage hit.
func _burst_push() -> void:
	if player == null or not is_instance_valid(player):
		return
	var away := player.global_position - global_position
	if away.length() > burst_push_radius:
		return
	if away.length() < 0.001:
		away = Vector2.UP
	player.velocity += away.normalized() * burst_push
	player.take_damage(0, global_position)


## Finished pretending. Hand over to the inherited FSM for good.
func _awaken() -> void:
	chain = Chain.AWAKE
	_apply_awake_shapes()
	# Size the shapes now rather than only at the end of the tween, so the first
	# awake frame is already hitbox-correct.
	sprite.scale = Vector2(float(data.get("scale", 1.0)), float(data.get("scale", 1.0)))
	# The inherited FSM is already running; it is simply gated out by
	# _physics_process until the chain reaches AWAKE.
	state = State.CHASE
	_play("walk")
	# An awake mimic counts as having fought even though it never went through
	# activate(): it woke by proximity, not by a room trigger. Without this it
	# would leash, go IDLE, and then refuse to re-engage - awake and inert.
	_has_been_activated = true
	active = true
	_last_swing_hit = -1


## The inherited FSM does not run until the mimic is awake.
func _physics_process(delta: float) -> void:
	if chain != Chain.AWAKE or state == State.DEAD:
		return
	super._physics_process(delta)
##
## The tween spans OPENING + HOLD + TRANSFORM rather than OPENING + TRANSFORM:
## HOLD sits between them, and a tween with a gap would snap at the seam, which
## is exactly what "no snap" is asking to avoid.
func _start_scale_tween() -> void:
	var from := float(data.get("dormant_scale", 1.0))
	var to := float(data.get("scale", 1.0))
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_property(sprite, "scale",
			Vector2(to, to), OPENING_TIME + HOLD_TIME + TRANSFORM_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_scale_tween.tween_callback(_apply_awake_shapes)