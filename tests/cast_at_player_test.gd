extends Node

## Headless check: casting toward a spot where a teammate is currently
## standing should still land on the real water there, not get silently
## rejected just because their RigidBody3D happens to be in the way of the
## validation raycast (see WaterValidator.find_water_point).

func _ready() -> void:
	print("--- Cast-at-player test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(_player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.request_start_round()
	var waited := 0.0
	while NetworkManager._current_scene_id != &"lake" and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if NetworkManager._current_scene_id != &"lake":
		print("FAIL: never reached the lake")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager._spawn_player_for_peer(2)
	await get_tree().process_frame
	await get_tree().process_frame

	var player2: Player = NetworkManager.spawned_players[2]
	# Past the boat's edge (hull spans roughly z -3..3), genuinely over open
	# water -- unlike standing on the deck itself, which has no water to land
	# on regardless of a player being there.
	var target := Vector3(0.0, 0.5, -10.0)
	player2.global_position = target
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Sanity check: confirm the ray really would hit player2 first (i.e. this
	# test is actually exercising the fix, not a no-op).
	var current_map := NetworkManager.get_current_map()
	var space_state := current_map.get_world_3d().direct_space_state
	var raw_query := PhysicsRayQueryParameters3D.create(
		target + Vector3(0.0, 10.0, 0.0), target + Vector3(0.0, -10.0, 0.0)
	)
	raw_query.collide_with_areas = false
	raw_query.collide_with_bodies = true
	var raw: Dictionary = space_state.intersect_ray(raw_query)
	if raw.is_empty() or not (raw.get("collider") is Player):
		print("FAIL: test setup didn't actually put a player in the ray's path")
		get_tree().quit(1)
		return

	var result: Variant = WaterValidator.find_water_point(target, current_map)
	if result == null:
		print("FAIL: cast toward a player's spot was rejected instead of landing on the water beneath them")
		get_tree().quit(1)
		return

	var landed: Vector3 = result
	print("Landed at: ", landed)

	# Cross-check against the same water height an unobstructed cast lands
	# at nearby -- proves the player didn't change WHERE the water is found,
	# just that it's still found at all.
	var unobstructed: Variant = WaterValidator.find_water_point(Vector3(5.0, 0.5, -10.0), current_map)
	if unobstructed == null:
		print("FAIL: test setup problem -- unobstructed control cast also failed")
		get_tree().quit(1)
		return
	var expected_y: float = (unobstructed as Vector3).y
	if absf(landed.y - expected_y) > 0.05:
		print("FAIL: landing height doesn't match the real water surface (expected ~%s, got %s)" % [expected_y, landed.y])
		get_tree().quit(1)
		return

	print("--- Cast-at-player test PASSED ---")
	get_tree().quit()
