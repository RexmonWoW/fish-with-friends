class_name Livewell
extends Node3D

## Shared, 5 slots. Host-authoritative state.
## Each map places its own Livewell in its PlayableArea.
## Architecture stub — actual add/remove/throw-overboard logic is a future dispatch.

const MAX_SLOTS: int = 5

var slots: Array = []                ## Array of CaughtFish (or null for empty slots)
var big_fish_slot: CaughtFish = null ## Reserved slot for big fish event catches


func _ready() -> void:
	slots.resize(MAX_SLOTS)
	add_to_group("livewell")  ## Systems can find any livewell via group lookup
