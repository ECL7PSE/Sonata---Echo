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
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


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
	fullscreen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)
	save_settings()
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	return DisplayServer.window_get_mode() == want


func _set_bus(bus: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value, 0.001)))
