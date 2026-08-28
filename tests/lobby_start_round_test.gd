extends Node

## Headless check for the bare-bones lobby: host lands in the lobby (not
## the lake) first, walking into the StartTrigger actually starts the round
## (swaps to the lake, repositions the player).
##
## Also regression-covers a real bug a planning-chat review caught: Rod used
## to cache current_map on the node, refreshed only for "whichever player is
## local on the machine running the refresh code" -- which on the host means
## only the HOST'S OWN rod, never a client's, since the host-side copy of a
## client's rod is never "local" there. Water validation always runs
## host-side, so every non-host client's casts would validate against a
## permanently-null cached map (silent permissive fallback, not a crash) no
## matter how long the round had been running. Fixed by not caching at all --
## Rod asks NetworkManager for the current map fresh on every validation.
## Proven below by validating a SECOND (non-local) player's rod, host-side,
## after the round starts, and confirming it's genuinely snapped to the real
## water height rather than silently passing through the old permissive path.

var _last_result: String = "(none)"
var _last_endpoint: Vector3 = Vector3.ZERO


func _ready() -> void:
	print("--- Lobby start-round test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	# Persistent connections, not per-call connect/disconnect -- that pattern
	# has already bitten this session once (cast_angle_smoke_test) with
	# signals silently not firing for reasons never fully pinned down.
	EventBus.cast_landed.connect(func(ep, _flight, _pid): _last_result = "landed"; _last_endpoint = ep)
	EventBus.cast_failed.connect(func(reason, _pid): _last_result = "failed:" + str(reason))

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

	var new_world_root := get_tree().root.get_node("GameRoot/NetworkRoot/World").get_child(0)
	if not (new_world_root is LakeMap):
		print("FAIL: World's child isn't the LakeMap after round start (", new_world_root, ")")
		get_tree().quit(1)
		return

	# ── Regression check: a second, non-local player's rod must still
	# validate against the REAL water, host-side, after the round started.
	NetworkManager._spawn_player_for_peer(2)
	await get_tree().process_frame
	await get_tree().process_frame

	var other_player: Player = NetworkManager.spawned_players.get(2)
	if other_player == null:
		print("FAIL: second player never registered")
		get_tree().quit(1)
		return

	var other_rod: Rod = other_player.equipment_slot.equipped_item as Rod

	# Aim height (5) well above the water -- if this were still using the
	# old permissive/no-map fallback, the endpoint's Y would come back near
	# this aim height, unchanged. Real validation snaps it to the actual
	# water surface (~0) instead. (Not 10: WaterValidator's raycast is a
	# fixed +-10 window around the aim point, so 10 would land the ray's
	# far end exactly on the water plane -- an edge case, not a fair test.)
	_last_result = "(none)"
	other_rod._validate_and_land_cast(Vector3(5.0, 5.0, 5.0), Vector3(0.0, 0.0, -1.0), 0.5)
	await get_tree().process_frame

	print("Second player's cast result=%s endpoint=%s" % [_last_result, _last_endpoint])
	if _last_result != "landed":
		print("FAIL: second player's rod cast was rejected -- can't confirm the fix this way")
		get_tree().quit(1)
		return
	if absf(_last_endpoint.y) > 1.0:
		print("FAIL: endpoint Y (%.2f) wasn't snapped to real water -- looks like the old permissive/stale-cache fallback" % _last_endpoint.y)
		get_tree().quit(1)
		return

	print("--- Lobby start-round test PASSED ---")
	get_tree().quit()
