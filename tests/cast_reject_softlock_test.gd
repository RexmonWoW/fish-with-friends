extends Node

## Headless check, updated for GDD Casting's cast collision: aiming at the
## boat deck instead of real water USED TO be an invisible rejection
## (_cast_failed with "invalid_water"); now it's a dead cast that lands and
## lies there -- nothing will ever bite it, but it's never a silent
## rejection. The original regression this guarded (a soft-lock: Rod.
## release_cast()'s optimistic state = ANIMATING assignment getting
## clobbered back to ANIMATING forever) is still just as real for the new
## flow -- the same ordering now has to survive a landed-then-settled dead
## cast reaching WAITING_BITE (not stuck at ANIMATING), same as any other
## cast. Player movement (Player._physics_process's can_move) and Rod.
## start_charge() both gate on state == IDLE, so getting stuck reads as
## "can't move, can't cast again" either way.

## Member, not local -- GDScript lambdas capture local variables BY VALUE,
## not by reference, so a lambda assigning to a local bool would silently
## mutate its own captured copy, not this flag (bit this test once already
## before being fixed). A member var is plain instance-property access, no
## capture involved -- same pattern as e.g. tangle_reel_pause_test's _tangled.
var _got_dead_cast: bool = false
var _got_cast_failed: bool = false


func _ready() -> void:
	print("--- Cast-reject soft-lock test ---")

	EventBus.cast_landed.connect(func(_ep, _flight, _pid, is_dead_cast): _got_dead_cast = is_dead_cast)
	EventBus.cast_failed.connect(func(_reason, _pid): _got_cast_failed = true)

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

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	var bite_mgr := get_tree().get_first_node_in_group("bite_event_manager")

	# Aim toward the OTHER half of the boat with a short/weak cast (power
	# 0.1 -> min_cast_distance=3.0 dominates) so the landing point stays on
	# the boat deck (Hull spans roughly x -2..2, z -3..3) instead of
	# reaching real water past the edge -- a genuine solid-obstacle hit.
	player.camera_rig.rotation.y = PI
	await get_tree().process_frame

	rod.start_charge()
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: start_charge didn't charge (state=%s)" % rod.state)
		get_tree().quit(1)
		return

	rod.current_power = 0.1
	rod.release_cast()
	await get_tree().process_frame

	if _got_cast_failed:
		print("FAIL: cast at the deck triggered the old invisible rejection -- should be a dead cast now, never a silent failure")
		get_tree().quit(1)
		return
	if not _got_dead_cast:
		print("FAIL: test setup problem -- casting at the deck didn't register as a dead cast at all")
		get_tree().quit(1)
		return
	print("Casting at the deck landed as a dead cast, not a silent rejection.")

	if rod.state != Rod.CastState.ANIMATING:
		print("FAIL: rod should still be ANIMATING while the dead cast's arc plays out (state=%s)" % rod.state)
		get_tree().quit(1)
		return

	var settle_waited := 0.0
	while rod.state == Rod.CastState.ANIMATING and settle_waited < 2.0:
		await get_tree().process_frame
		settle_waited += get_process_delta_time()
	if rod.state != Rod.CastState.WAITING_BITE:
		print("FAIL: rod soft-locked after the dead cast landed (state=%s, expected WAITING_BITE=%s)" %
			[rod.state, Rod.CastState.WAITING_BITE])
		get_tree().quit(1)
		return
	print("Rod correctly reached WAITING_BITE (dead cast, not stuck at ANIMATING).")

	if bite_mgr._pending.has(player.peer_id):
		print("FAIL: a bite sequence got scheduled for a dead cast -- nothing should ever bite it")
		get_tree().quit(1)
		return
	print("No bite sequence scheduled for the dead cast, as expected.")

	# GDD: "cancel or recast to reel it back" -- confirm the existing
	# cancel path still works for a dead cast exactly like any other.
	rod.request_cancel_cast()
	await get_tree().process_frame
	if rod.state != Rod.CastState.IDLE:
		print("FAIL: couldn't cancel the dead cast back to IDLE (state=%s)" % rod.state)
		get_tree().quit(1)
		return
	print("Dead cast canceled back to IDLE.")

	# Confirm it's not just the enum value that's right -- start_charge()
	# (what Player movement AND recasting both gate on) actually works again.
	rod.start_charge()
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: couldn't start a new charge after the dead cast (state=%s)" % rod.state)
		get_tree().quit(1)
		return

	print("--- Cast-reject soft-lock test PASSED ---")
	get_tree().quit()
