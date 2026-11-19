extends CanvasLayer

## The way down: three doors, one floor each.
##
## Shown when a floor is cleared instead of dropping the player straight down.
## The pick is written to GameState.floor_choice and read by the next floor when
## it builds, so each door changes what you land in.

const GothUI := preload("res://scripts/ui/gothic_ui.gd")
const RunReset := preload("res://scripts/core/run_reset.gd")

const DOORS := [
	{"id": "combat", "name": "COMBAT", "note": "every coin counts double"},
	{"id": "hoard", "name": "HOARD", "note": "chests carry twice the gold"},
	{"id": "rest", "name": "REST", "note": "the floor saves your run"},
]

const W := 660.0
const H := 400.0

var _picked := false


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_tree().paused = true


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -W * 0.5
	panel.offset_right = W * 0.5
	panel.offset_top = -H * 0.5
	panel.offset_bottom = H * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	GothUI.dress(panel, 12)
	add_child(panel)

	var title := GothUI.label("THE WAY DOWN", 32, GothUI.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.offset_top = 26
	title.offset_bottom = 74
	panel.add_child(title)

	var rule := ColorRect.new()
	rule.color = GothUI.BORDER
	rule.position = Vector2(140, 84)
	rule.size = Vector2(W - 280.0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rule)

	# Three doors, side by side.
	var gap := 24.0
	var bw := (W - 2.0 * 60.0 - gap * 2.0) / 3.0
	for i in DOORS.size():
		var door: Dictionary = DOORS[i]
		var x := 60.0 + float(i) * (bw + gap)

		var btn := GothUI.make_button(str(door.name), Vector2(bw, 120.0), 20)
		btn.position = Vector2(x, 130.0)
		btn.pressed.connect(_pick.bind(str(door.id)))
		panel.add_child(btn)

		var note := GothUI.label(str(door.note), 13, GothUI.DIM)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.position = Vector2(x, 262.0)
		note.size = Vector2(bw, 44.0)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(note)


func _pick(id: String) -> void:
	if _picked:
		return
	_picked = true
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.set("floor_choice", id)
		if id == "rest":
			state.set("pending_save", true)
	get_tree().paused = false
	RunReset.descend(get_tree())
