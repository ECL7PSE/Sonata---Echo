extends StaticBody2D
class_name DungeonDoor

const SHEET := preload("res://Assets/etc/pixor-library-door-selout-64px-8-sides.png")
const FRAME_SIZE := 64
const FRAMES_PER_DIRECTION := 10
const DIRECTION_COUNT := 8
const OPEN_FPS := 6.0
const SPRITE_SCALE := 0.5

@export var required_room := ""

static var _shared_frames: SpriteFrames
static var _art_bounds: Array[Rect2i] = []

var _orientation := 0
var _animation_name := ""
var _sprite: AnimatedSprite2D
var _collision: CollisionShape2D
var _opening := false
var _opened := false


static func opening_width_cells(orientation: int, grid_size: int,
		horizontal_corridor: bool) -> int:
	var bounds := _get_art_bounds()[clampi(orientation, 0, DIRECTION_COUNT - 1)]
	var sprite_span := bounds.size.y if horizontal_corridor else bounds.size.x
	# Round up so the unchanged sprite fits inside whole doorway cells.
	return maxi(1, ceili(float(sprite_span) * SPRITE_SCALE / grid_size))


func configure(room_name: String, orientation: int,
		blocker_size: Vector2, horizontal_corridor: bool) -> void:
	required_room = room_name
	_orientation = clampi(orientation, 0, DIRECTION_COUNT - 1)
	_animation_name = "open_%d" % _orientation

	collision_layer = Layers.WORLD
	collision_mask = 0

	var bounds := _get_art_bounds()[_orientation]
	var cross_axis_is_x := not horizontal_corridor
	var cross_axis_min := bounds.position.x if cross_axis_is_x else bounds.position.y
	var cross_axis_size := bounds.size.x if cross_axis_is_x else bounds.size.y
	var cross_axis_center := cross_axis_min + cross_axis_size * 0.5
	var sprite_offset := Vector2.ZERO
	if cross_axis_is_x:
		sprite_offset.x = FRAME_SIZE * 0.5 - cross_axis_center
	else:
		sprite_offset.y = FRAME_SIZE * 0.5 - cross_axis_center

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.sprite_frames = _get_shared_frames()
	_sprite.animation = _animation_name
	_sprite.frame = 0
	_sprite.offset = sprite_offset
	# Keep the sprite proportions intact; the parent dungeon itself is scaled 2x.
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	add_child(_sprite)

	_collision = CollisionShape2D.new()
	_collision.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = blocker_size
	_collision.shape = shape
	add_child(_collision)


static func _get_art_bounds() -> Array[Rect2i]:
	if not _art_bounds.is_empty():
		return _art_bounds
	var image := SHEET.get_image()
	for direction in range(DIRECTION_COUNT):
		var min_x := FRAME_SIZE
		var min_y := FRAME_SIZE
		var max_x := -1
		var max_y := -1
		for frame_index in range(FRAMES_PER_DIRECTION):
			var frame_origin := Vector2i(frame_index * FRAME_SIZE,
					direction * FRAME_SIZE)
			for y in range(FRAME_SIZE):
				for x in range(FRAME_SIZE):
					if image.get_pixel(frame_origin.x + x,
							frame_origin.y + y).a <= 0.0:
						continue
					min_x = mini(min_x, x)
					min_y = mini(min_y, y)
					max_x = maxi(max_x, x)
					max_y = maxi(max_y, y)
		if max_x < min_x or max_y < min_y:
			push_error("Door sprite orientation has no visible frames: %d" % direction)
			_art_bounds.append(Rect2i(0, 0, FRAME_SIZE, FRAME_SIZE))
		else:
			_art_bounds.append(Rect2i(min_x, min_y,
					max_x - min_x + 1, max_y - min_y + 1))
	return _art_bounds


func open() -> void:
	if _opening or _opened:
		return
	_opening = true
	Audio.play("door_open")
	_sprite.animation_finished.connect(_on_open_animation_finished,
			CONNECT_ONE_SHOT)
	_sprite.play(_animation_name)


func set_open_initially() -> void:
	if _sprite == null or _collision == null:
		return
	_opening = false
	_opened = true
	_sprite.stop()
	_sprite.animation = _animation_name
	_sprite.frame = FRAMES_PER_DIRECTION - 1
	_collision.disabled = true


func _on_open_animation_finished() -> void:
	if not _opening:
		return
	_opening = false
	_opened = true
	_collision.disabled = true


func _get_shared_frames() -> SpriteFrames:
	if _shared_frames != null:
		return _shared_frames
	if SHEET.get_width() != FRAME_SIZE * FRAMES_PER_DIRECTION \
			or SHEET.get_height() != FRAME_SIZE * DIRECTION_COUNT:
		push_error("Dungeon door sheet must contain 8 rows of 10 64px frames.")
		return SpriteFrames.new()

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for direction in range(DIRECTION_COUNT):
		var animation := "open_%d" % direction
		frames.add_animation(animation)
		frames.set_animation_speed(animation, OPEN_FPS)
		frames.set_animation_loop(animation, false)
		for frame_index in range(FRAMES_PER_DIRECTION):
			var atlas := AtlasTexture.new()
			atlas.atlas = SHEET
			atlas.region = Rect2(
					frame_index * FRAME_SIZE,
					direction * FRAME_SIZE,
					FRAME_SIZE,
					FRAME_SIZE)
			frames.add_frame(animation, atlas)
	_shared_frames = frames
	return _shared_frames
