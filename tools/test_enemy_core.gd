extends SceneTree
## Checks enemy clusters, centered spawns, prompts, and stationary world behavior.
##
##   godot --headless --path . --script res://tools/test_enemy_core.gd

const ENEMY_SCRIPT := preload("res://scripts/enemies/enemy.gd")
const MIMIC_SCRIPT := preload("res://scripts/enemies/mimic.gd")
const SPAWNER := preload("res://scripts/enemies/enemy_spawner.gd")

var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	for _frame in 8:
		await process_frame

	var player := main.get_node_or_null("Player(CharacterBody2D)") as Node2D
	var dungeon: Variant = main.get_node_or_null("Dungeon")
	_ok(player != null, "Main has no player")
	_ok(dungeon != null, "Main has no dungeon")
	if player == null or dungeon == null:
		_report()
		return

	var enemies: Array = get_nodes_in_group("enemies")
	var ordinary: Array = []
	var boss: Variant = null
	var by_room: Dictionary = {}
	for enemy in enemies:
		var cell := Vector2i(int(floor(enemy.position.x / 16.0)),
				int(floor(enemy.position.y / 16.0)))
		var room_name := ""
		for candidate in dungeon.ROOMS:
			if dungeon.ROOMS[candidate].has_point(cell):
				room_name = candidate
				break
		_ok(room_name != "", "%s is outside every room at %s" % [enemy.name, cell])
		if room_name == "":
			continue
		by_room[room_name] = int(by_room.get(room_name, 0)) + 1
		var room: Rect2i = dungeon.ROOMS[room_name]
		var centre := Vector2(room.position) * 16.0 + Vector2(room.size) * 8.0
		_ok(enemy.position.is_equal_approx(centre),
				"%s at %s is not at %s room centre %s"
						% [enemy.name, enemy.position, room_name, centre])
		var areas := 0
		for child in enemy.get_children():
			if child is Area2D:
				areas += 1
		_ok(areas == 1, "%s has %d interaction areas" % [enemy.name, areas])
		_ok(enemy.get_node_or_null("Hitbox") == null,
				"%s still has an overworld attack hitbox" % enemy.name)
		_ok(enemy.get_node_or_null("Hurtbox") == null,
				"%s still has a separate slash damage hurtbox" % enemy.name)
		var expected := int(ENEMY_SCRIPT.SPRITES_PER_SPECIES.get(
				enemy.species.to_upper(), 1))
		_ok(enemy._visual_sprites.size() == expected,
				"%s has %d sprites, expected %d" % [
				enemy.name, enemy._visual_sprites.size(), expected])
		var scale_factor := float(ENEMY_SCRIPT.SCALE_BY_SPRITE_COUNT[expected])
		var scale_used := float(enemy.data["scale"]) * scale_factor
		if enemy.boss:
			scale_used *= ENEMY_SCRIPT.BOSS_ENEMY_SCALE
		_ok(is_equal_approx(enemy._scale, scale_used),
				"%s has scale %.3f, expected %.3f"
						% [enemy.name, enemy._scale, scale_used])
		var body_size: Vector2i = enemy.data.get("body", Vector2i(16, 16))
		var expected_gap: float = maxf(ENEMY_SCRIPT.SPRITE_SPACING,
				float(body_size.x) + 4.0) * enemy._scale
		_ok(is_equal_approx(enemy._sprite_gap, expected_gap),
				"%s sprite spacing does not follow its scale" % enemy.name)
		if enemy.get_script() != MIMIC_SCRIPT:
			var interaction_rect := enemy.interaction_shape.shape \
					as RectangleShape2D
			var expected_area := Vector2(
					enemy._cluster_width + ENEMY_SCRIPT.INTERACTION_PADDING * 2.0,
					enemy._body_h + ENEMY_SCRIPT.INTERACTION_PADDING * 2.0)
			_ok(interaction_rect.size.is_equal_approx(expected_area),
					"%s interaction area does not fit its sprite cluster"
							% enemy.name)
			var body_rect := enemy.body_shape.shape as RectangleShape2D
			var expected_body := Vector2(enemy._body_w * 0.7,
					enemy._body_h * 0.55)
			_ok(body_rect.size.is_equal_approx(expected_body),
					"%s body collider does not match its final scale"
							% enemy.name)
		if dungeon.CHEST_BY_ROOM.has(room_name):
			var clearance: float = dungeon._enemy_chest_clearance_px(
					enemy, dungeon.CHEST_BY_ROOM[room_name])
			_ok(clearance >= dungeon.CHEST_ENEMY_CLEARANCE,
					"%s chest clearance is %.1fpx, need %.1fpx"
							% [enemy.name, clearance,
							dungeon.CHEST_ENEMY_CLEARANCE])
			if enemy.get_script() == MIMIC_SCRIPT:
				enemy._apply_awake_shapes()
				var awake_clearance: float = dungeon._enemy_chest_clearance_px(
						enemy, dungeon.CHEST_BY_ROOM[room_name])
				_ok(awake_clearance >= dungeon.CHEST_ENEMY_CLEARANCE,
						"%s awake chest clearance is %.1fpx, need %.1fpx"
								% [enemy.name, awake_clearance,
								dungeon.CHEST_ENEMY_CLEARANCE])
		if enemy.boss:
			boss = enemy
		elif enemy.get_script() == ENEMY_SCRIPT:
			ordinary.append(enemy)

	var expected_rooms: Array = SPAWNER.ROOM_MONSTER.keys()
	expected_rooms.append_array(SPAWNER.MIMIC_DENS.keys())
	for room_name in dungeon.ROOMS:
		var expected_count := 1 if expected_rooms.has(room_name) else 0
		_ok(int(by_room.get(room_name, 0)) == expected_count,
				"%s has %d enemy entities, expected %d"
						% [room_name, int(by_room.get(room_name, 0)),
						expected_count])
	_ok(not ordinary.is_empty(), "the dungeon has no ordinary enemies")
	_ok(InputMap.has_action("interact"), "the bench interaction action is missing")

	var flyer: Variant = null
	for enemy in enemies:
		if ENEMY_SCRIPT.SPRITES_PER_SPECIES.has(enemy.species.to_upper()):
			if enemy.species.to_upper() == "BAT" \
					or enemy.species.to_upper() == "FLYING_EYE":
				flyer = enemy
				break
	if flyer != null:
		var flyer_position: Vector2 = flyer.position
		flyer._process(0.5)
		_ok(flyer.position.is_equal_approx(flyer_position),
				"%s bob moved its entity" % flyer.name)
		_ok(not is_zero_approx(flyer.sprite.position.y),
				"%s did not bob its sprite cluster" % flyer.name)

	if boss != null:
		var room: Rect2i = dungeon.ROOMS["bone_hall"]
		var centre := Vector2(room.position) * 16.0 + Vector2(room.size) * 8.0
		_ok(boss.position.is_equal_approx(centre),
				"boss at %s is not at boss-room centre %s"
						% [boss.position, centre])
	else:
		_ok(false, "the boss enemy was not spawned")

	if ordinary.is_empty():
		_report()
		return
	var enemy: Variant = ordinary[0]
	var start: Vector2 = enemy.position
	enemy.activate()
	enemy.velocity = Vector2.ZERO
	enemy._physics_process(1.0)
	_ok(enemy.position.is_equal_approx(start),
			"room activation moved %s" % enemy.name)
	_ok(enemy.velocity == Vector2.ZERO,
			"stationary %s retained movement velocity" % enemy.name)

	enemy.player = player
	enemy._player_in_range = true
	enemy._process(0.0)
	_ok(enemy._prompt.visible, "nearest in-range enemy prompt is hidden")
	_ok(enemy._prompt.scale.is_equal_approx(
			Vector2.ONE * 0.5), "enemy prompt is not scaled to 0.5")
	enemy._player_in_range = false
	enemy._process(0.0)
	_ok(not enemy._prompt.visible, "enemy prompt stayed visible out of range")

	var attack_area := player.get_node("AttackArea(Area2D)") as Area2D
	var health: int = enemy.health
	enemy._on_interaction_area_entered(attack_area)
	_ok(enemy.health == health, "an overworld slash directly damaged an enemy")

	_report()


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_fails.append(message)


func _report() -> void:
	print("")
	print("assertions     : %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK")
		quit(0)
	else:
		for failure in _fails:
			print("FAIL: " + failure)
		print("RESULT: %d problem(s)" % _fails.size())
		quit(1)
