class_name SpawnPool
extends RefCounted

## Stateless helper for rolling a species when a cast lands.

## GDD Bite Detection: "rarity is spatial" -- bias strength for how hard
## distance_factor pulls the pick toward the pool's above/below-average
## value species. 0 would mean no distance effect at all (pure
## spawn_weight); this is a placeholder, tune by feel.
const DISTANCE_BIAS_STRENGTH: float = 1.5


## distance_factor is a 0..1 normalized "how far from the boat is this
## spawn point" (0 = right by the boat, 1 = the far edge of the habitat) --
## callers with no meaningful location (e.g. a Big Fish Event's own catch)
## can just leave it at the neutral default. Purely a weighting nudge on
## top of each species' own spawn_weight/base_value -- no species names
## hardcoded here, so new fish slot in automatically.
static func roll_species(
		current_map: StringName,
		distance_factor: float = 0.5,
		_escalation_pressure: float = 0.0,
		_bait_active: bool = false
) -> FishData:
	var pool := _get_pool_for_map(current_map)
	return _weighted_pick(pool, distance_factor)


static func _get_pool_for_map(map_id: StringName) -> Array[FishData]:
	var pool: Array[FishData] = []
	var dir := DirAccess.open("res://data/fish/species/")
	if dir == null:
		push_error("SpawnPool: cannot open res://data/fish/species/")
		return pool
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".tres"):
			var res := load("res://data/fish/species/" + file) as FishData
			if res and map_id in res.valid_locations:
				pool.append(res)
		file = dir.get_next()
	return pool


static func _weighted_pick(pool: Array[FishData], distance_factor: float) -> FishData:
	## Weighted-random pick across the whole pool by spawn_weight, nudged by
	## distance_factor relative to the pool's OWN average base_value -- never
	## a hardcoded species list, so this stays correct as species get added/
	## removed/retuned. Rarity-tier-aware weighting (roll a tier first, then
	## weight within it, per spawn_weight's own doc comment) is a further
	## refinement Minigame Logic still owns -- this is a real random pick,
	## just not tiered yet.
	if pool.is_empty():
		return null

	var avg_value := 0.0
	for species in pool:
		avg_value += maxf(species.base_value, 1.0)
	avg_value /= pool.size()

	# -DISTANCE_BIAS_STRENGTH right at the boat (suppress above-average
	# value, boost below-average), 0 at the pool's own midpoint distance
	# (neutral, pure spawn_weight), +DISTANCE_BIAS_STRENGTH at the far edge
	# (the reverse).
	var bias_exponent := (clampf(distance_factor, 0.0, 1.0) - 0.5) * 2.0 * DISTANCE_BIAS_STRENGTH

	var weights: Array[float] = []
	var total_weight := 0.0
	for species in pool:
		var value_ratio := maxf(species.base_value, 1.0) / avg_value
		var w := maxf(species.spawn_weight, 0.0) * pow(value_ratio, bias_exponent)
		weights.append(w)
		total_weight += w
	if total_weight <= 0.0:
		return pool[randi() % pool.size()]

	var roll := randf() * total_weight
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]  # float rounding fallback
