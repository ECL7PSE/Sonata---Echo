extends CanvasLayer
## Week 8: Web "Click to Start" gate.
## Browsers block audio until a user gesture; this screen provides the
## gesture, then swaps to the real main scene. No gameplay code touched.

const MAIN_SCENE := "res://Main.tscn"

func _ready() -> void:
	($Center/Panel/StartButton as Button).pressed.connect(_on_start)
	($Center/Panel/StartButton as Button).grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") or event.is_action_pressed("ui_accept"):
		_on_start()

func _on_start() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)
