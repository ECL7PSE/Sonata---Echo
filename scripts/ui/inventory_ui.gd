extends CanvasLayer
## The coin counter. Hearts live in health_ui.gd.
##
## Shares the Health UI's CanvasLayer idea: a separate canvas, so the dungeon
## ambient and the torch lights never touch it.
##
## The hotbar was removed entirely - no slots, no panel, no toggle. Nothing in
## the game puts anything in an inventory yet, so it was four empty boxes
## covering the bottom of the screen.

const COIN_ICON := preload("res://Assets/UI/pixel_ui/icons/coin.png")

## LAYOUT. Every position and size is here, so the HUD can be nudged without
## hunting through node paths.
##
## --- hearts (health_ui.gd owns these; the coin row is positioned under them)
const HEARTS_ORIGIN := Vector2(12, 10)
const HEART_SIZE := 16 * 3        # 16px source at 3x
const HEART_COUNT := 5
const COIN_SEPARATION := 14
## 16x16 coin at 2x = 32px. It was previously drawn from the 80px G001 spin
## sheet, which rendered ~150px on screen and ran over everything.
const COIN_SCALE := 2
const COUNT_FONT_SIZE := 18

var coin_icon: TextureRect
var coin_count: Label


## The coin row: a 16px icon at 2x with the count to its RIGHT, pinned in the
## top-right corner of the screen. Built here rather than authored in the scene so the
## layout constants above are the single source of truth.
func _build_coin_row() -> void:
	var row := HBoxContainer.new()
	row.name = "CoinRow"
	row.add_theme_constant_override("separation", COIN_SEPARATION)
	row.z_index = 1
	add_child(row)

	coin_icon = TextureRect.new()
	coin_icon.name = "CoinIcon"
	coin_icon.texture = COIN_ICON
	coin_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin_icon.custom_minimum_size = Vector2(
			COIN_ICON.get_width() * COIN_SCALE,
			COIN_ICON.get_height() * COIN_SCALE)
	# Drawn at the size the container allocates - stretching the texture instead
	# of scaling the node, so it cannot overpaint the count beside it.
	coin_icon.stretch_mode = TextureRect.STRETCH_SCALE
	coin_icon.pivot_offset = Vector2(
			COIN_ICON.get_width() * COIN_SCALE,
			COIN_ICON.get_height() * COIN_SCALE) * 0.5
	row.add_child(coin_icon)

	coin_count = Label.new()
	coin_count.name = "CoinCount"
	coin_count.text = "0"
	coin_count.add_theme_font_size_override("font_size", COUNT_FONT_SIZE)
	# Vertically centred on the coin rather than baseline-aligned to it.
	coin_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_count.custom_minimum_size = Vector2(44, 0)
	coin_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(coin_count)

	# Pinned to the top-right corner, clear of the hearts on the left and of the
	# duel's enemy bar below it.
	var w := coin_icon.custom_minimum_size.x + COIN_SEPARATION + coin_count.custom_minimum_size.x
	row.anchor_left = 1.0
	row.anchor_right = 1.0
	row.offset_right = -16
	row.offset_left = -16 - w
	row.offset_top = 12
	row.offset_bottom = 12 + coin_icon.custom_minimum_size.y


func _ready() -> void:
	layer = 10
	_build_coin_row()

	# Autoloads are resolved through the tree rather than as bare identifiers, so
	# this script still compiles under --script where autoloads are not set up.
	var tree := get_tree()
	if tree == null:
		return
	var state := tree.root.get_node_or_null("GameState")
	if state != null and not state.coins_changed.is_connected(_on_coins_changed):
		state.coins_changed.connect(_on_coins_changed)
		_on_coins_changed(state.coins)
	# The Inventory autoload is left in place for future use, but nothing here
	# listens to it any more: with no slots there is nothing to refresh.


func _on_coins_changed(current: int) -> void:
	coin_count.text = str(current)
	# Hide the row entirely at zero. A lone "0" under the hearts read as a stray
	# piece of UI rather than a coin count, and there is nothing to report until
	# the first coin is actually picked up.
	var row := coin_count.get_parent() as Control
	if row != null:
		row.visible = current > 0
	if current > 0:
		_pop()


## A short scale punch so a pickup reads as an event.
func _pop() -> void:
	var tween := coin_icon.create_tween()
	tween.tween_property(coin_icon, "scale", Vector2.ONE * 1.2, 0.09)
	tween.tween_property(coin_icon, "scale", Vector2.ONE, 0.11)


func _unused() -> void:
	pass