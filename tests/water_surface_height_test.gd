extends Node

## Headless check: a cast should land exactly at the water's VISIBLE
## surface height, not floating above/below it. lake.tscn's WaterCollision
## used a BoxShape3D with no offset from its parent StaticBody3D -- the box
## is centered on its own origin, so its TOP face (what the validation
## raycast actually hits) sat 0.5 units above the visual WaterMesh plane,
## which shares that same parent transform. Every cast landed, and every
## bobber sat, floating half a unit above the water players actually see.

func _ready() -> void:
	print("--- Water surface height test ---")

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

	var current_map := NetworkManager.get_current_map()
	var water_mesh := current_map.get_node_or_null("Environment/Water/WaterMesh") as MeshInstance3D
	if water_mesh == null:
		print("FAIL: test setup problem -- couldn't find Environment/Water/WaterMesh")
		get_tree().quit(1)
		return
	var visual_water_y: float = water_mesh.global_position.y
	print("Visual water surface Y: ", visual_water_y)

	var result: Variant = WaterValidator.find_water_point(Vector3(5.0, 0.5, -10.0), current_map)
	if result == null:
		print("FAIL: cast over open water was rejected")
		get_tree().quit(1)
		return

	var landed_y: float = (result as Vector3).y
	print("Landed Y: ", landed_y)
	if absf(landed_y - visual_water_y) > 0.01:
		print("FAIL: landed %.3f units off the visible water surface (landed=%s, water=%s)" %
			[absf(landed_y - visual_water_y), landed_y, visual_water_y])
		get_tree().quit(1)
		return

	print("--- Water surface height test PASSED ---")
	get_tree().quit()
