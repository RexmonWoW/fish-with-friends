extends Node

## Headless check: with a full livewell, a held fish can deliberately
## replace a specific existing slot (picked by number, same 1-5 keys as
## throwing overboard) instead of the catch just being discarded -- this is
## the actual point of the hold-then-decide flow (a great catch shouldn't
## just be lost to a full livewell without a choice).

func _ready() -> void:
	print("--- Held-fish replace-when-full test ---")

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

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	rod.start_charge()
	await get_tree().create_timer(0.2).timeout
	rod.release_cast()

	waited = 0.0
	while rod.state != Rod.CastState.REELING and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if rod.state != Rod.CastState.REELING:
		print("FAIL: never reached REELING")
		get_tree().quit(1)
		return

	var reel := get_tree().root.get_node("GameRoot/UILayer/ReelMinigame")
	reel._progress = 1.0
	await get_tree().process_frame

	var held: CaughtFish = player.equipment_slot.get_held_fish()
	if held == null:
		print("FAIL: catch wasn't handed to the player even with the livewell full")
		get_tree().quit(1)
		return
	print("Holding a new catch (value=%d) while the livewell is full." % held.final_value)

	print("Swapping it into slot 3 (index 2), replacing the low-value filler there...")
	player.equipment_slot.request_store_held_fish(2)
	await get_tree().process_frame

	if player.equipment_slot.has_fish_held():
		print("FAIL: still holding the fish after swapping it in")
		get_tree().quit(1)
		return

	var now_in_slot_2: CaughtFish = livewell.slots[2]
	if now_in_slot_2 == null:
		print("FAIL: slot 2 is empty after the swap")
		get_tree().quit(1)
		return
	if now_in_slot_2 == old_fish_in_slot_2:
		print("FAIL: slot 2 still holds the old filler fish, swap didn't happen")
		get_tree().quit(1)
		return
	if now_in_slot_2 != held:
		print("FAIL: slot 2 doesn't hold the fish that was just held")
		get_tree().quit(1)
		return
	print("Slot 2 now holds the new catch (value=%d), old filler is gone." % now_in_slot_2.final_value)

	# Every other slot should be untouched.
	for i in range(Livewell.MAX_SLOTS):
		if i == 2:
			continue
		if livewell.slots[i] == null or livewell.slots[i].final_value != 1:
			print("FAIL: slot %d was disturbed by the swap (should still hold its filler)" % i)
			get_tree().quit(1)
			return

	var rod_after: Rod = player.equipment_slot.equipped_item as Rod
	if rod_after == null or rod_after.state != Rod.CastState.IDLE:
		print("FAIL: rod wasn't properly re-equipped after the swap")
		get_tree().quit(1)
		return

	print("--- Held-fish replace-when-full test PASSED ---")
	get_tree().quit()
