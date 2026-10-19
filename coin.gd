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


## Supplied by CoinDrop so the coin knows where the walls are.
##
## Without this the scatter is a straight x slide that runs straight through a
## wall and the coin ends up outside the room or inside the masonry. The coin is
## an Area2D, not a physics body, so nothing stops it for us.
var _walkable: Callable = Callable()

## Cached player, found once so the magnet is not a tree walk every frame.
var _player_ref: Node2D = null

## Edge length of one dungeon cell in this node's LOCAL pixels.
const CELL := 16.0

## Clearance a coin needs from any wall, in LOCAL pixels.
##
## Testing only the coin's CENTRE cell is not enough, and that was the second
## half of the bug. A coin resting inside the strip of floor the player cannot
## physically enter is a coin the player can never walk into range of - it is
## visible, it is there, and it can never be collected. This is that strip.
##
## Player half-width + coin pickup radius, halved into local space. The player
## collider is 14 wide (Main.tscn), so 7 rendered px, plus the coin's 9 local px
## (18 rendered) radius = 25 rendered = 12.5 local. It was 13 at 16 wide.
const CLEARANCE := 12.5

## Magnet range in LOCAL px (48 rendered px at the Dungeon's 2x scale).
const MAGNET_RANGE := 24.0
## Magnet speed in LOCAL px per second (160 rendered px).
const MAGNET_SPEED := 80.0
## Magnet pickup radius in LOCAL px.
const MAGNET_PICKUP := 20.0


func set_walkable(fn: Callable) -> void:
	_walkable = fn


## The cell containing a LOCAL position.
func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


## Is the whole pickup circle at `p` on floor?
##
## Checks every cell the CLEARANCE box touches, not the centre cell, which is
## what makes a coin in a doorway or a corner reject itself.
func _valid(p: Vector2) -> bool:
	if not _walkable.is_valid():
		return true
	var x0 := int(floor((p.x - CLEARANCE) / CELL))
	var x1 := int(floor((p.x + CLEARANCE) / CELL))
	var y0 := int(floor((p.y - CLEARANCE) / CELL))
	var y1 := int(floor((p.y + CLEARANCE) / CELL))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not bool(_walkable.call(Vector2i(x, y))):
				return false
	return true


## The nearest legal spot to `p`, searched outward by ring.
##
## Used as the settle fallback (a scatter that ended somewhere illegal) and as
## the spawn rescue (a chest standing in a corner drops out of a spot the
## player can never reach). Returns `p` unchanged if nothing is found.
## Test instrumentation: how many coins the spawn rescue or the settle fallback
## had to move. Static, so a suite can drop hundreds of coins and read the total.
static var settle_rescues := 0


func _nearest_valid(p: Vector2) -> Vector2:
	if _valid(p):
		return p
	var start := _cell_of(p)
	for r in range(1, 10):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var cand := Vector2(
						(start.x + dx) * CELL + CELL * 0.5,
						(start.y + dy) * CELL + CELL * 0.5)
				if _valid(cand):
					settle_rescues += 1
					return cand
	return p


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
	# Spawn rescue. A chest in a corner, or an enemy pressed into a wall, drops
	# its coins from a position that is ALREADY illegal, and scattering out of
	# an illegal point only travels further into it. Start from the nearest
	# legal spot instead. _walkable is injected by CoinDrop before add_child,
	# so it is already live here.
	position = _nearest_valid(position)


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
	# One per pickup. The manager caps a burst of these at 3 so a coin shower
	# stays a rattle rather than a wall of noise.
	_sfx("coin_collect")
	_pop()
	queue_free()


func _physics_process(delta: float) -> void:
	if _arm_left > 0.0:
		_arm_left -= delta
		if _arm_left <= 0.0:
			# The arm delay just expired. A player standing ON a coin never
			# generates a body_entered, so the overlap is polled here.
			_try_collect_overlaps()
	# The scatter runs its own 0.45s, which outlives the 0.3s arm delay, so the
	# magnet and the scatter overlap for a few frames on purpose.
	_scatter(delta)
	if _arm_left <= 0.0:
		_magnet(delta)

