extends Node

## Headless check: quota progress should reflect fish sitting unsold in the
## livewell, not just RunState.total_money_earned (which only changes at day
## boundaries) -- otherwise the HUD sits flat all day and progress toward
## quota is invisible until it jumps at day end. Covers RunState.
## get_livewell_value()/get_projected_total() and confirms RoundHud's money
## label actually reflects it.

func _ready() -> void:
	print("--- Livewell quota-progress test ---")

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

	if RunState.get_livewell_value() != 0:
		print("FAIL: livewell value should start at 0, got %d" % RunState.get_livewell_value())
		get_tree().quit(1)
		return
	if RunState.total_money_earned != 0:
		print("FAIL: total_money_earned should start at 0, got %d" % RunState.total_money_earned)
		get_tree().quit(1)
		return

	var livewell := get_tree().get_first_node_in_group("livewell") as Livewell
	var fish := CaughtFish.new()
	fish.species = load("res://data/fish/species/sunfish.tres")
	fish.size = 5.0
	fish.final_value = 42
	livewell.add_fish(fish)
	await get_tree().process_frame

	if RunState.get_livewell_value() != 42:
		print("FAIL: livewell value should be 42 after one catch, got %d" % RunState.get_livewell_value())
		get_tree().quit(1)
		return
	if RunState.get_projected_total() != 42:
		print("FAIL: projected total should be 42 (0 banked + 42 unsold), got %d" % RunState.get_projected_total())
		get_tree().quit(1)
		return
	if RunState.total_money_earned != 0:
		print("FAIL: total_money_earned shouldn't change just from a catch sitting in the livewell (still %d expected 0, got %d)" % [0, RunState.total_money_earned])
		get_tree().quit(1)
		return
	print("Livewell value / projected total correctly reflect the unsold catch (42).")

	var round_hud := get_tree().root.get_node("GameRoot/UILayer/RoundHud")
	var money_label: Label = round_hud.get("_money_label")
	if money_label == null or not ("42" in money_label.text):
		print("FAIL: RoundHud's money label doesn't reflect the unsold catch: '%s'" % (money_label.text if money_label else "<null>"))
		get_tree().quit(1)
		return
	print("RoundHud money label: '%s'" % money_label.text)

	# Throwing it overboard should drop the projection back to 0.
	livewell.request_remove_fish(0)
	await get_tree().process_frame

	if RunState.get_livewell_value() != 0:
		print("FAIL: livewell value should be back to 0 after throwing the fish overboard, got %d" % RunState.get_livewell_value())
		get_tree().quit(1)
		return

	print("--- Livewell quota-progress test PASSED ---")
	get_tree().quit()
