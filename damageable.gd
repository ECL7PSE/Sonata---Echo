extends CharacterBody2D
## Shared health, damage, invincibility and death logic.
##
## Both the player and every enemy extend this, so "what happens when something
## takes damage" is written once. The two classes disagree about very little: the
## player respawns at PlayerStart, an enemy drops coins, and the player's
## invincibility is much longer - so those are overridable hooks that default to
## doing nothing rather than branches inside the damage path.
##
## Health is in half-hearts. max_health 10 is five hearts, and every hit is an
## even number, so there is never a half heart that is not also a whole number of
## hearts in progress.

signal health_changed(current: int, maximum: int)
signal died()

@export var max_health := 10
@export var invincibility_time := 0.8
## Seconds the floating damage number takes to rise and fade.
@export var damage_number_time := 0.6
## Knockback pushed away from the source. Zero disables it.
@export var knockback_strength := 180.0

var health: int
## Counts down while invulnerable. Zero means damage lands.
var _iframe_left := 0.0
var _dying := false
## Set while the invincibility flash is running, so the blink loop can stop.
var _flashing := false


func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if _iframe_left > 0.0:
		_iframe_left -= delta
		if _iframe_left <= 0.0:
			_end_invincibility()


## True while damage is being ignored.
func is_invulnerable() -> bool:
	return _iframe_left > 0.0 or _dying


## Applies damage, knockback and the invincibility window.
##
## `source_position` is the thing that hurt you; knockback pushes AWAY from it, so
## a trap shoves you off its spikes rather than into them. Returns true if the
## damage actually landed.
func take_damage(amount: int, source_position: Vector2) -> bool:
	if amount <= 0 or is_invulnerable():
		return false
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)

	var away := global_position - source_position
	if away.length() < 0.001:
		away = Vector2.UP
	away = away.normalized()
	# Knockback is applied directly to velocity rather than move_and_slide, so it
	# happens on the hit frame instead of waiting for the next physics step.
	velocity += away * knockback_strength

	_spawn_damage_number(amount, source_position)
	_on_damaged(away, amount)

	if health <= 0:
		_die()
	else:
		_begin_invincibility()
	return true


## Heals, clamped to max. Returns the amount actually healed.
func heal(amount: int) -> int:
	if amount <= 0 or _dying:
		return 0
	var before := health
	health = mini(health + amount, max_health)
	if health != before:
		health_changed.emit(health, max_health)
	return health - before


## Refills and clears the invincibility timer. Used on respawn.
func reset_health() -> void:
	_dying = false
	health = max_health
	_iframe_left = 0.0
	_end_invincibility()
	health_changed.emit(health, max_health)


func _begin_invincibility() -> void:
	_iframe_left = invincibility_time
	_start_invincibility_flash()


func _end_invincibility() -> void:
	_iframe_left = 0.0
	_stop_invincibility_flash()


## Overridable: the subclass decides what happens right after a hit.
func _on_damaged(_push_direction: Vector2, _amount: int) -> void:
	pass


## Overridable: the subclass decides what zero health means.
func _die() -> void:
	_dying = true
	died.emit()


## The white blink during invincibility. Overridden by subclasses that own a
## different visual, such as the player.
func _start_invincibility_flash() -> void:
	pass


func _stop_invincibility_flash() -> void:
	pass


## A Label that rises and fades over damage_number_time.
func _spawn_damage_number(amount: int, source_position: Vector2) -> void:
	var layer := get_tree().get_first_node_in_group("damage_numbers")
	if layer == null:
		layer = get_parent()
	if layer == null:
		return
	var label := Label.new()
	label.text = str(amount)
	# Centre the label on the point of impact and offset it above the body, so the
	# number does not sit inside the sprite.
	label.position = to_local(source_position) + Vector2(-8, -28)
	label.z_index = 100
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 0.72, 0.72))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 3)
	layer.add_child(label)

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(0, -22),
		damage_number_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, damage_number_time)
	tween.chain().tween_callback(label.queue_free)