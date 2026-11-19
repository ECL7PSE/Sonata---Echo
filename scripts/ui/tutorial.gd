extends CanvasLayer

## First-run prompts: four one-liners on a timer, then it never comes back.
##
## Spawned by SaveManager on floor 1 until GameState.tutorial_done is set, so a
## returning player who already knows the verbs is never nagged again.

const GothUI := preload("res://scripts/ui/gothic_ui.gd")

const STEPS := [
	"WASD  -  move",
	"F  -  strike",
	"E at the bench  -  it saves your run",
	"TAB  -  map and echoes",
	"Coins buy echoes at the bench",
]
const STEP_TIME := 4.0

var _label: Label
var _step := 0
var _t := 0.0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_show()


func _build() -> void:
	_label = GothUI.label("", 20, GothUI.TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 0.0
	_label.offset_right = 0.0
	_label.offset_top = -84
	_label.offset_bottom = -48
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)


func _show() -> void:
	_label.text = str(STEPS[_step])
	_t = 0.0
	_label.modulate.a = 1.0
	create_tween().tween_property(_label, "modulate:a", 1.0, 0.2).from(0.0)


func _process(delta: float) -> void:
	_t += delta
	# Fade out over the last half second of the step.
	if _t > STEP_TIME - 0.5:
		_label.modulate.a = clampf((STEP_TIME - _t) / 0.5, 0.0, 1.0)
	if _t < STEP_TIME:
		return
	_step += 1
	if _step >= STEPS.size():
		_finish()
	else:
		_show()


func _finish() -> void:
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.set("tutorial_done", true)
	queue_free()
