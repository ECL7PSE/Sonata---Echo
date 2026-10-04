extends SceneTree
## Proves the spike trap's cycle is the one the art actually describes: every
## measured travel frame is shown, in order, and the spikes are then flat for a
## full two seconds.
##
## This drives a real trap from the live scene and watches which animation frame
## the sprite ends up on, second by second, rather than trusting the constant.

const TRAP := preload("res://trap.gd")
## Mirrors trap.gd's own constants, restated here so the test fails if they drift.
const EXPECTED_TRAVEL: Array[int] = [4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
const EXPECTED_SAFE_SECONDS := 2.0
const DOWN_FRAME_1BASED := 1
## Generous slack: the loop only has to be accurate to a frame or two.
const TOLERANCE := 0.20

var _fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var trap: Node = TRAP.new()
	# trap.gd reaches for $Sprite and $CollisionShape2D, which live in the scene
	# rather than the script. Building them here keeps this a test of the script
	# without needing a trap.tscn of its own.
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	trap.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	trap.add_child(shape)

	# All 14 frames have to exist. An AnimatedSprite2D clamps a frame index that
	# is out of range back to the last real frame, so a one-frame stub would
	# silently pin every travel frame to 0 and make the whole cycle look broken.
	var lib := SpriteFrames.new()
	lib.add_animation("spikes")
	lib.set_animation_speed("spikes", 9.0)
	lib.set_animation_loop("spikes", false)
	for i in 14:
		lib.add_frame("spikes", AtlasTexture.new())
	sprite.sprite_frames = lib

	root.add_child(trap)
	await process_frame

	print("safe_time    : %.2f s" % trap.safe_time)
	print("cycle_fps    : %.1f" % trap.cycle_fps)

	# Watch one full cycle and record every frame the sprite displays, 1-based.
	#
	# Timed against the wall clock, not against an assumed per-frame delta.
	# Headless runs idle frames far faster than the physics tick rate, so
	# accumulating 1/physics_ticks_per_second per frame invents time that never
	# passed and the whole cycle looks like it never started.
	var seen: Array[int] = []
	var marks: Array[Dictionary] = []
	var last: int = -1
	var started_usec := Time.get_ticks_usec()
	var prev_usec := started_usec
	# Long enough for the opening safe window, one travel, and the whole of the
	# next safe window: the flat duration is measured from one "1" to the "4"
	# that follows it, so the run has to reach past that second 1.
	var limit_usec := int((float(trap.safe_time) * 2.0
		+ (1.0 / trap.cycle_fps) * EXPECTED_TRAVEL.size() + 0.6) * 1000000.0)

	while Time.get_ticks_usec() - started_usec < limit_usec:
		await process_frame
		var now := Time.get_ticks_usec()
		prev_usec = now
		var shown: int = int(trap.sprite.frame) + 1
		if shown != last:
			seen.append(shown)
			marks.append({"frame": shown, "at": now})
			last = shown

	# The flat window is the gap between a "1" and the "4" that rises out of it.
	# Timing the transitions rather than sampling totals matters here: an idle
	# frame in headless is far quicker than the trap's cadence, so counting how
	# many samples happen to land on frame 1 measures the sampler, not the trap.
	var flat_seconds := -1.0
	for i in range(marks.size() - 1):
		var here: Dictionary = marks[i]
		var nxt: Dictionary = marks[i + 1]
		if int(here["frame"]) == DOWN_FRAME_1BASED \
				and int(nxt["frame"]) == EXPECTED_TRAVEL[0]:
			flat_seconds = float(int(nxt["at"]) - int(here["at"])) / 1000000.0
			break

	# The first frame is the flat pose the trap starts in. The travel frames
	# follow it in sheet order, then it returns to flat for the safe window.
	print("frames shown : %s" % str(seen))

	# The first cycle is what is being asserted. The run deliberately overshoots
	# into a second cycle to time the flat window, so the later repeats are
	# expected and must not be counted again.
	var travel: Array = []
	var started := false
	for f in seen:
		if f == EXPECTED_TRAVEL[0]:
			started = true
		if started and EXPECTED_TRAVEL.has(f):
			travel.append(f)
		elif started:
			break

	if travel != EXPECTED_TRAVEL:
		_fails.append("travel frames were %s, expected %s" % [
			str(travel), str(EXPECTED_TRAVEL)])

	for f in EXPECTED_TRAVEL:
		if not seen.has(f):
			_fails.append("travel frame %d was never displayed" % f)

	# The spikes must come back to the flat pose and go out again, otherwise the
	# "predictable safe window" only happens once and then never repeats.
	var downs := 0
	for f in seen:
		if f == DOWN_FRAME_1BASED:
			downs += 1
	if downs < 2:
		_fails.append("spikes only reached the flat pose %d time(s); the cycle " +
			"does not repeat" % downs)

	# The flat window must be a real, continuous two seconds, measured while the
	# trap actually runs rather than read off the export default.
	if flat_seconds < 0.0:
		_fails.append("never saw the spikes return to flat and rise again, so " +
			"the cycle does not repeat")
	else:
		print("flat window  : %.2f s (expected %.2f)" % [
			flat_seconds, EXPECTED_SAFE_SECONDS])
		if absf(flat_seconds - EXPECTED_SAFE_SECONDS) > TOLERANCE:
			_fails.append("flat window was %.2f s, expected %.2f s" % [
				flat_seconds, EXPECTED_SAFE_SECONDS])

	# The window has to be one unbroken stretch. Between the flat pose and the rise
	# that ends it, only travel frames may appear: anything else would mean the
	# spikes flickered and the player never got a predictable two clear seconds.
	for i in range(marks.size()):
		var m: Dictionary = marks[i]
		if int(m["frame"]) != DOWN_FRAME_1BASED:
			continue
		for j in range(i + 1, marks.size()):
			var n: Dictionary = marks[j]
			var nf := int(n["frame"])
			# The rise ends the window; the rest of the travel is expected after.
			if nf == EXPECTED_TRAVEL[0]:
				break
			if not EXPECTED_TRAVEL.has(nf):
				_fails.append("frame %d interrupted the flat window" % nf)
				break

	print("")
	if _fails.is_empty():
		print("RESULT: OK - frames %s play in order, then a %.2f s safe window" % [
			str(EXPECTED_TRAVEL), flat_seconds])
		quit(0)
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: %d FAILURE(S)" % _fails.size())
		quit(1)