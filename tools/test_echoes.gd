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

	# --- upgrading an echo spends coins and strengthens it
	gs.coins = 500
	gs.echo_levels.clear()
	var up_cost: int = gs.echo_upgrade_cost("metronome")
	_check(up_cost > 0, "an owned echo must have an upgrade price")
	_check(gs.upgrade_echo("metronome"), "upgrading must succeed with coins")
	_check(gs.coins == 500 - up_cost, "upgrading must spend %d (coins=%d)" % [up_cost, gs.coins])
	_check(gs.echo_level("metronome") == 1, "upgrading must raise the level")
	_check(gs.echo_desc("metronome") != gs.ECHOES["metronome"].desc,
		"an upgraded echo must describe its stronger form")
	_check(gs.upgrade_echo("metronome"), "the second upgrade must succeed")
	_check(gs.echo_level("metronome") == gs.ECHO_LEVEL_MAX, "the level must cap at ECHO_LEVEL_MAX")
	_check(gs.echo_upgrade_cost("metronome") == 0, "a maxed echo must have no upgrade price")
	_check(not gs.upgrade_echo("metronome"), "a maxed echo must refuse another upgrade")
	gs.coins = 0
	_check(not gs.upgrade_echo("grubsong"), "upgrading without coins must fail")
	_check(gs.echo_level("grubsong") == 0, "a failed upgrade must not raise the level")

	# --- families: three worn from one family sets its bonus off
	gs.echoes_equipped.clear()
	_check(gs.family_complete("song") == false, "no family is complete yet")
	gs.echoes_equipped.assign(["hollow_note", "metronome", "grubsong"])
	_check(gs.family_worn("song") == 3, "three song echoes are worn")
	_check(gs.family_complete("song"), "the song family must be complete")
	_check(not gs.family_complete("grave"), "the grave family must not be complete")
	gs.echoes_equipped.assign(["hollow_note", "metronome", "candle_stub"])
	_check(gs.family_complete("song") == false, "a split family must not be complete")
	_check(gs.family_worn("grave") == 1, "the grave family counts its worn echoes")
	_check(gs.family_bonus() == "", "a split family grants no bonus")

	# --- the song family pays for perfect hits
	gs.echoes_equipped.assign(["hollow_note", "metronome", "grubsong"])
	_check(gs.perfect_bonus() == 1, "the song family pays a coin per perfect hit")
	_check(gs.family_bonus().begins_with("SONG"), "the song family says what it does")

	# --- the grave family makes every coin worth more
	gs.echoes_equipped.assign(["candle_stub", "dead_mans_toll", "grave_bell"])
	_check(gs.perfect_bonus() == 0, "the grave family pays no perfect bonus")
	_check(gs.family_bonus().begins_with("GRAVE"), "the grave family says what it does")
	gs.coin_value = 1
	_check(gs.coin_worth() == 2, "the grave family adds a coin to every coin (got %d)"
		% gs.coin_worth())
	gs.coin_value = 2
	_check(gs.coin_worth() == 3, "a combat floor and the grave family stack (got %d)"
		% gs.coin_worth())
	gs.coin_value = 1
	# Back to the song family, so the reset checks below still find metronome worn.
	gs.echoes_equipped.assign(["hollow_note", "metronome", "grubsong"])

	# --- death wipes the map but keeps the echoes
	gs.reset()
	_check(gs.explored.is_empty(), "reset must clear the map")
	_check(gs.has_echo("metronome"), "reset must keep owned echoes")
	_check(gs.echo_on("metronome"), "reset must keep the equipped set")
	_check(gs.echo_level("metronome") == 2, "reset must keep echo levels")

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
