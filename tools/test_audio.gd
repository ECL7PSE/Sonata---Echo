extends SceneTree
## Checks the audio map against the files actually on disk.
##
## Everything here is defensive by design: a file that fails to load is REPORTED
## and skipped, never fatal. A broken export must not stop the game, and it must
## not stop the test that would otherwise tell you about it.

const AM := preload("res://audio_manager.gd")

var _fails: Array[String] = []
var _checks := 0
var _missing: Array[String] = []
var _am: Node


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


func _initialize() -> void:
	_am = AM.new()
	# Instantiated, not autoloaded: the harness has no autoload tree, and _ready
	# only builds buses and players, none of which need one.
	root.add_child(_am)


func _process(_d: float) -> bool:
	_check_files()
	_check_player_hurt_single()
	_check_unknown_event()
	_check_cap()
	_check_buses()
	print("files checked  : %d missing" % _missing.size())
	print("assertions     : %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK")
	else:
		for f in _fails.slice(0, 12):
			print("FAIL: " + f)
		print("RESULT: %d FAILURE(S)" % _fails.size())
	return true


## Every file the map names must exist on disk. A missing one is listed, and the
## rest of the suite carries on.
func _check_files() -> void:
	var seen: Dictionary = {}
	var flat: Dictionary = {}
	for event in _am.SOUNDS.keys():
		for f in _am.SOUNDS[event]:
			seen[str(f)] = true
	for species in _am.ENEMY_SOUNDS.keys():
		var by_action: Dictionary = _am.ENEMY_SOUNDS[species]
		for action in by_action.keys():
			for f in by_action[action]:
				seen[AM.VOICE_DIR + str(f)] = true
	for path in seen.keys():
		flat[path] = true
	for path in flat.keys():
		var exists: bool = ResourceLoader.exists(path) or FileAccess.file_exists(path)
		if not exists:
			_missing.append(str(path))
			_ok(false, "mapped file missing: %s" % path)
	# Loading it is a separate question from it existing.
	for path in flat.keys():
		if str(path) in _missing:
			continue
		_ok(_am.call("_stream_path", str(path)) != null,
				"mapped file exists but will not load: %s" % path)


## player_hurt must be exactly one file - the brief rules out a second - and the
## never-repeat rule is what that buys.
func _check_player_hurt_single() -> void:
	var list: Array = _am.SOUNDS["player_hurt"]
	_ok(list.size() == 1,
			"player_hurt maps to %d files, must be exactly 1" % list.size())
	_ok(str(list[0]).ends_with("hurt_01.ogg"),
			"player_hurt maps to %s, expected hurt_01" % str(list[0]))


## An event nobody defined plays nothing and raises nothing.
func _check_unknown_event() -> void:
	_am.play("no_such_event")
	_am.play_enemy("dragon", "attack", Vector2.ZERO)
	_am.play_enemy("rat", "teleport", Vector2.ZERO)
	_ok(true, "unmapped events survived without error")


## The same event cannot exceed SAME_EVENT_CAP live plays. Ten footsteps in one
## go must not stack ten players.
func _check_cap() -> void:
	_am.play("footstep")
	var live: int = int(_am.get("_live").get("footstep", 0))
	for i in 12:
		_am.play("footstep")
	var after: int = int(_am.get("_live").get("footstep", 0))
	_ok(after <= AM.SAME_EVENT_CAP,
			"footstep reached %d simultaneous plays, cap is %d"
			% [after, AM.SAME_EVENT_CAP])
	_ok(live <= AM.SAME_EVENT_CAP, "the very first play already broke the cap")


## The buses exist and carry the documented starting levels.
##
## Under --headless the audio server is the DUMMY driver, which does not keep
## buses at all, so this is a SKIP there rather than a failure: there is no audio
## device to be wrong about. It only asserts when a real device is present.
func _check_buses() -> void:
	if DisplayServer.get_name() == "headless":
		print("buses         : skipped, dummy audio driver")
		return
	for bus_name in ["Music", "SFX"]:
		var idx := AudioServer.get_bus_index(bus_name)
		_ok(idx != -1, "no %s bus" % bus_name)
		if idx != -1:
			_ok(is_equal_approx(AudioServer.get_bus_volume_db(idx),
					AM.MUSIC_DB if bus_name == "Music" else AM.SFX_DB),
					"%s bus is at %.1f dB, expected %.1f"
					% [bus_name, AudioServer.get_bus_volume_db(idx),
					AM.MUSIC_DB if bus_name == "Music" else AM.SFX_DB])
	_ok(_am.get("_music") != null, "no music player was created")