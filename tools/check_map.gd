extends SceneTree

## Headless check of the map overlay: it builds, opens, and can read the
## dungeon's room rects off a bare instance (the risky bit — const access on an
## instance rather than on the script).

var _fails: Array[String] = []
var _map: Node


func _initialize() -> void:
	var script = load("res://scripts/ui/map_ui.gd")
	_check(script != null, "map_ui.gd must load")
	if script != null:
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
	if _map != null:
		var wrapped: String = _map.call("_wrap",
			"Long notes need only a third of the bar.", 22)
		_check(wrapped.contains("\n"), "long echo text must wrap onto a second line")
		for line in wrapped.split("\n"):
			_check(line.length() <= 22, "wrapped line too long: '%s'" % line)

	if _fails.is_empty():
		print("RESULT: OK - map builds and the room table reads")
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL")
	quit()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)
