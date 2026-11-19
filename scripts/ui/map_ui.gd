extends CanvasLayer
## Parchment map overlay: the rooms you have walked into, drawn from the
## dungeon builder's room table. Built out of plain rects, no textures.
##
## Owned by SaveManager so Tab works anywhere; the bench opens the same one.

signal closed

const GothUI := preload("res://scripts/ui/gothic_ui.gd")
const BUILDER_PATH := "res://scripts/world/dungeon_builder.gd"

## Screen pixels per dungeon grid cell on the parchment.
const CELL := 12.0

var _panel: Panel
var _board: Control
var _legend: Label
var _i_paused := false


func _ready() -> void:
	layer = 34
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputMap.has_action("map"):
		InputMap.add_action("map")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_TAB
		InputMap.action_add_event("map", ev)
	_build()


func open(pause := false) -> void:
	_build()
	_refresh()
	visible = true
	if pause and not get_tree().paused:
		get_tree().paused = true
		_i_paused = true


func close() -> void:
	visible = false
	if _i_paused:
		get_tree().paused = false
		_i_paused = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open(true)


func _build() -> void:
	if _panel != null:
		return
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -300
	_panel.offset_right = 300
	_panel.offset_top = -300
	_panel.offset_bottom = 300
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	GothUI.dress(_panel, 12)
	add_child(_panel)

	var title := GothUI.label("MAP", 32, GothUI.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.offset_top = 18
	title.offset_bottom = 62
	_panel.add_child(title)

	# Parchment: 43 grid cells at 12 px = 516 px, centred in the panel.
	var parchment := ColorRect.new()
	parchment.color = Color("#2b221a")
	parchment.position = Vector2(42, 74)
	parchment.size = Vector2(516, 516)
	parchment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(parchment)

	_board = Control.new()
	_board.position = parchment.position
	_board.size = parchment.size
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_board)

	_legend = GothUI.label("cyan = you    gold = bench    X = the way down", 12, GothUI.DIM)
	_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legend.anchor_right = 1.0
	_legend.offset_top = 592
	_legend.offset_bottom = 614
	_panel.add_child(_legend)

	var btn := GothUI.close_button(40.0)
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.offset_left = -76
	btn.offset_right = -36
	btn.offset_top = 26
	btn.offset_bottom = 66
	btn.pressed.connect(close)
	_panel.add_child(btn)


## Rebuilds the parchment from GameState.explored and the live player.
func _refresh() -> void:
	for c in _board.get_children():
		c.queue_free()
	var script = load(BUILDER_PATH)
	if script == null:
		return
	var builder = script.new()
	var rooms: Dictionary = builder.ROOMS
	# Through /root so this script compiles in --script tools too.
	var state := get_node_or_null("/root/GameState")
	var explored: Array = state.get("explored") if state != null else []
	var bell: bool = bool(state.call("echo_on", "grave_bell")) if state != null else false

	for room_name in rooms:
		if not (room_name in explored):
			continue
		var r: Rect2i = rooms[room_name]
		var box := Rect2(Vector2(r.position) * CELL, Vector2(r.size) * CELL)
		_rect(box, GothUI.BORDER)
		_rect(box.grow(-2.0), Color("#3a2e22"))
		if room_name == "bone_hall":
			_label("X", box, GothUI.CRIMSON, 14)
		if bell:
			var left := _enemies_left(room_name)
			_label(str(left), box, GothUI.TEXT, 12)

	var start: Variant = _player_start()
	if start != null:
		var s := Vector2(start) / (float(builder.GRID) * float(builder.SCALE)) * CELL
		_dot(s, Color("#ffd166"))

	var player := _find_player()
	if player != null:
		var p := player.global_position / (float(builder.GRID) * float(builder.SCALE)) * CELL
		_dot(p, GothUI.CYAN)

	builder.free()


func _rect(box: Rect2, color: Color) -> void:
	var c := ColorRect.new()
	c.color = color
	c.position = box.position
	c.size = box.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(c)


func _dot(cell: Vector2, color: Color) -> void:
	var c := ColorRect.new()
	c.color = color
	c.position = cell - Vector2(3, 3)
	c.size = Vector2(6, 6)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(c)


func _label(text: String, box: Rect2, color: Color, size: int) -> void:
	var l := GothUI.label(text, size, color)
	l.position = box.position
	l.size = box.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(l)


func _enemies_left(room_name: String) -> int:
	if not is_inside_tree():
		return 0
	var marker := "Enemy_%s_" % room_name
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if str(e.name).begins_with(marker):
			n += 1
	return n


## PlayerStart of the current floor, in world pixels.
func _player_start() -> Variant:
	if not is_inside_tree():
		return null
	var cs := get_tree().current_scene
	if cs == null:
		return null
	var node := cs.find_child("PlayerStart", true, false) as Node2D
	if node == null:
		return null
	return node.global_position


func _find_player() -> Node2D:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node2D:
			return n
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
