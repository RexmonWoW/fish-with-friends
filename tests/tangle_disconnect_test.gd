extends Node

## Headless check: if a peer disconnects while tangled, the OTHER
## (still-connected) player should be declared the winner immediately, not
## left waiting out the 6s stalemate timer only to have the result decided
## by whatever the rope happened to read at that random moment.
##
## Can't simulate a REAL peer disconnecting from within a single-process
## test (peer 2 here is a locally-spawned stand-in, not a real network
## connection -- same structural limit as line_tangle_test.gd), so this
## calls TangleManager's disconnect handler directly, the same way other
## tests bypass sender-gated RPC wrappers to exercise host-authoritative
## logic directly.

var _tangled: bool = false
var _resolved_winner: int = -1
var _resolved_loser: int = -1


func _ready() -> void:
	print("--- Tangle disconnect test ---")

	EventBus.tangle_started.connect(func(_a, _b): _tangled = true)
	EventBus.tangle_resolved.connect(func(w, l): _resolved_winner = w; _resolved_loser = l)

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

	NetworkManager._spawn_player_for_peer(2)
	await get_tree().process_frame
	await get_tree().process_frame

	var rod1: Rod = (NetworkManager.spawned_players[1] as Player).equipment_slot.equipped_item as Rod
	var rod2: Rod = (NetworkManager.spawned_players[2] as Player).equipment_slot.equipped_item as Rod

	var shared_endpoint := Vector3(0.0, 0.0, -15.0)
	rod1._cast_landed(shared_endpoint, 0.5, false)
	rod2._cast_landed(shared_endpoint, 0.5, false)

	var waited2 := 0.0
	while not _tangled and waited2 < 3.0:
		await get_tree().physics_frame
		waited2 += get_physics_process_delta_time()
	if not _tangled:
		print("FAIL: test setup problem -- lines never tangled")
		get_tree().quit(1)
		return

	var tangle_manager: Node = get_tree().get_first_node_in_group("tangle_manager")

	# Tip the rope toward peer 2 first -- if the disconnect handling only
	# worked by coincidence (e.g. always favored peer_to_tangle's "a"), this
	# would catch it: peer 1 (a) is the one about to "disconnect" here, so a
	# naive/wrong implementation would wrongly still hand them the win.
	tangle_manager._apply_mash(1)
	tangle_manager._apply_mash(1)
	print("Rope nudged toward peer 1 before they 'disconnect' -- should NOT matter.")

	# Simulate peer 1 disconnecting mid-tangle (see class doc for why this
	# calls the handler directly instead of a real network disconnect).
	tangle_manager._on_peer_disconnected(1)
	await get_tree().process_frame

	print("Resolved: winner=%d loser=%d" % [_resolved_winner, _resolved_loser])
	if _resolved_winner != 2 or _resolved_loser != 1:
		print("FAIL: expected peer 2 (still connected) to win, peer 1 (disconnected) to lose")
		get_tree().quit(1)
		return

	if rod2.state != Rod.CastState.WAITING_BITE:
		print("FAIL: survivor's (peer 2) rod should be untouched, still WAITING_BITE, got %s" % rod2.state)
		get_tree().quit(1)
		return

	# The tangle bookkeeping should be fully cleared -- no dangling entries
	# that could confuse a later tangle involving either peer_id again.
	if tangle_manager._peer_to_tangle.has(1) or tangle_manager._peer_to_tangle.has(2):
		print("FAIL: tangle bookkeeping wasn't cleared after the disconnect resolution")
		get_tree().quit(1)
		return

	# Calling it again (e.g. a duplicate disconnect signal) should be a
	# harmless no-op, not an error.
	tangle_manager._on_peer_disconnected(1)
	await get_tree().process_frame

	print("--- Tangle disconnect test PASSED ---")
	get_tree().quit()
