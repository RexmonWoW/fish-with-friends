extends Node

## Headless check: when a reel resolves (catch or escape), every OTHER
## peer's local mirror of that Rod must also see state return to IDLE, not
## just the owning client's own optimistic local assignment -- otherwise
## LureAnimator (which polls rod.state == IDLE to decide when to hide the
## bobber/line) never clears on anyone else's screen, and the bobber+line
## just sit there forever after the cast is actually done.
##
## Simulates peer 2 by spawning a second local Player, the same technique
## other 2-peer tests use (line_tangle_test, round_day_quota_test) -- calls
## the host-authoritative broadcast RPC directly (_broadcast_reel_state_reset,
## same "authority, call_local" shape as Rod._cast_landed elsewhere) rather
## than the sender-gated _request_reel_resolution wrapper, since the sender
## check is tied to this process's real multiplayer identity (always peer 1
## here) and would reject a call made "as" peer 2 regardless of which Rod
## object it's invoked on -- same structural limitation already noted for
## line_tangle_test/round_day_quota_test.

func _ready() -> void:
	print("--- Reel-finish broadcast test ---")

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

	var rod2: Rod = (NetworkManager.spawned_players[2] as Player).equipment_slot.equipped_item as Rod
	var lure2: Node3D = rod2.get_node("LureAnimator")

	rod2._cast_landed(Vector3(0.0, 0.0, -15.0), 0.5, false)
	# Real elapsed time, not just frame count -- the arc tween runs on wall-clock time.
	await get_tree().create_timer(1.0).timeout

	if rod2.state != Rod.CastState.WAITING_BITE:
		print("FAIL: test setup problem -- rod2 never reached WAITING_BITE (state=%s)" % rod2.state)
		get_tree().quit(1)
		return
	if not lure2.visible:
		print("FAIL: test setup problem -- rod2's bobber/line never showed up")
		get_tree().quit(1)
		return
	print("Setup confirmed: rod2 is WAITING_BITE with a visible bobber/line.")

	# Simulate peer 2's reel finishing (catch or escape -- doesn't matter
	# which for this check) and the resulting host broadcast.
	rod2._broadcast_reel_state_reset.rpc()
	await get_tree().process_frame
	await get_tree().process_frame

	if rod2.state != Rod.CastState.IDLE:
		print("FAIL: rod2.state didn't reset to IDLE after the reel-finish broadcast (state=%s)" % rod2.state)
		get_tree().quit(1)
		return
	if lure2.visible:
		print("FAIL: rod2's bobber/line is still visible after the reel finished -- this is the reported bug")
		get_tree().quit(1)
		return

	print("--- Reel-finish broadcast test PASSED ---")
	get_tree().quit()
