extends Area2D
## The shade: your coins, waiting where you died.
##
## Three slashes and it lets go. Nothing else in the dungeon reacts to a slash
## this way, so it is deliberately cheap to read: a dark wisp with two pale eyes
## that shivers while you are near it.

const HITS := 3
const LOCK := 0.22

var coins := 0

var _hits := 0
var _lock := 0.0
var _t := 0.0
var _flash := 0.0


func _ready() -> void:
	# Same trick as prop_breakable: the slash switches on for a few frames, so an
	# overlap here means the player just hit it. Mask names that bit explicitly.
	collision_layer = Layers.WORLD
	collision_mask = Layers.prop_mask()
	area_entered.connect(_on_area_entered)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	shape.shape = circle
	add_child(shape)
	z_index = 2


func _process(delta: float) -> void:
	_t += delta
	_lock = maxf(0.0, _lock - delta)
	_flash = maxf(0.0, _flash - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var bob := sin(_t * 1.7) * 2.0
	var sway := sin(_t * 1.1) * 1.5
	var body := Color(0.09, 0.06, 0.13, 0.92)
	var rim := Color(0.55, 0.35, 0.72, 0.75)
	if _flash > 0.0:
		body = body.lerp(Color(1, 0.85, 0.95), _flash * 0.7)
	# Aura, then a ragged blob body, then the eyes.
	draw_circle(Vector2(0, bob), 24.0, Color(0.45, 0.25, 0.6, 0.10))
	draw_circle(Vector2(0, bob), 15.0, Color(0.35, 0.2, 0.5, 0.14))
	draw_circle(Vector2(0, bob), 11.0, body)
	draw_arc(Vector2(0, bob), 11.0, PI * 0.15, PI * 0.85, 14, rim, 1.5)
	# Three wisps trailing below, so it reads as floating.
	for i in 3:
		var x := (float(i) - 1.0) * 5.0 + sway
		draw_circle(Vector2(x, bob + 11.0 + float(i) * 3.0), 3.0 - float(i) * 0.6,
			Color(0.35, 0.22, 0.48, 0.5 - float(i) * 0.12))
	# Eyes: pale, and they narrow as the shade weakens.
	var open := 2.2 - float(_hits) * 0.4
	draw_circle(Vector2(-4, bob - 2), open, Color(0.86, 0.95, 1.0, 0.95))
	draw_circle(Vector2(4, bob - 2), open, Color(0.86, 0.95, 1.0, 0.95))


func _on_area_entered(area: Area2D) -> void:
	if _lock > 0.0 or area == null:
		return
	if not (area.get_parent() is CharacterBody2D):
		return
	_lock = LOCK
	_hits += 1
	_flash = 1.0
	if _hits < HITS:
		return
	_release()


## Hands the coins back and disappears. Anything holding them is told it is done.
func _release() -> void:
	var state := get_tree().root.get_node_or_null("GameState")
	var save := get_tree().root.get_node_or_null("SaveManager")
	var owed := coins
	if save != null:
		owed = int(save.call("take_shade"))
	if state != null and owed > 0:
		state.call("add_coins", owed)
		_pop(owed)
	var audio := get_tree().root.get_node_or_null("Audio")
	if audio != null:
		audio.call("play", "coin_pickup", global_position)
	set_deferred("monitoring", false)
	queue_free()


## A small "+N" floating up, so the payout is visible where it happened. Parented
## to the room, not to the shade, which is about to be freed.
func _pop(amount: int) -> void:
	var host := get_parent()
	if host == null:
		return
	var label := Label.new()
	label.text = "+%d" % amount
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#ffd166"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 3)
	label.z_index = 200
	host.add_child(label)
	label.global_position = global_position + Vector2(-14, -40)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 22.0, 0.6)
	tw.tween_property(label, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(label.queue_free)
