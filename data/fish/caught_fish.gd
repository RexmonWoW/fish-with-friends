class_name CaughtFish
extends Resource

## A specific fish that was caught. Created on host at catch time.
## Stored in the livewell. Sold at end of day. Queried for achievements.

@export var species: FishData             ## reference to species template
@export var size: float                   ## actual rolled size
@export var weight: float                 ## actual rolled weight

@export_group("Catch Context")
@export var caught_by_peer_id: int = 0    ## Steam peer ID
@export var caught_by_player_name: String = ""  ## cached for display
@export var location_caught: StringName = &""   ## map ID where caught
@export var was_perfect_catch: bool = false     ## all QTEs nailed
@export var was_big_fish_event: bool = false    ## came from the big fish event, not normal fishing

@export_group("Modifiers")
@export var special_attributes: Array[StringName] = []  ## &"albino", &"shiny", &"electric", ...
@export var hazards_during_catch: Array[StringName] = []  ## &"lightning_strike", &"mosquito_blinded", &"cold_max", ...

@export_group("Computed")
@export var final_value: int = 0          ## money this fish sells for. Computed at catch, then frozen.


func has_attribute(attr: StringName) -> bool:
	return attr in special_attributes


func had_hazard(hazard: StringName) -> bool:
	return hazard in hazards_during_catch
