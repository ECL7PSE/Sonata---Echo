extends CanvasLayer

const FADE_SECONDS := 0.8

var _cover: ColorRect
var _tween: Tween
var _transitioning := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_cover = ColorRect.new()
	_cover.name = "FadeCover"
	_cover.color = Color.BLACK
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.modulate.a = 0.0
	add_child(_cover)


func is_transitioning() -> bool:
	return _transitioning


func change_scene(path: String, on_ready: Callable = Callable()) -> bool:
	if path.is_empty():
		push_error("SceneTransition.change_scene requires a scene path.")
		return false
	return await _run_transition(Callable(), path, on_ready, false)


func run_action(action: Callable, keep_paused := false) -> bool:
	if not action.is_valid():
		push_error("SceneTransition.run_action requires a valid action.")
		return false
	return await _run_transition(action, "", Callable(), keep_paused)


func _run_transition(action: Callable, scene_path: String, on_ready: Callable,
		keep_paused: bool) -> bool:
	if _transitioning:
		return false

	_transitioning = true
	var tree := get_tree()
	var was_paused := tree.paused
	var previous_scene := tree.current_scene
	var previous_mode := Node.PROCESS_MODE_INHERIT
	if previous_scene != null:
		previous_mode = previous_scene.process_mode
		previous_scene.process_mode = Node.PROCESS_MODE_DISABLED
	tree.paused = false
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.visible = true
	await _fade_to(1.0)

	var final_scene := previous_scene
	var final_mode := previous_mode
	if not scene_path.is_empty():
		var error := tree.change_scene_to_file(scene_path)
		if error != OK:
			push_error("Could not change scene to %s (error %d)." % [scene_path, error])
			if is_instance_valid(previous_scene):
				previous_scene.process_mode = previous_mode
			await _fade_to(0.0)
			tree.paused = was_paused
			_finish_transition()
			return false
		await tree.scene_changed
		final_scene = tree.current_scene
		if final_scene != null:
			final_mode = final_scene.process_mode
			final_scene.process_mode = Node.PROCESS_MODE_DISABLED
		if on_ready.is_valid():
			on_ready.call()
	else:
		action.call()
		await tree.process_frame

	await _fade_to(0.0)
	if is_instance_valid(final_scene):
		final_scene.process_mode = final_mode
	tree.paused = keep_paused
	_finish_transition()
	return true


func _fade_to(alpha: float) -> void:
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_cover, "modulate:a", alpha, FADE_SECONDS)
	await _tween.finished


func _finish_transition() -> void:
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false


func _input(_event: InputEvent) -> void:
	if _transitioning:
		get_viewport().set_input_as_handled()
