extends "res://damageable.gd"
## The player.
##
## Extends Damageable so health, damage, knockback, invincibility and the floating
## damage number are inherited rather than re-implemented. What is left here is
## what is genuinely specific to the player: movement, the four-frame slash, the
## existing movement penalties from traps, and dying.

@export var speed := 200.0
const BUILDER := preload("res://dungeon_builder.gd")

## The dungeon's carved-floor grid, read once so the per-frame bounds check does
## not walk the tree. Empty until _ready; every helper tolerates that.
var _grid: Array = []

## Half a cell in rendered px: the furthest this body may travel in one frame.
## A cell is GRID * SCALE = 32 rendered px, so this is 16.
const MAX_STEP_PX := 16.0
@export var attack_frame_time := 0.05
@export var idle_frame_time := 0.15
@export var walk_frame_time := 0.1
## invincibility_time is inherited from Damageable (0.8s). It is NOT redeclared
## here: GDScript rejects a member that shadows a parent export, and duplicating
## it would mean two values that silently disagree.

@onready var icon: Sprite2D = $"Icon(Sprite2D)"
@onready var attack_area: Area2D = $"AttackArea(Area2D)"
@onready var attack_shape: CollisionShape2D = $"AttackArea(Area2D)/CollisionShape2D"
@onready var slash_effect: Sprite2D = $"AttackArea(Area2D)/SlashEffect(Sprite2D)"
@onready var camera: Camera2D = $"Camera2D"


## Moves the player onto the dungeon builder's PlayerStart marker.
##
## The marker is the ONLY source of truth for the spawn. An earlier version
## hardcoded a position in Main.tscn, which put the player on cell (9,24) while
## the hall centre - the obvious "centre of the first room" - is cell (10,25).
## Two copies of the same fact drift apart the moment a room is nudged.
##
## The camera smoothing is reset afterwards on purpose. Smoothing interpolates
## from wherever the camera already was, so snapping the body from the scene's
## default (0,0) would slide the view across the map on the first frames.
func snap_to_player_start() -> void:
	var dungeon := _find_dungeon()
	if dungeon == null:
		return
	var marker := dungeon.get_node_or_null("PlayerStart") as Marker2D
	if marker == null:
		push_warning("player: no PlayerStart marker found, leaving spawn as-is")
		return
	global_position = marker.global_position
	velocity = Vector2.ZERO
	if camera != null:
		camera.reset_smoothing()


## The Dungeon node.
##
## The Dungeon is the player's SIBLING under the Main root, not its ancestor, so
## this searches downward from the common parent. Walking up from the player
## never finds it - it goes from Player to the root and stops.
func _find_dungeon() -> Node2D:
	var parent := get_parent()
	if parent != null:
		var sibling := parent.get_node_or_null("Dungeon")
		if sibling is Node2D:
			return sibling as Node2D
	# Fall back to a tree walk, so this still works if the player is ever nested.
	return _search_tree(get_tree().root) if get_tree() != null else null


func _search_tree(node: Node) -> Node2D:
	if node == null:
		return null
	if node.name == "Dungeon" and node is Node2D:
		return node as Node2D
	for child in node.get_children():
		var found := _search_tree(child)
		if found != null:
			return found
	return null


## Movement penalties currently applied, keyed by the source that set them
## (a trap's instance id), e.g. {"@Area2D_42": 0.45}.
##
## A source adds itself on entry and removes itself on exit, so the speed returns
## to normal by itself once the last slow lets go. Nothing has to remember to
## call a reset.
var _speed_scales: Dictionary = {}


var idle_texture := preload("res://Assets/Player/Dark_Hatman_Topdown_Character/Animations/Idle/darkhatman_idle_sheet_64x64.png")
var walk_texture := preload("res://Assets/Player/Dark_Hatman_Topdown_Character/Animations/Walk/darkhatman_walk_sheet_64x64.png")
var attack_texture := preload("res://Assets/Player/Dark_Hatman_Topdown_Character/Animations/Attack_Without_Effect/darkhatman_attack_sheet_64x64.png")
var slash_texture := preload("res://Assets/Player/Dark_Hatman_Topdown_Character/Animations/AttackEffect/attackeffect_sheet_64x64t.png")


const IDLE_ROWS := 4    
const WALK_ROWS := 8    
const ATTACK_ROWS := 4  
## Blink the sprite white while invulnerable.
##
## A modulate on the Icon only, so the collision shape and the slash hitbox are
## untouched: the player really is still there, just flickering.
func _start_invincibility_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	icon.modulate = Color(2.2, 2.2, 2.2, 1.0)
	_flash_tween = create_tween()
	_flash_tween.set_loops()
	_flash_tween.tween_property(icon, "modulate",
		Color(1, 1, 1, 0.25), 0.07)
	_flash_tween.tween_property(icon, "modulate",
		Color(2.2, 2.2, 2.2, 1.0), 0.07)


