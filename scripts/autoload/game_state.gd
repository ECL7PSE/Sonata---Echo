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

## Upgrade level per stat, 0..UPGRADE_MAX. Also KEPT across death.
var upgrades := {"hp": 0, "atk": 0, "spd": 0}

## Seed for the current run's floors. 0 = unseeded (a new seed is rolled).
var run_seed := 0
## Current floor, 1-based. Each floor is generated from run_seed + depth.
var depth := 1

## Highest level a single upgrade can reach.
const UPGRADE_MAX := 3


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


## Resets for a fresh run: coins and floor progress are lost, upgrades are kept.
func reset() -> void:
	coins = 0
	depth = 1
	run_seed = 0
	coins_changed.emit(coins)