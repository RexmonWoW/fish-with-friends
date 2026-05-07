class_name Fish
extends Node3D

## A specific fish currently on someone's line.
## Spawned by host when a bite fires. Despawned when the reel ends.
## NOT a CaughtFish — that's the dead/stored version, this is the live version.

@export var species: FishData
var bound_to_peer_id: int = 0
var was_perfect: bool = false
var hazards_active: Array[StringName] = []


func finalize_catch(
		perfect: bool,
		active_hazards: Array[StringName],
		rolled_specials: Array[StringName]
) -> CaughtFish:
	# TODO: build CaughtFish via FishFactory and return it
	return null
