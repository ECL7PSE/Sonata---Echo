extends "res://damageable.gd"
class_name Enemy
## A data-driven monster. Everything visual and numeric comes from monster_db.gd,
## so adding a species is a database entry rather than a new scene.
##
## The node tree is fixed and the shapes are SIZED from the monster's measured
## body, which is what lets one scene serve eight species:
##
##   Sprite    the artwork, anchored by its visible bottom-centre
##   Body      the solid collider, on `enemy`
##   Hurtbox   receives the player's slash, on `enemy_hurtbox`
##   Hitbox    damages the player, on `enemy_hitbox`, only during the swing
##
## Why the sprite origin IS the ground contact point: monster_db measures each
## frame's visible bottom-centre and stores the offset that puts it on the node
## origin. So `position` means "where this monster's feet are" for every species
## and every frame, with no per-species fudge factor.

signal activated()

enum State { IDLE, WANDER, CHASE, ATTACK, HURT, DEAD }

## The monster's row from monster_db. Set before _ready runs.
@export var data: Dictionary = {}
## A boss variant: tougher, hits harder, richer. 3B-2 spawns one.
@export var boss := false

## The player. Left null so a scene can be dropped in without wiring; the room
## trigger in 3B-2 sets it, and the tests set it directly.
var player: Node2D = null
## Where this enemy spawned. The leash sends it back here, not to the room centre.
@export var home_position := Vector2.ZERO

## Enemies wait dormant until activate() so walking past a room does not start a
## fight the player chose to avoid.
var active := false
var state: int = State.IDLE

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var body_shape: CollisionShape2D = $Body
@onready var hurtbox: Area2D = $Hurtbox
@onready var hurt_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var hitbox: Area2D = $Hitbox
@onready var hit_shape: CollisionShape2D = $Hitbox/CollisionShape2D

var _sheets: Dictionary = {}
var _scale := 1.0
var _body_w := 16.0
var _body_h := 16.0
## Seconds a hit locks the enemy out for. Longer than the hitbox window would make
## enemies unstoppable; shorter would make every trade lethal.
@export var hurt_time := 0.28
@export var white_flash_time := 0.1
@export var separation_push := 24.0
@export var attack_range := 34.0

## Boss modifiers, all in one place so the test can read the same numbers.
const BOSS_SCALE := 1.15
const BOSS_HP := 2.0
const BOSS_DAMAGE := 1.2
## Beyond this the enemy gives up and walks home. Sized so a room plus its
## corridor fits inside it: leashing at exactly detect range would snap an enemy
## back mid-chase the moment the player stepped into a doorway.
@export var leash_range := 240.0

var _state_time := 0.0
var _cooldown := 0.0
var _wander_dir := Vector2.ZERO
var _wander_left := 0.0
## One hit per swing. The swing_id is the authority, not this flag: the flag only
## exists to keep _last_swing_hit honest, and is re-armed by activate().
var _last_swing_hit := -1
var _flash_tween: Tween


## The offset for one frame, already corrected for mirroring.
##
## flip_h mirrors the content inside its rect, so the same offset walks the
## bottom-centre the other way. Without negating x every left-facing enemy would
## sit half its own width off its ground contact point.
static func frame_offset(sheet: Dictionary, frame: int, flip: bool) -> Vector2:
	var off: Vector2 = sheet.get("offset", Vector2.ZERO)
	var per: Array = sheet.get("offsets", [])
	if per.size() > frame:
		off = per[frame]
	return Vector2(-off.x if flip else off.x, off.y)


## Brings the enemy online. The room trigger calls this; nothing wakes an enemy
## on its own.
func activate() -> void:
	if active:
		return
	active = true
	# A re-activated enemy must be able to be hit by whatever swing is in flight.
	_last_swing_hit = -1
	if state == State.IDLE:
		state = State.WANDER
		_state_time = 0.0
	activated.emit()


## Walks back to the spawn point and goes dormant again.
##
## The return is a state, not a teleport: snapping would let a player kite an
## enemy across the room for free, and would look wrong.
func _return_home() -> void:
	_set_hitbox_active(false)
	var away := home_position - global_position
	if away.length() < 4.0:
		global_position = home_position
		velocity = Vector2.ZERO
		active = false
		_last_swing_hit = -1
		_enter(State.IDLE)
		return
	away = away.normalized()
	_face(away)
	velocity = away * _speed()
	_play("walk")
