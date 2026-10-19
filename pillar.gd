extends Node2D

## Placeholder boss reset pillar.
##
## The final boss in bone_hall dies, this pillar appears at the boss's death
## position, fades in over ~1.5s, and shows an [E] Interact prompt when the
## player is near. On interact it delegates to RoomManager.reset_run() so the
## whole run restores cleanly (enemies & boss respawn at original positions,
## player resets to spawn, health restored, room-cleared flags reset).

const PILLAR_Y_FADE := 1.5
const INTERACT_RANGE := 90.0

@export var label := "[E] Interact"
@export var pulse_speed := 6.0

## True while the pillar is fully visible and enabled for interaction.
var revealed := false

## The player; the pillar asks RoomManager (not the player) only to keep
## coupling loose. Set by the Dungeon builder or by the run reset flow.
var player: Node2D = null

## The tween that drives the reveal fade.
var _tween: Tween = null

func _ready() -> void:
	modulate = Color(1, 1, 1, 0.0)
	# The Area2D (if any) and its collision are disabled until revealed so the
	# player cannot read or interact with a fresh pillar before it fades in.
	var area := get_node_or_null("InteractArea") as Area2D
	if area != null:
		area.collision_layer = 0
		area.collision_mask = 0

func _process(delta: float) -> void:
	if not revealed:
		return
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist <= INTERACT_RANGE:
		modulate = Color(1, 1, 1, 1.0)
	else:
		modulate = Color(1, 1, 1, 0.55)

func reveal() -> void:
	# Fade the pillar (and its own sprite) from transparent to solid.
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(self, "modulate:a", 0.0, PILLAR_Y_FADE)
	tween.tween_callback(_on_pillar_revealed)
	_tween = tween

func _on_pillar_revealed() -> void:
	revealed = true
	var area := get_node_or_null("InteractArea") as Area2D
	if area != null:
		area.collision_layer = Layers.BOSS_PILLAR
		area.collision_mask = Layers.pillar_mask()
		area.area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	# Interact is wired by the player hitting [E] / the bound action; the
	# pillar signals interest and RoomManager performs the reset.
	pass

func reset_and_free() -> void:
	# Cleanly tear down the pillar when the run resets (it is a one-shot
	# reminder that the boss is dead, not a persistent prop).
	queue_free()

