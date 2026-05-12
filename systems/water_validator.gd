class_name WaterValidator
extends RefCounted

## Stateless helper. Determines if a world position is over valid water for fishing.
## Called by Rod._validate_and_land_cast on the host only.

static func is_valid_water(world_pos: Vector3, current_map: Node3D) -> bool:
	# TODO: proper map integration — current_map will be the active map root
	# once maps are implemented. Until then, allow all casts for testing.
	if current_map == null:
		return true

	var space_state := current_map.get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(
		world_pos + Vector3(0.0, 10.0, 0.0),
		world_pos + Vector3(0.0, -10.0, 0.0)
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false

	var collider := result.get("collider") as Node
	return collider != null and collider.is_in_group("water_surface")
