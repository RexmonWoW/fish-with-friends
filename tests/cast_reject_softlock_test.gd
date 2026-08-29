extends Node

## Headless check: a rejected cast (e.g. aimed at the boat instead of real
## water) must leave Rod.state at IDLE, not soft-lock the player. Root cause
## was ordering in Rod.release_cast(): the "optimistic" state = ANIMATING
## assignment ran AFTER _request_cast.rpc(...), which for a host/solo caster
## resolves synchronously (any_peer + call_local) -- including a rejection's
## _cast_failed.rpc() correctly resetting state to IDLE -- so the optimistic
## line then clobbered that real result back to ANIMATING forever. Player
## movement (Player._physics_process's can_move) and Rod.start_charge() both
## gate on state == IDLE, so this reads as "can't move, can't cast again."

## Member, not local -- GDScript lambdas capture local variables BY VALUE,
## not by reference, so a lambda assigning to a local bool would silently
## mutate its own captured copy, not this flag (bit this test once already
## before being fixed). A member var is plain instance-property access, no
## capture involved -- same pattern as e.g. tangle_reel_pause_test's _tangled.
var _got_cast_failed: bool = false


func _ready() -> void:
	print("--- Cast-reject soft-lock test ---")

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

	# Aim toward the OTHER half of the boat with a short/weak cast (power
	# 0.1 -> min_cast_distance=3.0 dominates) so the landing point stays on
	# the boat deck (Hull spans roughly x -2..2, z -3..3) instead of
	# reaching real water past the edge -- a genuine rejected cast.
	player.camera_rig.rotation.y = PI
	await get_tree().process_frame

	rod.start_charge()
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: start_charge didn't charge (state=%s)" % rod.state)
		get_tree().quit(1)
		return

	rod.current_power = 0.1
	rod.release_cast()

	# The host-self-cast path resolves synchronously inside release_cast(),
	# so this should already be settled -- but give it a frame either way
	# rather than assuming.
	await get_tree().process_frame

	if not _got_cast_failed:
		print("FAIL: test setup problem -- cast wasn't actually rejected (cast_failed never fired)")
		get_tree().quit(1)
		return

	if rod.state != Rod.CastState.IDLE:
		print("FAIL: rod soft-locked after a rejected cast (state=%s, expected IDLE=%s)" % [rod.state, Rod.CastState.IDLE])
		get_tree().quit(1)
		return
	print("Rod correctly back at IDLE after the rejected cast.")

	# Confirm it's not just the enum value that's right -- start_charge()
	# (what Player movement AND recasting both gate on) actually works again.
	rod.start_charge()
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: couldn't start a new charge after the rejected cast (state=%s)" % rod.state)
		get_tree().quit(1)
		return

	print("--- Cast-reject soft-lock test PASSED ---")
	get_tree().quit()
