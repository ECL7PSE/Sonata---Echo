extends CanvasLayer
## The coin counter and the item hotbar.
##
## Shares the Health UI's CanvasLayer idea: a separate canvas, so the dungeon
## ambient and the torch lights never touch it.
##
## Every position here is a constant, so the layout can be nudged without
## hunting through node paths.

const COIN_ICON := preload("res://Assets/UI/pixel_ui/icons/coin.png")
const SLOT_ICON := preload("res://Assets/UI/Inventory/Inventory_Slot_1.png")

## LAYOUT. Every position and size is here, so the HUD can be nudged without
## hunting through node paths or guessing at container behaviour.
const ICON_SCALE := 3
## How many hotbar slots to show. All empty for now.
const SLOT_COUNT := 4

## --- hearts (health_ui.gd owns these; the coin row is positioned under them)
const HEARTS_ORIGIN := Vector2(12, 10)
const HEART_SIZE := 16 * 3        # 16px source at 3x
## Gap between the bottom of the hearts and the top of the coin row.
const COIN_ROW_GAP := 8

## --- coin row, directly under the hearts
const COIN_ROW_ORIGIN := Vector2(HEARTS_ORIGIN.x,
		HEARTS_ORIGIN.y + HEART_SIZE * 5 + COIN_ROW_GAP)
## 16x16 coin at 2x. It was being drawn at 3x of an 80px G001 sheet, which is
## ~150px on screen and overlapped the hotbar.
const COIN_SCALE := 2
const COIN_GAP := 6              # between the icon and the count label
const COUNT_FONT_SIZE := 18

## --- hotbar, centred along the bottom edge
const SLOT_SCALE := 2            # 32px source -> 64px
const SLOT_GAP := 6
const HOTBAR_MARGIN := 10        # from the bottom of the screen

@onready var hotbar: HBoxContainer = $Hotbar

var coin_icon: TextureRect
var coin_count: Label


## The coin row: a 16px icon at 2x with the count to its RIGHT, both in a Control
## pinned under the hearts. Built here rather than authored in the scene so the
## layout constants above are the single source of truth.
func _build_coin_row() -> void:
	var row := HBoxContainer.new()
	row.name = "CoinRow"
	row.add_theme_constant_override("separation", COIN_GAP)
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
	_build_hotbar()

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
	if inv != null and not inv.inventory_changed.is_connected(_refresh_slots):
		inv.inventory_changed.connect(_refresh_slots)


func _build_hotbar() -> void:
	# Centred along the bottom, so it can never collide with the top-left hearts
	# or the coin row at any window size.
	hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	hotbar.add_theme_constant_override("separation", SLOT_GAP)
	var anchor := Control.new()
	anchor.name = "HotbarAnchor"
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.offset_top = -(SLOT_ICON.get_height() * SLOT_SCALE + HOTBAR_MARGIN)
	anchor.offset_bottom = -HOTBAR_MARGIN
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	hotbar.get_parent().remove_child(hotbar)
	anchor.add_child(hotbar)
	hotbar.anchors_preset = Control.PRESET_FULL_RECT
	for i in SLOT_COUNT:
		var slot := TextureRect.new()
		slot.texture = SLOT_ICON
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		slot.custom_minimum_size = Vector2(
			SLOT_ICON.get_width() * SLOT_SCALE,
			SLOT_ICON.get_height() * SLOT_SCALE)
		slot.tooltip_text = "slot %d" % (i + 1)
		hotbar.add_child(slot)


func _on_coins_changed(current: int) -> void:
	coin_count.text = str(current)
	_pop()


## A short scale punch so a pickup reads as an event.
func _pop() -> void:
	var tween := coin_icon.create_tween()
	tween.tween_property(coin_icon, "scale",
		Vector2.ONE * COIN_SCALE * 1.25, 0.09)
	tween.tween_property(coin_icon, "scale",
		Vector2.ONE * COIN_SCALE, 0.11)


func _refresh_slots(slots: Array) -> void:
	for i in mini(slots.size(), hotbar.get_child_count()):
		var slot := hotbar.get_child(i) as TextureRect
		if slot != null and slots[i] != "":
			slot.modulate = Color(1, 1, 1, 1)
		elif slot != null:
			slot.modulate = Color(1, 1, 1, 0.45)