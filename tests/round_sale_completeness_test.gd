extends Node

## Headless check: round-end selling actually sells EVERYTHING, not just
## the 5 normal livewell slots -- playtest report: "it seems to just sell
## 2, its supposed to sell all." Found two real gaps: the reserved Big Fish
## Event slot was never included in the sale at all (sat there forever),
## and a fish still HELD (caught but never stored with E) just silently
## carried forward into the next round instead of selling.

func _ready() -> void:
	print("--- Round sale completeness test ---")

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
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake")
		get_tree().quit(1)
		return
	await get_tree().process_frame

	var livewell := get_tree().get_first_node_in_group("livewell") as Livewell
	var sunfish: FishData = load("res://data/fish/species/sunfish.tres")

	# A normal fish in a regular slot.
	var normal_fish := CaughtFish.new()
	normal_fish.species = sunfish
	normal_fish.size = 5.0
	normal_fish.final_value = 30
	livewell.add_fish(normal_fish)

	# A big fish in the reserved slot.
	var big_fish := CaughtFish.new()
	big_fish.species = sunfish
	big_fish.size = 20.0
	big_fish.final_value = 300
	livewell.add_big_fish(big_fish)

	# A fish caught but never stored -- still in the player's hands.
	var held_fish := CaughtFish.new()
	held_fish.species = sunfish
	held_fish.size = 8.0
	held_fish.final_value = 15
	player.equipment_slot._receive_caught_fish(held_fish)
	await get_tree().process_frame

	if not player.equipment_slot.has_fish_held():
		print("FAIL: test setup problem -- fish isn't actually held")
		get_tree().quit(1)
		return

	RunState._time_remaining = 0.01
	await _wait_frames(5)

	# Round 1 < ROUNDS_PER_DAY, so this was a round_sold, not a day_summary
	# -- check the banked total directly instead.
	var expected := 30 + 300 + 15
	if RunState.total_money_earned != expected:
		print("FAIL: expected everything (normal + big fish + held) to sell for %d, got %d" %
			[expected, RunState.total_money_earned])
		get_tree().quit(1)
		return
	print("Sold normal slot (30) + big fish slot (300) + held fish (15) = %d." % RunState.total_money_earned)

	# Round 1 ending returns to the lobby, freeing the old Livewell node --
	# the money total already proves the big fish slot sold; just confirm
	# the held-fish state, which lives on the (still-alive) Player node.
	if player.equipment_slot.has_fish_held():
		print("FAIL: player should no longer be holding a fish after round-end selling")
		get_tree().quit(1)
		return
	print("Big fish slot and held fish both cleared after the sale.")

	print("--- Round sale completeness test PASSED ---")
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
