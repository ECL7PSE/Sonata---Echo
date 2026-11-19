extends Node
## Persistent player settings: audio volumes and window mode.
##
## Applied on boot and saved to user://settings.cfg whenever they change, so the
## menu and the pause screen share one source of truth and the choice survives a
## restart.

const PATH := "user://settings.cfg"

var music := 1.0
var sfx := 1.0
var fullscreen := false
## Window size to come back to when leaving fullscreen, so the window does not
## return at some cramped default.
var _windowed_size := Vector2i.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		music = clampf(float(cfg.get_value("audio", "music", 1.0)), 0.0, 1.0)
		sfx = clampf(float(cfg.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
		fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	apply()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(PATH)


## Pushes the current values into the engine. Safe to call any time.
func apply() -> void:
	_set_bus("Music", music)
	_set_bus("SFX", sfx)
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
		if not fullscreen and _windowed_size != Vector2i.ZERO:
			DisplayServer.window_set_size(_windowed_size)


## F11 toggles from anywhere, including mid-run.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F11:
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()


func set_music(value: float) -> void:
	music = clampf(value, 0.0, 1.0)
	apply()
	save_settings()


func set_sfx(value: float) -> void:
	sfx = clampf(value, 0.0, 1.0)
	apply()
	save_settings()


## Returns the mode actually in effect. Embedded editor views ignore the
## request, so callers can tell the user why nothing happened.
func set_fullscreen(on: bool) -> bool:
	if on and not fullscreen:
		_windowed_size = DisplayServer.window_get_size()
	fullscreen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if not on and _windowed_size != Vector2i.ZERO:
		DisplayServer.window_set_size(_windowed_size)
	save_settings()
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	return DisplayServer.window_get_mode() == want


func _set_bus(bus: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value, 0.001)))
