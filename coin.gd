extends Area2D
## A single collectable coin.
##
## A coin cannot be collected for `arm_delay` seconds after it spawns. That is
## not a fudge: without it, a coin that spawns underneath the player is picked
## up on the same frame it appears, so opening a chest while standing on it would
## silently swallow the drop instead of scattering it.

## Seconds before this coin can be collected.
@export var arm_delay := 0.3
## Friction applied while the coin settles.
@export var friction := 5.0
## Upward kick at spawn.
@export var launch_speed := 150.0

## Whichever child is called "Sprite" - an AnimatedSprite2D when the G001 frames
## are present, a plain Sprite2D otherwise. Typed as CanvasItem so both fit.
@onready var sprite: CanvasItem = $Sprite

var _arm_left := 0.0
## How much of the launch arc is left. The coin moves while this is positive.
var _launch_left := 0.45
## Arc height in LOCAL pixels, applied to the sprite only.
const BOUNCE_HEIGHT := 6.0
var _bounce_t := 0.0
## One pickup, one payout. Both entry paths can race.
var _taken := false


## Polls for a player already standing on the coin when the arm delay ends.
##
## body_entered only fires on a NEW overlap. A player who walked onto a coin
## during the 0.3s arm delay would otherwise never trigger it.
func _try_collect_overlaps() -> void:
	for body in get_overlapping_bodies():
		if body != null and body.has_method("take_damage"):
			_collect(body)
			return
var _settling := false


func _ready() -> void:
	# Only the player can pick this up. Leaving `world` out of the mask means a
	# coin can never be triggered by geometry.
	collision_layer = Layers.PICKUP
	collision_mask = Layers.pickup_mask()
	_arm_left = arm_delay
	# body_entered, NOT area_entered. The player is a CharacterBody2D, and an
	# Area2D reports body_entered for a PhysicsBody2D - listening for
	# area_entered meant the player could never trigger a pickup at all.
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _arm_left > 0.0 or body == null:
		return
	if body.has_method("take_damage"):
		_collect(body)


func _collect(_body: Node2D) -> void:
	if _taken:
		return
	_taken = true
	var state := _game_state()
	if state != null:
		state.add_coins(1)
	_pop()
	queue_free()


func _physics_process(delta: float) -> void:
	if _arm_left > 0.0:
		_launch_left -= delta
		if _launch_left <= 0.0:
			# The arm delay just expired. A player standing ON a coin never
			# generates a body_entered, so the overlap is polled here.
			_try_collect_overlaps()

	# The bounce, applied to the SPRITE ONLY.
	#
	# This used to move the coin's own `position`, which drags the
	# CollisionShape2D up with it: the pickup shape arced through the air and
	# came to rest wherever it landed, so the player walked under it and never
	# collected anything. The root now only ever moves along the floor, the arc
	# is the sprite's offset, and it is zeroed when the bounce ends so the art
	# sits exactly on its collider.
	if _launch_left > 0.0:
		var out: Vector2 = get_meta("launch", Vector2.ZERO)
		var dir: Vector2 = out.normalized()
		position.x += dir.x * launch_speed * delta
		_bounce_t += delta
		sprite.offset.y = -sin(_bounce_t * PI) * BOUNCE_HEIGHT
	elif sprite.offset.y != 0.0:
		sprite.offset.y = 0.0


## Retained only for the player's AttackArea, which is an Area2D and does
## report area_entered. The player's BODY arrives through body_entered.
func _on_area_entered(area: Area2D) -> void:
	if _arm_left > 0.0 or area == null:
		return
	if area.get_parent() is CharacterBody2D:
		_collect(null)


## The GameState autoload, looked up from the tree.
##
## Not referenced as a bare `GameState` identifier on purpose: an autoload is a
## compile-time global, and anything that resolves autoloads at runtime - the
## --script test harnesses, most importantly - compiles but fails at load when
## the global is absent. Going through the tree works in both cases.
func _game_state() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("GameState")


## A short scale-and-fade so the pickup reads as an event, not a disappearance.
func _pop() -> void:
	set_deferred("monitoring", false)
	if sprite == null:
		queue_free()
		return
	var tween := sprite.create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", sprite.scale * 1.8, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(queue_free)