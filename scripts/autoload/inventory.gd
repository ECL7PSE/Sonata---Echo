extends Node
## Item slots. Empty for now, but the plumbing is in place so pickups have
## somewhere to go later.
##
## Separate from GameState because these are two different kinds of thing: coins
## are a scored resource that only ever goes up, slots are a bounded set of
## identities that get consumed. Keeping them apart means a future "pick up a
## potion" does not have to touch the coin counter.

signal inventory_changed(slots: Array)

## Item id per slot. An empty string means the slot is empty.
var slots: Array[String] = []


func _ready() -> void:
	if slots.is_empty():
		resize(4)


## Resizes the slot list, keeping what is already in it.
func resize(count: int) -> void:
	slots.resize(maxi(count, 0))
	while slots.size() < count:
		slots.append("")
	inventory_changed.emit(slots)


## Puts `item_id` in the first free slot. Returns the slot index, or -1 if full.
func add_item(item_id: String) -> int:
	for i in slots.size():
		if slots[i] == "":
			slots[i] = item_id
			inventory_changed.emit(slots)
			return i
	return -1


## Empties a slot. Returns false if the index was out of range.
func remove_item(index: int) -> bool:
	if index < 0 or index >= slots.size() or slots[index] == "":
		return false
	slots[index] = ""
	inventory_changed.emit(slots)
	return true


func is_full() -> bool:
	for s in slots:
		if s == "":
			return false
	return true