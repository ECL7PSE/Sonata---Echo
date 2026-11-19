extends SceneTree

## Headless probe of the long-note (hold) logic in battle.gd.
##
## Drives the real methods on a built (but never started) duel instance, so the
## state machine is exercised without a window. Prints the facts; the checks at
## the end decide RESULT.

const BATTLE_PATH := "res://scripts/battle/battle.gd"

var _fails: Array[String] = []
var b: Node


func _initialize() -> void:
	# load() rather than preload(): battle.gd references the Audio autoload, which
	# is not registered yet while a tool script is being compiled.
	b = load(BATTLE_PATH).new()
	root.add_child(b)
	# Same bypass test_battle_ui uses: _ready() refuses to build on headless.
	b._build()

	# One long ATTACK note, then a REST and a plain ATTACK.
	b._beat_sec = 0.5
	b._pattern = [
		{"beat": 0.0, "type": 0, "hold": 1.0},
		{"beat": 1.0, "type": 1},
		{"beat": 2.0, "type": 0},
	]
	b._judged = [false, false, false]
	b._build_notes()
	b._active = true
	b._phase = b.P.PLAYER
	_reset_counters()

	# --- 1. press the long note exactly on time
	b._phase_time = b._note_time(0)
	b._try_hit(0)
	print("press      : hold=%d dmg=%d hits=%d judged0=%s" % [
		b._hold_note, b._dmg_dealt, b._hits, str(b._judged[0])])
	_check(b._hold_note == 0, "pressing the long note must start the hold")
	_check(b._judged[0], "the long note must be judged on press")
	_check(b._dmg_dealt >= 1 and b._dmg_dealt <= 2,
		"one on-time hit must deal 1 (GOOD) or 2 (PERFECT) damage (got %d)" % b._dmg_dealt)
	var press_dmg: int = b._dmg_dealt

	# --- 2. hold through the tail
	var tail: float = b._note_time(0) + 1.0 * b._beat_sec
	b._phase_time = tail + 0.01
	b._tick_hold()
	print("held       : hold=%d dmg=%d hits=%d misses=%d" % [
		b._hold_note, b._dmg_dealt, b._hits, b._misses])
	_check(b._hold_note == -1, "the hold must clear once the tail passes")
	_check(b._misses == 0, "a completed hold must not count a miss")
	_check(b._hits == 1, "a completed hold must count exactly one hit (got %d)" % b._hits)
	_check(b._dmg_dealt == press_dmg, "a completed hold must keep its damage")

	# --- 3. press-and-release fast (a tap) must not leave a stuck hold
	_reset_counters()
	b._pattern = [{"beat": 0.0, "type": 0, "hold": 1.0}]
	b._judged = [false]
	b._build_notes()
	b._phase_time = b._note_time(0)
	b._try_hit(0)
	b._break_hold()
	print("tap        : hold=%d dmg=%d hits=%d misses=%d" % [
		b._hold_note, b._dmg_dealt, b._hits, b._misses])
	_check(b._hold_note == -1, "breaking a hold must clear it")
	_check(b._dmg_dealt == 0, "a broken hold must not keep its damage")
	_check(b._hits == 0 and b._misses == 1, "a broken hold is one miss and no hit")

	# --- 4. a second press while still holding must not silently orphan the first
	_reset_counters()
	b._pattern = [
		{"beat": 0.0, "type": 0, "hold": 1.0},
		{"beat": 1.0, "type": 0},
	]
	b._judged = [false, false]
	b._build_notes()
	b._phase_time = b._note_time(0)
	b._try_hit(0)
	var first: int = b._hold_note
	b._phase_time = b._note_time(1)
	b._try_hit(0)
	print("overlap    : first=%d now=%d dmg=%d hits=%d" % [
		first, b._hold_note, b._dmg_dealt, b._hits])
	_check(first == 0, "the first long note must start holding")
	# A second long note resolves the first one rather than orphaning it: the
	# abandoned hold is banked as a miss and the new note takes over.
	_check(b._hold_note == -1, "a new press must end the held long note")
	_check(b._misses == 1, "the abandoned hold must count exactly one miss")

	# --- report
	if _fails.is_empty():
		print("RESULT: OK")
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL")
	quit()


func _reset_counters() -> void:
	b._hits = 0
	b._misses = 0
	b._total_hits = 0
	b._total_misses = 0
	b._total_feints = 0
	b._combo = 0
	b._dmg_dealt = 0
	b._clear_hold()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)
