extends Node
## Global run state: the coin counter.
##
## An autoload rather than a node in the dungeon because the counter outlives any
## one scene object - a coin collected in the vault still has to be readable by
## the HUD after the player has died and respawned in the start hall, and it has
## to survive the scene being rebuilt.

signal coins_changed(current: int)
signal upgrades_changed(upgrades: Dictionary)

## How many coins the player is carrying. Coins are deliberately KEPT across death.
var coins := 0
## Which door was taken on the way down: "", "combat", "hoard" or "rest".
## The next floor reads it and clears it again.
var floor_choice := ""
## What a single coin is worth this floor.
var coin_value := 1
## Set by the REST door: the next floor saves the run on arrival.
var pending_save := false
## Set once the first-run prompts have finished, so they never repeat.
var tutorial_done := false

## Upgrade level per stat, 0..UPGRADE_MAX. Also KEPT across death.
var upgrades := {"hp": 0, "atk": 0, "spd": 0}

## Seed for the current run's floors. 0 = unseeded (a new seed is rolled).
var run_seed := 0
## Current floor, 1-based. Each floor is generated from run_seed + depth.
var depth := 1

## Highest level a single upgrade can reach.
const UPGRADE_MAX := 3


# ------------------------------------------------------------------- echoes
# Equippable relics: bought once, three may be worn, and each one bends a
# single rule instead of adding a number.

signal echoes_changed

## How many echoes can be worn at once.
const ECHO_SLOTS := 3

## `desc` is the level-0 text; `levels` holds the text for each upgrade.
const ECHOES := {
	"hollow_note": {
		"name": "HOLLOW NOTE",
		"cost": 40,
		"desc": "Long notes need only a third of the bar.",
		"levels": ["Long notes need a fifth of the bar.",
			"Long notes need almost nothing."],
	},
	"metronome": {
		"name": "METRONOME",
		"cost": 45,
		"desc": "The first note of a section is easier.",
		"levels": ["The first note of a section is much easier.",
			"The first note of a section is a freebie."],
	},
	"grubsong": {
		"name": "GRUBSONG",
		"cost": 35,
		"desc": "Taking a hit pays you 3 coins.",
		"levels": ["Taking a hit pays you 6 coins.",
			"Taking a hit pays you 9 coins."],
	},
	"candle_stub": {
		"name": "CANDLE STUB",
		"cost": 50,
		"desc": "Everything in the shop costs 20% less.",
		"levels": ["Everything in the shop costs 27% less.",
			"Everything in the shop costs 34% less."],
	},
	"dead_mans_toll": {
		"name": "DEAD MAN'S TOLL",
		"cost": 60,
		"desc": "Death takes three quarters of your coins.",
		"levels": ["Death keeps 40% of your coins.",
			"Death keeps more than half your coins."],
	},
	"grave_bell": {
		"name": "GRAVE BELL",
		"cost": 30,
		"desc": "Your map counts the enemies left in a room.",
		"levels": ["Your map counts the enemies in every room.",
			"Your map counts every enemy left in the floor."],
	},
}

## Echoes bought this run, and the ones currently worn (max ECHO_SLOTS).
var echoes_owned: Array[String] = []
var echoes_equipped: Array[String] = []
## Rooms the player has walked into this run, for the map.
var explored: Array[String] = []
## Rooms that hold a boss, for the map.
var boss_rooms: Array[String] = []

## How far each owned echo has been reinforced at the bench: id -> 0..ECHO_LEVEL_MAX.
var echo_levels := {}

const ECHO_LEVEL_MAX := 2


func has_echo(id: String) -> bool:
	return id in echoes_owned


## Reinforcement level of an echo (0 for a fresh purchase).
func echo_level(id: String) -> int:
	return int(echo_levels.get(id, 0))


## What the next reinforcement costs, or 0 when it cannot be bought.
func echo_upgrade_cost(id: String) -> int:
	if not has_echo(id) or echo_level(id) >= ECHO_LEVEL_MAX:
		return 0
	return maxi(1, int(float(ECHOES[id].cost) * 0.6 * float(echo_level(id) + 1)))


## Reinforces an echo: the same trick, done harder.
func upgrade_echo(id: String) -> bool:
	var cost := echo_upgrade_cost(id)
	if cost <= 0 or not spend_coins(cost):
		return false
	echo_levels[id] = echo_level(id) + 1
	echoes_changed.emit()
	return true


