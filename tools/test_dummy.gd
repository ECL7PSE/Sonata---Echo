extends "res://damageable.gd"
## A bare stand-in for the player, used by the damage tests.
##
## Damageable is the shared base and every rule under test lives in it, so a
## CharacterBody2D extending it is enough. The tests need no scene, no physics
## and no frames for i-frames, the health signal, death and the heart maths.

## Set by the death test so a respawn can be observed without a dungeon.
var respawned := false
## Counts damage numbers instead of spawning them into a scene.
var damage_numbers := 0


func _die() -> void:
	_dying = true
	respawned = true
	died.emit()


func _spawn_damage_number(_amount: int, _source: Vector2) -> void:
	damage_numbers += 1