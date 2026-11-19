extends CanvasLayer
## Echo shop overlay, built entirely in code.
##
## Sells relics, not stat boosts: each echo bends one rule of the game. Bought
## echoes go straight into a free slot; a worn echo can be taken off again to
## make room. A CanvasLayer so it draws over the bench panel that opens it.

signal closed

const GothUI := preload("res://scripts/ui/gothic_ui.gd")

const PANEL_W := 760.0
const PANEL_H := 560.0
const ROW_STEP := 62.0
const ROW_H := 46.0
const BUTTON_W := 150.0

var _coins: Label
var _slots: Label
var _rows: Array[Dictionary] = []


func _ready() -> void:
	# Above the bench panel (layer 32): this is only opened from the bench now.
	layer = 33
	visible = false
	_build()
	GameState.coins_changed.connect(_on_changed)
	GameState.echoes_changed.connect(_on_changed)


## Shows the shop and syncs every label to the current GameState.
func open() -> void:
	visible = true
	_refresh()


## Hides the shop and tells whoever opened it.
func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_W * 0.5
	panel.offset_right = PANEL_W * 0.5
	panel.offset_top = -PANEL_H * 0.5
	panel.offset_bottom = PANEL_H * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	GothUI.dress(panel, 12)
	add_child(panel)

	_add_title(panel)
	_add_coins(panel)
	var y := 128.0
	for id in GameState.ECHOES:
		_add_row(panel, id, y)
		y += ROW_STEP
	_add_close(panel)


func _add_title(panel: Control) -> void:
	var title := GothUI.label("ECHOES", 32, GothUI.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.offset_top = 26
	title.offset_bottom = 82
	panel.add_child(title)

	# ornament() comes back anchored full-rect, so the vertical anchors must be
	# reset to the top or the rule lands on the panel's bottom edge.
	var rule := GothUI.ornament(GothUI.ORN_DIVIDER, GothUI.BORDER, GothUI.CRIMSON)
	rule.anchor_right = 1.0
	rule.anchor_top = 0.0
	rule.anchor_bottom = 0.0
	rule.offset_left = 120
	rule.offset_right = -120
	rule.offset_top = 90
	rule.offset_bottom = 108
	panel.add_child(rule)


func _add_coins(panel: Control) -> void:
	_coins = GothUI.label("COINS: 0", 16, GothUI.CYAN)
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coins.anchor_left = 1.0
	_coins.anchor_right = 1.0
	# Kept clear of the close button in the top-right corner.
	_coins.offset_left = -340
	_coins.offset_right = -110
	_coins.offset_top = 32
	_coins.offset_bottom = 60
	panel.add_child(_coins)

	_slots = GothUI.label("WORN 0/3", 16, GothUI.DIM)
	_slots.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slots.offset_left = 50
	_slots.offset_right = 250
	_slots.offset_top = 32
	_slots.offset_bottom = 60
	panel.add_child(_slots)


func _add_row(panel: Control, id: String, y: float) -> void:
	var info: Dictionary = GameState.ECHOES[id]

	var name_label := GothUI.label(str(info.name), 22, GothUI.TEXT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.offset_left = 50
	name_label.offset_right = 460
	name_label.offset_top = y
	name_label.offset_bottom = y + 26
	panel.add_child(name_label)

	var desc := GothUI.label(str(info.desc), 13, GothUI.DIM)
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc.offset_left = 50
	desc.offset_right = 560
	desc.offset_top = y + 24
	desc.offset_bottom = y + ROW_H
	panel.add_child(desc)

	var buy := GothUI.make_button("BUY", Vector2(BUTTON_W, ROW_H), 15)
	buy.anchor_left = 1.0
	buy.anchor_right = 1.0
	buy.offset_left = -BUTTON_W - 40
	buy.offset_right = -40
	buy.offset_top = y + 4
	buy.offset_bottom = y + 4 + ROW_H
	buy.pressed.connect(_on_press.bind(id))
	panel.add_child(buy)

	_rows.append({"id": id, "name": name_label, "button": buy})


func _add_close(panel: Control) -> void:
	var btn := GothUI.close_button(40.0)
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.offset_left = -76
	btn.offset_right = -36
	btn.offset_top = 26
	btn.offset_bottom = 66
	btn.pressed.connect(close)
	panel.add_child(btn)


func _on_press(id: String) -> void:
	if GameState.has_echo(id):
		GameState.toggle_echo(id)
	else:
		GameState.buy_echo(id)
	_refresh()


func _refresh() -> void:
	if _coins == null:
		return
	_coins.text = "COINS: %d" % GameState.coins
	_slots.text = "WORN %d/%d" % [GameState.echoes_equipped.size(), GameState.ECHO_SLOTS]
	for row in _rows:
		var id: String = row.id
		var own: bool = GameState.has_echo(id)
		var worn: bool = GameState.echo_on(id)
		var full: bool = GameState.echoes_equipped.size() >= GameState.ECHO_SLOTS
		var button: Button = row.button
		var name_label: Label = row.name
		name_label.add_theme_color_override("font_color",
			GothUI.CYAN if worn else GothUI.TEXT)
		button.disabled = false
		if not own:
			var cost := GameState.echo_cost(id)
			button.text = "BUY %d" % cost
			button.disabled = GameState.coins < cost
		elif worn:
			button.text = "UNEQUIP"
		elif full:
			button.text = "FULL"
			button.disabled = true
		else:
			button.text = "EQUIP"


func _on_changed(_value = null) -> void:
	if not is_inside_tree():
		return
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	close()
	get_viewport().set_input_as_handled()
