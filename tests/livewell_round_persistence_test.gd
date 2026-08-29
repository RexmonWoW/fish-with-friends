extends Node

## Headless check: a catch from round 1 must survive into round 2 of the
## same day. NetworkManager reloads the whole Lake scene (Livewell
## included) on every round transition, same as any other map swap -- found
## while writing quota_formula_test.gd that nothing was preserving the
## Livewell's contents across that reload, silently wiping any round-1
## catch the instant round 2 started. Confirms both that the fish survives
## and that the visual respawns under the new Livewell's slot marker too.

func _ready() -> void:
	print("--- Livewell round-persistence test ---")

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

	if livewell.slots[0] != fish:
		print("FAIL: test setup problem -- fish didn't land in slot 0")
		get_tree().quit(1)
		return
	print("Caught a fish in round 1 (value=77).")

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

	# Fresh Livewell instance (new Lake scene) -- re-fetch, don't reuse the
	# old (now-freed) reference.
	var livewell_r2 := get_tree().get_first_node_in_group("livewell") as Livewell
	if livewell_r2 == livewell:
		print("FAIL: test setup problem -- Livewell wasn't actually reloaded, this test proves nothing")
		get_tree().quit(1)
		return

	print("Round 2 Livewell slot 0: ", livewell_r2.slots[0])
	if livewell_r2.slots[0] == null:
		print("FAIL: round 1's catch was wiped when round 2 loaded")
		get_tree().quit(1)
		return
	if livewell_r2.slots[0].final_value != 77:
		print("FAIL: round 2's livewell has a fish, but it's not the one from round 1")
		get_tree().quit(1)
		return

	var slot_marker := livewell_r2.fish_display.get_child(0)
	if slot_marker.get_child_count() == 0:
		print("FAIL: restored fish has no visual under its slot marker")
		get_tree().quit(1)
		return

	print("--- Livewell round-persistence test PASSED ---")
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
