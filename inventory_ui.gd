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

## Integer scale only, for the same reason the hearts use one.
const ICON_SCALE := 3
## How many hotbar slots to show. All empty for now.
const SLOT_COUNT := 4

@onready var coin_icon: TextureRect = $CoinIcon
@onready var coin_count: Label = $CoinCount
@onready var hotbar: HBoxContainer = $Hotbar


func _ready() -> void:
	layer = 10
	coin_icon.texture = COIN_ICON
	coin_icon.scale = Vector2.ONE * ICON_SCALE
	coin_icon.custom_minimum_size = Vector2(
		COIN_ICON.get_width() * ICON_SCALE, COIN_ICON.get_height() * ICON_SCALE)
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
	for i in SLOT_COUNT:
		var slot := TextureRect.new()
		slot.texture = SLOT_ICON
		slot.custom_minimum_size = Vector2(
			SLOT_ICON.get_width() * ICON_SCALE,
			SLOT_ICON.get_height() * ICON_SCALE)
		slot.tooltip_text = "slot %d" % (i + 1)
		hotbar.add_child(slot)


func _on_coins_changed(current: int) -> void:
	coin_count.text = str(current)
	_pop()


## A short scale punch so a pickup reads as an event.
func _pop() -> void:
	var tween := coin_icon.create_tween()
	tween.tween_property(coin_icon, "scale",
		Vector2.ONE * ICON_SCALE * 1.35, 0.09)
	tween.tween_property(coin_icon, "scale",
		Vector2.ONE * ICON_SCALE, 0.11)


func _refresh_slots(slots: Array) -> void:
	for i in mini(slots.size(), hotbar.get_child_count()):
		var slot := hotbar.get_child(i) as TextureRect
		if slot != null and slots[i] != "":
			slot.modulate = Color(1, 1, 1, 1)
		elif slot != null:
			slot.modulate = Color(1, 1, 1, 0.45)