extends SceneTree

## Headless check: the bench save system spawns a bench next to PlayerStart.

func _initialize() -> void:
	change_scene_to_file("res://scenes/Main.tscn")
	var frames := 0
	while frames < 30:
		await process_frame
		frames += 1
	var bench := _find_bench(current_scene)
	var start := current_scene.find_child("PlayerStart", true, false) as Node2D
	if bench == null:
		print("RESULT: FAIL - no bench spawned")
		quit(1)
		return
	if start == null:
		print("RESULT: FAIL - no PlayerStart")
		quit(1)
		return
	var d := absf(bench.position.x - start.position.x)
	print("RESULT: OK - bench at %s, PlayerStart at %s" % [bench.position, start.position])
	quit(0 if d <= 120.0 else 1)


func _find_bench(n: Node) -> Node:
	if n == null:
		return null
	if n.get_script() != null and str(n.get_script().resource_path).ends_with("bench.gd"):
		return n
	for c in n.get_children():
		var found := _find_bench(c)
		if found != null:
			return found
	return null
