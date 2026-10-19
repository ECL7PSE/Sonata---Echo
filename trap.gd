extends Area2D
## Spike trap: the animated TP001 spikes on an AnimatedSprite2D, wrapped around
## a slow field the player feels while standing on it.
##
## The trap does NOT block movement - it damages nothing either. Its only job is
## to make the player cross it more slowly, so a corridor full of traps costs
## time and risk rather than ending a run.
##
## The slow is applied through the player's add_speed_scale / remove_speed_scale
## API in character_body_2d.gd. The player keeps a penalty per trap, so walking
## off the last trap restores full speed by itself - nothing has to remember to
## reset. Penalties do NOT stack: the player takes the STRONGEST active one.
##
## Timing is a fixed cycle, not a raw animation loop. Looping the 14-frame sheet
## gives roughly one second of spike travel per revolution with no pause, so the
## spikes flickered and there was never a safe moment to plan a crossing. The
## frames themselves were measured to decide the split:
##
##   frames 1-3 and 14  no spike visible   -> DOWN
##   frames 4-7         spikes extending   -> RISING
##   frames 8-9         spikes at full height -> UP
##   frames 10-13       spikes retracting  -> FALLING
##
## so the cycle is: hold DOWN for SAFE_TIME, then play the travel frames once, then
## hold DOWN again. That gives the player a predictable two-second window in which
## the spikes are flat and the tile can be crossed at full speed.

## Movement multiplier while the player overlaps an ACTIVE trap.
@export var slow_factor := 0.45
## Seconds the spikes stay fully retracted before they rise again.
@export var safe_time := 2.0
## Frames per second for the rise/stay/fall part of the cycle.
@export var cycle_fps := 9.0

## Index of the first and last frames of the DOWN pose (1-based, as in the sheet).
const DOWN_FRAME := 1
## The measured travel frames: rising, up, falling.
const TRAVEL_FRAMES: Array[int] = [4, 5, 6, 7, 8, 9, 10, 11, 12, 13]

enum Phase { SAFE, TRAVEL }

## Health removed by one bite.
@export var damage := 2
## How often the dangerous window re-checks for a player standing on it. This is
## what lets a player who survives the first hit be hit again once their
## invincibility runs out, without the trap having to know about i-frames.
@export var damage_recheck := 0.1

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var shape: CollisionShape2D = $CollisionShape2D

var _phase: int = Phase.SAFE
var _timer := 0.0
var _travel_index := 0
var _inside: Array[Node2D] = []
## Counts down between bites while the spikes are out.
var _damage_timer := 0.0


func _ready() -> void:
	shape.disabled = false
	# The trap now listens on the named `player` bit explicitly. The slow logic
	# below is untouched; only the layer it watches changed.
	collision_layer = Layers.WORLD
	collision_mask = Layers.trap_mask()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_show(safe_time)


## True on the frames where the spike tips are visibly out of the floor.
##
## TRAVEL_FRAMES maps index 0..9 onto sheet frames 4..13. The sheet was measured
## (see this file's header): 4-7 extending, 8-9 at full height, 10-13 retracting.
## The tips first appear on sheet frame 7 and last on 10, so indices 3..6 are
## the dangerous window - four frames at 9fps, about 0.44s.
##
## Indices 0-2 (still rising, tips not yet clear of the hole) and 7-9 (tips
## leaving) deal NO damage, even though the movement slow already applies across
## the whole of TRAVEL. That distinction is the point of the change: crossing a
## trap as it rises costs time, not health.
func _is_dangerous() -> bool:
	return _phase == Phase.TRAVEL and _travel_index >= 3 and _travel_index <= 6


## Bites everything currently overlapping the tile.
##
## get_overlapping_bodies() rather than body_entered is the whole reason a player
## who is ALREADY standing on a trap when it fires still gets hit. body_entered
## only fires on the frame of entry, so a player standing still would never be
## touched.
func _bite() -> void:
	for body in get_overlapping_bodies():
		_apply_damage(body)


func _apply_damage(body: Node2D) -> void:
	if body == null or not body.has_method("take_damage"):
		return
	# Only when the spike actually connects. take_damage returns false while
	# the player is in i-frames, so a trap ticking away at an invulnerable
	# player makes no noise at all - which is also why this cannot fire while
	# the spikes are merely rising, before any bite has happened.
	if body.take_damage(damage, global_position):
		_sfx("trap_spike")


## Drives the cycle. Kept out of the AnimatedSprite2D's own playback so the pause
## is exact: the sprite is stepped frame by frame here rather than left to loop.
func _process(delta: float) -> void:
	# The damage cadence runs on its own clock, independent of the sprite stepping
	# below, so it is not silently tied to cycle_fps.
	if _is_dangerous():
		_damage_timer -= delta
		if _damage_timer <= 0.0:
			_damage_timer = damage_recheck
			_bite()

	_timer -= delta
	if _timer > 0.0:
		return

	match _phase:
		Phase.SAFE:
			# The spikes start rising now, so the trap bites immediately. Doing
			# this on the transition rather than a tick later means there is no
			# window in which the spikes are visibly out but the player is still
			# at full speed.
			_phase = Phase.TRAVEL
			_travel_index = 0
			sprite.frame = TRAVEL_FRAMES[0] - 1
			_set_slow(true)
			_timer = 1.0 / cycle_fps
		Phase.TRAVEL:
			_travel_index += 1
			if _travel_index >= TRAVEL_FRAMES.size():
				# Travel finished: the spikes are flat again, so start the
				# predictable safe window.
				_show(safe_time)
			else:
				# While the spikes are out the trap bites. From here on the slow
				# is applied on a cadence rather than on overlap events alone, so
				# a player who walks on mid-travel is caught too.
				sprite.frame = TRAVEL_FRAMES[_travel_index] - 1
				_set_slow(true)
				_timer = 1.0 / cycle_fps


## Returns to the flat pose and arms the safe window.
func _show(seconds: float) -> void:
	_phase = Phase.SAFE
	_timer = seconds
	sprite.animation = "spikes"
	sprite.speed_scale = 0.0
	sprite.frame = DOWN_FRAME - 1
	_set_slow(false)


func _set_slow(active: bool) -> void:
	for body in _inside:
		_apply(body, active)


func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("add_speed_scale"):
		return
	if not _inside.has(body):
		_inside.append(body)
	# Only bite if the spikes are actually out.
	if _phase == Phase.TRAVEL:
		_apply(body, true)


func _on_body_exited(body: Node2D) -> void:
	_inside.erase(body)
	_apply(body, false)


## Adds or removes this trap's slow on `body`.
##
## The key is THIS node's instance id, not a shared "trap" string: a shared key
## would mean stepping into a second trap overwrites the first one's entry, and
## then leaving the second one clears both and the player is never slow again.
func _apply(body: Node2D, active: bool) -> void:
	if body == null or not body.has_method("add_speed_scale"):
		return
	var source := str(get_instance_id())
	if active:
		body.add_speed_scale(source, slow_factor)
	else:
		body.remove_speed_scale(source)
## Sound through the Audio autoload, if it is present.
func _sfx(event: String, at: Variant = null) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("Audio")
	if audio != null:
		audio.call("play", event, at)