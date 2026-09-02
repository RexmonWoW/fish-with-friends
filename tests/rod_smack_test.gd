extends Node

## Headless check for GDD Casting's rod smack: a melee swing, short range,
## cone in front of the camera, shoves whoever it hits -- reusing the cast
## bonk's exact broadcast (EventBus.player_bonked / Player.apply_bonk_
## impulse). Covers a hit directly in front, a miss for someone out of
## range, and a miss for someone behind (outside the cone) -- and that it
## works with no cast in flight at all (GDD: "works whether or not a line
## is out").

var _bonked: Array = []  # each entry: [hit_peer_id, impulse]


func _ready() -> void:
	print("--- Rod smack test ---")

	EventBus.player_bonked.connect(func(hit_peer_id, impulse): _bonked.append([hit_peer_id, impulse]))

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player1: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.request_start_round()
	var scene_waited := 0.0
	while NetworkManager._current_scene_id != &"lake" and scene_waited < 3.0:
		await get_tree().process_frame
		scene_waited += get_process_delta_time()
	if NetworkManager._current_scene_id != &"lake":
		print("FAIL: never reached the lake")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager._spawn_player_for_peer(2)
	NetworkManager._spawn_player_for_peer(3)
	NetworkManager._spawn_player_for_peer(4)
	await get_tree().process_frame
	await get_tree().process_frame

	var rod1: Rod = player1.equipment_slot.equipped_item as Rod
	var player2: Player = NetworkManager.spawned_players[2]  # directly in front, in range
	var player3: Player = NetworkManager.spawned_players[3]  # in front, but too far
	var player4: Player = NetworkManager.spawned_players[4]  # in range, but behind (outside the cone)

	player1.global_position = Vector3(0.0, 0.5, 0.0)
	player1.camera_rig.rotation.y = 0.0  # facing -Z
	player2.global_position = Vector3(0.0, 0.5, -1.5)   # in front, well within SMACK_RANGE
	player3.global_position = Vector3(0.0, 0.5, -10.0)  # in front, far outside SMACK_RANGE
	player4.global_position = Vector3(0.0, 0.5, 1.0)    # behind player1, within range but outside the cone
	await get_tree().physics_frame
	await get_tree().physics_frame

	# No cast in flight at all -- GDD: "works whether or not a line is out."
	if rod1.state != Rod.CastState.IDLE:
		print("FAIL: test setup problem -- rod1 should be IDLE (no cast in flight)")
		get_tree().quit(1)
		return

	rod1.request_smack()
	await get_tree().process_frame

	if _bonked.size() != 1:
		print("FAIL: expected exactly 1 player bonked (in front, in range), got %d: %s" % [_bonked.size(), _bonked])
		get_tree().quit(1)
		return
	if _bonked[0][0] != player2.peer_id:
		print("FAIL: smack hit the wrong peer (got %d, expected %d)" % [_bonked[0][0], player2.peer_id])
		get_tree().quit(1)
		return
	var impulse: Vector3 = _bonked[0][1]
	if impulse.length() < 1.0:
		print("FAIL: smack impulse suspiciously small/zero (%s)" % impulse)
		get_tree().quit(1)
		return
	print("Smack with no cast in flight correctly hit only the player directly in front: impulse=%s" % impulse)

	print("--- Rod smack test PASSED ---")
	get_tree().quit()
