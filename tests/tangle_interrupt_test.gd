extends Node

## Headless check for GDD Line Tangling's "full interrupt": a tangle must
## genuinely freeze BOTH players' bite sequences, not just defer a NEW bite
## from popping the reel open (the old, incomplete fix -- see
## tangle_reel_pause_test.gd for that half, still correct and unaffected).
## Covers the exact playtest bug report: mashing the tangle (which is also
## "cast") can't sneak a hook-set through even though the window's
## nominally still open, and it resumes for real once the duel resolves.
##
## Directly forces the "hook window open" precondition (bite_mgr._hook_open)
## rather than racing a real shadow's travel time to naturally reach that
## state within the 1s default window -- the mechanism under test is the
## tangle-freeze/server-side reject, not shadow-call timing, and a real
## shadow search introduces exactly the kind of physics-timing flakiness
## this project's testing notes warn about. Same "reach into internals for
## precise control" convention already used elsewhere (e.g.
## TangleManager._apply_mash).

var _tangle_started_count: int = 0
var _last_resolved_winner: int = -1


func _ready() -> void:
	print("--- Tangle interrupt test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	EventBus.tangle_started.connect(func(_a, _b): _tangle_started_count += 1)
	EventBus.tangle_resolved.connect(func(w, _l): _last_resolved_winner = w)

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player1: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

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

	NetworkManager._spawn_player_for_peer(2)
	await get_tree().process_frame
	await get_tree().process_frame

	var rod1: Rod = player1.equipment_slot.equipped_item as Rod
	var player2: Player = NetworkManager.spawned_players[2]
	var rod2: Rod = player2.equipment_slot.equipped_item as Rod
	var bite_mgr := get_tree().get_first_node_in_group("bite_event_manager")
	var tangle_mgr := get_tree().get_first_node_in_group("tangle_manager")

	# ── Tangle them: land both lines at the same point (same technique as ──
	# ── line_tangle_test.gd). ──
	var shared_endpoint := Vector3(0.0, 0.0, -15.0)
	rod1._cast_landed(shared_endpoint, 0.5, false)
	rod2._cast_landed(shared_endpoint, 0.5, false)

	var tangle_waited := 0.0
	while _tangle_started_count == 0 and tangle_waited < 3.0:
		await get_tree().physics_frame
		tangle_waited += get_physics_process_delta_time()
	if _tangle_started_count == 0:
		print("FAIL: test setup problem -- crossing lines never tangled")
		get_tree().quit(1)
		return
	if not tangle_mgr.is_tangled(1) or not tangle_mgr.is_tangled(2):
		print("FAIL: TangleManager.is_tangled should be true for both dueling peers")
		get_tree().quit(1)
		return
	print("Tangled. is_tangled correctly true for both peers.")

	# ── Force peer 1 into "hook window open" -- same state a real struck ──
	# ── shadow would leave, without racing its travel time to get there. ──
	bite_mgr._hook_open[1] = true
	bite_mgr._hook_set[1] = false

	bite_mgr.request_hook_set()
	await get_tree().process_frame
	if bite_mgr._hook_set.get(1, false):
		print("FAIL: hook-set succeeded while tangled -- mashing the duel could set the hook")
		get_tree().quit(1)
		return
	print("Hook-set correctly rejected while tangled, even with the window nominally open.")

	# ── Resolve the tangle in peer 1's favor -- their pending state (still ──
	# ── WAITING_BITE, hook window still open) should survive untouched. ──
	for i in range(20):
		tangle_mgr._apply_mash(1)
		if rod2.state == Rod.CastState.IDLE:
			break
	await get_tree().process_frame
	await get_tree().process_frame

	if _last_resolved_winner != 1:
		print("FAIL: test setup problem -- peer 1 should have won the mash-off")
		get_tree().quit(1)
		return
	if tangle_mgr.is_tangled(1) or tangle_mgr.is_tangled(2):
		print("FAIL: is_tangled should be false for both once resolved")
		get_tree().quit(1)
		return
	if rod1.state != Rod.CastState.WAITING_BITE:
		print("FAIL: peer 1 (winner) should still be WAITING_BITE with their pending bite intact, got %s" % rod1.state)
		get_tree().quit(1)
		return
	if rod2.state != Rod.CastState.IDLE:
		print("FAIL: peer 2 (loser) should have reset to IDLE, got %s" % rod2.state)
		get_tree().quit(1)
		return
	print("Tangle resolved: winner keeps their pending bite, loser's line snapped.")

	# ── Hook-set works again now that the duel is over -- a real resume, ──
	# ── not something that quietly stayed broken. ──
	bite_mgr.request_hook_set()
	await get_tree().process_frame
	if not bite_mgr._hook_set.get(1, false):
		print("FAIL: hook-set still rejected after the tangle resolved -- didn't actually resume")
		get_tree().quit(1)
		return
	print("Hook-set works again once untangled -- the interrupt genuinely lifted.")

	print("--- Tangle interrupt test PASSED ---")
	get_tree().quit()
