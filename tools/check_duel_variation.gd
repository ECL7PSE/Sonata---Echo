extends SceneTree
## Headless check for the duel's variety rules.
##
## The complaint was that every duel played the same phrase back and grew stale,
## so this pins the rules that keep it varied: every species has its own tempo
## and its own answer, the player's section is never a copy of the enemy's, and
## the generated track beats match the tempo the rail runs on.

const MUSIC_DIR := "res://audio/battle/"

var _battle: GDScript

var _fails: Array[String] = []
var _checks := 0


class MockEnemy extends Node:
	var species := ""


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


func _initialize() -> void:
	seed(4242)
	# load(), not preload(): battle.gd reaches the Audio autoload, which only
	# resolves once the project is up.
	_battle = load("res://scripts/battle/battle.gd")
	var b: CanvasLayer = _battle.new()
	root.add_child(b)
	var mock := MockEnemy.new()
	root.add_child(mock)
	b.set("_enemy", mock)

	var keys: Array = _battle.SPECIES_STYLE.keys()
	_ok(keys.size() == 8, "expected 8 species styles, got %d" % keys.size())

	var bpms: Dictionary = {}
	for key in keys:
		mock.species = key
		var style: Dictionary = _battle.SPECIES_STYLE[key]
		bpms[int(style["bpm"])] = true
		_ok(style.has("answer"), "%s has no answer style" % key)

		# The enemy's phrase and the player's answer must not be the same section.
		var demo: Array = b.call("_make_pattern", 2)
		var reply: Array = b.call("_make_reply", demo, 2)
		_ok(not demo.is_empty(), "%s produced an empty phrase" % key)
		_ok(not reply.is_empty(), "%s produced an empty answer" % key)
		_ok(str(b.call("_signature", demo)) != str(b.call("_signature", reply)),
				"%s answers its own phrase (copy, not variation)" % key)
		for arr in [demo, reply]:
			for n in arr:
				var t: int = int(n["type"])
				_ok(t >= 0 and t <= 2, "%s note has lane %d" % [key, t])
				_ok(float(n["beat"]) >= 0.0, "%s note lands before the section" % key)

		# Later rounds add double notes: two lanes on one beat.
		var late: Array = b.call("_make_reply", demo, 6)
		var paired := false
		for i in late.size():
			for j in range(i + 1, late.size()):
				if is_equal_approx(float(late[i]["beat"]), float(late[j]["beat"])) \
						and int(late[i]["type"]) != int(late[j]["type"]):
					paired = true
		_ok(paired, "%s never lands a double note by round 6" % key)

		# The rail runs on the same grid as the generated track.
		var path: String = MUSIC_DIR + key + ".wav"
		_ok(FileAccess.file_exists(path), "missing track " + path)
		if not FileAccess.file_exists(path):
			continue
		var stream: AudioStreamWAV = AudioStreamWAV.load_from_file(path)
		_ok(stream != null, "track will not load: " + path)
		if stream == null:
			continue
		var seconds := float(stream.data.size() * 0.5) / float(stream.mix_rate)
		var beat := 60.0 / float(style["bpm"])
		var beats := seconds / beat
		_ok(seconds > 3.0, "%s track is only %.1f s" % [key, seconds])
		_ok(absf(beats - roundf(beats)) < 0.06,
				"%s track is %.2f beats at %d bpm, not a whole bar count"
				% [key, beats, int(style["bpm"])])

	_ok(bpms.size() == keys.size(),
			"%d of %d species share a tempo" % [keys.size() - bpms.size(), keys.size()])

	# The answer ignores memory: swapping lanes is a real change of keys.
	mock.species = "mimic"
	var demo_m: Array = b.call("_make_pattern", 1)
	var reply_m: Array = b.call("_make_reply", demo_m, 1)
	var moved := false
	for i in mini(demo_m.size(), reply_m.size()):
		if int(demo_m[i]["type"]) != int(reply_m[i]["type"]):
			moved = true
	_ok(moved, "the mimic's answer kept every key the same")

	print("species checked: %d" % keys.size())
	print("assertions     : %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK")
	else:
		for f in _fails.slice(0, 12):
			print("FAIL: " + f)
		print("RESULT: %d FAILURE(S)" % _fails.size())
	quit(0 if _fails.is_empty() else 1)
