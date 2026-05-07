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
	# TODO: real weighted selection — Minigame Logic chat owns this
	if pool.is_empty():
		return null
	return pool[0]