## The description of an echo at its current level.
func echo_desc(id: String) -> String:
	var info: Dictionary = ECHOES.get(id, {})
	var levels: Array = info.get("levels", [])
	var lv := echo_level(id)
	if lv > 0 and lv <= levels.size():
		return str(levels[lv - 1])
	return str(info.get("desc", ""))


## True when the echo is bought AND worn.
func echo_on(id: String) -> bool:
	return id in echoes_equipped


## The two echo families. Three worn from one family sets its bonus off.
const ECHO_FAMILIES := {
	"song": ["hollow_note", "metronome", "grubsong"],
	"grave": ["candle_stub", "dead_mans_toll", "grave_bell"],
}


## How many echoes of a family are worn right now.
func family_worn(family: String) -> int:
	var n := 0
	for id in ECHO_FAMILIES.get(family, []):
		if echo_on(id):
			n += 1
	return n


## True when every echo of a family is worn.
func family_complete(family: String) -> bool:
	var members: Array = ECHO_FAMILIES.get(family, [])
	return not members.is_empty() and family_worn(family) == members.size()


## What the complete family does for you, in words. Empty when none is.
func family_bonus() -> String:
	if family_complete("song"):
		return "SONG: perfect hits pay 1 coin"
	if family_complete("grave"):
		return "GRAVE: every coin is worth 1 more"
	return ""


## What a single coin is worth right now: the floor's value, plus the grave
## family bonus.
func coin_worth() -> int:
	var v := maxi(1, coin_value)
	if family_complete("grave"):
		v += 1
	return v


## What a PERFECT hit rings loose. Zero unless the song family is complete.
func perfect_bonus() -> int:
	return 1 if family_complete("song") else 0


## Price after the Candle Stub discount.
func echo_cost(id: String) -> int:
	var c := int(ECHOES.get(id, {}).get("cost", 0))
	if echo_on("candle_stub"):
		var cut := 0.2 + 0.07 * float(echo_level("candle_stub"))
		c = maxi(1, int(float(c) * (1.0 - minf(cut, 0.45))))
	return c


## Buys an echo and wears it if there is a free slot.
func buy_echo(id: String) -> bool:
	if has_echo(id) or not ECHOES.has(id):
		return false
	if not spend_coins(echo_cost(id)):
		return false
	echoes_owned.append(id)
	if echoes_equipped.size() < ECHO_SLOTS:
		echoes_equipped.append(id)
	echoes_changed.emit()
	return true


## Wears or removes an owned echo, if a slot is free.
func toggle_echo(id: String) -> void:
	if not has_echo(id):
		return
	if echo_on(id):
		echoes_equipped.erase(id)
	elif echoes_equipped.size() < ECHO_SLOTS:
		echoes_equipped.append(id)
	else:
		return
	echoes_changed.emit()


func mark_explored(room_name: String) -> void:
	if room_name.is_empty() or room_name in explored:
		return
	explored.append(room_name)


## Remembers a room that holds a boss, so the map can point at the fight.
func mark_boss_room(room_name: String) -> void:
	if room_name.is_empty() or room_name in boss_rooms:
		return
	boss_rooms.append(room_name)


## Adds coins and notifies the HUD. Returns the new total.
func add_coins(amount: int) -> int:
	if amount == 0:
		return coins
	coins = maxi(coins + amount, 0)
	coins_changed.emit(coins)
	return coins


## Spends coins if there are enough. Returns false and changes nothing otherwise.
func spend_coins(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins)
	return true


## Current level of an upgrade. Unknown keys read as 0.
func get_upgrade(key: String) -> int:
	return upgrades.get(key, 0)


## Sets an upgrade level, clamped to 0..UPGRADE_MAX, and notifies listeners.
func set_upgrade(key: String, level: int) -> void:
	var clamped := clampi(level, 0, UPGRADE_MAX)
	if upgrades.get(key) == clamped:
		return
	upgrades[key] = clamped
	upgrades_changed.emit(upgrades)


## Resets for a fresh run: coins and floor progress are lost, upgrades and
## echoes are kept.
func reset() -> void:
	coins = 0
	depth = 1
	run_seed = 0
	explored.clear()
	floor_choice = ""
	coin_value = 1
	pending_save = false
	coins_changed.emit(coins)