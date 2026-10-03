extends Area2D
## Wakes every enemy in one room when the player walks in.
##
## Deliberately one-shot from the player's point of view but NOT toggling: the
## trigger fires on entry, calls activate() on its room's enemies, and that is
## it. Whether an individual enemy later gives up is the leash's decision, in
## enemy.gd - if the trigger switched enemies back off it would fight the leash
## and the two would flap.

## The room this trigger guards. Set by EnemySpawner before the node is added.
@export var room_name := ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.has_method("take_damage"):
		return
	var woke := 0
	for enemy in _room_enemies():
		if not enemy.active:
			enemy.activate()
			woke += 1
	if woke > 0:
		print("trigger %s woke %d enemy/enemies" % [room_name, woke])


## The enemies belonging to this room, matched by the name the spawner gave
## them rather than by walking the whole tree.
func _room_enemies() -> Array:
	var out: Array = []
	var root := get_tree().current_scene
	if root == null:
		return out
	var marker := "Enemy_%s_" % room_name
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if str(enemy.name).begins_with(marker):
			out.append(enemy)
	return out