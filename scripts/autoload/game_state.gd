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

const ECHOES := {
	"hollow_note": {
		"name": "HOLLOW NOTE",
		"cost": 40,
		"desc": "Long notes need only a third of the bar.",
	},
	"metronome": {
		"name": "METRONOME",
		"cost": 45,
		"desc": "The first note of a section is easier.",
	},
	"grubsong": {
		"name": "GRUBSONG",
		"cost": 35,
		"desc": "Taking a hit pays you 3 coins.",
	},
	"candle_stub": {
		"name": "CANDLE STUB",
		"cost": 50,
		"desc": "Everything in the shop costs 20% less.",
	},
	"dead_mans_toll": {
		"name": "DEAD MAN'S TOLL",
		"cost": 60,
		"desc": "Death takes three quarters of your coins.",
	},
	"grave_bell": {
		"name": "GRAVE BELL",
		"cost": 30,
		"desc": "Your map counts the enemies left in a room.",
	},
}

## Echoes bought this run, and the ones currently worn (max ECHO_SLOTS).
var echoes_owned: Array[String] = []
var echoes_equipped: Array[String] = []
## Rooms the player has walked into this run, for the map.
var explored: Array[String] = []


func has_echo(id: String) -> bool:
	return id in echoes_owned


## True when the echo is bought AND worn.
func echo_on(id: String) -> bool:
	return id in echoes_equipped


## Price after the Candle Stub discount.
func echo_cost(id: String) -> int:
	var c := int(ECHOES.get(id, {}).get("cost", 0))
	if echo_on("candle_stub"):
		c = int(float(c) * 0.8)
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
	coins_changed.emit(coins)