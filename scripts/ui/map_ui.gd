extends CanvasLayer
## Explorer's ledger: one overlay, two pages.
##
## MAP is the parchment the dungeon builder's room table is drawn onto; ECHOES
## is what you own and are wearing. Tab opens it anywhere in the run, Q and E
## turn the page. SaveManager owns the single instance so the bench and the
## keyboard open the same one.

signal closed

const GothUI := preload("res://scripts/ui/gothic_ui.gd")
const EchoIcon := preload("res://scripts/ui/echo_icon.gd")
const BUILDER_PATH := "res://scripts/world/dungeon_builder.gd"

const PAGE_MAP := 0
const PAGE_ECHOES := 1

## Screen pixels per dungeon grid cell on the parchment.
const CELL := 10.4

var _panel: Panel
var _title: Label
var _map_page: Control
var _echo_page: Control
var _board: Control
var _echoes_box: Control
var _legend: Label
var _worn: Label
var _page := PAGE_MAP
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
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.connect("echoes_changed", Callable(self, "_on_state_changed"))
		state.connect("coins_changed", Callable(self, "_on_state_changed"))


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


## Q/E turn the page, wrapping.
func turn(step: int) -> void:
	_page = wrapi(_page + step, 0, 2)
	_refresh()


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

	_title = GothUI.label("MAP", 32, GothUI.CYAN)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.anchor_right = 1.0
	_title.offset_top = 18
	_title.offset_bottom = 62
	_panel.add_child(_title)

	var close_btn := GothUI.close_button(40.0)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -76
	close_btn.offset_right = -36
	close_btn.offset_top = 26
	close_btn.offset_bottom = 66
	close_btn.pressed.connect(close)
	_panel.add_child(close_btn)

	_build_map_page()
	_build_echo_page()
	_build_tabs()


func _build_map_page() -> void:
	_map_page = Control.new()
	_map_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_map_page)

	# Parchment: the 43x43 grid at CELL px per cell, centred in the panel.
	var board_size := Vector2(43, 43) * CELL
	var parchment := ColorRect.new()
	parchment.color = Color("#2b221a")
	parchment.position = Vector2((600.0 - board_size.x) * 0.5, 74.0)
	parchment.size = board_size
	parchment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_page.add_child(parchment)

	_board = Control.new()
	_board.position = parchment.position
	_board.size = parchment.size
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_page.add_child(_board)

	_legend = GothUI.label("cyan = you    gold = bench    X = the way down", 12, GothUI.DIM)
	_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legend.anchor_right = 1.0
	_legend.offset_top = 528
	_legend.offset_bottom = 548
	_map_page.add_child(_legend)


func _build_echo_page() -> void:
	_echo_page = Control.new()
	_echo_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_echo_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_echo_page.visible = false
	_panel.add_child(_echo_page)

	_worn = GothUI.label("WORN 0/3", 16, GothUI.DIM)
	_worn.position = Vector2(50, 74)
	_worn.size = Vector2(240, 24)
	_echo_page.add_child(_worn)

	_echoes_box = Control.new()
	_echoes_box.position = Vector2(50, 104)
	_echoes_box.size = Vector2(500, 436)
	_echoes_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_echo_page.add_child(_echoes_box)


