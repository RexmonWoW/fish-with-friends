class_name WaterValidator
extends RefCounted

## Stateless helper. Finds where the water surface actually is under an aim
## point -- used both to validate a cast and to snap the landing height so
## the lure/bobber sits on the surface instead of floating at aim height.
## Called by Rod._validate_and_land_cast on the host (the real outcome), and
## by every client's own Rod._update_landing_preview while charging (a local
## cosmetic preview, same math, no authority implications either way).

## Returns the actual water-surface hit position (Vector3), or null if
## aim_pos isn't over water.
static func find_water_point(aim_pos: Vector3, current_map: Node3D) -> Variant:
	# TODO: proper map integration — current_map will be the active map root
	# once maps are implemented. Until then, allow all casts for testing,
	# landing exactly where aimed since there's no real water to snap to.
	if current_map == null:
		return aim_pos

	var space_state := current_map.get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(
		aim_pos + Vector3(0.0, 10.0, 0.0),
		aim_pos + Vector3(0.0, -10.0, 0.0)
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	# A teammate standing at the landing spot shouldn't be able to block a
	# cast from reaching the real water beneath/around them -- without this,
	# the ray hits their RigidBody3D first, which isn't in "water_surface",
	# so the cast gets silently rejected even though the water underneath is
	# perfectly valid. Re-cast past any Player body the ray hits (bounded,
	# so a genuine obstruction -- boat hull, dock -- still rejects normally)
	# instead of treating a player's body as "not water."
	var excluded: Array[RID] = []
	for _attempt in range(4):
		query.exclude = excluded
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			return null

		var collider := result.get("collider") as Node
		if collider == null:
			return null
		if collider.is_in_group("water_surface"):
			return result.position as Vector3
		if collider is Player:
			excluded.append(result.get("rid") as RID)
			continue
		return null

	return null
