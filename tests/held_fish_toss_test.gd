extends Node

## Headless check: a held fish can be tossed back (released, no reward) via
## the "cast" input from anywhere -- doesn't need to be near a livewell --
## and the rod comes back to hand afterward, exactly the same rod instance
## (not a fresh one) since it was only ever stowed, not freed.

func _ready() -> void:
	print("--- Held-fish toss test ---")

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

	var original_rod: Rod = player.equipment_slot.equipped_item as Rod

	original_rod.start_charge()
	await get_tree().create_timer(0.2).timeout
	original_rod.release_cast()

	waited = 0.0
	while original_rod.state != Rod.CastState.REELING and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if original_rod.state != Rod.CastState.REELING:
		print("FAIL: never reached REELING")
		get_tree().quit(1)
		return

	var reel := get_tree().root.get_node("GameRoot/UILayer/ReelMinigame")
	reel._progress = 1.0
	await get_tree().process_frame

	if not player.equipment_slot.has_fish_held():
		print("FAIL: test setup problem -- catch wasn't handed to the player")
		get_tree().quit(1)
		return
	print("Holding a fish, now tossing it back (should work from anywhere, no livewell needed)...")

	# Same convention as other tests exercising an input-gated action (e.g.
	# Rod.start_charge()/release_cast() called directly rather than
	# synthesizing hardware events) -- calls the same request the "cast"
	# input in EquipmentSlot._process() would trigger.
	player.equipment_slot.request_toss_held_fish()
	await get_tree().process_frame
	await get_tree().process_frame

	if player.equipment_slot.has_fish_held():
		print("FAIL: still holding the fish after tossing it back")
		get_tree().quit(1)
		return

	var livewell: Livewell = get_tree().get_first_node_in_group("livewell")
	if livewell.slots.count(null) != Livewell.MAX_SLOTS:
		print("FAIL: tossed fish ended up in the livewell instead of just being released")
		get_tree().quit(1)
		return
	print("Livewell untouched by the toss, as expected.")

	var rod_after: Rod = player.equipment_slot.equipped_item as Rod
	if rod_after == null:
		print("FAIL: rod wasn't re-equipped after tossing the fish")
		get_tree().quit(1)
		return
	if rod_after != original_rod:
		print("FAIL: re-equipped rod is a different instance -- should be the same stowed one")
		get_tree().quit(1)
		return
	if not rod_after.is_equipped:
		print("FAIL: re-equipped rod still thinks it's stowed")
		get_tree().quit(1)
		return

	rod_after.start_charge()
	if rod_after.state != Rod.CastState.CHARGING:
		print("FAIL: rod doesn't work again after being re-equipped (state=%s)" % rod_after.state)
		get_tree().quit(1)
		return

	print("--- Held-fish toss test PASSED ---")
	get_tree().quit()
