extends Node

## Headless check for movement while swimming during a capsize -- playtest
## report: "when you capsize you cant move." The water's collision surface
## never got a low-friction PhysicsMaterial like the boat hull did early
## this session (same "stuck against the boat" bug class) -- under normal
## play nobody ever actually rests on the water's own collision (casting
## only raycasts against it), so this went unnoticed until the swim
## feature made players actually slide along it for the first time.

func _ready() -> void:
	print("--- Swim movement test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
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

	var capsize_manager := get_tree().get_first_node_in_group("capsize_manager")
	capsize_manager.start_capsize()
	await get_tree().process_frame

	if not player.is_swimming:
		print("FAIL: test setup problem -- player never entered swim mode")
		get_tree().quit(1)
		return
	print("Swimming, tossed to: ", player.global_position)

	Input.action_press(&"move_forward")
	var reached_near_max := false
	for i in range(90):  # up to 1.5s
		await get_tree().physics_frame
		var speed := Vector2(player.linear_velocity.x, player.linear_velocity.z).length()
		if i % 10 == 0:
			print("t=%.2f speed=%.3f" % [i / 60.0, speed])
		if speed >= player.max_speed * 0.9:
			reached_near_max = true
			break
	Input.action_release(&"move_forward")

	if not reached_near_max:
		print("FAIL: never got close to max_speed (%.1f) while swimming and holding movement -- 'can't move'" % player.max_speed)
		get_tree().quit(1)
		return
	print("Reached near max_speed while swimming.")

	print("--- Swim movement test PASSED ---")
	get_tree().quit()
