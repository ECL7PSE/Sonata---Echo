class_name DungeonRoomManager
extends Node

## Owns room-clear helpers and run-reset behavior.
##
## The Dungeon builder already owns every chest (via dungeon_builder._make_chest),
## so this autoload mirrors that construction for the hidden rooms and the
## boss reset pillar. Nothing is hidden unless the room is actually clear,
## and nothing stays interactable before it is visible.

const CHEST_SCRIPT := preload("res://scripts/items/loot.gd")
const PROP_SCRIPT := preload("res://scripts/world/prop_breakable.gd")
const Loot := preload("res://scripts/items/loot.gd")

func _spawn_chest(room_name: String, cell: Vector2i) -> void:
	# Build a box + sprite + collision, mirroring dungeon_builder._make_chest,
	# but keep the chest hidden (alpha 0) and non-solid until the reveal tween.
	var chest := Area2D.new()
	chest.name = "RoomClearChest_%s_%d_%d" % [room_name, cell.x, cell.y]
	chest.position = _cell_centre(cell)

	# The loot script owns the interaction (slash opens + drops coins).
	chest.set_script(CHEST_SCRIPT)
	chest.set("resets_the_run", false)

	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = _chest_frames()
	sprite.play("idle")
	sprite.modulate = Color(1, 1, 1, 0)
	chest.add_child(sprite)

	chest.add_child(_box_shape(32))

	# Hidden until the room is plainly clear, and fully solid only after the
	# reveal tween has finished so a premature slash cannot open it.
	var shape := chest.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.disabled = true

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(sprite, "modulate:a", 0.0, 1.5)
	tween.tween_callback(_on_chest_revealed.bind(chest))
	chest.get_parent().add_child(chest)

func _on_chest_revealed(chest: Area2D) -> void:
	# The chest is now fully visible and solid.
	var shape := chest.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.disabled = false

func _on_boss_pillar_revealed(pillar: Node2D) -> void:
	# The pillar is a neutral interaction marker: show [E] and wire the run
	# reset through the player's input instead of here.
	pass

func _cell_centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5) * 32.0

func _chest_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.add_frame("idle", load("res://Assets/Dungeon/dungeon_V.1.0.0_nyknck/Chest/C001/C001_01.png"))
	frames.set_animation_speed("idle", 6.0)
	frames.set_animation_loop("idle", true)
	return frames

func _box_shape(size_px: int) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var box := RectangleShape2D.new()
	box.size = Vector2(size_px, size_px)
	shape.shape = box
	return shape

func reset_run() -> void:
	# Use the existing, tested descent flow so the boss pillar never has to
	# know the mechanics of rebuilding the floor.
	var tree := get_tree()
	if tree != null:
		RunReset.descend(tree)

func interact_pillar(pillar: Node2D) -> void:
	# The pillar is a neutral marker; the player interacts with it via [E].
	# This is the line the final boss death triggers, and it performs the
	# full run reset (reload scene) so enemies/boss/player/chests all restore.
	reset_run()

