extends Node

## Headless check for the adaptive quota formula (GDD Quota Scaling):
## day 1 = BASE_QUOTA * player-count multiplier; every day after,
## next_quota = round(previous_quota * QUOTA_DAILY_GROWTH + surplus *
## QUOTA_SURPLUS_FACTOR), surplus being how much that day's own
## total_money_earned cleared the day's quota by (quota gets paid out of the
## pot at day end -- only the surplus carries into the next day). Covers a
## bare pass (surplus=0, pure QUOTA_DAILY_GROWTH growth) and a big-surplus
## pass (grows faster) against hand-computed expected values, not just "did
## it move."

func _ready() -> void:
	print("--- Quota formula test ---")

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
		print("FAIL: never reached the lake")
		get_tree().quit(1)
		return

	var expected_day1: int = int(round(float(RunState.BASE_QUOTA) * RunState.PLAYER_COUNT_MULTIPLIER[1]))
	print("Day 1 quota: expected=%d actual=%d" % [expected_day1, RunState.current_quota])
	if RunState.current_quota != expected_day1:
		print("FAIL: day 1 quota doesn't match BASE_QUOTA * 1-player multiplier")
		get_tree().quit(1)
		return

	# ── Bare pass: earn exactly the quota, zero surplus -- pure QUOTA_DAILY_GROWTH growth. ──
	var day1_quota: int = RunState.current_quota
	var livewell := get_tree().get_first_node_in_group("livewell") as Livewell
	var fish := CaughtFish.new()
	fish.species = load("res://data/fish/species/sunfish.tres")
	fish.size = 5.0
	fish.final_value = day1_quota  # exactly meets it, no surplus
	livewell.add_fish(fish)
	await get_tree().process_frame

	RunState._time_remaining = 0.01
	await _wait_frames(5)
	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for round 2")
		get_tree().quit(1)
		return
	RunState._time_remaining = 0.01
	await _wait_frames(5)

	if RunState.day_number != 2:
		print("FAIL: day 1 should have passed (earned exactly the quota)")
		get_tree().quit(1)
		return

	var expected_day2 := int(round(float(day1_quota) * RunState.QUOTA_DAILY_GROWTH))  # surplus=0
	print("Day 2 quota (bare pass, surplus=0): expected=%d actual=%d" % [expected_day2, RunState.current_quota])
	if RunState.current_quota != expected_day2:
		print("FAIL: bare-pass day 2 quota doesn't match previous_quota * QUOTA_DAILY_GROWTH")
		get_tree().quit(1)
		return

	# ── Big-surplus pass: earn well past the quota -- should grow faster. ──
	var day2_quota: int = RunState.current_quota
	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for day 2 round 1")
		get_tree().quit(1)
		return

	# Re-fetch -- the round transition above freed the old Lake (and its
	# Livewell) and loaded a fresh one; the earlier reference is stale.
	livewell = get_tree().get_first_node_in_group("livewell") as Livewell
	var big_fish := CaughtFish.new()
	big_fish.species = load("res://data/fish/species/golden_koi.tres")
	big_fish.size = 10.0
	big_fish.final_value = day2_quota * 3  # well past the quota -- a real surplus
	livewell.add_fish(big_fish)
	await get_tree().process_frame

	RunState._time_remaining = 0.01
	await _wait_frames(5)
	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake for day 2 round 2")
		get_tree().quit(1)
		return
	RunState._time_remaining = 0.01
	await _wait_frames(5)

	if RunState.day_number != 3:
		print("FAIL: day 2 should have passed (earned 3x the quota)")
		get_tree().quit(1)
		return

	# Quota is paid out of the pot at the end of each passed day (see
	# RunState._end_round) -- day 1 exactly met its quota with zero surplus,
	# so nothing carried into day 2. total_money_earned at day 2's own end
	# is just this round's big catch on top of that.
	var total_after_day2: int = 0 + day2_quota * 3
	var surplus := maxi(total_after_day2 - day2_quota, 0)
	var expected_day3 := int(round(float(day2_quota) * RunState.QUOTA_DAILY_GROWTH + float(surplus) * RunState.QUOTA_SURPLUS_FACTOR))
	print("Day 3 quota (big surplus): expected=%d actual=%d" % [expected_day3, RunState.current_quota])
	if RunState.current_quota != expected_day3:
		print("FAIL: surplus-pass day 3 quota doesn't match the adaptive formula")
		get_tree().quit(1)
		return

	if RunState.current_quota <= expected_day2:
		print("FAIL: a big-surplus pass should grow the quota faster than a bare pass did, but it didn't")
		get_tree().quit(1)
		return

	print("--- Quota formula test PASSED ---")
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
