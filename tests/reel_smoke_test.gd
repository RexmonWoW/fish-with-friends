extends Node

## Headless smoke test for the reel loop closing back to IDLE, i.e. the
## "cast once then stuck forever" bug, plus the hold-then-decide flow: a
## catch is now handed to the player to hold (not auto-dropped in the
## livewell), casting is blocked while holding a fish, and storing it
## actually fills the livewell and hands the rod back.

func _ready() -> void:
	print("--- Reel smoke test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	EventBus.bite_started.connect(func(fish_data, pid): print("bite_started species=%s peer=%d" % [fish_data.species_id, pid]))
	EventBus.reel_finished.connect(func(success, pid): print("reel_finished success=%s peer=%d" % [success, pid]))
	EventBus.cast_landed.connect(func(endpoint, flight, pid): print("cast_landed peer=", pid))

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# Players now land in the lobby first (bare-bones lobby); skip straight
	# to the lake for this test rather than walking into the StartTrigger.
	NetworkManager.request_start_round()
	var scene_waited := 0.0
	while NetworkManager._current_scene_id != &"lake" and scene_waited < 3.0:
		await get_tree().process_frame
		scene_waited += get_process_delta_time()
	if NetworkManager._current_scene_id != &"lake":
		print("FAIL: never reached the lake")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	print("First cast...")
	rod.start_charge()
	await get_tree().create_timer(0.3).timeout
	rod.release_cast()

	# Flight (0.5s) + BITE_DELAY (2.0s) + margin.
	print("Waiting for bite...")
	var waited := 0.0
	while rod.state != Rod.CastState.REELING and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()

	print("Rod state once bite fires: ", rod.state)
	if rod.state != Rod.CastState.REELING:
		print("FAIL: never entered REELING")
		get_tree().quit(1)
		return

	# Force the reel minigame to a win without needing to play it skillfully --
	# this test is about the state machine, not player skill.
	var reel := get_tree().root.get_node("GameRoot/UILayer/ReelMinigame")
	reel._progress = 1.0
	await get_tree().process_frame

	print("Rod state after forced catch: ", rod.state)
	if rod.state != Rod.CastState.IDLE:
		print("FAIL: rod did not return to IDLE after reel resolved")
		get_tree().quit(1)
		return

	if not player.equipment_slot.has_fish_held():
		print("FAIL: catch didn't hand the fish to the player to hold")
		get_tree().quit(1)
		return
	var held: CaughtFish = player.equipment_slot.get_held_fish()
	print("Holding a catch: species=%s size=%.2f value=%d" % [
		held.species.species_id, held.size, held.final_value
	])

	var livewell: Livewell = get_tree().get_first_node_in_group("livewell")
	if livewell.slots.count(null) != Livewell.MAX_SLOTS:
		print("FAIL: catch landed straight in the livewell instead of being held")
		get_tree().quit(1)
		return

	print("Trying to cast while holding a fish (should be blocked)...")
	rod.start_charge()
	if rod.state != Rod.CastState.IDLE:
		print("FAIL: could still cast while holding a fish (state=%s)" % rod.state)
		get_tree().quit(1)
		return
	print("Cast correctly blocked while holding a fish.")

	print("Storing the held fish...")
	player.equipment_slot.request_store_held_fish(0)
	await get_tree().process_frame

	if player.equipment_slot.has_fish_held():
		print("FAIL: still holding a fish after storing it")
		get_tree().quit(1)
		return

	var caught: CaughtFish = livewell.slots[0]
	if caught == null:
		print("FAIL: no fish landed in the livewell after storing")
		get_tree().quit(1)
		return
	print("Livewell slot filled: species=%s size=%.2f value=%d" % [
		caught.species.species_id, caught.size, caught.final_value
	])

	var slot_marker := livewell.fish_display.get_child(0)
	if slot_marker.get_child_count() == 0:
		print("FAIL: no visual spawned under slot marker 0")
		get_tree().quit(1)
		return
	print("Visual spawned under slot 0: %s" % slot_marker.get_child(0))

	print("Second cast (rod should be back in hand after storing)...")
	rod.start_charge()
	await get_tree().process_frame
	print("Rod state after second start_charge: ", rod.state)
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: second cast did not start charging -- still stuck")
		get_tree().quit(1)
		return

	print("--- Reel smoke test PASSED ---")
	get_tree().quit()
