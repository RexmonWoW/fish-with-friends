extends Node

## Headless check for the Big Fish Event's trigger condition (GDD, changed
## 2026-08-30): no longer a random per-round chance -- fires once per day,
## in the final stretch of the day's second (last) round. Confirms it stays
## quiet on round 1 no matter how little time is left, stays quiet on round
## 2 until the final-stretch window opens, fires once inside that window,
## and doesn't fire again later the same round even though the window is
## still open (GDD: once per day, not "every time conditions are met").

func _ready() -> void:
	print("--- Big Fish trigger timing test ---")

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
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for round 1")
		get_tree().quit(1)
		return
	await get_tree().process_frame

	var mgr := get_tree().get_first_node_in_group("big_fish_event_manager")

	# Round 1, almost no time left -- must NOT trigger, even deep in what
	# would be the final-stretch window on round 2.
	RunState._time_remaining = 5.0
	mgr._process(0.1)
	if mgr._phase != mgr.Phase.INACTIVE:
		print("FAIL: event triggered during round 1")
		get_tree().quit(1)
		return
	print("Stayed quiet on round 1 with 5s left.")

	# Advance to round 2 (a fresh Lake, fresh manager instance).
	RunState._time_remaining = 0.01
	await _wait_frames(5)
	if not await _wait_for_scene(&"lobby"):
		print("FAIL: never returned to the lobby after round 1")
		get_tree().quit(1)
		return
	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for round 2")
		get_tree().quit(1)
		return
	await get_tree().process_frame

	mgr = get_tree().get_first_node_in_group("big_fish_event_manager")
	if RunState.round_number != RunState.ROUNDS_PER_DAY:
		print("FAIL: test setup problem -- expected to be in the day's final round")
		get_tree().quit(1)
		return

	# Round 2, plenty of time left (outside the final-stretch window) --
	# still must not trigger.
	RunState._time_remaining = mgr.FINAL_STRETCH_SECONDS + 50.0
	mgr._process(0.1)
	if mgr._phase != mgr.Phase.INACTIVE:
		print("FAIL: event triggered before the final-stretch window opened")
		get_tree().quit(1)
		return
	print("Stayed quiet on round 2 outside the final-stretch window.")

	# Round 2, inside the window -- should trigger (retry a few frames since
	# a bad-luck water probe just gets retried, not treated as a final no).
	RunState._time_remaining = mgr.FINAL_STRETCH_SECONDS - 5.0
	var triggered := false
	for i in range(10):
		mgr._process(0.1)
		if mgr._phase == mgr.Phase.READY_CHECK:
			triggered = true
			break
	if not triggered:
		print("FAIL: event never triggered inside the final-stretch window")
		get_tree().quit(1)
		return
	if not mgr._already_triggered:
		print("FAIL: _already_triggered wasn't set once the event actually started")
		get_tree().quit(1)
		return
	print("Triggered inside the final-stretch window.")

	# Resolve it (fizzle -- nobody joined) and confirm it does NOT fire
	# again later this same round, even though time is still in-window.
	mgr._phase_timer = 0.0
	mgr._process(0.1)
	if mgr._phase != mgr.Phase.INACTIVE:
		print("FAIL: test setup problem -- event never resolved back to INACTIVE")
		get_tree().quit(1)
		return
	mgr._process(0.1)
	if mgr._phase != mgr.Phase.INACTIVE:
		print("FAIL: event fired a second time in the same round -- should be once per day")
		get_tree().quit(1)
		return
	print("Didn't fire again later the same round.")

	print("--- Big Fish trigger timing test PASSED ---")
	get_tree().quit()


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _wait_for_scene(scene_id: StringName, timeout: float = 3.0) -> bool:
	var waited := 0.0
	while NetworkManager._current_scene_id != scene_id and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return NetworkManager._current_scene_id == scene_id
