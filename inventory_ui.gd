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
## Gap between the bottom of the hearts and the top of the coin row.
const COIN_ROW_GAP := 8

## --- coin row: one HBox, 8px separation, directly under the hearts
const COIN_ROW_ORIGIN := Vector2(HEARTS_ORIGIN.x,
		HEARTS_ORIGIN.y + HEART_SIZE * HEART_COUNT + COIN_ROW_GAP)
const COIN_SEPARATION := 8
## 16x16 coin at 2x = 32px. It was previously drawn from the 80px G001 spin
## sheet, which rendered ~150px on screen and ran over everything.
const COIN_SCALE := 2
const COUNT_FONT_SIZE := 18

var coin_icon: TextureRect
var coin_count: Label


## The coin row: a 16px icon at 2x with the count to its RIGHT, both in a Control
## pinned under the hearts. Built here rather than authored in the scene so the
## layout constants above are the single source of truth.
func _build_coin_row() -> void:
	var row := HBoxContainer.new()
	row.name = "CoinRow"
	row.add_theme_constant_override("separation", COIN_SEPARATION)
	row.position = COIN_ROW_ORIGIN
	row.z_index = 1
	add_child(row)

	coin_icon = TextureRect.new()
	coin_icon.name = "CoinIcon"
	coin_icon.texture = COIN_ICON
	coin_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin_icon.custom_minimum_size = Vector2(
			COIN_ICON.get_width() * COIN_SCALE,
			COIN_ICON.get_height() * COIN_SCALE)
	coin_icon.scale = Vector2.ONE * COIN_SCALE
	# A TextureRect inside a container is laid out by its custom_minimum_size, so
	# the visual scale is folded in rather than left to fight the container.
	coin_icon.pivot_offset = Vector2.ZERO
	row.add_child(coin_icon)

	coin_count = Label.new()
	coin_count.name = "CoinCount"
	coin_count.text = "0"
	coin_count.add_theme_font_size_override("font_size", COUNT_FONT_SIZE)
	# Vertically centred on the coin rather than baseline-aligned to it.
	coin_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin_count)


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
	var inv := tree.root.get_node_or_null("Inventory")
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
	tween.tween_property(coin_icon, "scale",
		Vector2.ONE * COIN_SCALE * 1.25, 0.09)
	tween.tween_property(coin_icon, "scale",
		Vector2.ONE * COIN_SCALE, 0.11)


func _unused() -> void:
	pass