func _build_tabs() -> void:
	var prev := GothUI.make_button("< Q", Vector2(64, 34), 14)
	prev.position = Vector2(20, 550)
	prev.pressed.connect(turn.bind(-1))
	_panel.add_child(prev)

	var next := GothUI.make_button("E >", Vector2(64, 34), 14)
	next.position = Vector2(516, 550)
	next.pressed.connect(turn.bind(1))
	_panel.add_child(next)

	var hint := GothUI.label("Q / E turn the page    TAB closes", 12, GothUI.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.anchor_right = 1.0
	hint.offset_top = 550
	hint.offset_bottom = 584
	_panel.add_child(hint)


func _refresh() -> void:
	_title.text = "MAP" if _page == PAGE_MAP else "ECHOES"
	_map_page.visible = _page == PAGE_MAP
	_echo_page.visible = _page == PAGE_ECHOES
	if _page == PAGE_MAP:
		_refresh_map()
	else:
		_refresh_echoes()


## Rebuilds the parchment from GameState.explored and the live player.
func _refresh_map() -> void:
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
			_label(str(_enemies_left(room_name)), box, GothUI.TEXT, 12)

	var start: Variant = _player_start()
	if start != null:
		var s := Vector2(start) / (float(builder.GRID) * float(builder.SCALE)) * CELL
		_dot(s, Color("#ffd166"))

	var player := _find_player()
	if player != null:
		var p := player.global_position / (float(builder.GRID) * float(builder.SCALE)) * CELL
		_dot(p, GothUI.CYAN)

	builder.free()


## The three worn slots, then every echo you can wear.
func _refresh_echoes() -> void:
	for c in _echoes_box.get_children():
		c.queue_free()
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	var echoes: Dictionary = state.get("ECHOES")
	var owned: Array = state.get("echoes_owned")
	var worn: Array = state.get("echoes_equipped")
	var slots: int = int(state.get("ECHO_SLOTS"))
	_worn.text = "WORN %d/%d" % [worn.size(), slots]

	# Slots across the top.
	var slot_w := 84.0
	var gap := 16.0
	var total := slots * slot_w + (slots - 1) * gap
	var sx := (500.0 - total) * 0.5
	for i in slots:
		var box := Rect2(Vector2(sx + float(i) * (slot_w + gap), 0.0), Vector2(slot_w, slot_w))
		_plate(box, Color("#241d2c"), GothUI.BORDER_DIM)
		if i < worn.size():
			var icon := EchoIcon.new(str(worn[i]))
			icon.position = box.position + Vector2((slot_w - 52.0) * 0.5, 8)
			icon.size = Vector2(52, 52)
			_echoes_box.add_child(icon)
			var tag := GothUI.label(str(echoes.get(worn[i], {}).get("name", "")), 10, GothUI.CYAN)
			tag.position = box.position + Vector2(0, 62)
			tag.size = Vector2(slot_w, 16)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_echoes_box.add_child(tag)

	# The whole catalogue, two columns of three.
	var ids: Array = echoes.keys()
	for i in ids.size():
		var id := str(ids[i])
		var col := i % 2
		var row := i / 2
		var cell := Rect2(
			Vector2(float(col) * 256.0, slot_w + 26.0 + float(row) * 110.0),
			Vector2(244, 100))
		_add_echo_cell(id, cell, id in owned, id in worn, int(echoes.get(id, {}).get("cost", 0)))


func _add_echo_cell(id: String, cell: Rect2, owned: bool, worn: bool, cost: int) -> void:
	var button := GothUI.make_button("", cell.size, 12)
	button.position = cell.position
	button.pressed.connect(_on_echo_pressed.bind(id))
	_echoes_box.add_child(button)

	var icon := EchoIcon.new(id)
	icon.position = Vector2(12, 12)
	icon.size = Vector2(48, 48)
	icon.modulate = Color(1, 1, 1, 1) if owned else Color(1, 1, 1, 0.4)
	button.add_child(icon)

	var info: Dictionary = {}
	var state := get_node_or_null("/root/GameState")
	if state != null:
		info = state.get("ECHOES").get(id, {})

	var name_label := GothUI.label(str(info.get("name", id)), 15, GothUI.CYAN if worn else GothUI.TEXT)
	name_label.position = Vector2(70, 8)
	name_label.size = Vector2(164, 22)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(name_label)

	var desc := GothUI.label(_wrap(str(info.get("desc", "")), 22), 11, GothUI.DIM)
	desc.position = Vector2(70, 32)
	desc.size = Vector2(164, 56)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(desc)

	var tag_text := "WORN" if worn else ("EQUIP" if owned else "buy at a bench - %d" % cost)
	var tag := GothUI.label(tag_text, 11, GothUI.CRIMSON if worn else GothUI.DIM)
	tag.position = Vector2(70, 76)
	tag.size = Vector2(164, 18)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(tag)


## Label autowrap does not survive being sized by code here, so break the line
## by hand at a fixed character count.
func _wrap(text: String, width: int) -> String:
	var out := ""
	var line := ""
	for word in text.split(" ", false):
		if line.length() + word.length() + 1 > width:
			out += line + "\n"
			line = word
		else:
			line = word if line.is_empty() else line + " " + word
	return out + line

func _on_echo_pressed(id: String) -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	if not bool(state.call("has_echo", id)):
		return
	state.call("toggle_echo", id)
	_refresh_echoes()


func _on_state_changed(_value = null) -> void:
	if not visible:
		return
	if _page == PAGE_ECHOES:
		_refresh_echoes()


func _rect(box: Rect2, color: Color) -> void:
	var c := ColorRect.new()
	c.color = color
	c.position = box.position
	c.size = box.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(c)


func _plate(box: Rect2, fill: Color, border: Color) -> void:
	var outer := ColorRect.new()
	outer.color = border
	outer.position = box.position
	outer.size = box.size
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_echoes_box.add_child(outer)
	_rect_into(_echoes_box, box.grow(-2.0), fill)


func _rect_into(parent: Control, box: Rect2, color: Color) -> void:
	var c := ColorRect.new()
	c.color = color
	c.position = box.position
	c.size = box.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)


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


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_Q:
				turn(-1)
				get_viewport().set_input_as_handled()
				return
			KEY_E:
				turn(1)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
