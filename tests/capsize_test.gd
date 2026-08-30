extends Node

## Headless check for the Capsize Minigame (GDD item 10): starting a
## capsize scales required corners to player count, swimming blocks normal
## rod casting, claiming a corner needs real proximity, one corner per
## player and one player per corner, and claiming enough corners resolves
## it -- swimming turns back off for everyone. Also covers CapsizeManager
## actually tossing the local player off the boat into the water (added
## 2026-08-30 -- playtest report: capsizing left a player stuck on the
## boat deck, swim mode on but blocked by the Hull's own collision).

var _started_required: int = -1
var _claim_events: Array = []  # [corner_index, peer_id, claimed_count, required]
var _resolved_count: int = 0


func _ready() -> void:
	print("--- Capsize test ---")

	EventBus.capsize_started.connect(func(required): _started_required = required)
	EventBus.capsize_corner_claimed.connect(
		func(idx, pid, claimed, required): _claim_events.append([idx, pid, claimed, required])
	)
	EventBus.capsize_resolved.connect(func(): _resolved_count += 1)

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
	var rod1: Rod = player1.equipment_slot.equipped_item as Rod
	var capsize_manager := get_tree().get_first_node_in_group("capsize_manager")
	if capsize_manager == null:
		print("FAIL: no CapsizeManager found")
		get_tree().quit(1)
		return

	capsize_manager.start_capsize()
	await get_tree().process_frame

	if _started_required != 2:
		print("FAIL: expected 2 required corners for 2 players, got %s" % _started_required)
		get_tree().quit(1)
		return
	print("Capsize started, required=%d" % _started_required)

	if not player1.is_swimming or player1.gravity_scale != 0.0:
		print("FAIL: local player didn't enter swim mode (is_swimming=%s gravity_scale=%s)" %
			[player1.is_swimming, player1.gravity_scale])
		get_tree().quit(1)
		return
	print("Local player is swimming.")

	# Free-swim physics alone doesn't help if the player's still sitting on
	# the boat deck, blocked by its collision -- "capsized but can't move."
	# Confirm they actually got tossed clear of the boat, not just
	# switched to swim mode in place.
	var boat_center: Vector3 = capsize_manager._boat_center()
	var boat_radius: float = capsize_manager._boat_radius()
	if boat_center.distance_to(player1.global_position) <= boat_radius:
		print("FAIL: local player is still within the boat's radius after capsizing -- not actually in the water")
		get_tree().quit(1)
		return
	print("Local player tossed clear of the boat into the water.")

	# Rod should be stowed to the back (an empty, same as while holding a
	# fish), not left sitting visibly in-hand while swimming.
	if player1.equipment_slot.equipped_item is Rod:
		print("FAIL: rod still equipped in-hand while swimming")
		get_tree().quit(1)
		return
	if player1.equipment_slot.stowed_item != rod1:
		print("FAIL: rod isn't stowed on the back (stowed_item=%s)" % player1.equipment_slot.stowed_item)
		get_tree().quit(1)
		return
	print("Rod stowed to the back.")

	# Casting should be blocked entirely while swimming.
	rod1.start_charge()
	if rod1.state == Rod.CastState.CHARGING:
		print("FAIL: could start charging a cast while swimming")
		get_tree().quit(1)
		return
	print("Casting correctly blocked while swimming.")

	var corners: Array = capsize_manager._corner_markers
	var corner0_pos: Vector3 = (corners[0] as Marker3D).global_position
	var corner1_pos: Vector3 = (corners[1] as Marker3D).global_position

	# Too far away -- should be rejected.
	player1.global_position = corner0_pos + Vector3(50.0, 0.0, 0.0)
	capsize_manager._apply_claim(1, 0)
	if capsize_manager._claimed_by.has(0):
		print("FAIL: claimed a corner from far away")
		get_tree().quit(1)
		return
	print("Far-away claim correctly rejected.")

	# Actually get close, then claim.
	player1.global_position = corner0_pos
	capsize_manager._apply_claim(1, 0)
	if not capsize_manager._claimed_by.has(0) or capsize_manager._claimed_by[0] != 1:
		print("FAIL: peer 1's close-range claim on corner 0 didn't register")
		get_tree().quit(1)
		return
	print("Corner 0 claimed by peer 1.")

	# Same player trying a second corner shouldn't work (one corner each).
	player1.global_position = corner1_pos
	capsize_manager._apply_claim(1, 1)
	if capsize_manager._claimed_by.has(1):
		print("FAIL: peer 1 claimed a second corner")
		get_tree().quit(1)
		return
	print("Second claim by the same player correctly rejected.")

	# Someone else trying the ALREADY-claimed corner shouldn't work either.
	player2.global_position = corner0_pos
	capsize_manager._apply_claim(2, 0)
	if capsize_manager._claimed_by[0] != 1:
		print("FAIL: corner 0 got reassigned away from peer 1")
		get_tree().quit(1)
		return
	print("Claim on an already-taken corner correctly rejected.")

	# Peer 2 claims corner 1 for real -- that's the required count (2), so
	# this should resolve the whole capsize.
	player2.global_position = corner1_pos
	capsize_manager._apply_claim(2, 1)
	await get_tree().process_frame

	if capsize_manager.is_active():
		print("FAIL: capsize still active after all required corners were claimed")
		get_tree().quit(1)
		return
	if _resolved_count != 1:
		print("FAIL: capsize_resolved didn't fire exactly once (fired %d times)" % _resolved_count)
		get_tree().quit(1)
		return
	if player1.is_swimming or player1.gravity_scale != 1.0:
		print("FAIL: local player still swimming after capsize resolved (is_swimming=%s gravity_scale=%s)" %
			[player1.is_swimming, player1.gravity_scale])
		get_tree().quit(1)
		return
	print("Capsize resolved, swimming ended.")

	if player1.equipment_slot.equipped_item != rod1:
		print("FAIL: rod not back in hand after capsize resolved (equipped_item=%s)" % player1.equipment_slot.equipped_item)
		get_tree().quit(1)
		return
	print("Rod back in hand.")

	rod1.start_charge()
	if rod1.state != Rod.CastState.CHARGING:
		print("FAIL: couldn't cast again after the capsize resolved (state=%s)" % rod1.state)
		get_tree().quit(1)
		return

	print("--- Capsize test PASSED ---")
	get_tree().quit()
