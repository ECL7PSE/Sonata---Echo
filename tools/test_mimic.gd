extends SceneTree
## Checks dormant mimic waking, stationary animation, and shared duel interaction.
##
##   godot --headless --path . --script res://tools/test_mimic.gd

const DB := preload("res://scripts/enemies/monster_db.gd")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const MIMIC_SCRIPT := preload("res://scripts/enemies/mimic.gd")

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
	if player == null:
		_ok(false, "Main has no player")
		_report()
		return

	var mimic: Variant = _make_mimic(main, player, Vector2(10000.0, 10000.0))
	for _frame in 2:
		await process_frame
	var areas := 0
	for child in mimic.get_children():
		if child is Area2D:
			areas += 1
	_ok(areas == 1, "mimic has %d Area2D nodes instead of one" % areas)
	_ok(mimic.interaction_shape.shape is CircleShape2D,
			"dormant mimic does not use its proximity interaction shape")
	_ok(mimic.chain == MIMIC_SCRIPT.Chain.DORMANT,
			"new mimic did not start dormant")

	var health: int = mimic.health
	var velocity: Vector2 = player.velocity
	var position: Vector2 = mimic.global_position
	var attack_area := player.get_node("AttackArea(Area2D)") as Area2D
	mimic._on_interaction_area_entered(attack_area)
	_ok(mimic.chain == MIMIC_SCRIPT.Chain.OPENING,
			"slash did not wake the dormant mimic")
	_ok(mimic.health == health, "slash damaged the dormant mimic")
	_ok(player.velocity == velocity, "mimic awakening pushed the player")

	mimic._process(MIMIC_SCRIPT.OPENING_TIME)
	mimic._process(MIMIC_SCRIPT.HOLD_TIME + 0.01)
	mimic._process(MIMIC_SCRIPT.TRANSFORM_TIME + 0.01)
	mimic._process(MIMIC_SCRIPT.SETTLE_TIME + 0.01)
	_ok(mimic.chain == MIMIC_SCRIPT.Chain.AWAKE,
			"mimic did not finish its wake sequence")
	_ok(mimic.active and mimic.state == MIMIC_SCRIPT.State.IDLE,
			"awake mimic is not stationary and interactable")
	_ok(mimic.global_position.is_equal_approx(position),
			"mimic moved during its wake sequence")
	_ok(player.velocity == velocity, "mimic wake sequence changed player velocity")
	_ok(mimic.interaction_shape.shape is RectangleShape2D,
			"awake mimic did not restore its interaction bounds")

	mimic._player_in_range = true
	mimic._process(0.0)
	_ok(mimic._prompt.visible, "awake mimic prompt is hidden in range")
	_ok(mimic._prompt.text == "E to fight",
			"mimic prompt text is '%s'" % mimic._prompt.text)
	_ok(mimic._prompt.scale.is_equal_approx(Vector2.ONE * 0.5),
			"mimic prompt is not scaled to 0.5")
	var before_duel_slash: int = mimic.health
	mimic._on_interaction_area_entered(attack_area)
	_ok(mimic.health == before_duel_slash,
			"awake mimic slash damaged it outside the rhythm duel")

	_report()


func _make_mimic(parent: Node, player: Node2D, at: Vector2) -> Variant:
	var mimic: Variant = ENEMY_SCENE.instantiate()
	mimic.set_script(MIMIC_SCRIPT)
	mimic.data = DB.MIMIC
	mimic.species = "mimic"
	mimic.player = player
	mimic.position = at
	parent.add_child(mimic)
	return mimic


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
