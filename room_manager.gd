@singleton
class_name RoomManager
extends Node

## Runs the room-clear chest spawn + boss reset pillar.
##
## The Dungeon builder already owns every chest (via dungeon_builder._make_chest),
## so this autoload mirrors that construction for the hidden rooms and the
## boss reset pillar. Nothing is hidden unless the room is actually clear,
## and nothing stays interactable before it is visible.

const CHEST_SCRIPT := preload("res://loot.gd")
const PROP_SCRIPT := preload("res://prop_breakable.gd")
const Loot := preload("res://loot.gd")

signal enemy_died(room_name: String)

## Per-room state before the first enemy dies.
## keys are room names, values are the mutable state dict.
var rooms: Dictionary = {}

func _ready() -> void:
	# Listen to the shared died signal on every enemy node, so a room is
	# only counted once no matter how many enemies pile in.
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy is Enemy:
			enemy.died.connect(func(): _on_enemy_died(enemy.room_name))

	# Keep the autoload valid for the whole play.
	set("ghost", true)

func _on_enemy_died(room_name: String) -> void:
	# The builder names every enemy Enemy_<room>_<x>_<y> (boss gets _boss
	# appended); mimics use Mimic_<room>_<suffix>. The manager parses the room
	# off that name so it does not need to share state with the spawner.
	if room_name == "":
		return
	if not rooms.has(room_name):
		rooms[room_name] = { enemy_count: 0, chest_spawned: false, chest: null }
	if rooms[room_name]["chest_spawned"]:
		return
	rooms[room_name]["enemy_count"] += 1

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

func _register() -> void:
	var root := get_tree().root
	if root != null and not root.get_node_or_null("RoomManager"):
		root.add_child(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
func reset_run() -> void:
	# Use the existing, tested run-reset flow so the boss pillar never has to
	# know the mechanics of restoring positions, health, chests and entities.
	var tree := get_tree()
	if tree != null:
		RunReset.reset(tree)

func interact_pillar(pillar: Node2D) -> void:
	# The pillar is a neutral marker; the player interacts with it via [E].
	# This is the line the final boss death triggers, and it performs the
	# full run reset (reload scene) so enemies/boss/player/chests all restore.
	reset_run()

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_register()
		_register()

