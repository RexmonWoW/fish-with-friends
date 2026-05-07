class_name WaterValidator
extends RefCounted

## Stateless helper. Determines if a world position is over valid water for fishing.
## Called by Rod._validate_and_land_cast on the host.

static func is_valid_water(world_pos: Vector3, current_map: Node3D) -> bool:
	# Strategy: maps tag their water surfaces with group "water_surface".
	# Cast a downward ray from above world_pos, check if it hits a water_surface collider.
	# TODO: implement
	return true
