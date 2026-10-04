extends Area2D
## Lootable chest.
##
## The plain breakable prop (prop_breakable.gd) with the one thing a chest has
## and a pot does not: it opens rather than shattering, and it throws coins.
##
## There is deliberately no "[J]" prompt label floating above the chest. It was
## clutter drawn in world space that never went away, it advertised a key the
## chest never needed (the slash opens it, the same as every other prop), and
## "J" is not even the bound action - the attack is bound to "K" in
## project.godot. The chest is discoverable by looking at it.
##
## The player's "AttackArea(Area2D)" is only enabled for the few frames of a
## slash (see character_body_2d.gd), so an overlap here means the player just hit
## the chest. The hit plays the open animation, spawns the gold, then lets the
## chest keep sitting there open - it stays solid so the player cannot walk
## through a chest they have already looted, which also means the object never
## disappears out from under them.

@export var idle_animation := "idle"
@export var open_animation := "open"
@export var coin_count := 5
## The LAST chest in the run. Opening it does not pay out: it sends the player
## back to PlayerStart and puts every enemy back to sleep, which is how the run
## loops instead of ending.
@export var resets_the_run := false
## Frames the chest is vulnerable for after a hit, so one swing cannot loot it
## several times over.
@export var cooldown := 0.6

const SHEET_DIR := "res://Assets/Dungeon/dungeon_V.1.0.0_nyknck/"

const CoinDrop := preload("res://coin_drop.gd")

@onready var sprite: AnimatedSprite2D = $Sprite

var _used := false
var _cooldown_left := 0.0


func _ready() -> void:
	# Props react to the player's SLASH and nothing else. The old setup used the
	# default layer 1 for everything; now the slash is on the `player_hitbox` bit,
	# so the mask has to name it explicitly or the chest silently stops opening.
	collision_layer = Layers.WORLD
	collision_mask = Layers.prop_mask()
	sprite.play(idle_animation)
	area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta


func _on_area_entered(area: Area2D) -> void:
	if _used or _cooldown_left > 0.0 or area == null:
		return
	# Only the player's slash should trigger the chest.
	if not area.get_parent() is CharacterBody2D:
		return
	_used = true
	# chest_open here, and coin_drop ONCE for the whole chest - not once per
	# coin, which would turn a single opening into a dozen overlapping clatters.
	_sfx("chest_open")
	_sfx("coin_drop")
	_cooldown_left = cooldown
	sprite.play(open_animation)
	_spawn_coins()


## Drops the gold through the shared coin system.
##
## This used to spawn bare Sprite2Ds that fanned out and faded away over 0.45s.
## They were never collectable - there was no counter and no collider - so the
## chest gave the player nothing. Now it uses coin_drop.gd, the same helper the
## enemy deaths will use, so a coin from a chest and a coin from a goblin behave
## identically.
func _spawn_coins() -> void:
	if resets_the_run:
		# The last chest is a doorway, not a payout.
		preload("res://run_reset.gd").reset(get_tree())
		return
	var parent := get_parent()
	if parent == null:
		return
	# Deferred, and this matters. _spawn_coins runs from inside an area_entered
	# callback, which is a physics query flush: adding CollisionShape2D nodes at
	# that moment makes the engine throw "Can't change this state while flushing
	# queries" and the coins end up with no collider at all. Waiting a frame sidesteps
	# it entirely.
	CoinDrop.drop.call_deferred(parent, global_position, coin_count, 34.0,
			_floor())


## The dungeon's floor test, so coins bounce off walls instead of through them.
func _floor() -> Callable:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return func(_c: Vector2i) -> bool: return true
	var builder := tree.current_scene.get_node_or_null("Dungeon")
	if builder == null or not builder.has_method("_walkable"):
		return func(_c: Vector2i) -> bool: return true
	var grid: Array = builder.get("_grid")
	return func(c: Vector2i) -> bool: return builder._walkable(grid, c)
## Sound through the Audio autoload, if it is present.
##
## The --script test harnesses boot scenes without autoloads, so call sites go
## through this guard rather than assuming Audio exists.
func _sfx(event: String, at: Variant = null) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("Audio")
	if audio != null:
		audio.call("play", event, at)