extends Node

## Run persistence: a bench rest is the checkpoint. Coins/upgrades live in
## GameState; this only stores where the run is.

signal saved

const PATH := "user://run.save"

var has_run := false
var seed_value := 0
var depth := 1
var health := 10
var max_health := 10
var scene := "res://scenes/Main.tscn"
var pos := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_save()


var _bench: Node = null
var _map: Node = null
var _applied_scene := ""
var _hooked_player: Node = null


## Polled instead of tree_changed: the signal also fires during teardown, when
## get_tree() is already gone.
func _process(_delta: float) -> void:
	_ensure_map()
	if _bench != null and is_instance_valid(_bench) and _hooked_player != null \
			and is_instance_valid(_hooked_player) and _applied_scene != "":
		return
	_maybe_spawn_bench()


## The map overlay lives here so Tab works in every room without a HUD to own
## it. Created only once a floor with a player is up, never over the menu.
func _ensure_map() -> void:
	if _map != null and is_instance_valid(_map):
		return
	if not is_inside_tree() or get_tree().current_scene == null:
		return
	if _find_player(get_tree().current_scene) == null:
		return
	_map = load("res://scripts/ui/map_ui.gd").new()
	add_child(_map)


func toggle_map() -> Node:
	_ensure_map()
	if _map != null and is_instance_valid(_map):
		_map.toggle()
		return _map
	return null


func _maybe_spawn_bench() -> void:
	if not is_inside_tree():
		return
	var cs := get_tree().current_scene
	if cs == null or not (cs is Node2D):
		return
	_apply_if_needed(cs)
	if _bench != null and is_instance_valid(_bench):
		return
	var start := cs.find_child("PlayerStart", true, false) as Node2D
	if start == null:
		return
	var b = load("res://scripts/world/bench.gd").new()
	b.position = start.position + Vector2(56, 0)
	cs.add_child(b)
	_bench = b


func _apply_if_needed(cs: Node) -> void:
	var p := _find_player(cs)
	if p == null:
		return
	# The death hook is not a save feature: a run that never rested still has to
	# end. Hook whichever player is alive, once per instance.
	if p != _hooked_player and p.has_signal("died"):
		p.died.connect(on_death)
		_hooked_player = p
	if not has_run or _applied_scene == cs.scene_file_path:
		return
	_applied_scene = cs.scene_file_path
	apply_to_player(p)


func _find_player(n: Node) -> Node:
	if n is CharacterBody2D and n.has_method("do_attack") and n.has_signal("health_changed"):
		return n
	for c in n.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null


func save_run(player: Node) -> void:
	if player == null:
		return
	seed_value = GameState.run_seed
	depth = GameState.depth
	health = int(player.get("health"))
	max_health = int(player.get("max_health"))
	pos = player.global_position
	scene = get_tree().current_scene.scene_file_path
	if scene.is_empty():
		scene = "res://scenes/Main.tscn"

	var cfg := ConfigFile.new()
	cfg.set_value("run", "seed", seed_value)
	cfg.set_value("run", "depth", depth)
	cfg.set_value("run", "health", health)
	cfg.set_value("run", "max_health", max_health)
	cfg.set_value("run", "pos", pos)
	cfg.set_value("run", "scene", scene)
	cfg.set_value("run", "coins", GameState.coins)
	cfg.set_value("run", "upgrades", GameState.upgrades)
	cfg.set_value("run", "echoes_owned", GameState.echoes_owned)
	cfg.set_value("run", "echoes_equipped", GameState.echoes_equipped)
	cfg.set_value("run", "explored", GameState.explored)
	cfg.save(PATH)
	has_run = true
	saved.emit()


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		has_run = false
		return
	has_run = true
	seed_value = int(cfg.get_value("run", "seed", 0))
	depth = int(cfg.get_value("run", "depth", 1))
	GameState.run_seed = seed_value
	GameState.depth = depth
	health = int(cfg.get_value("run", "health", 10))
	max_health = int(cfg.get_value("run", "max_health", 10))
	pos = cfg.get_value("run", "pos", Vector2.ZERO)
	scene = str(cfg.get_value("run", "scene", "res://scenes/Main.tscn"))
	GameState.coins = int(cfg.get_value("run", "coins", 0))
	var up = cfg.get_value("run", "upgrades", {})
	if up is Dictionary:
		for k in ["hp", "atk", "spd"]:
			GameState.set_upgrade(k, int(up.get(k, 0)))
	GameState.echoes_owned = _strings(cfg.get_value("run", "echoes_owned", []))
	GameState.echoes_equipped = _strings(cfg.get_value("run", "echoes_equipped", []))
	GameState.explored = _strings(cfg.get_value("run", "explored", []))
	GameState.echoes_changed.emit()


## Typed copy of an untyped value read back from a ConfigFile.
func _strings(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for v in value:
			out.append(str(v))
	return out


func clear_save() -> void:
	has_run = false
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## Applies the loaded run to a freshly spawned player.
func apply_to_player(player: Node) -> void:
	if player == null:
		return
	if max_health > 0:
		player.set("max_health", max_health)
		player.set("health", clampi(health, 1, max_health))
	player.global_position = pos
	if player.has_signal("health_changed"):
		player.emit_signal("health_changed", int(player.get("health")), int(player.get("max_health")))


## Roguelike death: keep upgrades and echoes, lose the run's coins and the
## checkpoint, and drop back to a fresh run. Dead Man's Toll keeps a quarter.
func on_death() -> void:
	var keep := 0
	if GameState.echo_on("dead_mans_toll"):
		keep = int(float(GameState.coins) * 0.25)
	GameState.reset()
	if keep > 0:
		GameState.add_coins(keep)
	clear_save()
	_applied_scene = ""
	_hooked_player = null
	if is_inside_tree():
		get_tree().call_deferred("reload_current_scene")
