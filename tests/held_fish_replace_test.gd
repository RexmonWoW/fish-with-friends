extends Node

## Headless check for the new "grab, then store" livewell flow (replacing
## the old direct-overwrite): with a full livewell, you can't just swap a
## new catch in over an old one in one step anymore -- you grab the
## unwanted fish out (1-5, only works with empty hands), which frees you to
## toss it (Q) or store it elsewhere, THEN store your new catch (E). "You
## can only hold 1 thing at a time" is enforced throughout: can't grab
## while already holding the new catch, can't store while still holding
## the grabbed-out old one.

func _ready() -> void:
	print("--- Held-fish grab-then-store test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	# GDD Bite Detection: bite_started now waits on a shadow strike + hook-set
	# window -- auto-answer it immediately so this test's cast-and-wait-for-
	# REELING still works the same as before.
	EventBus.bite_hook_window_opened.connect(func(peer_id, _duration):
		if peer_id != 1:
			return
		var bite_manager := get_tree().get_first_node_in_group("bite_event_manager")
		if bite_manager:
			bite_manager.request_hook_set()
	)

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
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

	var livewell: Livewell = get_tree().get_first_node_in_group("livewell")
	var sunfish: FishData = load("res://data/fish/species/sunfish.tres")
	var slot: EquipmentSlot = player.equipment_slot

	# Fill every slot with a cheap placeholder catch.
	var old_fish_in_slot_2: CaughtFish = null
	for i in range(Livewell.MAX_SLOTS):
		var filler := FishFactory.create_caught_fish(
			sunfish, 99, "Filler", &"lake", false, [], [], false
		)
		filler.final_value = 1  # deliberately low-value, "a bad fish"
		livewell.add_fish(filler)
		if i == 2:
			old_fish_in_slot_2 = filler
	if not livewell.is_full():
		print("FAIL: test setup problem -- livewell isn't actually full")
		get_tree().quit(1)
		return

	var rod: Rod = slot.equipped_item as Rod
	rod.start_charge()
	await get_tree().create_timer(0.2).timeout
	rod.release_cast()

	waited = 0.0
	while rod.state != Rod.CastState.REELING and waited < 8.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if rod.state != Rod.CastState.REELING:
		print("FAIL: never reached REELING")
		get_tree().quit(1)
		return

	var reel := get_tree().root.get_node("GameRoot/UILayer/ReelMinigame")
	reel._progress = 1.0
	await get_tree().process_frame

	var new_catch: CaughtFish = slot.get_held_fish()
	if new_catch == null:
		print("FAIL: catch wasn't handed to the player even with the livewell full")
		get_tree().quit(1)
		return
	print("Holding a new catch (value=%d) while the livewell is full." % new_catch.final_value)

	print("Trying to grab slot 2 while already holding the new catch (should fail, hands full)...")
	slot.request_grab_from_livewell(2)
	await get_tree().process_frame
	if slot.get_held_fish() != new_catch:
		print("FAIL: grabbing while hands were full replaced what was held")
		get_tree().quit(1)
		return
	if livewell.slots[2] != old_fish_in_slot_2:
		print("FAIL: slot 2 changed even though the grab should have failed")
		get_tree().quit(1)
		return
	print("Correctly blocked -- can only hold 1 thing at a time.")

	print("Trying to store the new catch while the well is full (should fail, no empty slot)...")
	slot.request_store_held_fish()
	await get_tree().process_frame
	if not slot.has_fish_held():
		print("FAIL: new catch got stored despite the livewell being full")
		get_tree().quit(1)
		return
	print("Correctly blocked -- no empty slot to store into.")

	print("Tossing the new catch to free my hands, then grabbing the old fish out of slot 2...")
	slot.request_toss_held_fish()
	await get_tree().process_frame
	if slot.has_fish_held():
		print("FAIL: still holding something after tossing")
		get_tree().quit(1)
		return

	slot.request_grab_from_livewell(2)
	await get_tree().process_frame
	if slot.get_held_fish() != old_fish_in_slot_2:
		print("FAIL: didn't grab the expected fish out of slot 2")
		get_tree().quit(1)
		return
	if livewell.slots[2] != null:
		print("FAIL: slot 2 still occupied after grabbing its fish out")
		get_tree().quit(1)
		return
	print("Grabbed the old fish out of slot 2 -- it's now empty and I'm holding the old fish.")

	print("Tossing the old (bad) fish -- don't want it...")
	slot.request_toss_held_fish()
	await get_tree().process_frame
	if slot.has_fish_held():
		print("FAIL: still holding the old fish after tossing it")
		get_tree().quit(1)
		return

	# Every OTHER slot should be untouched throughout all of this.
	for i in range(Livewell.MAX_SLOTS):
		if i == 2:
			continue
		if livewell.slots[i] == null or livewell.slots[i].final_value != 1:
			print("FAIL: slot %d was disturbed (should still hold its filler)" % i)
			get_tree().quit(1)
			return

	# Close the loop -- with the slot actually free now, storing a fresh
	# catch should work (direct equip_fish() call, not a real cast/reel,
	# matches how other tests poke host-authoritative state directly).
	print("Storing a fresh catch into the now-empty slot 2...")
	slot.equip_fish(new_catch)
	slot.request_store_held_fish()
	await get_tree().process_frame

	if slot.has_fish_held():
		print("FAIL: still holding the fresh catch after storing it")
		get_tree().quit(1)
		return
	if livewell.slots[2] != new_catch:
		print("FAIL: slot 2 doesn't hold the fresh catch (got %s)" % livewell.slots[2])
		get_tree().quit(1)
		return
	print("Slot 2 now holds the fresh catch -- the full grab-then-store loop works.")

	print("--- Held-fish grab-then-store test PASSED ---")
	get_tree().quit()
