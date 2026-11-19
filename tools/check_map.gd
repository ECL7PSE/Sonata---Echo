extends SceneTree

## Headless check of the map overlay: it builds, opens, can read the dungeon's
## room rects off a bare instance (the risky bit - const access on an instance
## rather than on the script), and marks the things worth walking to.
##
## The markers are the map paying off: a gold dot on every chest that has not
## been opened yet, and one red mark on the room the boss is in.

## The map's own colours, restated here.
##
## gothic_ui.gd is NOT preloaded: it names the Audio autoload, and a --script
## tool has no autoloads at compile time, so preloading it breaks the tool.
const GOLD := Color("#d4af37")
const CRIMSON := Color("#b81422")

var _fails: Array[String] = []
var _map: Node
var _main: Node
var _frames := 0
var _stage := 0


func _initialize() -> void:
	var script = load("res://scripts/ui/map_ui.gd")
	_check(script != null, "map_ui.gd must load")
	if script == null:
		_finish()
		return
	_map = script.new()
	root.add_child(_map)
	_map.call("open", false)
	_check(_map.visible, "open() must show the map")
	_check(_map.get_child_count() > 0, "the map must build a panel")
	_map.call("close")
	_check(not _map.visible, "close() must hide the map")

	var builder = load("res://scripts/world/dungeon_builder.gd").new()
	_check(builder.ROOMS.size() == 9, "the map needs 9 rooms (got %d)" % builder.ROOMS.size())
	var cell: float = float(builder.GRID) * float(builder.SCALE)
	_check(cell > 0.0, "GRID * SCALE must be a real pixel scale")
	var hall: Rect2i = builder.ROOMS["hall"]
	_check(hall.size.x > 0 and hall.size.y > 0, "hall must have a real footprint")
	builder.free()

	# Echo descriptions must be hand-wrapped or they run under the next cell.
	var wrapped: String = _map.call("_wrap",
		"Long notes need only a third of the bar.", 22)
	_check(wrapped.contains("\n"), "long echo text must wrap onto a second line")
	for line in wrapped.split("\n"):
		_check(line.length() <= 22, "wrapped line too long: '%s'" % line)

	# The marker checks need the real dungeon standing.
	_main = load("res://scenes/Main.tscn").instantiate()


func _process(_delta: float) -> bool:
	match _stage:
		0:
			root.add_child(_main)
			_frames = 0
			_stage = 1
		1:
			_frames += 1
			if _frames < 8:
				return false
			_check_markers()
			_finish()
			return true
	return false


## The boss room is marked, and every unopened chest has a gold dot.
func _check_markers() -> void:
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_fails.append("no GameState autoload")
		return
	var boss_rooms: Array = gs.get("boss_rooms")
	_check(boss_rooms.has("bone_hall"),
		"the dungeon must mark the boss room (got %s)" % str(boss_rooms))

	var props := _main.get_node_or_null("Dungeon/Props")
	if props == null:
		_fails.append("no Props node, cannot count the chests")
		return
	var unopened := 0
	for child in props.get_children():
		if str(child.name).begins_with("Chest_") and not bool(child.get("opened")):
			unopened += 1
	_check(unopened > 0, "the floor must have chests to mark")
	print("chests to mark : %d" % unopened)

	_map.call("open", false)
	var board: Node = _map.get("_board")
	if board == null:
		_fails.append("the map has no board to draw on")
		return
	var gold := 0
	var red := 0
	for c in board.get_children():
		if not c is ColorRect:
			continue
		var col: Color = (c as ColorRect).color
		if col.a < 0.99:
			continue
		if col.is_equal_approx(GOLD):
			gold += 1
		elif col.is_equal_approx(CRIMSON):
			red += 1
	print("markers drawn  : %d gold, %d red" % [gold, red])
	_check(gold == unopened,
		"the map must mark every unopened chest (%d marked, %d waiting)" % [gold, unopened])
	_check(red == 1, "the map must mark the boss room once (got %d)" % red)


func _finish() -> void:
	if _main != null:
		_main.queue_free()
	if _fails.is_empty():
		print("RESULT: OK - map builds, reads the room table and marks the loot and the boss")
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL")
	quit()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)
