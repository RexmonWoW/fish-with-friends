extends Node

## Headless check: while a player is in an active, unresolved tangle, they
## should be fully "planted" -- no walking, no jumping, no starting a new
## cast -- the same way an active cast/reel already blocks them, since
## Rod.state stays WAITING_BITE (not IDLE) for the whole tangle and both
## Player.can_move and Rod.start_charge() gate on state == IDLE. Reuses
## line_tangle_test.gd's real Area3D-crossing setup, but checks mid-tangle
## instead of after resolving it.

## Member, not local -- GDScript lambdas capture local variables BY VALUE,
## so a lambda assigning to a local bool would silently mutate its own
## captured copy, not this flag (bit a test once already this session --
## see cast_reject_softlock_test.gd -- same fix, a plain instance property).
var _tangled: bool = false


func _ready() -> void:
	print("--- Tangle blocks movement test ---")

	EventBus.tangle_started.connect(func(_a, _b): _tangled = true)

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

	var player1: Player = NetworkManager.spawned_players.get(1)  # local/host player
	var player2: Player = NetworkManager.spawned_players.get(2)
	var rod1: Rod = player1.equipment_slot.equipped_item as Rod
	var rod2: Rod = player2.equipment_slot.equipped_item as Rod

	var shared_endpoint := Vector3(0.0, 0.0, -15.0)
	rod1._cast_landed(shared_endpoint, 0.5)
	rod2._cast_landed(shared_endpoint, 0.5)

	var waited2 := 0.0
	while not _tangled and waited2 < 3.0:
		await get_tree().physics_frame
		waited2 += get_physics_process_delta_time()
	if not _tangled:
		print("FAIL: test setup problem -- lines never tangled")
		get_tree().quit(1)
		return
	print("Tangled. rod1.state=%s" % rod1.state)

	# ── Casting: shouldn't be able to start a new charge mid-tangle.
	rod1.start_charge()
	if rod1.state == Rod.CastState.CHARGING:
		print("FAIL: could start charging a new cast while tangled")
		get_tree().quit(1)
		return
	print("Casting correctly blocked while tangled.")

	# ── Movement: shouldn't accelerate under held move input.
	player1.linear_velocity = Vector3.ZERO
	Input.action_press(&"move_forward")
	for i in range(10):
		await get_tree().physics_frame
	Input.action_release(&"move_forward")

	var horiz_speed := Vector2(player1.linear_velocity.x, player1.linear_velocity.z).length()
	print("Horizontal speed after holding move_forward while tangled: %.3f" % horiz_speed)
	if horiz_speed > 0.1:
		print("FAIL: player moved while tangled (speed=%.3f)" % horiz_speed)
		get_tree().quit(1)
		return
	print("Movement correctly blocked while tangled.")

	# ── Jump: shouldn't launch upward.
	var vel_before_jump := player1.linear_velocity.y
	Input.action_press(&"jump")
	await get_tree().physics_frame
	Input.action_release(&"jump")
	await get_tree().physics_frame

	var vel_after_jump := player1.linear_velocity.y
	print("Vertical velocity before/after jump attempt while tangled: %.3f / %.3f" % [vel_before_jump, vel_after_jump])
	if vel_after_jump - vel_before_jump > 1.0:
		print("FAIL: player jumped while tangled")
		get_tree().quit(1)
		return
	print("Jump correctly blocked while tangled.")

	print("--- Tangle blocks movement test PASSED ---")
	get_tree().quit()
