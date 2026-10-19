extends Node
## Every sound in the game, in one place.
##
## SOUNDS is the single source of truth: an event maps to a list of files and
## play() picks one at random, so adding a sound is adding a line HERE. No
## other file in the project knows an audio filename.
##
## Everything degrades safely: an unknown event, or one whose files all fail to
## load, plays NOTHING and raises no error. A headless run on the dummy audio
## driver has no output device, and that must not stop the game.

const OGG_DIR := "res://audio/OGG/"
## The monster voices come from a different pack and sit at the top level of
## Sound/, so they resolve here, not under OGG/. Only the Kenney footsteps and
## knives live in the sub-folder.
const VOICE_DIR := "res://audio/"

## Starting levels, in dB, in one place.
const MUSIC_DB := -12.0
const SFX_DB := -4.0

## Simultaneous plays of the SAME event before more are dropped. A chest throws
## a dozen coins at once; without this it is a wall of noise.
const SAME_EVENT_CAP := 3

const SFX_POOL := 12
const POSITIONAL_POOL := 8

## Pitch spread so a repeated effect never sounds copy-pasted.
const PITCH_MIN := 0.92
const PITCH_MAX := 1.08
## Events that also get a volume wobble.
const VARIED := ["player_slash", "footstep", "coin_collect", "player_hurt"]
const VARIATION_DB := 2.0

## A monster further than this is silent.
const MAX_AUDIBLE_PX := 400.0

## Music. An MP3 loops with an audible click at the seam, but ffmpeg is not
## installed on this machine, so the MP3 ships as-is with loop enabled.
const MUSIC := "res://audio/Background Music.mp3"
const MUSIC_FADE := 1.5

## The boss is a skeleton with the same clips, pitched down so it reads as bigger.
const BOSS_PITCH := 0.8
const BOSS_SPECIES := "skeleton"


func _footsteps() -> Array:
	var out: Array = []
	for i in 10:
		out.append(OGG_DIR + "footstep%02d.ogg" % i)
	return out


## event -> [files]. This is the map; nothing else lists audio filenames.
var SOUNDS: Dictionary = {
	"music": [MUSIC],
	"player_slash": ["res://audio/Sword Slash.mp3"],
	"footstep": _footsteps(),
	"chest_open": ["res://audio/freesound_community-wood-chest-slid3-90317.mp3"],
	"coin_drop": ["res://audio/freesound_community-coins-falling-022-37390.mp3"],
	"coin_collect": ["res://audio/driken5482-retro-coin-4-236671.mp3"],
	"vase_break": ["res://audio/freesound_community-breaking-a-vase-remix-87091.mp3"],
	"crate_break": ["res://audio/freesound_community-wood-crate-destory-2-97263.mp3"],
	# ONE file only, so the never-repeat rule is skipped for it; the random
	# pitch is kept so repeated hits are not identical.
	"player_hurt": ["res://audio/hurt_01.ogg"],
	"trap_spike": [OGG_DIR + "knifeSlice.ogg", OGG_DIR + "knifeSlice2.ogg"],
}

## species -> action -> [files, in OGG_DIR]. Positional, via play_enemy().
var ENEMY_SOUNDS: Dictionary = {
	"rat": {"attack": ["bug_01.ogg", "bug_02.ogg"],
		"hurt": ["cute_01.ogg", "cute_02.ogg"],
		"death": ["cute_03.ogg", "cute_04.ogg"]},
	"bat": {"attack": ["bug_03.ogg", "bug_04.ogg"],
		"hurt": ["cute_05.ogg", "cute_06.ogg"],
		"death": ["cute_07.ogg", "cute_08.ogg"]},
	"slime": {"attack": ["burble_01.ogg"],
		"hurt": ["burble_02.ogg"],
		"death": ["burp_01.ogg", "burp_02.ogg"]},
	"mushroom": {"attack": ["spit_01.ogg", "spit_02.ogg"],
		"hurt": ["spit_03.ogg"],
		"death": ["cough_01.ogg", "cough_02.ogg"]},
	"flying_eye": {"attack": ["alien_01.ogg", "alien_02.ogg"],
		"hurt": ["alien_03.ogg", "alien_04.ogg"],
		"death": ["alien_05.ogg", "alien_06.ogg"]},
	"goblin": {"attack": ["troll_01.ogg", "grunt_01.ogg"],
		"hurt": ["grunt_02.ogg", "grunt_03.ogg"],
		"death": ["troll_02.ogg", "troll_03.ogg"]},
	"skeleton": {"attack": ["weird_01.ogg", "weird_02.ogg"],
		"hurt": ["weird_03.ogg"],
		"death": ["weird_04.ogg", "weird_05.ogg"]},
	"mimic": {"burst": ["monster_01.ogg", "roar_01.ogg"],
		"attack": ["monster_02.ogg", "monster_03.ogg"],
		"hurt": ["monster_04.ogg"],
		"death": ["monster_05.ogg", "monster_06.ogg", "roar_02.ogg"]},
}

var _players: Array[AudioStreamPlayer] = []
var _positional: Array[AudioStreamPlayer2D] = []
var _stream_cache: Dictionary = {}
func _ready() -> void:
	_rng.randomize()
	_make_buses()
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	for i in POSITIONAL_POOL:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = "SFX"
		p2.max_distance = MAX_AUDIBLE_PX * 2.0
		add_child(p2)
		_positional.append(p2)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	start_music()


