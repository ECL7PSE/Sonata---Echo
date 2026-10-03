extends Node
## Collision layer numbers, shared by every script that needs them.
##
## Bit 1 ("world") is deliberately left exactly as it always was: the wall
## TileSet, the props and the traps all sit on it and their behaviour must not
## change. The player MOVES from bit 1 to bit 3 so that enemies can be told apart
## from static geometry, but its collision MASK still contains bit 1, so it
## collides with exactly the same set of bodies it always did.
##
##   bit 1 world         walls, props, traps            (unchanged)
##   bit 2 enemy         enemy bodies
##   bit 3 player        the player body
##   bit 4 player_hitbox the player's slash
##   bit 5 enemy_hitbox  enemy attacks (damages the player)
##   bit 6 pickup        coins
##   bit 7 enemy_trigger room aggro areas, mimic proximity
##   bit 8 enemy_hurtbox enemy bodies (receives the slash)
class_name Layers

const WORLD := 1 << 0
const ENEMY := 1 << 1
const PLAYER := 1 << 2
const PLAYER_HITBOX := 1 << 3
const ENEMY_HITBOX := 1 << 4
const PICKUP := 1 << 5
const ENEMY_TRIGGER := 1 << 6
const ENEMY_HURTBOX := 1 << 7


## What a player body must collide with.
##
## Bit 1 only. The player used to be ON bit 1 and masked bit 1; moving it to bit 3
## while keeping bit 1 in the mask means it still collides with the walls, the
## chests and the traps, and with nothing else. Enemies are deliberately NOT in
## this mask so they cannot shove the player around, and so a dying enemy never
## blocks the player.
static func player_mask() -> int:
	return WORLD


## What an enemy body collides with: the world plus other enemies.
##
## Other enemies are here so they cannot stack into one sprite. The player is
## excluded on purpose - see player_mask().
static func enemy_mask() -> int:
	return WORLD | ENEMY


## What a prop (chest, pot, crate) listens for: the slash, and nothing else.
##
## If this included PLAYER the chest would open by walking into it.
static func prop_mask() -> int:
	return PLAYER_HITBOX


## What a trap listens for: the player body.
static func trap_mask() -> int:
	return WORLD | PLAYER


## What the player's slash looks for: enemy hurtboxes.
static func player_hitbox_mask() -> int:
	return ENEMY_HURTBOX


## What an enemy hurtbox listens for: the player's slash.
static func enemy_hurtbox_mask() -> int:
	return PLAYER_HITBOX


## What an enemy attack listens for: the player.
static func enemy_hitbox_mask() -> int:
	return PLAYER


## What a coin listens for: the player.
static func pickup_mask() -> int:
	return PLAYER


## What an aggro / mimic trigger listens for: the player.
static func trigger_mask() -> int:
	return PLAYER