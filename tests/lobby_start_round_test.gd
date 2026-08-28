extends Node

## Headless check for the bare-bones lobby: host lands in the lobby (not
## the lake) first, walking into the StartTrigger actually starts the
## round (swaps to the lake, repositions the player, refreshes
## Rod.current_map which was captured null back in the lobby).

func _ready() -> void:
	print("--- Lobby start-round test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("Scene after joining: ", NetworkManager._current_scene_id)
	if NetworkManager._current_scene_id != &"lobby":
		print("FAIL: didn't land in the lobby first")
		get_tree().quit(1)
		return

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	print("Rod.current_map while in lobby (expect null): ", rod.current_map)
	if rod.current_map != null:
		print("FAIL: rod already has a map while still in the lobby")
		get_tree().quit(1)
		return

	var lobby := get_tree().root.get_node("GameRoot/NetworkRoot/World").get_child(0)
	var trigger: Area3D = lobby.get_node("StartTrigger")
	print("Walking into the start trigger at ", trigger.global_position)
	player.global_position = trigger.global_position
	player.linear_velocity = Vector3.ZERO

	var waited := 0.0
	while NetworkManager._current_scene_id != &"lake" and waited < 3.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()

	print("Scene after entering trigger: ", NetworkManager._current_scene_id)
	if NetworkManager._current_scene_id != &"lake":
		print("FAIL: round never started (still ", NetworkManager._current_scene_id, ")")
		get_tree().quit(1)
		return

	await get_tree().process_frame

	print("Player position after round start: ", player.global_position)
	print("Rod.current_map after round start: ", rod.current_map)
	if rod.current_map == null:
		print("FAIL: Rod.current_map never got refreshed for the new map")
		get_tree().quit(1)
		return

	var new_world_root := get_tree().root.get_node("GameRoot/NetworkRoot/World").get_child(0)
	if not (new_world_root is LakeMap):
		print("FAIL: World's child isn't the LakeMap after round start (", new_world_root, ")")
		get_tree().quit(1)
		return

	print("--- Lobby start-round test PASSED ---")
	get_tree().quit()
