extends Area2D
## Breakable / openable dungeon prop (chest, pot, crate).
##
## The player's "AttackArea(Area2D)" is only switched on for the few frames of a
## slash (see character_body_2d.gd), so an overlap here means the player just hit
## this prop: play the reaction once and keep holding the last frame (debris, an
## open lid, ...).

@export var idle_animation := "idle"
@export var react_animation := "break"

@onready var sprite: AnimatedSprite2D = $Sprite

var _used := false


func _ready() -> void:
	# Same reasoning as loot.gd: the prop reacts to the slash, not to the player
	# walking into it, so the mask names the player_hitbox bit explicitly.
	collision_layer = Layers.WORLD
	collision_mask = Layers.prop_mask()
	sprite.play(idle_animation)
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if _used or area == null:
		return
	# Only the player's slash should trigger props.
	if area.get_parent() is CharacterBody2D:
		_used = true
		sprite.play(react_animation)
		# A pot and a crate are different objects with different clips; the
		# distinction is the node name the builder gave it.
		if str(name).begins_with("Crate"):
			_sfx("crate_break")
		else:
			_sfx("vase_break")
## Sound through the Audio autoload, if it is present.
func _sfx(event: String, at: Variant = null) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("Audio")
	if audio != null:
		audio.call("play", event, at)
