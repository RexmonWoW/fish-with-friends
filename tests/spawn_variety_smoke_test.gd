extends Node

## Headless check that SpawnPool actually varies now that the weighted-pick
## stub always returned pool[0], and that there's more than one species in
## the lake pool to begin with.

func _ready() -> void:
	print("--- Spawn variety smoke test ---")

	var counts: Dictionary = {}
	for i in range(500):
		var fish := SpawnPool.roll_species(&"lake")
		if fish == null:
			print("FAIL: roll_species returned null")
			get_tree().quit(1)
			return
		counts[fish.species_id] = counts.get(fish.species_id, 0) + 1

	for species_id in counts:
		print("%s: %d" % [species_id, counts[species_id]])

	if counts.size() < 2:
		print("FAIL: only ever rolled %d distinct species out of 500 tries" % counts.size())
		get_tree().quit(1)
		return

	print("--- Spawn variety smoke test PASSED (%d distinct species) ---" % counts.size())
	get_tree().quit()