func _stop_invincibility_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	icon.modulate = Color(1, 1, 1, 1)


## Death: a short fade, then back to PlayerStart with full health.
##
## Coins are NOT reset. GameState is an autoload precisely so the purse survives
## the respawn, and losing it here would be the single most annoying thing the
## feature could do.
func _die() -> void:
	_dying = true
	is_attacking = false
	attack_shape.disabled = true
	slash_effect.visible = false
	set_physics_process(false)
	icon.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(icon, "modulate:a", 0.0, 0.35)
	await tween.finished
	if not is_inside_tree():
		return
	snap_to_player_start()
	icon.modulate.a = 1.0
	reset_health()
	set_physics_process(true)
const SLASH_ROWS := 3   


const ATTACK_HITBOX_DISTANCE := 24.0

var is_attacking := false
var last_direction := Vector2.DOWN
var _flash_tween: Tween  

var anim_frame := 0
var anim_timer := 0.0

func _ready():
	# Full health before anything else can touch it. The base class already
	# does this, but an empty HUD on the first frame is a bad first
	# impression, so the guarantee is made explicit here.
	health = max_health
	# The body moves onto the named `player` bit. Its MASK is unchanged in
	# practice - still just `world` - so it collides with exactly the same walls,
	# chests and traps it always did. Only the label on the body changed.
	collision_layer = Layers.PLAYER
	collision_mask = Layers.player_mask()
	# The slash listens for enemy hurtboxes only. It is off almost all the time.
	attack_area.collision_layer = Layers.PLAYER_HITBOX
	attack_area.collision_mask = Layers.player_hitbox_mask()

	# Take the spawn from the dungeon's PlayerStart marker before anything else,
	# so the very first physics frame already happens at the right place.
	snap_to_player_start()

	var dungeon := get_node_or_null("../Dungeon")
	if dungeon != null:
		_grid = dungeon.get("_grid")

	attack_area.position = Vector2.ZERO
	attack_shape.position = Vector2(0, ATTACK_HITBOX_DISTANCE)
	attack_shape.disabled = true
	
	slash_effect.texture = slash_texture
	slash_effect.hframes = 4
	slash_effect.vframes = SLASH_ROWS
	slash_effect.position = Vector2.ZERO
	slash_effect.scale = icon.scale
	slash_effect.visible = false
	
	
	icon.texture = idle_texture
	icon.hframes = 4
	icon.vframes = IDLE_ROWS
	icon.flip_h = false
	icon.frame = 0 * 4 + _get_dir_col(last_direction)

func _physics_process(delta):
	# The invincibility timer lives in Damageable._physics_process. This method
	# OVERRIDES it, so without the explicit super call the timer never counts
	# down and the player stays invulnerable for the rest of the run after a
	# single hit. It must come before the is_attacking early-return below.
	super._physics_process(delta)

	_clamp_step(delta)

	if is_attacking:
		move_and_slide()
		_enforce_bounds()
		return

	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * current_speed()
	move_and_slide()
	_enforce_bounds()

	if direction != Vector2.ZERO:
		last_direction = direction
		_animate_walk(delta)
	else:
		_animate_idle(delta)

	# The attack key is read HERE, at the tail of _physics_process, and nowhere
	# else. A helper function inserted in the middle of this body once stranded
	# it after a `return`, so it compiled perfectly and the attack silently did
	# nothing - no error, no failure, just a game where the sword was dead.
	if Input.is_action_just_pressed("attack"):
		do_attack()
	_footsteps(delta)


## Footsteps on a timer, but only while genuinely moving.
##
## Gated on the body's own speed rather than on "a key is down", so the steps
## stop when the player is stopped by a wall, slowed by a trap, or mid-swing -
## otherwise they keep ticking while the character visibly stands still.
func _footsteps(delta: float) -> void:
	var moving: bool = velocity.length() > FOOTSTEP_MIN_SPEED and not is_attacking
	if not moving:
		_footstep_left = 0.0
		return
	_footstep_left -= delta
	if _footstep_left > 0.0:
		return
	_footstep_left = FOOTSTEP_INTERVAL
	_sfx("footstep")


