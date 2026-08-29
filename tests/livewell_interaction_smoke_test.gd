extends Node

## Headless smoke test for the livewell proximity + look popup and the
## grab interaction: walk into range -> look at the specific (swimming)
## fish -> its info shows -> press "1" -> the fish is grabbed into the
## player's hand (not discarded) -> slot empties and the info clears again.

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
	if display._current_livewell != livewell:
		print("FAIL: display's current_livewell doesn't match")
		get_tree().quit(1)
		return

	# Aim the camera at the specific (swimming) fish -- info only shows for
	# whichever slot the player is actually looking at, not a blanket dump.
	_look_at_slot(player, livewell, slot_index)
	waited = 0.0
	while display._looked_at_index != slot_index and waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()

	print("Looked-at index: ", display._looked_at_index)
	if display._looked_at_index != slot_index:
		print("FAIL: display never picked up the fish being looked at")
		get_tree().quit(1)
		return
	print("Info while looking at it: ", display._info_label.text)
	if not ("Sunfish" in display._info_label.text):
		print("FAIL: info label doesn't show the looked-at fish's species")
		get_tree().quit(1)
		return

	print("Simulating '1' key press to grab the fish into hand...")
	var key_event := InputEventKey.new()
	key_event.pressed = true
	key_event.keycode = KEY_1
	Input.parse_input_event(key_event)
	await get_tree().process_frame
	await get_tree().process_frame

	print("Slot 0 after grabbing: ", livewell.slots[0])
	if livewell.slots[0] != null:
		print("FAIL: fish was not removed from the livewell")
		get_tree().quit(1)
		return
	if not player.equipment_slot.has_fish_held():
		print("FAIL: grabbed fish wasn't handed to the player -- it should be held, not discarded")
		get_tree().quit(1)
		return
	if player.equipment_slot.get_held_fish() != caught:
		print("FAIL: player is holding a different fish than the one grabbed")
		get_tree().quit(1)
		return
	print("Fish grabbed into hand (not discarded).")

	# Nothing left in that slot to look at -- the label should fall back to
	# the generic hint instead of continuing to show the (now gone) fish.
	await get_tree().process_frame
	print("Info after grabbing: ", display._info_label.text)
	if "Sunfish" in display._info_label.text:
		print("FAIL: info label still shows the grabbed fish's old slot")
		get_tree().quit(1)
		return

	print("--- Livewell interaction smoke test PASSED ---")
	get_tree().quit()


## Orients the player's camera (yaw + pitch) so it's looking directly at the
## given slot's current (swimming) visual position -- the fish sit well
## below eye level, so yaw alone isn't enough to bring them within the
## look-angle threshold.
func _look_at_slot(player: Player, livewell: Livewell, slot_index: int) -> void:
	var fish_pos: Vector3 = livewell.get_visual_global_position(slot_index)
	var cam_origin: Vector3 = player.camera.global_transform.origin
	var to_fish := fish_pos - cam_origin
	var horizontal := Vector3(to_fish.x, 0.0, to_fish.z)
	if horizontal.length_squared() < 0.0001:
		return

	var forward := Vector3(0.0, 0.0, -1.0)
	player.camera_rig.rotation.y = forward.signed_angle_to(horizontal.normalized(), Vector3.UP)

	var pitch := atan2(to_fish.y, horizontal.length())
	player.camera_pitch.rotation.x = clampf(pitch, -PI / 2.0 * 0.95, PI / 2.0 * 0.95)
