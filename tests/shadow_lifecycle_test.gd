extends Node

## Headless check for a real playtest bug: ambient shadows (VisualFish)
## used to be parented at the scene root instead of under the map, so a
## round ending left the whole standing population behind, still
## wandering, right in the lobby -- instead of getting cleaned up with
## everything else in the map that just unloaded. Also checks a fresh
## round rolls exactly one clean population, not a doubled-up mess of old
## + new.

func _ready() -> void:
	print("--- Shadow lifecycle test ---")

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
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for round 1")
		get_tree().quit(1)
		return
	await get_tree().process_frame

	var round1_shadows := get_tree().get_nodes_in_group("visual_fish")
	if round1_shadows.size() != VisualFishSpawner.AMBIENT_COUNT:
		print("FAIL: expected %d ambient shadows in round 1, got %d" %
			[VisualFishSpawner.AMBIENT_COUNT, round1_shadows.size()])
		get_tree().quit(1)
		return
	print("Round 1: %d ambient shadows spawned." % round1_shadows.size())

	# End the round (same transition a real timeout triggers) and land in
	# the lobby -- this is the reported bug: shadows used to still be here.
	RunState.debug_skip_round()
	if not await _wait_for_scene(&"lobby"):
		print("FAIL: skip_round never ended round 1")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame

	var lobby_shadows := get_tree().get_nodes_in_group("visual_fish")
	if not lobby_shadows.is_empty():
		print("FAIL: %d shadows survived into the lobby -- this is the reported bug" % lobby_shadows.size())
		get_tree().quit(1)
		return
	print("Lobby: no leftover shadows.")

	# Round 2 should roll a fresh, clean population -- not doubled up with
	# anything left behind from round 1.
	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for round 2")
		get_tree().quit(1)
		return
	await get_tree().process_frame

	var round2_shadows := get_tree().get_nodes_in_group("visual_fish")
	if round2_shadows.size() != VisualFishSpawner.AMBIENT_COUNT:
		print("FAIL: expected a fresh %d-shadow population in round 2, got %d" %
			[VisualFishSpawner.AMBIENT_COUNT, round2_shadows.size()])
		get_tree().quit(1)
		return
	print("Round 2: a fresh, clean population of %d shadows." % round2_shadows.size())

	print("--- Shadow lifecycle test PASSED ---")
	get_tree().quit()


func _wait_for_scene(scene_id: StringName, timeout: float = 3.0) -> bool:
	var waited := 0.0
	while NetworkManager._current_scene_id != scene_id and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return NetworkManager._current_scene_id == scene_id
