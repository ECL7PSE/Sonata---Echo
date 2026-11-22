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
	var boss := false


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


## The phrase length the duel uses: whole bars, one to three of them.
func _bars_for(bonus: int, tier: int, round_num: int) -> int:
	var extra := maxi(1, tier) - 1
	return clampi(1 + (round_num + bonus + extra) / 4, 1, 3) * 4


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

		# Difficulty: every species declares a tier, and it lengthens the section
		# in whole bars, so the phrase ends on the music's bar line.
		var tier := int(style.get("tier", 0))
		_ok(tier >= 1 and tier <= 3, "%s has tier %d" % [key, tier])
		var want := _bars_for(int(style.get("bonus", 0)), tier, 1)
		var got := int(b.call("_phrase_len", 1))
		_ok(got == want, "%s phrase is %d beats at round 1, expected %d" % [key, got, want])
		_ok(got % 4 == 0, "%s phrase is %d beats, not whole bars" % [key, got])

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
				_ok(t >= 0 and t <= 3, "%s note has lane %d" % [key, t])
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

		# The long notes: a bar you can finish, and the phrase waits for its tail.
		var longest := 0.0
		var tail_beat := 0.0
		for n in demo:
			var hold := float(n.get("hold", 0.0))
			longest = maxf(longest, hold)
			tail_beat = maxf(tail_beat, float(n["beat"]) + hold)
		if int(style.get("holds", 0)) > 0:
			# Over a handful of phrases the duelist must hand out a real bar.
			var best := longest
			for r2 in range(3, 9):
				var phrase2: Array = b.call("_make_pattern", r2)
				for n2 in phrase2:
					best = maxf(best, float(n2.get("hold", 0.0)))
			_ok(best >= 2.0,
					"%s promises long notes but the longest is %.1f beats" % [key, best])
			_ok(best <= float(style.get("hold_beats", 2)) + 0.01,
					"%s has a %.1f beat long note, longer than its %.1f beat bar"
					% [key, best, float(style.get("hold_beats", 2))])
		b.call("_set_pattern", demo)
		_ok(float(b.get("_pattern_last_beat")) >= tail_beat - 0.01,
				"%s ends its phrase before the long note finishes" % key)

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

	# Four rails: every lane must turn up in the phrases, or a key is dead.
	var seen_lanes := {}
	mock.species = "skeleton"
	for r in range(1, 9):
		var phrase: Array = b.call("_make_pattern", r)
		for n in phrase:
			seen_lanes[int(n["type"])] = true
	for lane in range(4):
		_ok(seen_lanes.has(lane), "lane %d never appears in any phrase" % lane)

	# The answer ignores memory: swapping lanes is a real change of keys. The
	# mimic trades rest and feint, so look over a few rounds - a single phrase
	# can be all strikes.
	mock.species = "mimic"
	mock.boss = false
	var moved := false
	for r in range(1, 7):
		var demo_m: Array = b.call("_make_pattern", r)
		var reply_m: Array = b.call("_make_reply", demo_m, r)
		for i in mini(demo_m.size(), reply_m.size()):
			if int(demo_m[i]["type"]) != int(reply_m[i]["type"]):
				moved = true
	_ok(moved, "the mimic's answer kept every key the same")

	# A boss extends the phrase on top of its species tier - in whole bars.
	mock.species = "skeleton"
	mock.boss = false
	var plain: int = b.call("_phrase_len", 1)
	mock.boss = true
	var boss_len: int = b.call("_phrase_len", 1)
	_ok(boss_len >= plain and (boss_len - plain) % 4 == 0,
			"a boss must get a longer section in whole bars (%d vs %d)" % [boss_len, plain])
	mock.boss = false

	# Harder duelists pair their notes earlier: a tier 3 answers in chords by
	# round 2, an easy tier 1 still answers one key at a time.
	for key in ["mimic", "rat"]:
		mock.species = key
		var tier := int(_battle.SPECIES_STYLE[key]["tier"])
		var demo_t: Array = b.call("_make_pattern", 2)
		var reply_t: Array = b.call("_make_reply", demo_t, 2)
		var paired := false
		for i in reply_t.size():
			for j in range(i + 1, reply_t.size()):
				if is_equal_approx(float(reply_t[i]["beat"]), float(reply_t[j]["beat"])) \
						and int(reply_t[i]["type"]) != int(reply_t[j]["type"]):
					paired = true
		_ok(paired == (tier >= 3), "%s (tier %d) doubles at round 2: %s" % [key, tier, paired])

	# A badly hurt duelist is bruised and slumped; a healthy one is untouched.
	var actor := Node2D.new()
	root.add_child(actor)
	actor.set_meta("face_left", false)
	actor.set_meta("slump", 0.0)
	actor.set_meta("tint", Color.WHITE)
	b.call("_apply_battered", actor, 1.0)
	_ok(actor.modulate == Color.WHITE and is_zero_approx(actor.rotation),
			"a duelist at full health must look untouched")
	b.call("_apply_battered", actor, 0.1)
	_ok(actor.modulate.r > actor.modulate.g, "a battered duelist must be bruised red")
	_ok(absf(actor.rotation) > 0.01, "a battered duelist must slump")
	actor.queue_free()

	print("species checked: %d" % keys.size())
	print("assertions     : %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK")
	else:
		for f in _fails.slice(0, 12):
			print("FAIL: " + f)
		print("RESULT: %d FAILURE(S)" % _fails.size())
	quit(0 if _fails.is_empty() else 1)