## Below this the player is not really walking, so no step plays.
const FOOTSTEP_MIN_SPEED := 20.0
const FOOTSTEP_INTERVAL := 0.28
var _footstep_left := 0.0


## Sound through the Audio autoload, if it is present.
##
## The --script test harnesses boot scenes without autoloads, so call sites go
## through this guard rather than assuming Audio exists.
func _sfx(event: String, at: Variant = null) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("Audio")
	if audio != null:
		audio.call("play", event, at)

## Catches the player if they end a frame off the floor, whatever moved them.
##
## The wall seal and the border ring are the real fix; this is the belt to that
## braces, and it is deliberately checked EVERY physics frame rather than only
## after damage. A tunnel, a teleport, a future bug in a push - none of them can
## leave the player standing in the void if this runs.
##
## The snap is to the nearest walkable cell CENTRE, found by expanding rings, so
## the player is put somewhere legal rather than merely nudged.
func _enforce_bounds() -> void:
	if global_position.is_finite() == false:
		return
	var cell := _cell_of(global_position)
	if _is_floor(cell):
		return
	global_position = _nearest_floor_centre(global_position)
	velocity = Vector2.ZERO


## Never let one frame move the body more than half a cell.
##
## move_and_slide is a solver, not a swept test: at high speed, or through a
## gap thinner than the per-frame step, a body can end up inside geometry it
## passed through. Capping the step at half a cell keeps the body from skipping
## a wall cell entirely, which is what turned a fast dash into a way out of the
## map. Applied to velocity, never to position - position is owned by
## move_and_slide and is never written here.
func _clamp_step(delta: float) -> void:
	var limit := MAX_STEP_PX / maxf(delta, 0.0001)
	if velocity.length() > limit:
		velocity = velocity.normalized() * limit


## The dungeon cell containing a world position.
func _cell_of(p: Vector2) -> Vector2i:
	var cell_px := BUILDER.GRID * BUILDER.SCALE
	return Vector2i(int(floor(p.x / cell_px)), int(floor(p.y / cell_px)))


func _is_floor(cell: Vector2i) -> bool:
	if _grid.is_empty():
		return true
	if cell.x < 0 or cell.y < 0 \
			or cell.x >= BUILDER.MAP_W or cell.y >= BUILDER.MAP_H:
		return false
	return bool(_grid[cell.y][cell.x] == 1)


