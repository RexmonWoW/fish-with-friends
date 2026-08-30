extends Node

## Headless check: a catch is sold and banked at the end of EVERY round,
## not just at day's end (2026-08-30 direction -- "heading back to shore"
## between rounds). Confirms round 1's catch sells immediately (money
## banked, livewell empty going into round 2, round_sold fires with the
## right numbers) and that the day summary still only evaluates the quota
## once both rounds are in.

var _round_sold_events: Array = []
var _day_summaries: Array = []


func _ready() -> void:
	print("--- Round sale test ---")

	RunState.round_sold.connect(func(r, d, earned, total): _round_sold_events.append([r, d, earned, total]))
	RunState.day_summary.connect(func(d, earned, total, quota, passed): _day_summaries.append([d, earned, total, quota, passed]))

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

	var livewell := get_tree().get_first_node_in_group("livewell") as Livewell
	var fish := CaughtFish.new()
	fish.species = load("res://data/fish/species/catfish.tres")
	fish.size = 12.0
	fish.final_value = 77
	livewell.add_fish(fish)
	await get_tree().process_frame

	RunState._time_remaining = 0.01
	await _wait_frames(5)

	if _round_sold_events.is_empty():
		print("FAIL: round_sold never fired at the end of round 1")
		get_tree().quit(1)
		return
	var sale: Array = _round_sold_events[0]
	print("Round sold: round=%s day=%s earned=%s total=%s" % sale)
	if sale[2] != 77 or sale[3] != 77:
		print("FAIL: round 1's catch should have sold for 77 and banked immediately (got earned=%s total=%s)" % [sale[2], sale[3]])
		get_tree().quit(1)
		return
	if RunState.total_money_earned != 77:
		print("FAIL: total_money_earned should already be 77 right after round 1, not deferred to day end (got %d)" % RunState.total_money_earned)
		get_tree().quit(1)
		return
	if not _day_summaries.is_empty():
		print("FAIL: day_summary shouldn't fire yet -- only round 1 of 2 has ended")
		get_tree().quit(1)
		return
	print("Round 1's catch sold and banked immediately; no day summary yet (correct).")

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

	var livewell_r2 := get_tree().get_first_node_in_group("livewell") as Livewell
	if livewell_r2.slots[0] != null:
		print("FAIL: round 2's livewell should start empty -- round 1's catch was already sold, not carried over")
		get_tree().quit(1)
		return
	print("Round 2's livewell starts empty (round 1's catch was sold, not carried over).")

	RunState.current_quota = 0  # guarantee a pass regardless of round 2's catch
	RunState._time_remaining = 0.01
	await _wait_frames(5)

	if _day_summaries.is_empty():
		print("FAIL: day_summary never fired at the end of round 2")
		get_tree().quit(1)
		return
	var summary: Array = _day_summaries[0]
	print("Day summary: day=%s earned=%s total=%s quota=%s passed=%s" % summary)
	if summary[1] != 77:
		print("FAIL: day summary's 'earned' should sum BOTH rounds' sales (round 1's 77 + round 2's 0), got %s" % summary[1])
		get_tree().quit(1)
		return
	if summary[2] != 77:
		print("FAIL: day summary's running total should still include round 1's 77, got %s" % summary[2])
		get_tree().quit(1)
		return

	print("--- Round sale test PASSED ---")
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
