extends Node

## Headless check for the debug console's RunState hooks (skip_round,
## set_time, skip_day) -- added so playtesting the Big Fish Event (only
## triggers in the last ~90s of the day's second round) and other
## day-boundary logic doesn't mean sitting through most of two 5-min
## rounds per attempt. Also covers set_time actually syncing RoundHud's
## displayed countdown, not just RunState's internal timer.
##
## Quota is forced to 0 before each skip_day so day-pass/fail (irrelevant
## to what's being tested here) doesn't gate whether the day actually
## advances -- a real playtest would have real catches instead.

var _day_summaries: Array = []


func _ready() -> void:
	print("--- Debug console test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(_player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	RunState.day_summary.connect(func(d, earned, total, quota, passed): _day_summaries.append(
		{"day": d, "earned": earned, "total": total, "quota": quota, "passed": passed}
	))

	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for round 1")
		get_tree().quit(1)
		return
	await get_tree().process_frame

	# set_time: jumps the clock without ending the round, AND the displayed
	# countdown (RoundHud keeps its own locally-ticking copy, not a live
	# read of RunState._time_remaining) needs to actually reflect the jump.
	var round_hud := get_tree().root.get_node("GameRoot/UILayer/RoundHud")
	RunState.debug_set_time_remaining(42.0)
	await get_tree().process_frame
	# Both timers keep actively ticking down (real gameplay, not paused), so
	# allow a bit of drift from the extra frame(s) waited above -- the point
	# is confirming they're near 42s, not that they're frozen there.
	if absf(RunState._time_remaining - 42.0) > 0.5:
		print("FAIL: set_time didn't set _time_remaining (got %.2f)" % RunState._time_remaining)
		get_tree().quit(1)
		return
	var hud_time: float = round_hud.get("_time_remaining")
	if absf(hud_time - 42.0) > 0.5:
		print("FAIL: set_time didn't sync RoundHud's displayed countdown (got %.2f)" % hud_time)
		get_tree().quit(1)
		return
	print("set_time jumped the clock to 42s, and the HUD countdown reflects it.")

	# skip_round: ends round 1 immediately, same transition a real timeout
	# would trigger (round 1 -> round 2, same day).
	RunState.debug_skip_round()
	await _wait_frames(5)
	if not await _wait_for_scene(&"lobby"):
		print("FAIL: skip_round never ended round 1")
		get_tree().quit(1)
		return
	print("skip_round ended round 1.")

	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for round 2")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	if RunState.round_number != RunState.ROUNDS_PER_DAY:
		print("FAIL: test setup problem -- expected round 2")
		get_tree().quit(1)
		return

	# skip_day, called from the day's final round: ends it immediately and
	# produces a day summary (quota forced to 0 so it's a guaranteed pass,
	# unrelated to what's actually being tested here).
	RunState.current_quota = 0
	RunState.debug_skip_day()
	await _wait_frames(10)
	if _day_summaries.size() != 1 or not _day_summaries[0]["passed"]:
		print("FAIL: skip_day from round 2 didn't produce a passing day summary (%s)" % [_day_summaries])
		get_tree().quit(1)
		return
	print("skip_day from round 2 produced a day summary: ", _day_summaries[0])

	if not await _wait_for_scene(&"lobby"):
		print("FAIL: never returned to the lobby after day 1's summary")
		get_tree().quit(1)
		return

	# Full case: skip_day called from round 1 should walk itself through
	# round 2 automatically (not just end round 1 and stop) and still land
	# on a day summary.
	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for day 2 round 1")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	if RunState.round_number != 1:
		print("FAIL: test setup problem -- expected day 2 round 1")
		get_tree().quit(1)
		return

	RunState.current_quota = 0
	RunState.debug_skip_day()
	# Give the round1->round2 auto-continue (round_ended -> timer -> request_start_round
	# -> round_started -> timer -> skip round 2) plenty of frames to play out.
	var got_second_summary := false
	for i in range(120):
		await get_tree().process_frame
		if _day_summaries.size() >= 2:
			got_second_summary = true
			break
	if not got_second_summary:
		print("FAIL: skip_day from round 1 never made it through round 2 to a day summary")
		get_tree().quit(1)
		return
	print("skip_day from round 1 auto-continued through round 2 to a day summary: ", _day_summaries[1])

	print("--- Debug console test PASSED ---")
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
