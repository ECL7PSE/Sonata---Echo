extends Node2D
## Scatters coins out of something that was just broken.
##
## One helper for both the chests and the enemy deaths, so a coin dropped by a
## goblin and a coin dropped by a chest are indistinguishable and behave
## identically. Before this existed, loot.gd threw plain Sprite2Ds that faded out
## after 0.45s and could never be collected at all.

## Declared first: GDScript resolves constants in source order, and drop() below
## refers to it.
const COIN_SCRIPT := preload("res://coin.gd")

const COIN_SHEET_DIR := "res://Assets/Dungeon/dungeon_V.1.0.0_nyknck/Gold/G001/"

## The G001 spin frames. Four 16x16 cells; if a future export has more, raise
## COIN_FRAMES rather than guessing at runtime.
const COIN_FRAMES := 4

## Cached spin animation, shared by every coin in the run.
static var _frames: SpriteFrames


## Drops `count` coins from `origin`, fanned out in `radius` screen pixels.
##
## The parent is where the coins are added, so the caller decides whether they
## land in the world or in some container.
## `origin` is in GLOBAL space; the coins are placed in the parent's LOCAL space.
##
## These are not the same thing here. The Dungeon node is scaled 2x, so a coin
## parented to Dungeon/Props and given a global position is drawn at DOUBLE its
## world position - which is how coins ended up off in the wall band, apparently
## invisible, while every old test still passed because it only checked that a
## coin node existed with a collider.
static func drop(parent: Node, origin: Vector2, count: int,
		radius := 34.0, walkable: Callable = Callable()) -> void:
	if parent == null or count <= 0:
		return
	var local: Vector2 = parent.to_local(origin)
	for i in count:
		var coin := Area2D.new()
		coin.set_script(COIN_SCRIPT)
		coin.name = "Coin%d" % i
		coin.position = local
		# Lets the bounce stop at a wall instead of sliding through it.
		#
		# This MUST be set while the coin is still OUTSIDE the tree, and it must
		# name the real member `_walkable`. It used to be
		# `coin.set("walkable", walkable)` - a property that does not exist on
		# coin.gd, which has a `_walkable` var and a set_walkable() method.
		# Object.set() on an unknown name fails silently, so the callable never
		# reached the coin, _can_stand() always returned true and every coin
		# scattered straight through the masonry. Set it before add_child so
		# _ready() can already see it and snap an unsafe spawn point.
		if walkable.is_valid():
			coin.set("_walkable", walkable)
		# Above the floor and props, below nothing that matters. Without this the
		# coin drew behind the dungeon layers and looked like it had not spawned.
		coin.z_index = 40
		coin.modulate = Color(1, 1, 1, 1)
		coin.visible = true
		# A fan, not a ring: a full circle of coins looks like an explosion, and
		# half of them land behind the thing that dropped them.
		var t: float = float(i) / maxf(float(count - 1), 1.0) - 0.5
		var dir := Vector2(t * 1.6, -1.0).normalized()
		# The coin moves its own `position` (an Area2D is not a physics body, so it
		# has no velocity to set); this is just the target offset it arcs toward.
		coin.set_meta("launch", dir * radius + Vector2(0, 18))

		# Give the Area2D the shape the coin script needs. Named explicitly: an
		# unnamed child gets an auto-generated name like "@CollisionShape2D@7",
		# which nothing can look up by a stable path.
		var shape := CollisionShape2D.new()
		shape.name = "Shape"
		var circle := CircleShape2D.new()
		circle.radius = 9.0
		shape.shape = circle
		coin.add_child(shape)

		# coin.gd animates whichever child is called "Sprite". Prefer the
		# AnimatedSprite2D spin; fall back to a single static frame if the G001
		# frames are missing, so a missing export degrades instead of vanishing.
		var frames := _coin_frames()
		if frames != null:
			var anim := AnimatedSprite2D.new()
			anim.name = "Sprite"
			anim.sprite_frames = frames
			anim.scale = Vector2.ONE * 1.5
			coin.add_child(anim)
			anim.play("spin")
		else:
			var sprite := Sprite2D.new()
			sprite.name = "Sprite"
			var sheet: Texture2D = _sheet()
			if sheet != null:
				sprite.texture = sheet
				sprite.hframes = COIN_FRAMES
				sprite.frame = i % COIN_FRAMES
			sprite.scale = Vector2.ONE * 1.5
			coin.add_child(sprite)

		# Added to the tree LAST, once every child exists.
		#
		# Adding the coin before its Sprite is in place makes coin.gd's @onready
		# `$Sprite` fail, because _ready fires the instant the node enters the tree
		# and it has no children yet.
		parent.add_child(coin)


## The four-frame spin, built once and shared by every coin.
static func _coin_frames() -> SpriteFrames:
	if _frames != null:
		return _frames
	_frames = SpriteFrames.new()
	_frames.remove_animation("default")
	_frames.add_animation("spin")
	for i in COIN_FRAMES:
		var tex: Texture2D = load(COIN_SHEET_DIR + "G001_%02d.png" % (i + 1))
		if tex == null:
			return null
		_frames.add_frame("spin", tex)
	_frames.set_animation_speed("spin", 10.0)
	_frames.set_animation_loop("spin", true)
	return _frames


static func _sheet() -> Texture2D:
	var path := COIN_SHEET_DIR + "G001.png"
	if ResourceLoader.exists(path):
		return load(path)
	return null