extends Node

## Headless probe for player movement tuning. Prints velocity over time
## while holding "move_forward" so we can see the actual accel/top-speed
## curve instead of guessing at move_force/max_speed/linear_damp.

func _ready() -> void:
	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	Input.action_press("move_forward")

	for i in range(60):  # ~2s at 30 samples/s-ish via physics frames
		await get_tree().physics_frame
		if i % 5 == 0:
			print("t=%.2f speed=%.3f pos=%s" % [
				i * (1.0 / Engine.physics_ticks_per_second),
				player.linear_velocity.length(),
				player.global_position
			])

	Input.action_release("move_forward")
	print("--- Movement smoke test complete ---")
	get_tree().quit()
