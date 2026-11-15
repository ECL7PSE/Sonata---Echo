extends CanvasLayer
## Coin shop overlay, built entirely in code.
##
## A CanvasLayer so it draws over whatever scene is running, and hidden by
## default - it appears only when something calls open(). The gothic frame is
## drawn by gothic_ui.gd, so no sprite sheet is involved.

signal closed

const GothUI := preload("res://scripts/ui/gothic_ui.gd")

const PANEL_W := 760.0
const PANEL_H := 420.0
const ROW_H := 44.0
const BUTTON_W := 120.0

## key, label, cost at level 0, and the row's top y.
const ROWS := [
	{"key": "hp", "name": "HEALTH", "base": 25, "y": 150.0},
	{"key": "atk", "name": "ATTACK", "base": 40, "y": 225.0},
	{"key": "spd", "name": "SPEED", "base": 30, "y": 300.0},
]

var _coins: Label
var _rows: Array[Dictionary] = []


func _ready() -> void:
	# Above the bench panel (layer 32): this is only opened from the bench now.
	layer = 33
	visible = false
	_build()
	GameState.coins_changed.connect(_on_coins_changed)


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
	for row in ROWS:
		_add_row(panel, row)
	_add_close(panel)


func _add_title(panel: Control) -> void:
	var title := GothUI.label("SHOP", 32, GothUI.CYAN)
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


func _add_row(panel: Control, row: Dictionary) -> void:
	var y: float = row.y

	var name_label := GothUI.label(row.name, 24, GothUI.TEXT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.offset_left = 90
	name_label.offset_right = 330
	name_label.offset_top = y
	name_label.offset_bottom = y + ROW_H
	panel.add_child(name_label)

	var level_label := GothUI.label("LV 0/0", 16, GothUI.DIM)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.anchor_left = 0.5
	level_label.anchor_right = 0.5
	level_label.offset_left = -80
	level_label.offset_right = 80
	level_label.offset_top = y
	level_label.offset_bottom = y + ROW_H
	panel.add_child(level_label)

	var buy := GothUI.make_button("BUY", Vector2(BUTTON_W, ROW_H), 16)
	buy.anchor_left = 1.0
	buy.anchor_right = 1.0
	buy.offset_left = -BUTTON_W - 90
	buy.offset_right = -90
	buy.offset_top = y
	buy.offset_bottom = y + ROW_H
	buy.pressed.connect(_on_buy.bind(row.key, row.base))
	panel.add_child(buy)

	_rows.append({"key": row.key, "base": row.base, "level": level_label, "button": buy})


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


func _on_buy(key: String, base: int) -> void:
	var level: int = GameState.get_upgrade(key)
	if level >= GameState.UPGRADE_MAX:
		return
	var cost := base * (level + 1)
	if not GameState.spend_coins(cost):
		return
	GameState.set_upgrade(key, level + 1)
	_refresh()


func _refresh() -> void:
	_coins.text = "COINS: %d" % GameState.coins
	for row in _rows:
		var level: int = GameState.get_upgrade(row.key)
		var maxed := level >= GameState.UPGRADE_MAX
		row.level.text = "LV %d/%d" % [level, GameState.UPGRADE_MAX]
		row.button.text = "MAX" if maxed else "BUY %d" % (int(row["base"]) * (level + 1))
		row.button.disabled = maxed


func _on_coins_changed(_current: int) -> void:
	if not is_inside_tree():
		return
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	close()
	get_viewport().set_input_as_handled()
