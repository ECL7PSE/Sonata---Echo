extends CanvasLayer
## The hearts, drawn in a CanvasLayer so the dungeon's CanvasModulate and its
## torch lights cannot tint them.
##
## A CanvasLayer is a separate canvas: the ambient darkness multiplies whatever
## is drawn on the world canvas and has no effect on this one. That is the whole
## reason the HUD is not a Control parented to the player or to Main.
##
## The art is the 16x16 pixel_ui heart set (full / half / empty). The Health_Bar
## folder holds a radial health WHEEL, not hearts - nine 48px compass frames -
## so the paths below are exposed as constants if that is ever the better read.

const HEART_FULL := preload("res://Assets/UI/pixel_ui/icons/heart.png")
const HEART_HALF := preload("res://Assets/UI/pixel_ui/icons/heart_half.png")
const HEART_EMPTY := preload("res://Assets/UI/pixel_ui/icons/heart_empty.png")

## Integer scale only. A fractional scale on 16px art resamples it and the
## nearest-neighbour filter turns the result into uneven pixels.
const HEART_SCALE := 3

## Health is in half-hearts; the HUD shows whole hearts.
const HEARTS_PER_FULL := 2

@onready var row: HBoxContainer = $Margin/Row

var _hearts: Array[TextureRect] = []
var _pulse: Tween
## Set after the first hit, when the low-health pulse may start.
var _seen_damage := false


func _ready() -> void:
	# Layer 10: above the world canvas, and high enough to stay above anything
	# the dungeon adds later.
	layer = 10
	var player := _find_player()
	if player == null:
		push_warning("health_ui: no player found")
		return
	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	player.add_to_group("damage_numbers")
	# Draw the starting hearts immediately rather than waiting for the first hit.
	_on_health_changed(player.health, player.max_health)


## The player body, found by capability rather than by name.
##
## Matching on a name prefix is not safe here: the dungeon places a Marker2D called
## "PlayerStart", which begins with "Player" and was being picked up instead of
## the body - so the HUD tried to read `health` off a Marker2D and failed.
##
## `do_attack` is required as well as `health_changed`, and that is not
## decoration. Enemies are CharacterBody2Ds extending the same Damageable base,
## so they publish `health_changed` too. Without this second test the HUD bound
## to whichever came first in the tree walk - an enemy - and drew ITS max_health:
## a Slime's 6 half-hearts rendered as three hearts instead of the player's five.
func _find_player() -> Node2D:
	var root := get_tree().root
	for child in root.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null


func _search(node: Node) -> Node2D:
	if node == null:
		return null
	# A player is a CharacterBody2D that publishes a health signal AND swings a
	# sword. Anything else with a similar shape is an enemy or decoration.
	if node is CharacterBody2D and node.has_signal("health_changed") \
			and node.has_method("do_attack"):
		return node as Node2D
	for child in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null


## `current` is in half-hearts, so 10 is five full hearts.
func _on_health_changed(current: int, maximum: int) -> void:
	var hearts: int = int(ceil(float(maximum) / HEARTS_PER_FULL))
	var shown: int = int(ceil(float(current) / HEARTS_PER_FULL))
	while _hearts.size() < hearts:
		var heart := TextureRect.new()
		heart.texture = HEART_EMPTY
		heart.scale = Vector2.ONE * HEART_SCALE
		# TextureRect does not lay children out at a fractional size, so the row is
		# given explicit minimum sizes instead.
		heart.custom_minimum_size = Vector2(
			heart.texture.get_width() * HEART_SCALE,
			heart.texture.get_height() * HEART_SCALE)
		row.add_child(heart)
		_hearts.append(heart)

	for i in _hearts.size():
		if i >= shown:
			_hearts[i].texture = HEART_EMPTY
		elif i < shown - 1:
			_hearts[i].texture = HEART_FULL
		else:
			_hearts[i].texture = HEART_HALF if _is_partial(current) else HEART_FULL

	if current < maximum:
		_seen_damage = true
		_shake()
	# At one heart or less, pulse instead of shake.
	if _seen_damage and shown <= 1:
		_pulse_hearts()
	else:
		_stop_pulse()


## True when the remaining health is an odd number of half-hearts.
func _is_partial(current: int) -> bool:
	return current % HEARTS_PER_FULL != 0


## A short shake so losing a heart is felt, not just seen.
func _shake() -> void:
	var tween := create_tween()
	tween.tween_property(row, "position:x", row.position.x + 4.0, 0.04)
	tween.tween_property(row, "position:x", row.position.x - 3.0, 0.04)
	tween.tween_property(row, "position:x", row.position.x, 0.05)


## A slow pulse while the player is on their last heart.
func _pulse_hearts() -> void:
	if _pulse != null and _pulse.is_valid():
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(row, "modulate",
		Color(1.6, 1.1, 1.1, 1.0), 0.5)
	_pulse.tween_property(row, "modulate",
		Color(1, 1, 1, 1), 0.5)


func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	row.modulate = Color(1, 1, 1, 1)