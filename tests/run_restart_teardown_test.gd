extends Node

## Headless check for a real playtest bug: failing the quota, returning to
## the main menu, and starting a new game left the OLD run's World
## contents (an old map -- _load_map only ever ADDS a scene, never
## replaces one) and OLD Player nodes behind, read as "the old run's
## boat/livewell show up in the lobby, plus a duplicate player."
## Runs the whole fail -> menu -> new game cycle TWICE in a row, solo,
## confirming after each teardown that nothing survived: no leftover
## Player nodes, no leftover map/lobby scene, RunState's per-run
## bookkeeping actually reset -- not just spawned_players no longer
## tracking them.

var _spawned: bool = false
var _run_over_fired: bool = false


func _ready() -> void:
	print("--- Run restart teardown test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(func(_p): _spawned = true)
	RunState.run_over.connect(func(_day, _money): _run_over_fired = true)

	await _run_one_cycle(1)
	await _run_one_cycle(2)
	print("--- Run restart teardown test PASSED ---")
	get_tree().quit()


func _run_one_cycle(cycle_number: int) -> void:
	print("-- Cycle %d: starting a new game --" % cycle_number)

	_spawned = false
	NetworkManager.host_lobby()

	var waited := 0.0
	while not _spawned and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not _spawned:
		print("FAIL: cycle %d never spawned a local player" % cycle_number)
		get_tree().quit(1)
		return

	var players_container := get_tree().root.get_node("GameRoot/NetworkRoot/Players")
	var world := get_tree().root.get_node("GameRoot/NetworkRoot/World")

	if NetworkManager.spawned_players.size() != 1 or players_container.get_child_count() != 1:
		print("FAIL: cycle %d expected exactly 1 player (spawned_players=%d, node children=%d)" %
			[cycle_number, NetworkManager.spawned_players.size(), players_container.get_child_count()])
		get_tree().quit(1)
		return
	print("Cycle %d: exactly 1 player spawned, no leftovers." % cycle_number)

	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: cycle %d never reached the lake" % cycle_number)
		get_tree().quit(1)
		return
	await get_tree().process_frame

	if world.get_child_count() != 1:
		print("FAIL: cycle %d expected exactly 1 map loaded in World, got %d" %
			[cycle_number, world.get_child_count()])
		get_tree().quit(1)
		return
	print("Cycle %d: exactly 1 map loaded (the lake)." % cycle_number)

	# Fail the quota -- set it impossibly high, then let debug_skip_day walk
	# both rounds and resolve the day as a loss.
	_run_over_fired = false
	RunState.current_quota = 999999
	RunState.debug_skip_day()

	var over_waited := 0.0
	while not _run_over_fired and over_waited < 5.0:
		await get_tree().process_frame
		over_waited += get_process_delta_time()
	if not _run_over_fired:
		print("FAIL: cycle %d never got run_over after missing the quota" % cycle_number)
		get_tree().quit(1)
		return
	print("Cycle %d: quota missed, run over." % cycle_number)

	# "Click to return to main menu" -- the actual teardown under test.
	NetworkManager.disconnect_from_lobby()
	await get_tree().process_frame
	await get_tree().process_frame

	if NetworkManager.spawned_players.size() != 0:
		print("FAIL: cycle %d spawned_players not cleared after teardown (%d left)" %
			[cycle_number, NetworkManager.spawned_players.size()])
		get_tree().quit(1)
		return
	if players_container.get_child_count() != 0:
		print("FAIL: cycle %d Players container still has %d children after teardown" %
			[cycle_number, players_container.get_child_count()])
		get_tree().quit(1)
		return
	if world.get_child_count() != 0:
		print("FAIL: cycle %d World still has %d children after teardown" %
			[cycle_number, world.get_child_count()])
		get_tree().quit(1)
		return
	if RunState.day_number != 1 or RunState.total_money_earned != 0:
		print("FAIL: cycle %d RunState not reset (day=%d earned=%d)" %
			[cycle_number, RunState.day_number, RunState.total_money_earned])
		get_tree().quit(1)
		return
	print("Cycle %d: teardown clean -- no players, no world, RunState reset." % cycle_number)


func _wait_for_scene(scene_id: StringName, timeout: float = 3.0) -> bool:
	var waited := 0.0
	while NetworkManager._current_scene_id != scene_id and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return NetworkManager._current_scene_id == scene_id