## Nearest walkable cell centre to a world position, searched by ring.
func _nearest_floor_centre(p: Vector2) -> Vector2:
	var cell_px := BUILDER.GRID * BUILDER.SCALE
	var start := _cell_of(p)
	for r in range(0, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if r > 0 and absi(dx) != r and absi(dy) != r:
					continue
				var c := Vector2i(start.x + dx, start.y + dy)
				if not _is_floor(c):
					continue
				return Vector2(c) * cell_px + Vector2(cell_px, cell_px) * 0.5
	# Nothing within 12 cells: the PlayerStart is always floor, so fall back.
	var marker := get_node_or_null("../Dungeon/PlayerStart") as Marker2D
	if marker != null:
		return marker.global_position
	return p

func _get_dir_col(dir: Vector2) -> int:
	
	if abs(dir.x) > abs(dir.y):
		return 2 if dir.x > 0 else 3
	else:
		return 1 if dir.y < 0 else 0

## Applies a named movement multiplier. Called by hazards such as trap.gd when
## the player steps into them. Re-applying the same source refreshes it rather
## than stacking with itself, so standing in one trap is not slower than standing
## in the same trap twice.
func add_speed_scale(source: String, factor: float) -> void:
	_speed_scales[source] = clampf(factor, 0.0, 1.0)


## Drops a penalty applied earlier by add_speed_scale. When the last one is
## dropped the multiplier goes back to 1.0, so the player is never left slow.
func remove_speed_scale(source: String) -> void:
	_speed_scales.erase(source)


## True when nothing is holding the player back.
func is_normal_speed() -> bool:
	return _speed_scales.is_empty()


## The movement speed right now.
##
## Overlapping hazards do NOT multiply - the STRONGEST active slow wins, and the
## others are simply ignored until it lets go. Multiplying looked tempting but
## breaks in practice: the player collider is 43x67 px while a tile is 32 px, so
## stepping onto a three-tile spike strip overlaps all three traps at once. At
## 0.45 each that is 0.09x - effectively frozen, which reads as a bug rather
## than a hazard. Taking the minimum caps the penalty at one trap's worth, which
## is both predictable and fair.
func current_speed() -> float:
	var scale := 1.0
	for factor in _speed_scales.values():
		scale = minf(scale, float(factor))
	return speed * scale


func _animate_idle(delta):
	if icon.texture != idle_texture:
		icon.texture = idle_texture
		icon.hframes = 4
		icon.vframes = IDLE_ROWS
		anim_frame = 0
		anim_timer = 0.0

	var col := _get_dir_col(last_direction)
	icon.flip_h = false

	anim_timer += delta
	if anim_timer >= idle_frame_time:
		anim_timer = 0.0
		anim_frame = (anim_frame + 1) % IDLE_ROWS

	icon.frame = anim_frame * 4 + col

func _animate_walk(delta):
	if icon.texture != walk_texture:
		icon.texture = walk_texture
		icon.hframes = 4
		icon.vframes = WALK_ROWS
		anim_frame = 0
		anim_timer = 0.0

	var col := _get_dir_col(last_direction)
	icon.flip_h = false

	anim_timer += delta
	if anim_timer >= walk_frame_time:
		anim_timer = 0.0
		anim_frame = (anim_frame + 1) % WALK_ROWS

	icon.frame = anim_frame * 4 + col

## Health removed by one slash. Enemies read this rather than hardcoding 2, so
## buffing the sword is a single change here.
@export var slash_damage := 2

## Incremented once per swing, and never reused.
##
## Enemies remember the last swing_id that connected and ignore a repeat from the
## same one. That replaces relying on the attack shape being toggled between
## swings, which is an accident of the current timing rather than a rule: if the
## shape ever stayed enabled across two frames, one swing could chew through a
## whole enemy's health.
var swing_id := 0

func do_attack():
	is_attacking = true
	velocity = Vector2.ZERO
	swing_id += 1
	# The slash sounds at the START of the swing, not on contact: it is the
	# player's own action, so hearing it the instant the key lands is what makes
	# the swing feel responsive.
	_sfx("player_slash")

	var col := _get_dir_col(last_direction)

	var hitbox_offset := Vector2.ZERO
	match col:
		0:
			hitbox_offset = Vector2(0, ATTACK_HITBOX_DISTANCE)
		1:
			hitbox_offset = Vector2(0, -ATTACK_HITBOX_DISTANCE)
		2:
			hitbox_offset = Vector2(ATTACK_HITBOX_DISTANCE, 0)
		3:
			hitbox_offset = Vector2(-ATTACK_HITBOX_DISTANCE, 0)

	attack_area.position = Vector2.ZERO
	attack_shape.position = hitbox_offset

	
	icon.texture = attack_texture
	icon.hframes = 4
	icon.vframes = ATTACK_ROWS
	icon.flip_h = false

	slash_effect.texture = slash_texture
	slash_effect.hframes = 4
	slash_effect.vframes = SLASH_ROWS
	slash_effect.position = Vector2.ZERO
	slash_effect.scale = icon.scale
	slash_effect.flip_h = false


	icon.frame = 0 * 4 + col
	slash_effect.visible = false
	attack_shape.disabled = true
	await get_tree().create_timer(attack_frame_time).timeout
	if not is_inside_tree():
		return


	icon.frame = 1 * 4 + col
	slash_effect.frame = 0 * 4 + col
	slash_effect.visible = true
	attack_shape.disabled = false
	await get_tree().create_timer(attack_frame_time).timeout
	if not is_inside_tree():
		return


	icon.frame = 2 * 4 + col
	slash_effect.frame = 1 * 4 + col
	slash_effect.visible = true
	attack_shape.disabled = false
	await get_tree().create_timer(attack_frame_time).timeout
	if not is_inside_tree():
		return


	icon.frame = 3 * 4 + col
	slash_effect.frame = 2 * 4 + col
	slash_effect.visible = true
	attack_shape.disabled = true
	await get_tree().create_timer(attack_frame_time).timeout
	if not is_inside_tree():
		return


	slash_effect.visible = false
	attack_shape.disabled = true
	is_attacking = false

	icon.texture = idle_texture
	icon.hframes = 4
	icon.vframes = IDLE_ROWS
	anim_frame = 0
	anim_timer = 0.0
	icon.frame = 0 * 4 + col
## Player-only override, so the enemies never inherit the player's hurt noise.
##
## Damageable.take_damage already returns false when the hit was BLOCKED - i-
## frames, or zero damage - and that is the signal used here: the sound plays
## when damage was genuinely applied and not otherwise. Putting this in the base
## class instead would make every monster cry out in pain when the player is hit.
func take_damage(amount: int, source_position: Vector2) -> bool:
	var applied := super.take_damage(amount, source_position)
	if applied:
		_sfx("player_hurt")
	return applied