func _ready() -> void:
	super._ready()
	if data.is_empty():
		push_error("Enemy has no data; nothing to build")
		return
	# The sprite must stay lit by the dungeon's PointLight2D lights, so it keeps
	# the default material - setting CanvasItemMaterial here would opt it out.
	sprite.material = null
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_sheets = data["sheets"]
	if home_position == Vector2.ZERO:
		home_position = position
	# A boss is the same art, bigger, with more health and a heavier hit.
	# The scale has to multiply the SHAPES too: scaling only the sprite would
	# leave a 1.15x sprite with the small monster's hitbox, so the boss would
	# look bigger and hit smaller.
	_scale = float(data["scale"])
	if boss:
		_scale *= BOSS_SCALE
		max_health = int(round(float(data["hp"]) * BOSS_HP))
		invincibility_time = 0.35
	else:
		max_health = int(data["hp"])
	invincibility_time = 0.25
	knockback_strength = 260.0 if boss else 200.0
	# Short enough that a lost exchange is survivable, long enough that a swarm
	# cannot chain a single swing into an instant kill.

	var body: Vector2i = data.get("body", Vector2i(16, 16))
	_body_w = float(body.x) * _scale
	_body_h = float(body.y) * _scale

	collision_layer = Layers.ENEMY
	collision_mask = Layers.enemy_mask()
	hurtbox.collision_layer = Layers.ENEMY_HURTBOX
	hurtbox.collision_mask = Layers.enemy_hurtbox_mask()
	hitbox.collision_layer = Layers.ENEMY_HITBOX
	hitbox.collision_mask = Layers.enemy_hitbox_mask()

	_size_shapes()
	_build_animations()

	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	hurtbox.area_exited.connect(_on_hurtbox_area_exited)
	# _on_frame_changed re-anchors AND drives the hitbox, so it is the single
	# place frames are handled - connecting _apply_frame_offset separately would
	# fire the anchor twice per frame and fight the hitbox logic.
	sprite.frame_changed.connect(_on_frame_changed)
	add_to_group("enemies")
	set_physics_process(true)


## Collision boxes sized from the measured body rather than guessed per species.
##
## They all sit ABOVE the node origin, because the origin is the bottom-centre of
## the visible body: a box centred on the origin would be half underground.
func _size_shapes() -> void:
	body_shape.shape = _rect(0.7 * _body_w, 0.55 * _body_h)
	body_shape.position = Vector2(0, -0.275 * _body_h)
	# Generous, so a swing that clips a corner still connects.
	hurt_shape.shape = _rect(1.15 * 0.7 * _body_w, 1.15 * 0.55 * _body_h)
	hurt_shape.position = Vector2(0, -0.316 * _body_h)
	hit_shape.shape = _rect(0.9 * _body_w, 0.7 * _body_h)
	# The hitbox starts fully off and is only brought forward on the frames that
	# actually connect, so the wind-up is visibly harmless.
	hit_shape.position = Vector2(0, -0.35 * _body_h)
	_set_hitbox_active(false)


func _rect(w: float, h: float) -> RectangleShape2D:
	var r := RectangleShape2D.new()
	r.size = Vector2(maxf(w, 1.0), maxf(h, 1.0))
	return r


func _build_animations() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in _sheets.keys():
		var sheet: Dictionary = _sheets[anim]
		var atlas: Texture2D = load(sheet["path"])
		var fw: int = sheet["frame_size"].x
		var fh: int = sheet["frame_size"].y
		frames.add_animation(anim)
		for i in int(sheet["frames"]):
			var at := AtlasTexture.new()
			at.atlas = atlas
			at.region = Rect2(i * fw, 0, fw, fh)
			frames.add_frame(anim, at)
	sprite.sprite_frames = frames
	sprite.scale = Vector2(_scale, _scale)
	_play("idle")
	_apply_frame_offset()


## Re-anchors the current frame. Called on every frame change AND when an
## animation starts, because starting an animation can jump the frame without
## frame_changed firing, and a sprite one frame out of place reads as a jump.
func _apply_frame_offset() -> void:
	if _sheets.is_empty() or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(sprite.animation):
		return
	var sheet: Dictionary = _sheets.get(sprite.animation, {})
	if sheet.is_empty():
		return
	sprite.offset = frame_offset(sheet, sprite.frame, sprite.flip_h)


func _play(anim: String) -> void:
	if not _sheets.has(anim):
		return
	sprite.play(anim)
	sprite.frame = 0
	_apply_frame_offset()


