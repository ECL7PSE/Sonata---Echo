extends SceneTree

## Headless check for cursed chests.
##
## One chest per floor bites: it is tinted purple, it costs the player a heart
## when it is slashed, and it pays double. The seed is pinned before the scene
## boots so the same floor always produces the same cursed chest.

var _fails: Array[String] = []

var _frames_left := 0
var _stage := 0
var _main: Node
var _player: Node2D
var _chest: Node2D
var _chest_sprite: AnimatedSprite2D
var _health_before := 0
var _expected_coins := 0
var _seed_used := 4242


func _initialize() -> void:
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_fails.append("no GameState autoload")
		_finish()
		return
	gs.set("run_seed", _seed_used)
	gs.set("depth", 1)
	_main = load("res://scenes/Main.tscn").instantiate()


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
				_player.set_physics_process(false)
				_chest = _find_cursed(_main)
				if _chest == null:
					_fails.append("this floor has no cursed chest")
					_finish()
					return true
				_chest_sprite = _chest.get_node_or_null("Sprite")
				if _chest_sprite == null:
					_fails.append("the cursed chest has no Sprite")
				else:
					var tint: Color = _chest_sprite.modulate
					print("cursed tint    : %s" % tint)
					if tint.r >= tint.b:
						_fails.append("the cursed chest must be tinted purple so "
							+ "the player can see the risk before swinging")
				_health_before = int(_player.get("health"))
				_expected_coins = int(_chest.get("coin_count")) * 2
				print("cursed chest   : %s  coins=%d  health=%d"
					% [_chest.name, _expected_coins, _health_before])
				_player.global_position = _chest.global_position
				_frames_left = 4
				_stage = 2
		2:
			_frames_left -= 1
			if _frames_left <= 0:
				_attack(_player)
				_frames_left = 8
				_stage = 3
		3:
			_frames_left -= 1
			if _frames_left <= 0:
				_check_result()
				_finish()
				return true
	return false


func _check_result() -> void:
	if _chest_sprite == null or _chest_sprite.animation == "idle":
		_fails.append("the cursed chest did not open")
	if not bool(_chest.get("opened")):
		_fails.append("the cursed chest must remember that it was opened")
	var health := int(_player.get("health"))
	if health != _health_before - 2:
		_fails.append("the curse must cost 2 health (was %d, now %d)"
			% [_health_before, health])
	var coins := 0
	var props := _main.get_node_or_null("Dungeon/Props")
	if props != null:
		for child in props.get_children():
			if str(child.name).begins_with("Coin"):
				coins += 1
	print("cursed payout  : %d coin(s)" % coins)
	if coins != _expected_coins:
		_fails.append("a cursed chest must pay double (%d wanted, %d got)"
			% [_expected_coins, coins])


func _find_player(main: Node) -> Node2D:
	return main.get_node_or_null("Player(CharacterBody2D)") as Node2D


func _find_cursed(main: Node) -> Node2D:
	var props := main.get_node_or_null("Dungeon/Props")
	if props == null:
		return null
	for child in props.get_children():
		if str(child.name).begins_with("Chest_") and bool(child.get("cursed")):
			return child as Node2D
	return null


func _attack(player: Node2D) -> void:
	var attack := player.get_node_or_null("AttackArea(Area2D)") as Area2D
	if attack == null:
		return
	var shape := attack.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.set_deferred("disabled", false)


func _finish() -> void:
	if _main != null:
		_main.queue_free()
	print("")
	if _fails.is_empty():
		print("RESULT: OK - the cursed chest bites and pays double")
		quit(0)
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL")
		quit(1)