## Buses are made in code so there is no .tres to drift out of step with the
## levels above.
func _make_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
	var sfx := AudioServer.get_bus_index("SFX")
	var music := AudioServer.get_bus_index("Music")
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, SFX_DB)
		AudioServer.set_bus_send(sfx, "Master")
	if music >= 0:
		AudioServer.set_bus_volume_db(music, MUSIC_DB)
		AudioServer.set_bus_send(music, "Master")


## Background music, started on load and faded in. Nothing re-triggers it, so it
## loops for the whole session and never restarts on death or respawn.
func start_music() -> void:
	if _music == null:
		return
	var s := _stream_path(MUSIC)
	if s == null:
		return
	# loop lives on the STREAM, not on the player: AudioStreamPlayer has no loop
	# property, and assigning one is a runtime error. _stream_path turns looping
	# off for every clip it hands out, so the music's is re-enabled here.
	if s is AudioStreamMP3 or s is AudioStreamOggVorbis:
		s.loop = true
	_music.stream = s
	_music.volume_db = -40.0
	_music.play()
	var tw := create_tween()
	if tw != null:
		tw.tween_property(_music, "volume_db", 0.0, MUSIC_FADE)


## Plays a sound. An unknown event, or one whose files are all missing, is a
## silent no-op - never an error.
##
## `at` is a world position; null means non-positional. Everything the player
## causes passes null, which is what keeps their own footsteps centred.
func play(event: String, at: Variant = null) -> void:
	if not SOUNDS.has(event):
		return
	var files: Array = SOUNDS[event]
	if files.is_empty() or int(_live.get(event, 0)) >= SAME_EVENT_CAP:
		return
	var s := _pick(files, event)
	if s == null:
		return
	var pitch := _rng.randf_range(PITCH_MIN, PITCH_MAX)
	var vol := 0.0
	if VARIED.has(event):
		vol = _rng.randf_range(-VARIATION_DB, VARIATION_DB)
	if at == null:
		var p := _free_player()
		if p == null:
			return
		p.stream = s
		p.pitch_scale = pitch
		p.volume_db = vol
		p.play()
	else:
		var p2 := _free_positional()
		if p2 == null:
			return
		p2.stream = s
		p2.pitch_scale = pitch
		p2.volume_db = vol
		p2.global_position = at
		p2.play()
	_note(event)


## A species' attack / hurt / death / burst clip: positional, and only if the
## monster is near enough to hear.
func play_enemy(species: String, action: String, at: Vector2,
		boss := false) -> void:
	var key := BOSS_SPECIES if boss else species.to_lower()
	if not ENEMY_SOUNDS.has(key):
		return
	var by_action: Dictionary = ENEMY_SOUNDS[key]
	if not by_action.has(action) or not _in_range(at):
		return
	var files: Array = []
	for n in by_action[action]:
		files.append(VOICE_DIR + str(n))
	var event := "enemy:%s:%s" % [key, action]
	var s := _pick(files, event)
	if s == null:
		return
	var p := _free_positional()
	if p == null:
		return
	p.stream = s
	p.pitch_scale = _rng.randf_range(PITCH_MIN, PITCH_MAX) \
			* (BOSS_PITCH if boss else 1.0)
	p.volume_db = 0.0
	p.global_position = at
	p.play()
	_note(event)


func _in_range(at: Vector2) -> bool:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return true
	var player: Node = null
	for c in tree.current_scene.get_children():
		if c.has_method("take_damage") and c.has_method("do_attack"):
			player = c
			break
	if player == null:
		return true
	return (player as Node2D).global_position.distance_to(at) <= MAX_AUDIBLE_PX


## Random pick, never the same file twice in a row. A single-file event has
## nothing to choose between, so the rule costs it nothing.
func _pick(files: Array, event: String) -> AudioStream:
	if files.size() == 1:
		return _stream_path(str(files[0]))
	var idx := _rng.randi_range(0, files.size() - 1)
	if idx == int(_last_pick.get(event, -1)):
		idx = (idx + 1) % files.size()
	_last_pick[event] = idx
	return _stream_path(str(files[idx]))


## Loads and caches. A file that will not load is reported ONCE and remembered,
## so one broken export does not retry on every footstep for the whole run.
func _stream_path(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	if s == null:
		push_warning("audio: could not load %s" % path)
	else:
		# Only the music loops, and it has its own player, so nothing on a
		# pooled player may ever be left looping.
		s.loop = false
	_stream_cache[path] = s
	return s


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return null


func _free_positional() -> AudioStreamPlayer2D:
	for p in _positional:
		if not p.playing:
			return p
	return null


func _note(event: String) -> void:
	_live[event] = int(_live.get(event, 0)) + 1
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(1.2).timeout.connect(func() -> void:
		_live[event] = maxi(0, int(_live.get(event, 0)) - 1))
## event -> file index played last, so the same file is not repeated.
var _last_pick: Dictionary = {}
## event -> how many of its clips are sounding now, for the cap.
var _live: Dictionary = {}
var _music: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()