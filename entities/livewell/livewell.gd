class_name Livewell
extends Node3D

## Shared, 5 slots. Host-authoritative state.
## Each map places its own Livewell in its PlayableArea.
## Negotiation UI for a full livewell, throw-overboard interaction, and
## per-slot visual fish display are still a future dispatch -- this covers
## the data-layer add/remove that BiteEventManager needs to close the loop.

const MAX_SLOTS: int = 5

var slots: Array = []                ## Array of CaughtFish (or null for empty slots)
var big_fish_slot: CaughtFish = null ## Reserved slot for big fish event catches


func _ready() -> void:
	slots.resize(MAX_SLOTS)
	add_to_group("livewell")  ## Systems can find any livewell via group lookup


## Host-authoritative. Returns the slot index the fish landed in, or -1 if
## every slot is full (caller decides what to do -- MVP just discards it).
func add_fish(fish: CaughtFish) -> int:
	for i in range(MAX_SLOTS):
		if slots[i] == null:
			slots[i] = fish
			EventBus.livewell_updated.emit(self)
			return i
	return -1


## Host-authoritative. Removes and returns the fish at index (throw overboard
## or sell-at-end-of-day both go through this). Null if the slot was empty
## or out of range.
func remove_fish(index: int) -> CaughtFish:
	if index < 0 or index >= MAX_SLOTS:
		return null
	var fish: CaughtFish = slots[index]
	if fish != null:
		slots[index] = null
		EventBus.livewell_updated.emit(self)
	return fish


func is_full() -> bool:
	return not slots.has(null)
