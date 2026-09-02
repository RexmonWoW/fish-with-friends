extends Node

## Headless check: a bite that fires while its owner is mid-tangle shouldn't
## pop the ReelMinigame up on top of the tangle UI (both would fight over
## the same "cast" input). The reel should stay deferred until the tangle
## resolves, then start normally for the winner.

var _tangled: bool = false


func _ready() -> void:
	print("--- Tangle/reel pause test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	EventBus.tangle_started.connect(func(_a, _b): _tangled = true)

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

	var rod1: Rod = (NetworkManager.spawned_players[1] as Player).equipment_slot.equipped_item as Rod
	var rod2: Rod = (NetworkManager.spawned_players[2] as Player).equipment_slot.equipped_item as Rod

	# Land both at the same point -- guarantees their lines cross (same
	# technique as line_tangle_test.gd).
	var shared_endpoint := Vector3(0.0, 0.0, -15.0)
	rod1._cast_landed(shared_endpoint, 0.5, false)
	rod2._cast_landed(shared_endpoint, 0.5, false)

	var waited := 0.0
	while not _tangled and waited < 3.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	if not _tangled:
		print("FAIL: lines never tangled")
		get_tree().quit(1)
		return
	var tangle_manager: Node = get_tree().get_first_node_in_group("tangle_manager")

	# Force peer 1's bite to fire RIGHT NOW, while the tangle is still active.
	var reel: Control = get_tree().root.get_node("GameRoot/UILayer/ReelMinigame")
	print("reel visible immediately after forcing bite mid-tangle (should be false): ", )
	EventBus.bite_started.emit(load("res://data/fish/species/sunfish.tres"), 1)
	await get_tree().process_frame

	if reel.visible:
		print("FAIL: ReelMinigame popped up while still tangled")
		get_tree().quit(1)
		return
	print("Reel correctly deferred while tangled (rod1 state=%s)" % rod1.state)

	# Resolve the tangle in peer 1's favor.
	for i in range(20):
		tangle_manager._apply_mash(1)
		if rod2.state == Rod.CastState.IDLE:  # peer 2 lost -> reset to IDLE
			break
	await get_tree().process_frame
	await get_tree().process_frame

	print("After tangle resolves: rod1.state=%s reel.visible=%s" % [rod1.state, reel.visible])
	if rod1.state != Rod.CastState.REELING:
		print("FAIL: deferred bite never started the reel once the tangle cleared")
		get_tree().quit(1)
		return
	if not reel.visible:
		print("FAIL: reel should be visible now that it started")
		get_tree().quit(1)
		return

	print("--- Tangle/reel pause test PASSED ---")
	get_tree().quit()
