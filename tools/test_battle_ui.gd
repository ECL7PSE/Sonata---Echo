extends SceneTree

# Headless smoke test for the rhythm-duel UI. _ready() bails out in headless,
# so we call _build() by hand and assert the layout is sane.

func _initialize() -> void:
	var problems: Array[String] = []
	var BattleScript = load("res://scripts/battle/battle.gd")
	var b = BattleScript.new()
	root.add_child(b)
	b._build()

	if b.get_child_count() == 0:
		problems.append("battle built no UI root")

	var labels := {}
	var stack: Array = [b]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Label:
			labels[str(n.text)] = n

	for name in ["ATTACK", "REST", "FEINT"]:
		if not labels.has(name):
			problems.append("missing lane label " + name)
		else:
			var ly: float = labels[name].position.y
			if ly < 506.0:
				problems.append("lane label %s at y=%.0f overlaps the track" % [name, ly])

	if b._beat_dots.size() != 4:
		problems.append("expected 4 beat dots, got %d" % b._beat_dots.size())
	if b._lane_glow.size() != 3:
		problems.append("expected 3 lane glows, got %d" % b._lane_glow.size())
	if b._pbar_fills.size() != 5:
		problems.append("expected 5 player bar fills, got %d" % b._pbar_fills.size())
	if b._ebar_fills.size() != 5:
		problems.append("expected 5 enemy bar fills, got %d" % b._ebar_fills.size())

	# the "RHYTHM DUEL" caption was removed on request; the phase label now
	# lives directly under the turn rings at the top instead.
	if b._phase_label.offset_top > 120:
		problems.append("phase label drifted away from the turn rings: y=%d" % b._phase_label.offset_top)
	if b._beat_dots.size() > 0 and b._beat_dots[0].position.y > 60:
		problems.append("turn rings not at the top: y=%.0f" % b._beat_dots[0].position.y)

	for key in ["rat", "slime", "bat", "mushroom", "flying_eye", "goblin", "mimic", "skeleton"]:
		var path := "res://audio/battle/%s.wav" % key
		if not FileAccess.file_exists(path):
			problems.append("missing battle music " + key)
			continue
		var s: AudioStreamWAV = AudioStreamWAV.load_from_file(path)
		if s == null or s.data.size() < 1000:
			problems.append("battle music failed to load " + key)

	print("battle ui : labels=%d dots=%d glows=%d" % [labels.size(), b._beat_dots.size(), b._lane_glow.size()])
	if problems.size() == 0:
		print("RESULT: OK")
	else:
		for p in problems:
			print("FAIL ", p)
		print("RESULT: %d problem(s)" % problems.size())
	quit()
