extends "res://scripts/core/damageable.gd"
class_name Enemy
## One entity owns its collision, interaction area, duel, and visual sprite cluster.

signal activated()

enum State { IDLE, HURT, DEAD }

const InteractPrompt := preload("res://scripts/ui/interact_prompt.gd")

@export var data: Dictionary = {}
@export var boss := false
var player: Node2D = null
@export var home_position := Vector2.ZERO
var active := false
var state: int = State.IDLE

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var body_shape: CollisionShape2D = $Body
@onready var interaction_area: Area2D = $InteractionArea
@onready var interaction_shape: CollisionShape2D = \
		$InteractionArea/CollisionShape2D

var species := ""
var _sheets: Dictionary = {}
var _scale := 1.0
var _body_w := 16.0
var _body_h := 16.0
var _cluster_width := 16.0
var _sprite_gap := 0.0
var _sprite_count := 1
var _visual_sprites: Array[AnimatedSprite2D] = []
var _prompt: Label
var _player_in_range := false
var _state_time := 0.0
var _bob_time := 0.0
var _battle_cooldown := 0.0
var _last_swing_hit := -1
var _dead_handled := false
var _coins_dropped := false
var _flash_tween: Tween

@export var hurt_time := 0.28
@export var white_flash_time := 0.1

const SPRITES_PER_SPECIES := {
	"RAT": 3,
	"SLIME": 3,
	"BAT": 2,
	"FLYING_EYE": 2,
}
const SCALE_BY_SPRITE_COUNT := {
	1: 1.25,
	2: 1.0,
	3: 0.8,
}
const SPRITE_SPACING := 24.0
const BOSS_ENEMY_SCALE := 1.6
const INTERACTION_PADDING := 4.0
const FLYING_SPECIES := ["BAT", "FLYING_EYE"]
const FLY_BOB_AMPLITUDE := 2.0
const FLY_BOB_SPEED := 2.0
const BOSS_HP := 2.0
const BOSS_DAMAGE := 1.2


static func frame_offset(sheet: Dictionary, frame: int, flip: bool) -> Vector2:
	var off: Vector2 = sheet.get("offset", Vector2.ZERO)
	var per: Array = sheet.get("offsets", [])
	if per.size() > frame:
		off = per[frame]
	return Vector2(-off.x if flip else off.x, off.y)


func _ready() -> void:
	if data.is_empty():
		push_error("Enemy has no data; nothing to build")
		return
	_sheets = data["sheets"]
	if player == null:
		_resolve_player()
	home_position = global_position
	_sprite_count = int(SPRITES_PER_SPECIES.get(species.to_upper(), 1))
	var count_scale := float(SCALE_BY_SPRITE_COUNT.get(_sprite_count, 1.25))
	_scale = float(data["scale"]) * count_scale
	if boss:
		_scale *= BOSS_ENEMY_SCALE
		max_health = int(round(float(data["hp"]) * BOSS_HP))
	else:
		max_health = int(data["hp"])
	invincibility_time = 0.25
	knockback_strength = 0.0
	super._ready()

	var body: Vector2i = data.get("body", Vector2i(16, 16))
	_body_w = float(body.x) * _scale
	_body_h = float(body.y) * _scale
	_sprite_gap = maxf(SPRITE_SPACING, float(body.x) + 4.0) * _scale
	_cluster_width = _body_w + float(_sprite_count - 1) * _sprite_gap

	collision_layer = Layers.ENEMY
	collision_mask = Layers.enemy_mask()
	interaction_area.collision_layer = Layers.ENEMY_INTERACTABLE
	interaction_area.collision_mask = Layers.PLAYER | Layers.PLAYER_HITBOX
	interaction_area.monitoring = true
	_size_shapes()
	_build_animations()

	interaction_area.body_entered.connect(_on_interaction_body_entered)
	interaction_area.body_exited.connect(_on_interaction_body_exited)
	interaction_area.area_entered.connect(_on_interaction_area_entered)
	sprite.frame_changed.connect(_on_sprite_frame_changed)
	_prompt = InteractPrompt.make("E to fight",
			Vector2(-80.0, -maxf(66.0, _body_h * 1.5 + 36.0)))
	add_child(_prompt)
	add_to_group("enemies")


func activate() -> void:
	if active:
		return
	active = true
	_last_swing_hit = -1
	velocity = Vector2.ZERO
	activated.emit()


func deactivate() -> void:
	active = false
	_last_swing_hit = -1
	_player_in_range = false
	velocity = Vector2.ZERO
	global_position = home_position
	state = State.IDLE
	_state_time = 0.0
	_play("idle")
	if _prompt != null:
		_prompt.visible = false


