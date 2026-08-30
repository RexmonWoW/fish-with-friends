extends Node

## Headless check for the new one-step "swap into a full slot" flow, added
## by request on top of the existing grab-then-store two-step: pressing a
## number while holding a fish over an OCCUPIED slot replaces that slot's
## fish with the held one, handing the old fish back to the player -- one
## action instead of grab (empty hands first) then store.

func _ready() -> void:
	print("--- Held-fish swap test ---")

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

	var livewell: Livewell = get_tree().get_first_node_in_group("livewell")
	var sunfish: FishData = load("res://data/fish/species/sunfish.tres")
	var slot: EquipmentSlot = player.equipment_slot
	var original_rod: Rod = slot.equipped_item as Rod

	var old_fish := CaughtFish.new()
	old_fish.species = sunfish
	old_fish.size = 5.0
	old_fish.final_value = 5  # "a bad fish"
	livewell.add_fish(old_fish)
	await get_tree().process_frame

	var untouched_fish := CaughtFish.new()
	untouched_fish.species = sunfish
	untouched_fish.size = 5.0
	untouched_fish.final_value = 1
	livewell.add_fish(untouched_fish)
	await get_tree().process_frame

	var new_fish := CaughtFish.new()
	new_fish.species = sunfish
	new_fish.size = 12.0
	new_fish.final_value = 500  # "a great catch"
	slot._receive_caught_fish(new_fish)
	await get_tree().process_frame

	if not slot.has_fish_held():
		print("FAIL: test setup problem -- not holding the new catch")
		get_tree().quit(1)
		return

	slot.request_swap_into_livewell(0)
	await get_tree().process_frame

	if livewell.slots[0] != new_fish:
		print("FAIL: slot 0 doesn't hold the new fish after swapping (got %s)" % livewell.slots[0])
		get_tree().quit(1)
		return
	print("Slot 0 now holds the new fish.")

	if slot.get_held_fish() != old_fish:
		print("FAIL: didn't get the old fish back in hand (got %s)" % slot.get_held_fish())
		get_tree().quit(1)
		return
	print("Old fish came back into hand -- not discarded.")

	if livewell.slots[1] != untouched_fish:
		print("FAIL: an unrelated slot got disturbed by the swap")
		get_tree().quit(1)
		return
	print("Other slots untouched.")

	# Swapping onto an EMPTY slot shouldn't do anything (nothing to swap
	# OUT of) -- that's what E/store is for.
	livewell.remove_fish(1)
	await get_tree().process_frame
	slot.request_swap_into_livewell(1)
	await get_tree().process_frame
	if slot.get_held_fish() != old_fish:
		print("FAIL: swap onto an empty slot changed what's held")
		get_tree().quit(1)
		return
	if livewell.slots[1] != null:
		print("FAIL: swap onto an empty slot shouldn't have put anything there")
		get_tree().quit(1)
		return
	print("Swapping onto an empty slot correctly did nothing.")

	# The rod must survive the swap correctly too -- equip_fish() is called
	# a SECOND time here (once for the original catch, once for the old
	# fish handed back by the swap) while a rod, not a fish, was the first
	# thing ever unequipped; a naive unequip_rod()-every-time would instead
	# stow the fish visual itself and clobber the tracked rod reference.
	slot.request_toss_held_fish()
	await get_tree().process_frame
	if slot.equipped_item != original_rod:
		print("FAIL: rod didn't come back correctly after the swap -- got %s, expected the original rod %s" %
			[slot.equipped_item, original_rod])
		get_tree().quit(1)
		return
	print("Original rod correctly back in hand after tossing.")

	print("--- Held-fish swap test PASSED ---")
	get_tree().quit()


func _wait_for_scene(scene_id: StringName, timeout: float = 3.0) -> bool:
	var waited := 0.0
	while NetworkManager._current_scene_id != scene_id and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return NetworkManager._current_scene_id == scene_id
