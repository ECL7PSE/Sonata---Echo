extends Node2D

## Bench = checkpoint. Resting saves the run, heals, and opens the shop.

const GothUI := preload("res://scripts/ui/gothic_ui.gd")
const InteractPrompt := preload("res://scripts/ui/interact_prompt.gd")

const REACH := 44.0

var _prompt: Label
var _menu: Control
var _player: Node2D
var _near := false
var _shop: Node
var _t := 0.0


func _ready() -> void:
	z_index = 3
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_E
		InputMap.action_add_event("interact", ev)
	_build_prompt()
	_build_menu()


func _draw() -> void:
	# Stone bench with a candle. Local px; the Dungeon is scaled 2x, so this
	# reads as ~90 screen px wide. Drawn to sit on the 16px tile grid.
	var seat_top := Color("#6b5f73")
	var seat := Color("#3c3444")
	var seat_dark := Color("#241f2b")
	var gold := Color("#d9cf9a")

	# Warm pool of light on the floor, so the bench reads as a safe spot.
	var flick := 1.0 + sin(_t * 7.0) * 0.06
	draw_circle(Vector2(0, 16), 30.0 * flick, Color(1.0, 0.68, 0.28, 0.07))
	draw_circle(Vector2(0, 16), 18.0 * flick, Color(1.0, 0.72, 0.32, 0.10))

	# Back rest: two uprights, a top rail and three slats.
	draw_rect(Rect2(-21, -20, 4, 20), seat_dark)
	draw_rect(Rect2(17, -20, 4, 20), seat_dark)
	draw_rect(Rect2(-23, -22, 46, 4), seat)
	draw_rect(Rect2(-23, -22, 46, 1), seat_top)
	for i in 3:
		draw_rect(Rect2(-14 + i * 11, -18, 6, 14), Color("#2f2939"))

	# Seat slab with a lit top edge.
	draw_rect(Rect2(-25, -4, 50, 6), seat_dark)
	draw_rect(Rect2(-25, -6, 50, 4), seat)
	draw_rect(Rect2(-25, -6, 50, 1), seat_top)

	# Legs.
	draw_rect(Rect2(-20, 0, 4, 14), seat_dark)
	draw_rect(Rect2(16, 0, 4, 14), seat_dark)
	draw_rect(Rect2(-20, 13, 4, 1), seat_top)
	draw_rect(Rect2(16, 13, 4, 1), seat_top)

	# Candle, flame and its close glow.
	draw_rect(Rect2(8, -16, 4, 10), gold)
	draw_rect(Rect2(8, -16, 1, 10), Color("#f2ecc4"))
	draw_circle(Vector2(10, -19), 2.5 * flick, Color("#ffd166"))
	draw_circle(Vector2(10, -19), 6.0 * flick, Color(1.0, 0.72, 0.3, 0.20))

	# Faint cyan rune on the front of the seat: this is what ties the bench to
	# the gothic menu it opens.
	draw_rect(Rect2(-4, -3, 8, 1), GothUI.CYAN)
	draw_rect(Rect2(-1, -3, 2, 3), GothUI.CYAN)


func _build_prompt() -> void:
	_prompt = InteractPrompt.make("E  REST", Vector2(-80, -66))
	add_child(_prompt)

func _build_menu() -> void:
	var page := CanvasLayer.new()
	page.layer = 32
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(page)

	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.visible = false
	page.add_child(_menu)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -180
	panel.offset_bottom = 180
	GothUI.dress(panel, 12)
	_menu.add_child(panel)

	var title := GothUI.label("BENCH", 32, GothUI.CYAN)
	title.position = Vector2(0, 24)
	title.size = Vector2(600, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var rule := ColorRect.new()
	rule.color = GothUI.BORDER
	rule.position = Vector2(120, 78)
	rule.size = Vector2(360, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rule)

	var rest := GothUI.make_button("REST", Vector2(280, 44), 16)
	rest.position = Vector2(160, 116)
	rest.pressed.connect(_on_rest)
	panel.add_child(rest)

	# No MAP button: the floor map lives behind TAB, not in the bench panel.
	var shop := GothUI.make_button("SHOP", Vector2(280, 44), 16)
	shop.position = Vector2(160, 184)
	shop.pressed.connect(_on_shop)
	panel.add_child(shop)

	var leave := GothUI.make_button("LEAVE", Vector2(280, 44), 16)
	leave.position = Vector2(160, 252)
	leave.pressed.connect(_close)
	panel.add_child(leave)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()  # candle flicker
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		return
	_near = global_position.distance_to(_player.global_position) <= REACH
	_prompt.visible = _near and not _menu.visible


func _find_player() -> Node2D:
	for n in get_tree().get_nodes_in_group("player"):
		return n
	var found: Node2D = null
	var stack: Array[Node] = [get_tree().root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is CharacterBody2D and n.has_method("do_attack"):
			found = n
			break
		for c in n.get_children():
			stack.append(c)
	return found


func _unhandled_input(event: InputEvent) -> void:
	if _menu.visible:
		if event.is_action_pressed("ui_cancel"):
			_close()
			get_viewport().set_input_as_handled()
		return
	if _near and event.is_action_pressed("interact"):
		_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	_menu.visible = true
	get_tree().paused = true
	_on_rest()


func _close() -> void:
	if _shop != null:
		_shop.close()
	_menu.visible = false
	get_tree().paused = false


func _on_rest() -> void:
	if _player == null:
		return
	_player.call("reset_health")
	SaveManager.save_run(_player)


func _on_shop() -> void:
	if _shop == null:
		var sc = load("res://scripts/ui/shop_ui.gd")
		if sc == null:
			return
		_shop = sc.new()
		_shop.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_shop)
		_shop.closed.connect(_on_shop_closed)
	# The shop replaces the bench panel instead of stacking on it.
	_menu.visible = false
	_shop.open()


func _on_shop_closed() -> void:
	if _menu.visible:
		return
	_menu.visible = true
