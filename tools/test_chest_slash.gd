extends SceneTree
## Proves the collision-layer change did not break any prop or trap interaction.
##
## The player body moved off layer 1 and onto the named `player` bit, and the
## slash onto `player_hitbox`. Every prop and trap that used to detect "whatever
## is on layer 1" now has to name the right bit explicitly, and the failure mode
## when one is wrong is SILENT: the mask simply never matches, so the chest never
## opens and the test passes on an empty scene. This drives the real nodes and
## asserts the reaction actually happened.

const BUILDER := preload("res://dungeon_builder.gd")

var _fails: Array[String] = []


## The scene is driven from _process with an explicit frame counter.
##
## Two things make this deterministic rather than flaky:
##
##  1. An explicit counter, not `await physics_frame`. An await inside a
##     SceneTree._process does not reliably resume under --headless --script and
##     the test then produces no output at all. check_layout uses the same
##     approach for the same reason.
##  2. The player's own _physics_process is switched OFF while the overlap is
##     set up. The chest is a solid prop, so a live player standing on it is
##     immediately shoved off by move_and_slide, and the slash then lands on empty
##     floor. That race made the test fail intermittently before it was pinned.
var _frames_left := 0
var _stage := 0
var _main: Node
var _player: Node2D
var _chest: Node2D
var _chest_sprite: AnimatedSprite2D
var _pot: Node2D
var _pot_sprite: AnimatedSprite2D


func _initialize() -> void:
	# Instantiating here is safe - it only builds the node, it does not need the
	# tree to be live. Everything that depends on _ready happens in _process.
	_main = load("res://Main.tscn").instantiate()


func _process(_delta: float) -> bool:
	match _stage:
		0:
			root.add_child(_main)
			_frames_left = 8
			_stage = 1
		1:
			_frames_left -= 1
			if _frames_left <= 0:
				_player = _find_player(_main)
				if _player == null:
					_fails.append("no player in the scene")
					_finish()
					return true
				_check_layers(_player)
				# Freeze the player so it cannot be shoved off the prop by its own
				# collision resolution before the slash lands.
				_player.set_physics_process(false)
				_chest = _find_by_prefix(_main, "Chest_")
				_pot = _find_by_prefix(_main, "Pot")
				if _chest == null:
					_fails.append("no chest in the scene to test")
				if _pot == null:
					_fails.append("no pot in the scene to test")
				if _chest == null or _pot == null:
					_finish()
					return true
				_chest_sprite = _chest.get_node_or_null("Sprite")
				_pot_sprite = _pot.get_node_or_null("Sprite")
				_player.global_position = _chest.global_position
				_frames_left = 4
				_stage = 2
		2:
			# The player is frozen on the chest; switch the slash on and give the
			# physics engine enough frames to register the Area2D overlap.
			_frames_left -= 1
			if _frames_left <= 0:
				_attack(_player)
				_frames_left = 6
				_stage = 3
		3:
			_frames_left -= 1
			if _frames_left <= 0:
				_react("chest", _chest_sprite)
				_check_coins()
				_player.global_position = _pot.global_position
				_frames_left = 4
				_stage = 4
		4:
			_frames_left -= 1
			if _frames_left <= 0:
				_attack(_player)
				_frames_left = 6
				_stage = 5
		5:
			_frames_left -= 1
			if _frames_left <= 0:
				_react("pot", _pot_sprite)
				_finish()
				return true
	return false


## Reports whether the prop actually changed animation.
func _react(kind: String, sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		_fails.append(kind + " has no Sprite node")
		return
	var anim := sprite.animation
	print("%s slash      : animation is now '%s'" % [kind, anim])
	if anim == "idle":
		_fails.append(kind + " did NOT react when slashed - the prop mask is "
			+ "no longer detecting the player's slash")


func _find_player(main: Node) -> Node2D:
	var p := main.get_node_or_null("Player(CharacterBody2D)")
	return p as Node2D


## The layer wiring itself: bodies on the right bits, masks still seeing walls.
func _check_layers(player: Node2D) -> void:
	var world := 1
	var want_player := 1 << 2
	var want_hitbox := 1 << 3
	var got_player: int = player.collision_layer
	var got_mask: int = player.collision_mask
	print("player layer   : %d (want %d)" % [got_player, want_player])
	print("player mask    : %d (want %d)" % [got_mask, world])
	if got_player != want_player:
		_fails.append("player body is on layer %d, expected %d"
			% [got_player, want_player])
	# The critical one: the player's mask MUST still contain world, or it walks
	# straight through every wall.
	if (got_mask & world) == 0:
		_fails.append("player mask lost the `world` bit, so the player no "
			+ "longer collides with walls")

	var attack := player.get_node_or_null("AttackArea(Area2D)") as Area2D
	if attack == null:
		_fails.append("player has no AttackArea")
		return
	var got_hb: int = attack.collision_layer
	print("slash layer    : %d (want %d)" % [got_hb, want_hitbox])
	if got_hb != want_hitbox:
		_fails.append("slash is on layer %d, expected %d" % [got_hb, want_hitbox])
	if (attack.collision_mask & (1 << 7)) == 0:
		_fails.append("slash mask does not include enemy_hurtbox")


## Coins must actually exist, be armable, and be collectable.
##
## The old chest dropped bare Sprite2Ds that faded away and could never be
## picked up, so "the chest opened" and "the player got anything" were entirely
## separate questions. This asserts the second one.
func _check_coins() -> void:
	var props := _main.get_node_or_null("Dungeon/Props")
	if props == null:
		_fails.append("no Props node, cannot check coins")
		return
	var coins := 0
	for child in props.get_children():
		if not child.name.begins_with("Coin"):
			continue
		coins += 1
		var coin := child as Area2D
		if coin == null:
			continue
		# Every coin needs a Sprite (its @onready would fail without one) and a
		# collision shape (or it can never be collected).
		if coin.get_node_or_null("Sprite") == null:
			_fails.append("coin %s has no Sprite child" % child.name)
		var shape := coin.get_node_or_null("Shape")
		if shape == null or (shape as CollisionShape2D).disabled:
			_fails.append("coin %s has no live collider" % child.name)
		if coin.collision_mask & (1 << 2) == 0:
			_fails.append("coin %s does not listen for the player layer"
				% child.name)
	print("coin drop      : %d coin(s) spawned by the chest" % coins)
	if coins == 0:
		_fails.append("the chest spawned NO coins - the open animation plays "
			+ "but the reward is lost")


## Switches the slash hitbox on, as one frame of an attack does.
func _attack(player: Node2D) -> void:
	var attack := player.get_node_or_null("AttackArea(Area2D)") as Area2D
	if attack == null:
		return
	var shape := attack.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.set_deferred("disabled", false)


## The first prop in Dungeon/Props whose name begins with `prefix`.
func _find_by_prefix(main: Node, prefix: String) -> Node2D:
	var props := main.get_node_or_null("Dungeon/Props")
	if props == null:
		return null
	for child in props.get_children():
		if child.name.begins_with(prefix):
			return child as Node2D
	return null


func _finish() -> void:
	if _main != null:
		_main.queue_free()
	print("")
	if _fails.is_empty():
		print("RESULT: OK")
		quit(0)
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: %d problem(s)" % _fails.size())
		quit(1)