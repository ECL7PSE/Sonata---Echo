extends SceneTree

## Headless check of the Echo system in the GameState autoload.
##
## Autoloads are not registered while a --script tool compiles, so everything is
## reached through /root instead of by identifier.

var _fails: Array[String] = []
var gs: Node


func _initialize() -> void:
	gs = root.get_node_or_null("GameState")
	if gs == null:
		print("FAIL: no GameState autoload")
		print("RESULT: FAIL")
		quit()
		return

	_clear()
	gs.coins = 500

	# --- buying: spends, owns, and auto-equips into a free slot
	_check(gs.buy_echo("candle_stub"), "buying candle_stub must succeed")
	_check(gs.coins == 450, "buying must spend 50 (coins=%d)" % gs.coins)
	_check(gs.has_echo("candle_stub"), "the bought echo must be owned")
	_check(gs.echo_on("candle_stub"), "a bought echo must auto-equip")
	_check(not gs.buy_echo("candle_stub"), "buying an owned echo must fail")

	# --- candle stub discounts the shelf
	_check(gs.echo_cost("metronome") == 36, "candle_stub must make metronome 36 (got %d)"
		% gs.echo_cost("metronome"))
	gs.toggle_echo("candle_stub")
	_check(not gs.echo_on("candle_stub"), "toggling a worn echo must take it off")
	_check(gs.echo_cost("metronome") == 45, "price must go back to 45 when unworn")

	# --- three slots, not four
	for id in ["metronome", "grubsong", "grave_bell"]:
		_check(gs.buy_echo(id), "buying %s must succeed" % id)
	_check(gs.echoes_equipped.size() == gs.ECHO_SLOTS,
		"equipped must fill exactly %d slots (got %d)"
		% [gs.ECHO_SLOTS, gs.echoes_equipped.size()])
	gs.toggle_echo("candle_stub")
	_check(gs.echoes_equipped.size() == gs.ECHO_SLOTS,
		"a fourth echo must not fit (got %d)" % gs.echoes_equipped.size())
	_check(not gs.echo_on("candle_stub"), "the overflowing echo must stay off")

	# --- coins are enforced
	gs.coins = 0
	_check(not gs.buy_echo("hollow_note"), "buying without coins must fail")
	_check(not gs.has_echo("hollow_note"), "a failed buy must not grant the echo")

	# --- the map remembers rooms once
	gs.mark_explored("hall")
	gs.mark_explored("hall")
	gs.mark_explored("")
	_check(gs.explored.size() == 1, "mark_explored must dedupe (got %d)" % gs.explored.size())

	# --- death wipes the map but keeps the echoes
	gs.reset()
	_check(gs.explored.is_empty(), "reset must clear the map")
	_check(gs.has_echo("metronome"), "reset must keep owned echoes")
	_check(gs.echo_on("metronome"), "reset must keep the equipped set")

	if _fails.is_empty():
		print("RESULT: OK")
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: FAIL")
	quit()


func _clear() -> void:
	gs.echoes_owned.clear()
	gs.echoes_equipped.clear()
	gs.explored.clear()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)
