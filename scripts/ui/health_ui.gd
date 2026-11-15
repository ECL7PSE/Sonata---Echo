extends CanvasLayer
## The player's segmented health bar.
##
## The chrome is drawn in code (gothic_ui.gd) rather than sliced from the sheet.
## The five-slot contract is unchanged: the bar always holds exactly five
## ColorRect fills, and only each fill's fraction follows health.

const GothUI := preload("res://scripts/ui/gothic_ui.gd")

const SLOT_COUNT := 5
const BAR_W := 260.0
const BAR_H := 48.0
const SLOT_X0 := 14.0
const SLOT_Y0 := 10.0
const SLOT_W := 40.0
const SLOT_H := 28.0
const SLOT_PITCH := 48.0
const FILL_COLOR := Color("#b81422")

var _bar: Control
var _fills: Array[ColorRect] = []
var _pulse: Tween
var _seen_damage := false
var _slot_base_w := SLOT_W


func _ready() -> void:
	layer = 10
	_build_bar()
	var player := _find_player()
	if player == null:
		push_warning("health_ui: no player found")
		return
	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	player.add_to_group("damage_numbers")
	_on_health_changed(player.health, player.max_health)


func _build_bar() -> void:
	_bar = Control.new()
	_bar.position = Vector2(16, 14)
	_bar.size = Vector2(BAR_W, BAR_H)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	_bar.add_child(GothUI.segmented_bar(BAR_W, BAR_H, SLOT_COUNT, SLOT_X0,
			SLOT_Y0, SLOT_PITCH, SLOT_W, SLOT_H))
	for f in GothUI.bar_fills(SLOT_COUNT, SLOT_X0, SLOT_Y0, SLOT_PITCH,
			SLOT_W, SLOT_H, FILL_COLOR):
		_bar.add_child(f)
		_fills.append(f)


func _find_player() -> Node2D:
	var root := get_tree().root
	for child in root.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null


func _search(node: Node) -> Node2D:
	if node == null:
		return null
	if node is CharacterBody2D and node.has_signal("health_changed") \
			and node.has_method("do_attack"):
		return node as Node2D
	for child in node.get_children():
		var found := _search(child)
		if found != null:
			return found
	return null


func _on_health_changed(current: int, maximum: int) -> void:
	var per_slot := float(maximum) / float(SLOT_COUNT)
	for i in _fills.size():
		var fill := clampf((float(current) - i * per_slot) / per_slot, 0.0, 1.0)
		_fills[i].visible = fill > 0.001
		_fills[i].size.x = _slot_base_w * fill

	if current < maximum:
		_seen_damage = true
		_shake()
	if _seen_damage and current <= 2:
		_pulse_bar()
	else:
		_stop_pulse()


func _shake() -> void:
	var tween := create_tween()
	tween.tween_property(_bar, "position:x", 20.0, 0.04)
	tween.tween_property(_bar, "position:x", 13.0, 0.04)
	tween.tween_property(_bar, "position:x", 16.0, 0.05)


func _pulse_bar() -> void:
	if _pulse != null and _pulse.is_valid():
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_bar, "modulate", Color(1.5, 0.9, 0.9, 1.0), 0.5)
	_pulse.tween_property(_bar, "modulate", Color.WHITE, 0.5)


func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	_bar.modulate = Color.WHITE
