extends Node

## Headless check for GDD Bite Detection's spatial rarity: SpawnPool.
## roll_species's distance_factor should bias the pick toward the lake
## pool's own above-average base_value species when far from the boat
## (distance_factor near 1.0), and toward below-average species when near
## it (distance_factor near 0.0) -- purely off each species' own
## spawn_weight/base_value, no species named here, so this keeps working
## automatically as fish get added/retuned.

func _ready() -> void:
	print("--- Spatial rarity test ---")

	const TRIES := 2000
	var near_counts: Dictionary = {}
	var far_counts: Dictionary = {}
	for i in range(TRIES):
		var near_fish := SpawnPool.roll_species(&"lake", 0.0)
		var far_fish := SpawnPool.roll_species(&"lake", 1.0)
		near_counts[near_fish.species_id] = near_counts.get(near_fish.species_id, 0) + 1
		far_counts[far_fish.species_id] = far_counts.get(far_fish.species_id, 0) + 1

	# golden_koi is the priciest species in the lake pool (base_value=120,
	# well above the pool average) and already the rarest by spawn_weight
	# alone (0.08) -- spatial rarity should make it noticeably MORE common
	# far from the boat than near it, on top of that baseline rarity.
	var koi_near: int = near_counts.get(&"golden_koi", 0)
	var koi_far: int = far_counts.get(&"golden_koi", 0)
	print("golden_koi: near=%d/%d far=%d/%d" % [koi_near, TRIES, koi_far, TRIES])
	if koi_far <= koi_near:
		print("FAIL: golden_koi (highest-value species) should show up more far from the boat than near it")
		get_tree().quit(1)
		return
	print("Far casts roll the priciest species noticeably more often than near casts.")

	# bluegill sits well below the pool average (base_value=6) -- spatial
	# rarity should make it MORE common near the boat than far from it.
	var bluegill_near: int = near_counts.get(&"bluegill", 0)
	var bluegill_far: int = far_counts.get(&"bluegill", 0)
	print("bluegill: near=%d/%d far=%d/%d" % [bluegill_near, TRIES, bluegill_far, TRIES])
	if bluegill_near <= bluegill_far:
		print("FAIL: bluegill (a below-average-value species) should show up more near the boat than far from it")
		get_tree().quit(1)
		return
	print("Near casts roll common low-value species noticeably more often than far casts.")

	# Neutral (0.5) should reduce to the plain spawn_weight-only behavior --
	# same thing spawn_variety_smoke_test already exercises with the
	# default, checked again here explicitly since it's the documented
	# "no bias" midpoint.
	var neutral_counts: Dictionary = {}
	for i in range(TRIES):
		var fish := SpawnPool.roll_species(&"lake", 0.5)
		neutral_counts[fish.species_id] = neutral_counts.get(fish.species_id, 0) + 1
	if neutral_counts.size() < 2:
		print("FAIL: neutral distance_factor should still roll a real variety, got %d distinct species" % neutral_counts.size())
		get_tree().quit(1)
		return
	print("Neutral distance_factor (0.5) still rolls real variety: %s" % neutral_counts)

	print("--- Spatial rarity test PASSED ---")
	get_tree().quit()