func _size_shapes() -> void:
	body_shape.shape = _rect(0.7 * _body_w, 0.55 * _body_h)
	body_shape.position = Vector2(0, -0.275 * _body_h)
	_size_interaction_area()


func _size_interaction_area() -> void:
	interaction_shape.shape = _rect(
			_cluster_width + INTERACTION_PADDING * 2.0,
			_body_h + INTERACTION_PADDING * 2.0)
	interaction_shape.position = Vector2(0, -_body_h * 0.5)


func _rect(w: float, h: float) -> RectangleShape2D:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(w, 1.0), maxf(h, 1.0))
	return shape


func _build_animations() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in _sheets.keys():
		var sheet: Dictionary = _sheets[anim]
		var atlas: Texture2D = load(sheet["path"])
		var fw: int = sheet["frame_size"].x
		var fh: int = sheet["frame_size"].y
		frames.add_animation(anim)
		frames.set_animation_loop(anim, anim == "idle" or anim == "walk")
		for i in int(sheet["frames"]):
			var at := AtlasTexture.new()
			at.atlas = atlas
			at.region = Rect2(i * fw, 0, fw, fh)
			frames.add_frame(anim, at)

	sprite.sprite_frames = frames
	_visual_sprites = [sprite]
	var first_x := -float(_sprite_count - 1) * _sprite_gap * 0.5
	for i in _sprite_count:
		var visual := sprite
		if i > 0:
			visual = AnimatedSprite2D.new()
			visual.name = "Sprite_%d" % (i + 1)
			visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			visual.sprite_frames = frames
			add_child(visual)
			_visual_sprites.append(visual)
		visual.material = null
		visual.position = Vector2(first_x + float(i) * _sprite_gap, 0)
		visual.scale = Vector2(_scale, _scale)
	_play("idle")
	_apply_frame_offset()


func _apply_frame_offset() -> void:
	if _sheets.is_empty() or sprite.sprite_frames == null \
			or not sprite.sprite_frames.has_animation(sprite.animation):
		return
	var sheet: Dictionary = _sheets.get(sprite.animation, {})
	if sheet.is_empty():
		return
	for visual in _visual_sprites:
		visual.offset = frame_offset(sheet, sprite.frame, sprite.flip_h)


func _play(anim: String) -> void:
	if not _sheets.has(anim):
		return
	for visual in _visual_sprites:
		visual.play(anim)
		visual.frame = 0
	_apply_frame_offset()


func _on_sprite_frame_changed() -> void:
	_apply_frame_offset()
	for visual in _visual_sprites:
		if visual == sprite:
			continue
		if visual.animation != sprite.animation:
			visual.play(sprite.animation)
		visual.flip_h = sprite.flip_h
		visual.frame = sprite.frame
		visual.frame_progress = sprite.frame_progress


func _on_interaction_body_entered(body: Node2D) -> void:
	if body != null and body.has_method("do_attack"):
		player = body
		_player_in_range = true


func _on_interaction_body_exited(body: Node2D) -> void:
	if body == player:
		_player_in_range = false


func _on_interaction_area_entered(area: Area2D) -> void:
	if area == null or state == State.DEAD:
		return
	var attacker := area.get_parent()
	if attacker == null or not attacker.has_method("do_attack"):
		return
	var swing_id: int = attacker.get("swing_id")
	if swing_id == _last_swing_hit:
		return
	_last_swing_hit = swing_id
	_try_start_battle(attacker as Node2D)


func _try_start_battle(attacker: Node2D) -> bool:
	if state == State.DEAD or _battle_cooldown > 0.0 or is_invulnerable():
		return false
	var battle := get_node_or_null("/root/Battle")
	if battle == null or not battle.has_method("start") or battle.is_active():
		return false
	var fighter := player
	if fighter == null or not is_instance_valid(fighter):
		fighter = attacker
	if fighter == null:
		return false
	battle.start(self, fighter)
	if not battle.is_active():
		return false
	_battle_cooldown = 4.0
	_hide_enemy_prompts()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo() \
			and _player_in_range and active and state != State.DEAD \
			and _battle_cooldown <= 0.0 and _is_nearest_interactable():
		_try_start_battle(player)
		get_viewport().set_input_as_handled()