## The launch arc. FLOOR on the root, ARC on the sprite.
##
## The arc used to move the coin's own `position`, which drags the
## CollisionShape2D up with it: the pickup shape arced through the air and
## came to rest wherever it landed, so the player walked under it and never
## collected anything. The root only ever moves along the floor, the arc is the
## sprite's offset, and it is zeroed when the bounce ends so the art sits
## exactly on its collider.
##
## Every step is validated as a whole pickup circle against the floor, not as
## a centre cell, so the coin can never even momentarily overlap masonry.
func _scatter(delta: float) -> void:
	if _launch_left <= 0.0:
		if sprite.offset.y != 0.0:
			sprite.offset.y = 0.0
		return
	_launch_left -= delta
	if _launch_left <= 0.0:
		_launch_left = 0.0
		# SETTLE FALLBACK. The scatter is over, so if it finished somewhere
		# illegal - a tight room, a chest tight to a wall, a fan that ran out
		# of room - snap to the nearest legal spot. A coin must never come to
		# rest where it cannot be collected.
		position = _nearest_valid(position)
		sprite.offset.y = 0.0
		return
	var out: Vector2 = get_meta("launch", Vector2.ZERO)
	var step := out.normalized().x * launch_speed * delta
	# Whole step, then half a step, then give up. The half step is what makes
	# it BOUNCE off a wall rather than sticking dead at the limit.
	if _valid(position + Vector2(step, 0.0)):
		position.x += step
	elif _valid(position + Vector2(step * -0.5, 0.0)):
		position.x += step * -0.5
	else:
		_launch_left = 0.0
		sprite.offset.y = 0.0
		return
	_bounce_t += delta
	sprite.offset.y = -sin(_bounce_t * PI) * BOUNCE_HEIGHT

## The safety net: once armed, a coin near the player homes in and is taken.
##
## This is what makes an unreachable coin reachable even if some spawn point
## survives the clearance test. It obeys the same floor test, so it slides
## along a wall rather than into one, and it collects on its own pickup radius
## rather than relying on body_entered, which never fires for a coin that
## started out of range.
func _magnet(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	# NOTE: to_local() returns an OFFSET FROM THIS NODE in the node's own local
	# units, not an absolute position in the parent's space. Subtracting
	# position as well double-counts it, and the "distance to the player"
	# then bore no relation to where the player actually was - so the magnet
	# sat still and every coin read as uncollectable.
	var to := to_local(p.global_position)
	var d := to.length()
	if d <= MAGNET_PICKUP:
		_collect(p)
		return
	if d > MAGNET_RANGE:
		return
	var step := to.normalized() * MAGNET_SPEED * delta
	if _valid(position + step):
		position += step

## The player, found by the same duck-typing the rest of the game uses.
##
## Falls back to searching one level deeper. Under `--headless --script` the
## harness adds Main.tscn as a child of the tree root rather than as
## `current_scene`, so a lookup that only looks at current_scene's children
## finds nothing and the magnet silently never runs - which is exactly how a
## suite can appear to pass a coin test while proving nothing. The player is
## nested three deep (Main -> Node2D -> Player) and the --script harness adds
## one more level above that, so this searches a bounded depth rather than
## assuming a fixed shape.
const PLAYER_SEARCH_DEPTH := 5


func _player() -> Node2D:
	if is_instance_valid(_player_ref):
		return _player_ref
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.current_scene
	if root == null:
		root = tree.root
	if root == null:
		return null
	_player_ref = _find_player(root, 0)
	return _player_ref


func _find_player(n: Node, depth: int) -> Node2D:
	if depth > PLAYER_SEARCH_DEPTH:
		return null
	for child in n.get_children():
		if child.has_method("take_damage") and child.has_method("do_attack"):
			return child as Node2D
	for child in n.get_children():
		var hit := _find_player(child, depth + 1)
		if hit != null:
			return hit
	return null



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
## Sound through the Audio autoload, if it is present.
func _sfx(event: String, at: Variant = null) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("Audio")
	if audio != null:
		audio.call("play", event, at)
