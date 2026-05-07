class_name FishFactory
extends RefCounted

## Builds CaughtFish instances from species data + catch context.
## Called on the host only, the moment a fish is reeled in.
## Pure functions — no state, no side effects.


static func create_caught_fish(
		species: FishData,
		caught_by_peer_id: int,
		caught_by_player_name: String,
		location: StringName,
		was_perfect: bool,
		special_attrs: Array[StringName],
		hazards: Array[StringName],
		from_big_fish_event: bool = false
) -> CaughtFish:
	var fish := CaughtFish.new()
	fish.species = species
	fish.size = species.roll_size()
	fish.weight = species.roll_weight()
	fish.caught_by_peer_id = caught_by_peer_id
	fish.caught_by_player_name = caught_by_player_name
	fish.location_caught = location
	fish.was_perfect_catch = was_perfect
	fish.special_attributes = special_attrs
	fish.hazards_during_catch = hazards
	fish.was_big_fish_event = from_big_fish_event
	fish.final_value = _compute_value(fish)
	return fish


static func _compute_value(fish: CaughtFish) -> int:
	## Multiplier formula. PLACEHOLDER VALUES.
	## General owns the actual numbers — these are scaffold to make the system runnable.
	## When General nails the economy, replace the constants here.
	var value: float = float(fish.species.base_value)

	# Size scales linearly between min and max
	var size_range := fish.species.max_size - fish.species.min_size
	var size_t: float = 0.5 if size_range <= 0.0 else (fish.size - fish.species.min_size) / size_range
	value *= 1.0 + size_t  # 1.0x at min size, 2.0x at max size

	if fish.was_perfect_catch:
		value *= 1.5

	# Each special attribute and hazard multiplies value
	for _attr in fish.special_attributes:
		value *= 1.5
	for _hazard in fish.hazards_during_catch:
		value *= 1.25

	if fish.was_big_fish_event:
		value *= 3.0

	return int(round(value))