func _is_nearest_interactable() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var nearest: Enemy = self
	var nearest_distance := global_position.distance_squared_to(player.global_position)
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Enemy):
			continue
		var candidate := node as Enemy
		if candidate == self or not candidate._player_in_range \
				or not candidate.active or candidate.state == State.DEAD \
				or candidate.player != player:
			continue
		var distance := candidate.global_position.distance_squared_to(
				player.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest == self


func _hide_enemy_prompts() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Enemy:
			var other := node as Enemy
			if other._prompt != null:
				other._prompt.visible = false


func _process(delta: float) -> void:
	if FLYING_SPECIES.has(species.to_upper()) and state != State.DEAD:
		_bob_time += delta
		var bob := sin(_bob_time * FLY_BOB_SPEED) * FLY_BOB_AMPLITUDE
		for visual in _visual_sprites:
			visual.position.y = bob
	if _prompt == null:
		return
	var battle := get_node_or_null("/root/Battle")
	var duel_active: bool = battle != null and battle.has_method("is_active") \
			and battle.is_active()
	_prompt.visible = active and _player_in_range and state != State.DEAD \
			and _battle_cooldown <= 0.0 and not duel_active \
			and is_instance_valid(player) and _is_nearest_interactable()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD:
		return
	_state_time += delta
	_battle_cooldown = maxf(_battle_cooldown - delta, 0.0)
	if state == State.HURT and _state_time >= hurt_time:
		state = State.IDLE
		_play("idle")


func damage_amount() -> int:
	var raw := float(data.get("damage", 1))
	if boss:
		raw *= BOSS_DAMAGE
	return int(round(raw)) * 2


func _on_damaged(_push_direction: Vector2, _amount: int) -> void:
	if state == State.DEAD:
		return
	state = State.HURT
	_state_time = 0.0
	_play("hurt")
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	for visual in _visual_sprites:
		visual.modulate = Color(4, 4, 4, 1)
		var tween := create_tween()
		tween.tween_property(visual, "modulate", Color.WHITE, white_flash_time)
		if visual == sprite:
			_flash_tween = tween


func _start_invincibility_flash() -> void:
	for visual in _visual_sprites:
		visual.modulate = Color(4, 4, 4, 1)


func _stop_invincibility_flash() -> void:
	for visual in _visual_sprites:
		visual.modulate = Color.WHITE


func _die() -> void:
	if state == State.DEAD:
		return
	_dying = true
	state = State.DEAD
	_sfx_enemy("death")
	_state_time = 0.0
	velocity = Vector2.ZERO
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 0
	interaction_area.monitoring = false
	collision_layer = 0
	body_shape.disabled = true
	set_physics_process(false)
	set_process(false)
	if _prompt != null:
		_prompt.visible = false
	_play("death")
	_stop_invincibility_flash()
	died.emit()
	sprite.animation_finished.connect(_on_death_finished, CONNECT_ONE_SHOT)
	if not sprite.is_playing():
		_on_death_finished()
		return
	var frame_count := int(sprite.sprite_frames.get_frame_count("death"))
	var fps: float = sprite.sprite_frames.get_animation_speed("death")
	if fps <= 0.0:
		fps = 12.0
	var timer := Timer.new()
	timer.name = "DeathSafety"
	timer.one_shot = true
	timer.wait_time = float(frame_count) / fps + 0.5
	timer.timeout.connect(_on_death_finished)
	add_child(timer)
	timer.start()


func _on_death_finished() -> void:
	if _dead_handled or state != State.DEAD:
		return
	_dead_handled = true
	var timer := get_node_or_null("DeathSafety")
	if timer != null:
		timer.queue_free()
	if not _coins_dropped:
		_coins_dropped = true
		_drop_coins()
	if is_inside_tree():
		var fade := create_tween()
		fade.set_parallel(true)
		for visual in _visual_sprites:
			fade.tween_property(visual, "modulate:a", 0.0, 0.4)
		fade.chain().tween_callback(queue_free)
	else:
		queue_free()


func _drop_coins() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var lo := int(data.get("coin_min", 1))
	var hi := int(data.get("coin_max", 3))
	var amount := randi_range(lo, hi)
	if boss:
		amount = maxi(hi, 6)
	preload("res://scripts/items/coin_drop.gd").drop(parent, global_position,
			amount, 34.0, func(c: Vector2i) -> bool: return _floor().call(c))


func _floor() -> Callable:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return func(_c: Vector2i) -> bool: return true
	var builder := tree.current_scene.get_node_or_null("Dungeon")
	if builder == null or not builder.has_method("_walkable"):
		return func(_c: Vector2i) -> bool: return true
	var grid: Array = builder.get("_grid")
	return func(c: Vector2i) -> bool: return builder._walkable(grid, c)


func _resolve_player() -> void:
	call_deferred("_look_for_player")


func _look_for_player() -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	if root == null:
		return
	for child in root.get_children():
		if child.has_method("take_damage") and child.has_method("do_attack"):
			player = child as Node2D
			return


func _sfx_enemy(action: String) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("Audio")
	if audio != null:
		audio.call("play_enemy", species, action, global_position, boss)