## Moves the hitbox forward on the frames that connect and parks it behind the
## sprite otherwise.
func _set_hitbox_active(on: bool) -> void:
	hit_shape.disabled = not on
	var reach := 0.0
	if on:
		reach = _facing_x() * 0.45 * _body_w
	hit_shape.position = Vector2(reach, -0.35 * _body_h)


func _facing_x() -> float:
	return -1.0 if sprite.flip_h else 1.0
## The player walked out of a hurtbox: nothing to do, because the swing id
## already decided it. Kept as a named no-op so the connection is not mistaken
## for a missing behaviour.
func _on_hurtbox_area_exited(_area: Area2D) -> void:
	pass


func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area == null or state == State.DEAD:
		return
	var owner_body := area.get_parent()
	if owner_body == null or not owner_body.has_method("do_attack"):
		return
	# One hit per SWING, decided by the swing's id rather than by whether this
	# area happens to have emitted an enter event. An enemy standing inside a
	# held-open hitbox gets one hit, and stays immune until a new swing id.
	var id: int = owner_body.get("swing_id")
	if id == _last_swing_hit:
		return
	_last_swing_hit = id
	var amount: int = owner_body.get("slash_damage")
	if amount == 0:
		amount = 2
	take_damage(amount, area.global_position)


## Re-arms the per-swing guard. The id, not the signal, decides - this only
## exists so a fresh enemy has a value that cannot equal swing 0.
func arm_for_first_swing() -> void:
	_last_swing_hit = -1


func _physics_process(delta: float) -> void:
	# Damageable counts the invincibility timer down here. This method overrides
	# it, so without super the timer never runs and a hurt enemy would be immune
	# for the rest of the run.
	super._physics_process(delta)
	if state == State.DEAD:
		return
	_state_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)

	if state == State.HURT:
		# Knockback decays here rather than in take_damage, so the enemy slides
		# to a stop instead of stopping dead.
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		_move()
		if _state_time >= hurt_time:
			_enter(State.CHASE)
		return

	var target := _player_position()
	var to_target := Vector2.ZERO
	if target != Vector2.INF:
		to_target = target - global_position
	var dist := to_target.length()
	_face(to_target)

	# The leash. A fight you can walk away from is not a fight; an enemy that
	# chases forever turns every room into a corridor sprint. Past the leash the
	# enemy walks home and goes dormant again, so the room can be re-entered.
	if state != State.IDLE and dist > leash_range:
		_return_home()
		return

	match state:
		State.IDLE:
			velocity = Vector2.ZERO
		State.WANDER:
			_wander(delta, target != Vector2.INF and dist < _detect())
		State.CHASE:
			if target == Vector2.INF or dist > _detect():
				_enter(State.WANDER)
			elif dist <= attack_range and _cooldown <= 0.0:
				_enter(State.ATTACK)
			else:
				velocity = to_target.normalized() * _speed()
		State.ATTACK:
			# The hitbox follows the animation's damage frames; the rest of the
			# swing is handled by _on_frame_changed.
			velocity = velocity.move_toward(Vector2.ZERO, 700.0 * delta)
			if not sprite.is_playing():
				# Read from the database, not a literal: a per-species cadence is a
				# data change, not a code change.
				_cooldown = float(data.get("attack_cooldown", 1.0))
				_enter(State.CHASE)
	_move()


## Movement, separation, pixel snapping.
func _move() -> void:
	velocity += _separation()
	move_and_slide()
	# Snapped so a half-pixel position cannot make the sprite shimmer between two
	# texel columns as it walks.
	global_position = global_position.round()


## A small push away from neighbours, so a pack spreads out instead of stacking
## into one sprite. Never applied vertically, or enemies would climb each other.
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not (other is Node2D):
			continue
		if (other as Node2D).global_position.y > global_position.y + 40.0:
			continue
		var away := global_position - (other as Node2D).global_position
		var d := away.length()
		if d < 0.01 or d > _body_w * 0.9:
			continue
		push += (away / d) * (1.0 - d / (_body_w * 0.9)) * separation_push
	return push


func _enter(next: int) -> void:
	state = next
	_state_time = 0.0
	match next:
		State.WANDER:
			_wander_left = randf_range(0.6, 1.8)
			_wander_dir = Vector2(randf_range(-1.0, 1.0), 0.0).normalized()
			_play("walk")
		State.CHASE:
			_play("walk")
		State.ATTACK:
			_set_hitbox_active(false)
			_play("attack")
		State.HURT:
			_set_hitbox_active(false)
			_play("hurt")


