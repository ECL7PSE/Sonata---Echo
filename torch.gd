extends Node2D
## Standing torch: flickers its PointLight2D so the dungeon feels alive.

# A gentler wobble than before. The previous 0.14 swing on an additive light
# large enough to cover a room made the brightness visibly pump, which reads as
# the flicker itself rather than as a flame.
@export var flicker_speed := 4.0
@export var flicker_amount := 0.07

@onready var light: PointLight2D = $Light

var _base_energy := 1.0
var _phase := 0.0


func _ready() -> void:
	_base_energy = light.energy
	# Offset every torch so they do not all flicker in sync.
	_phase = randf() * TAU


func _process(delta: float) -> void:
	_phase += delta * flicker_speed
	var wobble := sin(_phase) + 0.5 * sin(_phase * 2.7)
	light.energy = maxf(0.0, _base_energy * (1.0 + flicker_amount * wobble))
