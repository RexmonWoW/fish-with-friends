extends Node

## Headless check for player movement tuning: accelerates to near max_speed
## while holding movement (protects the original "movement too slow, stuck
## against the boat" fix from early this session), then decelerates to a
## near-stop shortly after releasing it (protects the "I slide everywhere"
## fix -- a dedicated active brake, since passive linear_damp alone only
## asymptotically approaches a stop given the low surface friction needed
## for the original stuck-movement fix).

func _ready() -> void:
	print("--- Movement smoke test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	Input.action_press(&"move_forward")
	var reached_near_max := false
	for i in range(90):  # up to 1.5s
		await get_tree().physics_frame
		var speed := _horiz_speed(player)
		if i % 10 == 0:
			print("t=%.2f speed=%.3f" % [i / 60.0, speed])
		if speed >= player.max_speed * 0.9:
			reached_near_max = true
			break  # stop as soon as we know -- don't keep walking toward the platform edge

	if not reached_near_max:
		print("FAIL: never got close to max_speed (%.1f) while holding movement" % player.max_speed)
		get_tree().quit(1)
		return
	print("Reached near max_speed while holding movement.")

	Input.action_release(&"move_forward")

	# Horizontal (XZ) speed only -- once released the player may still be
	# in the air/falling from momentum carrying them off the small test
	# platform, and vertical fall speed under gravity is expected to climb.
	# "Sliding" is specifically an unwanted horizontal-plane phenomenon.
	var stopped := false
	var stop_time := -1.0
	for i in range(60):  # up to 1s to stop
		await get_tree().physics_frame
		var speed := _horiz_speed(player)
		if i % 10 == 0:
			print("t=%.2f horiz speed after release=%.3f" % [i / 60.0, speed])
		if speed <= 0.5:
			stopped = true
			stop_time = i / 60.0
			break

	if not stopped:
		print("FAIL: player still sliding horizontally a full second after releasing movement")
		get_tree().quit(1)
		return
	print("Stopped %.2fs after releasing movement." % stop_time)

	print("--- Movement smoke test PASSED ---")
	get_tree().quit()


func _horiz_speed(player: Player) -> float:
	return Vector2(player.linear_velocity.x, player.linear_velocity.z).length()
