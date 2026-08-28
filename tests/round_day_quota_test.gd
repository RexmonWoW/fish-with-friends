extends Node

## Headless check: RunState's round timer -> lobby return -> day/quota
## evaluation loop (GDD item 12/13). Pokes RunState._time_remaining directly
## rather than waiting out real 5-minute rounds, same as other tests reach
## into internals for speed (e.g. TangleManager._apply_mash).
##
## Covers: round 1 ending returns to the lobby without touching money/quota;
## a real livewell catch gets sold at end of day 1 and the day passes when
## the (lowered, for the test) quota is met; day 2's auto-escalated quota
## then fails with no new catches, ending the run.

var _round_ended_events: Array = []
var _day_summaries: Array = []
var _run_over_events: Array = []


func _ready() -> void:
	print("--- Round/day/quota test ---")

	RunState.round_ended.connect(func(r, d): _round_ended_events.append([r, d]))
	RunState.day_summary.connect(func(d, earned, total, quota, passed): _day_summaries.append([d, earned, total, quota, passed]))
	RunState.run_over.connect(func(d, money): _run_over_events.append([d, money]))

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

	if RunState.round_number != 1 or RunState.day_number != 1:
		print("FAIL: round/day not 1/1 at round start (got %d/%d)" % [RunState.round_number, RunState.day_number])
		get_tree().quit(1)
		return

	RunState._time_remaining = 0.01
	await _wait_frames(5)

	if _round_ended_events.is_empty():
		print("FAIL: round_ended never fired for round 1")
		get_tree().quit(1)
		return
	if not await _wait_for_scene(&"lobby"):
		print("FAIL: never returned to the lobby after round 1")
		get_tree().quit(1)
		return
	if RunState.round_number != 2:
		print("FAIL: round_number should be 2 after round 1 ends (got %d)" % RunState.round_number)
		get_tree().quit(1)
		return
	print("Round 1 ended correctly, back in lobby, round_number=2")

	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for round 2")
		get_tree().quit(1)
		return

	# Real catch, so selling is exercised for real -- then lower the quota
	# below what this one catch is worth (BASE_QUOTA is tuned for many
	# rounds' worth of fish, not a single test catch).
	var livewell := get_tree().get_first_node_in_group("livewell") as Livewell
	var fish := CaughtFish.new()
	fish.species = load("res://data/fish/species/golden_koi.tres")
	fish.size = 10.0
	fish.final_value = 500
	livewell.add_fish(fish)
	await get_tree().process_frame

	RunState.current_quota = 100  # day 1 should pass with $500 earned

	RunState._time_remaining = 0.01
	await _wait_frames(5)

	if _day_summaries.is_empty():
		print("FAIL: day_summary never fired at end of day 1")
		get_tree().quit(1)
		return
	var summary: Array = _day_summaries[0]
	print("Day summary: day=%s earned=%s total=%s quota=%s passed=%s" % summary)
	if summary[1] != 500:
		print("FAIL: earned should be 500 (the one catch sold), got %s" % summary[1])
		get_tree().quit(1)
		return
	if summary[4] != true:
		print("FAIL: day 1 should have passed (500 earned >= 100 quota)")
		get_tree().quit(1)
		return
	if RunState.day_number != 2 or RunState.round_number != 1:
		print("FAIL: should be day 2 round 1 after passing (got day=%d round=%d)" % [RunState.day_number, RunState.round_number])
		get_tree().quit(1)
		return
	if not await _wait_for_scene(&"lobby"):
		print("FAIL: never returned to the lobby after day 1")
		get_tree().quit(1)
		return
	print("Day 1 passed correctly -- now day 2 round 1, back in lobby, quota auto-escalated to %d" % RunState.current_quota)

	# Day 2: no new catches, and total_money_earned is cumulative (by design,
	# per GDD -- it never resets), so it'd still clear day 2's auto-escalated
	# quota on its own. Force a genuine miss the same way day 1's pass was
	# forced -- override the quota directly, well above the $500 total.
	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for day 2 round 1")
		get_tree().quit(1)
		return
	RunState._time_remaining = 0.01
	await _wait_frames(5)

	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for day 2 round 2")
		get_tree().quit(1)
		return
	RunState.current_quota = 999999
	RunState._time_remaining = 0.01
	await _wait_frames(5)

	if _run_over_events.is_empty():
		print("FAIL: run_over never fired for a missed quota")
		get_tree().quit(1)
		return
	print("Quota miss correctly ended the run: ", _run_over_events[0])

	print("--- Round/day/quota test PASSED ---")
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
