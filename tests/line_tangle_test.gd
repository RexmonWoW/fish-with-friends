extends Node

## Headless check for line tangling: two different players' rods, cast to
## the same water point (guaranteed geometric crossing -- two different
## rod-tip origins converging on one endpoint), should trigger a tangle via
## real Area3D overlap detection. Then verifies resolution: mashing more
## wins, the loser's line snaps (Rod -> IDLE) while the winner's line stays
## out, and the loser's pending bite gets canceled.

var _tangle_started_count: int = 0
var _last_resolved_winner: int = -1
var _last_resolved_loser: int = -1


func _ready() -> void:
	print("--- Line tangle test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	EventBus.tangle_started.connect(func(a, b): _tangle_started_count += 1; print("tangle_started a=%d b=%d" % [a, b]))
	EventBus.tangle_resolved.connect(func(w, l): _last_resolved_winner = w; _last_resolved_loser = l; print("tangle_resolved winner=%d loser=%d" % [w, l]))

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
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

	var player1: Player = NetworkManager.spawned_players.get(1)
	var player2: Player = NetworkManager.spawned_players.get(2)
	var rod1: Rod = player1.equipment_slot.equipped_item as Rod
	var rod2: Rod = player2.equipment_slot.equipped_item as Rod

	# Land both casts at the EXACT same point directly -- different rod-tip
	# origins converging on one shared endpoint guarantees the two lines
	# cross. (Going through _validate_and_land_cast with matching aim
	# directions doesn't actually guarantee this: cast distance is driven
	# by power, not by how far the aim target actually is, so two rods
	# aimed at the same nearby point can still land nowhere near each
	# other -- that's not what's under test here anyway, just detection.)
	var tip1: Vector3 = (rod1.get_node("RodTip") as Marker3D).global_position
	var tip2: Vector3 = (rod2.get_node("RodTip") as Marker3D).global_position
	var shared_endpoint := Vector3(0.0, 0.0, -15.0)
	print("Landing rod1 (tip ", tip1, ") and rod2 (tip ", tip2, ") both at ", shared_endpoint)

	rod1._cast_landed(shared_endpoint, 0.5)
	rod2._cast_landed(shared_endpoint, 0.5)

	# Let the arcs finish (0.5s) and physics detect the overlap.
	var waited := 0.0
	while _tangle_started_count == 0 and waited < 3.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()

	print("tangle_started fired %d time(s)" % _tangle_started_count)
	if _tangle_started_count == 0:
		print("FAIL: crossing lines never triggered a tangle")
		get_tree().quit(1)
		return
	if rod1.state != Rod.CastState.WAITING_BITE or rod2.state != Rod.CastState.WAITING_BITE:
		print("FAIL: expected both rods WAITING_BITE going into the tangle, got %s / %s" % [rod1.state, rod2.state])
		get_tree().quit(1)
		return

	# ── Resolve it: mash for peer 2 until they win.
	var tangle_manager: Node = get_tree().get_first_node_in_group("tangle_manager")
	if tangle_manager == null:
		print("FAIL: no TangleManager found")
		get_tree().quit(1)
		return

	for i in range(20):
		tangle_manager._apply_mash(2)
		if _last_resolved_winner != -1:
			break
	await get_tree().process_frame

	print("Resolved: winner=%d loser=%d" % [_last_resolved_winner, _last_resolved_loser])
	if _last_resolved_winner != 2 or _last_resolved_loser != 1:
		print("FAIL: expected peer 2 (who mashed) to win, peer 1 to lose")
		get_tree().quit(1)
		return

	if rod2.state != Rod.CastState.WAITING_BITE:
		print("FAIL: winner's (peer 2) rod should be untouched, still WAITING_BITE, got ", rod2.state)
		get_tree().quit(1)
		return
	if rod1.state != Rod.CastState.IDLE:
		print("FAIL: loser's (peer 1) rod should have reset to IDLE, got ", rod1.state)
		get_tree().quit(1)
		return

	var bite_manager: Node = get_tree().get_first_node_in_group("bite_event_manager")
	if bite_manager._pending.has(1):
		print("FAIL: loser's pending bite was not canceled")
		get_tree().quit(1)
		return

	print("--- Line tangle test PASSED ---")
	get_tree().quit()
