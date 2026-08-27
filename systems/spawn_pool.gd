class_name SpawnPool
extends RefCounted

## Stateless helper for rolling a species when a cast lands.


static func roll_species(
		current_map: StringName,
		_escalation_pressure: float = 0.0,
		_bait_active: bool = false
) -> FishData:
	var pool := _get_pool_for_map(current_map)
	return _weighted_pick(pool)


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


static func _weighted_pick(pool: Array[FishData]) -> FishData:
	## Flat weighted-random pick across the whole pool by spawn_weight.
	## Rarity-tier-aware weighting (roll a tier first, then weight within it,
	## per spawn_weight's own doc comment) is a further refinement Minigame
	## Logic still owns -- this is a real random pick, just not tiered yet.
	if pool.is_empty():
		return null

	var total_weight := 0.0
	for species in pool:
		total_weight += maxf(species.spawn_weight, 0.0)
	if total_weight <= 0.0:
		return pool[randi() % pool.size()]

	var roll := randf() * total_weight
	for species in pool:
		roll -= maxf(species.spawn_weight, 0.0)
		if roll <= 0.0:
			return species
	return pool[pool.size() - 1]  # float rounding fallback
