extends SceneTree

## The shade holds your death coins and pays them back once it dies.

const SHADE := preload("res://scripts/world/shade.gd")

var _fails: Array[String] = []


func _initialize() -> void:
	var state := root.get_node_or_null("GameState")
	var save := root.get_node_or_null("SaveManager")
	_check(state != null, "GameState autoload is missing")
	_check(save != null, "SaveManager autoload is missing")
	if state == null or save == null:
		_report()
		return

	state.call("reset")
	save.set("shade_coins", 0)
	save.set("shade_scene", "")

	var shade = SHADE.new()
	_check(shade.HITS == 3, "a shade should take three hits (got %d)" % shade.HITS)
	shade.set("coins", 45)
	root.add_child(shade)
	_check(int(shade.get("coins")) == 45, "the shade must carry the dropped coins")
	shade.free()

	# The debt lives on SaveManager: the shade asks for it when it dies, and it
	# may only be paid once.
	save.set("shade_coins", 45)
	var paid := int(save.call("take_shade"))
	_check(paid == 45, "the shade must owe the dropped coins (got %d)" % paid)
	_check(int(save.get("shade_coins")) == 0, "the debt must be cleared once it is paid")
	_check(int(save.call("take_shade")) == 0, "a cleared debt must not pay twice")

	_report()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _report() -> void:
	if _fails.is_empty():
		print("RESULT: OK - the shade holds your coins and pays them back")
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL")
	quit()
