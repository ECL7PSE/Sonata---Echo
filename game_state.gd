extends Node
## Global run state: the coin counter.
##
## An autoload rather than a node in the dungeon because the counter outlives any
## one scene object - a coin collected in the vault still has to be readable by
## the HUD after the player has died and respawned in the start hall, and it has
## to survive the scene being rebuilt.

signal coins_changed(current: int)

## How many coins the player is carrying. Coins are deliberately KEPT across death.
var coins := 0


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


## Resets for a fresh run. Not called on death - dying keeps the coins.
func reset() -> void:
	coins = 0
	coins_changed.emit(coins)