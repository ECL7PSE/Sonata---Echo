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

	# The lane words were cut on request: the rail and the keycaps carry the
	# meaning now, so none of them may come back.
	for name in ["fight", "rest", "feint", "ATTACK", "REST", "FEINT"]:
		if labels.has(name):
			problems.append("lane word %s should have been removed" % name)

	if b._beat_dots.size() != 4:
		problems.append("expected 4 beat dots, got %d" % b._beat_dots.size())
	if b._lane_glow.size() != 4:
		problems.append("expected 4 lane glows, got %d" % b._lane_glow.size())
	if b._pbar_fill == null or b._pbar_fill.texture == null:
		problems.append("player health bar has no fill texture")
	if b._ebar_fill == null or b._ebar_fill.texture == null:
		problems.append("enemy health bar has no fill texture")
	if b._turn_layer == null or b._turn_layer.get_child_count() == 0:
		problems.append("turn banner has no artwork")
	if b._turn_layer != null and b._turn_layer.visible:
		problems.append("turn banner should start hidden")

	# the small top phase label was replaced by a centred fade-in banner; the
	# sparkle pips still sit at the top of the screen.
	if b._beat_dots.size() > 0 and b._beat_dots[0].position.y > 60:
		problems.append("turn pips not at the top: y=%.0f" % b._beat_dots[0].position.y)

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
