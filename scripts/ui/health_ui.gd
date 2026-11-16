extends CanvasLayer
## The player's health bar, top-left of the screen.
##
## Built from two pieces of artwork exported from Canva on the SAME canvas:
##   health_frame.png - heart, music notes and side flourishes (no red)
##   health_fill.png  - the red bar only
## Both are trimmed of transparent padding at load time. The fill is placed
## relative to the frame using their positions on the shared canvas, so they
## line up exactly as designed.
##
## The five-slot contract is kept: the bar still holds exactly five ColorRect
## fills, and only each fill's width follows health. Each ColorRect clips a
## slice of the red bar, so together they read as one smooth bar that empties
## from the right.

const ART_DIR := "res://Assets/UI/Health_Bar/"
const FRAME_PNG := ART_DIR + "health_frame.png"
const FILL_PNG := ART_DIR + "health_fill.png"

const SLOT_COUNT := 5
## On-screen width of the whole frame, in game pixels (1152x648 space).
const FRAME_W := 270.0
## Top-left position of the bar on screen.
const BAR_POS := Vector2(12.0, 8.0)

## Flourish lift and split coordinates:
const FLOURISH_LIFT := 30.0
const SPLIT_LEFT := 480.0
const SPLIT_RIGHT := 1440.0

## ADJUST THIS: Positive values move the red bar down, negative values move it up.
const FILL_Y_OFFSET := 40.0

## Tint of the red bar where health has been lost.
const EMPTY_TINT := Color(0.25, 0.12, 0.15, 1.0)

var _bar: Control
var _fills: Array[ColorRect] = []
var _pulse: Tween
var _seen_damage := false
var _slot_base_w := 0.0


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
	var frame_tex := load(FRAME_PNG) as Texture2D
	var fill_tex := load(FILL_PNG) as Texture2D
	var frame_rect := _used_rect(frame_tex)
	var fill_rect := _used_rect(fill_tex)

	# One scale for everything, so the pieces keep their designed proportions.
	var k := FRAME_W / frame_rect.size.x
	var frame_size := frame_rect.size * k
	var fill_size := fill_rect.size * k
	
	# Added FILL_Y_OFFSET here to push the red bar lower relative to the frame
	var fill_pos := ((fill_rect.position - frame_rect.position) * k) + Vector2(0.0, FILL_Y_OFFSET * k)

	_bar = Control.new()
	_bar.position = BAR_POS
	_bar.size = frame_size
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	var fill_art := _region(fill_tex, fill_rect)

	# Dark copy of the bar underneath, visible where health is lost.
	var track := _tex_rect(fill_art, fill_size)
	track.position = fill_pos
	track.modulate = EMPTY_TINT
	_bar.add_child(track)

	# Five clipping slices of the red bar.
	_slot_base_w = fill_size.x / float(SLOT_COUNT)
	for i in SLOT_COUNT:
		var slot := ColorRect.new()
		slot.color = Color(0.0, 0.0, 0.0, 0.0)
		slot.clip_contents = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.position = fill_pos + Vector2(i * _slot_base_w, 0.0)
		slot.size = Vector2(_slot_base_w, fill_size.y)
		var art := _tex_rect(fill_art, fill_size)
		art.position = Vector2(-i * _slot_base_w, 0.0)
		slot.add_child(art)
		_bar.add_child(slot)
		_fills.append(slot)

	# Frame on top, cut into left flourish / heart group / right flourish.
	var x0 := frame_rect.position.x
	var x1 := frame_rect.end.x
	var cuts := [x0, SPLIT_LEFT, SPLIT_RIGHT, x1]
	for p in 3:
		var region := Rect2(cuts[p], frame_rect.position.y,
				cuts[p + 1] - cuts[p], frame_rect.size.y)
		var piece := _tex_rect(_region(frame_tex, region), region.size * k)
		piece.position = (region.position - frame_rect.position) * k
		if p != 1:
			piece.position.y -= FLOURISH_LIFT * k
		_bar.add_child(piece)


## Bounding box of the non-transparent pixels, in the texture's own pixels.
func _used_rect(tex: Texture2D) -> Rect2:
	var img := tex.get_image()
	if img != null:
		var r := img.get_used_rect()
		if r.size.x > 0 and r.size.y > 0:
			return Rect2(r)
	return Rect2(Vector2.ZERO, tex.get_size())


func _region(tex: Texture2D, rect: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = rect
	return a


func _tex_rect(tex: Texture2D, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = size
	return t


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
	tween.tween_property(_bar, "position:x", BAR_POS.x + 4.0, 0.04)
	tween.tween_property(_bar, "position:x", BAR_POS.x - 3.0, 0.04)
	tween.tween_property(_bar, "position:x", BAR_POS.x, 0.05)


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