func _wander(delta: float, aggro: bool) -> void:
	if aggro:
		_enter(State.CHASE)
		return
	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = randf_range(0.6, 1.8)
		_wander_dir = Vector2(randf_range(-1.0, 1.0), 0.0).normalized()
		if randf() < 0.4:
			_wander_dir = Vector2.ZERO
	if _wander_dir == Vector2.ZERO:
		velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
		if sprite.animation != "idle":
			_play("idle")
	else:
		sprite.flip_h = _wander_dir.x < 0.0
		velocity = _wander_dir * _speed() * 0.35


## The swing's contact window. `damage_frames` is the middle band of the sheet:
## the wind-up before it does nothing, so a committed enemy can still be
## interrupted, and the follow-through after it is over.
func _on_frame_changed() -> void:
	_apply_frame_offset()
	if state != State.ATTACK or sprite.animation != "attack":
		return
	var sheet: Dictionary = _sheets.get("attack", {})
	var win: Vector2i = sheet.get("damage_frames", Vector2i(-1, -1))
	var live: bool = sprite.frame >= win.x and sprite.frame <= win.y
	_set_hitbox_active(live)
	if live:
		_strike()


## Deals this enemy's damage to `target`, as the hitbox does on a damage frame.
##
## Exposed separately from _strike so a test can prove the damage amount and the
## i-frame interaction without having to physically overlap two bodies.
func _strike_at(target: Node2D) -> void:
	if target == null or state == State.DEAD:
		return
	if target.has_method("take_damage"):
		target.take_damage(damage_amount(), global_position)


## Damage in half-hearts, doubled for the game's 2-per-heart scale.
func damage_amount() -> int:
	var raw := float(data.get("damage", 1))
	if boss:
		raw *= BOSS_DAMAGE
	return int(round(raw)) * 2


func _strike() -> void:
	for body in hitbox.get_overlapping_bodies():
		_strike_at(body)


## Hurt reaction: a short white flash and the hurt animation.
##
## A hit interrupts a wind-up that has not connected yet, which is what makes
## enemies punishable - committing to an attack is a real cost.
func _on_damaged(_push_direction: Vector2, _amount: int) -> void:
	if state == State.DEAD:
		return
	# Once the damage frames are up, the swing is unstoppable.
	if state == State.ATTACK and not hit_shape.disabled:
		return
	_enter(State.HURT)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(4, 4, 4, 1)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate",
			Color(1, 1, 1, 1), white_flash_time)


func _start_invincibility_flash() -> void:
	if sprite != null:
		sprite.modulate = Color(4, 4, 4, 1)


func _stop_invincibility_flash() -> void:
	if sprite != null:
		sprite.modulate = Color(1, 1, 1, 1)


## Death: stop being a physical thing immediately, then pay out when the
## animation has finished.
##
## Collision goes first, not last. A corpse that can still block a corridor or
## land one last hit is the single most unfair thing an enemy can do.
func _die() -> void:
	if state == State.DEAD:
		return
	_dying = true
	state = State.DEAD
	_state_time = 0.0
	velocity = Vector2.ZERO
	_set_hitbox_active(false)
	hurtbox.collision_layer = 0
	hitbox.collision_layer = 0
	collision_layer = 0
	# Set directly, not deferred. The spec is that a corpse stops being solid on
	# the same frame it dies; set_deferred would leave it solid until the end of
	# the frame, which is a frame a player can be pushed or trapped inside.
	body_shape.disabled = true
	hurt_shape.disabled = true
	set_physics_process(false)
	_play("death")
	sprite.modulate = Color(1, 1, 1, 1)
	died.emit()
	sprite.animation_finished.connect(_on_death_finished, CONNECT_ONE_SHOT)
	if not sprite.is_playing():
		_on_death_finished()


func _on_death_finished() -> void:
	if state != State.DEAD:
		return
	_drop_coins()
	queue_free()


## Spawns the payout through the SAME helper the chests use, so a dead enemy and
## an opened chest drop identical loot and cannot drift apart later.
func _drop_coins() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var lo := int(data.get("coin_min", 1))
	var hi := int(data.get("coin_max", 3))
	var amount := randi_range(lo, hi)
	if boss:
		amount = maxi(hi, 6)
	preload("res://coin_drop.gd").drop(parent, global_position, amount)


func _player_position() -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.INF
	return player.global_position


func _detect() -> float:
	return float(data.get("detect_range", 120.0))


func _speed() -> float:
	return float(data.get("speed", 90.0))


func _face(to_target: Vector2) -> void:
	if to_target == Vector2.ZERO:
		return
	sprite.flip_h = to_target.x < 0.0