extends Node

## Headless check: (1) right-click cancels a charging or waiting cast back
## to IDLE (there was previously no way out of either state short of it
## resolving on its own), (2) canceling a WAITING_BITE cast actually cancels
## the pending bite too, not just the visible state, and (3) a capsize mid-
## cast force-resets the rod so the player doesn't come back from swimming
## still stuck ("locked into the cast" -- playtest report 2026-08-30).

func _ready() -> void:
	print("--- Cast cancel test ---")

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
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake")
		get_tree().quit(1)
		return
	await get_tree().process_frame

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	var bite_mgr := get_tree().get_first_node_in_group("bite_event_manager")

	# ── Cancel while CHARGING ──
	rod.start_charge()
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: test setup problem -- didn't start charging")
		get_tree().quit(1)
		return
	rod.request_cancel_cast()
	await get_tree().process_frame
	if rod.state != Rod.CastState.IDLE:
		print("FAIL: cancel didn't return a charging rod to IDLE (state=%s)" % rod.state)
		get_tree().quit(1)
		return
	print("Cancel while CHARGING works.")

	# Confirm casting works again right after.
	rod.start_charge()
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: couldn't start charging again after a cancel")
		get_tree().quit(1)
		return
	rod.request_cancel_cast()
	await get_tree().process_frame

	# ── Cancel while WAITING_BITE -- must cancel the pending bite too ──
	# Calls BiteEventManager's handler directly rather than emitting
	# EventBus.cast_landed -- that signal also reaches LureAnimator, whose
	# own flight-tween callback would independently overwrite rod.state
	# later (on some later frame, unsynced with the rest of this test) and
	# pollute the capsize check below.
	bite_mgr._on_cast_landed(Vector3(5.0, -0.5, 5.0), 0.01, 1)
	rod.state = Rod.CastState.WAITING_BITE
	if not bite_mgr._pending.has(1):
		print("FAIL: test setup problem -- bite wasn't scheduled")
		get_tree().quit(1)
		return

	rod.request_cancel_cast()
	await get_tree().process_frame
	if rod.state != Rod.CastState.IDLE:
		print("FAIL: cancel didn't return a waiting rod to IDLE (state=%s)" % rod.state)
		get_tree().quit(1)
		return
	if bite_mgr._pending.has(1):
		print("FAIL: canceling didn't actually cancel the pending bite -- it would still fire")
		get_tree().quit(1)
		return
	print("Cancel while WAITING_BITE works, and the pending bite is actually canceled.")

	# ── Capsize mid-charge should force-reset the rod ──
	rod.start_charge()
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: test setup problem -- didn't start charging for the capsize case")
		get_tree().quit(1)
		return

	var capsize_manager := get_tree().get_first_node_in_group("capsize_manager")
	capsize_manager.start_capsize()
	await get_tree().process_frame

	if rod.state != Rod.CastState.IDLE:
		print("FAIL: capsizing mid-charge left the rod stuck (state=%s) -- 'locked into the cast'" % rod.state)
		get_tree().quit(1)
		return
	print("Capsizing mid-charge force-reset the rod to IDLE.")

	# Resolve the capsize (1 player -> 1 corner needed) and confirm casting
	# works normally again once back on the boat.
	var corner_pos: Vector3 = (capsize_manager._corner_markers[0] as Marker3D).global_position
	player.global_position = corner_pos
	capsize_manager._apply_claim(1, 0)
	await get_tree().process_frame

	rod.start_charge()
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: couldn't cast again after the capsize resolved (state=%s)" % rod.state)
		get_tree().quit(1)
		return
	print("Casting works normally again after the capsize resolved.")

	print("--- Cast cancel test PASSED ---")
	get_tree().quit()


func _wait_for_scene(scene_id: StringName, timeout: float = 3.0) -> bool:
	var waited := 0.0
	while NetworkManager._current_scene_id != scene_id and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return NetworkManager._current_scene_id == scene_id
