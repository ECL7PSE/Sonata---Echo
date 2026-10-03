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
var _settling := false


func _ready() -> void:
	# Only the player can pick this up. Leaving `world` out of the mask means a
	# coin can never be triggered by geometry.
	collision_layer = Layers.PICKUP
	collision_mask = Layers.pickup_mask()
	_arm_left = arm_delay
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _arm_left > 0.0:
		_launch_left -= delta
		if _launch_left <= 0.0:
			_settling = true

	# An Area2D is not a physics body, so nothing moves it for us: the launch arc
	# and the settle are applied to `position` directly. Once settled it stops
	# moving entirely, so the coin rests on an exact pixel rather than creeping
	# forever with a sub-pixel velocity.
	if _launch_left > 0.0:
		var out: Vector2 = get_meta("launch", Vector2.ZERO)
		var dir: Vector2 = out.normalized()
		# A small arc: rise, then fall back to roughly where it started.
		position += Vector2(dir.x * launch_speed, -dir.y * launch_speed * 0.5) * delta
		position.y += 180.0 * delta * delta * 8.0
	elif _settling:
		_settling = false


func _on_area_entered(area: Area2D) -> void:
	if _arm_left > 0.0 or area == null:
		return
	if not area.get_parent() is CharacterBody2D:
		return
	var state := _game_state()
	if state != null:
		state.add_coins(1)
	_pop()


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