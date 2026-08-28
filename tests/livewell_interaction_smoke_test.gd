extends Node

## Headless smoke test for the livewell proximity popup + throw-overboard
## interaction: walk into range -> popup shows the fish -> press "1" ->
## slot empties again.

func _ready() -> void:
	print("--- Livewell interaction smoke test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# Players now land in the lobby first (bare-bones lobby); skip straight
	# to the lake for this test rather than walking into the StartTrigger.
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

	var livewell: Livewell = get_tree().get_first_node_in_group("livewell")

	# Manually stock a fish so there's something to show/remove --
	# reel_smoke_test already covers the cast->catch path.
	var species: FishData = load("res://data/fish/species/sunfish.tres")
	var caught := FishFactory.create_caught_fish(
		species, player.peer_id, "Player %d" % player.peer_id, &"lake", false, [], [], false
	)
	var slot_index := livewell.add_fish(caught)
	print("Stocked fish in slot ", slot_index)

	var display: Control = get_tree().root.get_node("GameRoot/UILayer/LivewellDisplay")
	print("Display visible before entering range: ", display.visible)

	print("Teleporting player into the livewell zone...")
	player.global_position = Vector3(0.0, 1.5, 0.0)
	player.linear_velocity = Vector3.ZERO

	var waited := 0.0
	while not display.visible and waited < 3.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()

	print("Display visible after entering range: ", display.visible)
	if not display.visible:
		print("FAIL: LivewellDisplay never showed up on proximity")
		get_tree().quit(1)
		return

	print("Row 0 text: ", display._slot_labels[0].text)
	if display._current_livewell != livewell:
		print("FAIL: display's current_livewell doesn't match")
		get_tree().quit(1)
		return

	print("Simulating '1' key press to throw the fish overboard...")
	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.keycode = KEY_1
	Input.parse_input_event(key_event)
	await get_tree().process_frame
	await get_tree().process_frame

	print("Slot 0 after removal: ", livewell.slots[0])
	if livewell.slots[0] != null:
		print("FAIL: fish was not removed from the livewell")
		get_tree().quit(1)
		return
	print("Row 0 text after removal: ", display._slot_labels[0].text)

	print("--- Livewell interaction smoke test PASSED ---")
	get_tree().quit()
