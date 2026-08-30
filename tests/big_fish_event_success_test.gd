extends Node

## Headless check for the Big Fish Event's happy path (GDD item 9): a cast
## landing on the ready-check spot joins instead of becoming a normal bite,
## holding raises the bar, answered QTEs don't cost anything, reaching and
## holding the soft-max band locks in, and with the only participant locked
## in the event resolves as a success -- big fish lands in the reserved
## slot with the 3x value multiplier, rod's back to normal.
##
## Bypasses the once-per-day final-stretch trigger (_start_ready_check()
## called directly) same as other tests reach into host-internal state for
## determinism.

## Members, not locals -- GDScript lambdas capture local variables BY
## VALUE, so a lambda assigning to a local flag would silently mutate its
## own captured copy, not these (bit tests a few times already this
## session). Plain instance properties instead.
var _ready_check_started: bool = false
var _joined: bool = false
var _event_active: bool = false
var _resolved_success: Variant = null


func _ready() -> void:
	print("--- Big Fish Event success test ---")

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
	await get_tree().process_frame

	var mgr := get_tree().get_first_node_in_group("big_fish_event_manager")
	var bite_mgr := get_tree().get_first_node_in_group("bite_event_manager")
	var livewell := get_tree().get_first_node_in_group("livewell") as Livewell
	var rod: Rod = player.equipment_slot.equipped_item as Rod

	EventBus.big_fish_ready_check_started.connect(func(_s, _d): _ready_check_started = true)
	EventBus.big_fish_participant_joined.connect(func(_pid): _joined = true)
	EventBus.big_fish_event_active.connect(func(_ids, _d): _event_active = true)
	EventBus.big_fish_event_resolved.connect(func(success): _resolved_success = success)

	mgr._start_ready_check()
	if not _ready_check_started or mgr._phase != mgr.Phase.READY_CHECK:
		print("FAIL: ready check didn't start")
		get_tree().quit(1)
		return
	print("Ready check started, target spot: ", mgr._target_spot)

	# Playtest report: the disturbance could land under the boat.
	var dist_from_boat: float = mgr._target_spot.distance_to(mgr._center)
	if dist_from_boat < mgr._boat_clearance:
		print("FAIL: target spot is only %.1f from center, inside the boat's %.1f clearance" %
			[dist_from_boat, mgr._boat_clearance])
		get_tree().quit(1)
		return
	print("Target spot is %.1f from center, clear of the boat (clearance=%.1f)." % [dist_from_boat, mgr._boat_clearance])

	await get_tree().process_frame
	var markers := get_tree().get_nodes_in_group("big_fish_disturbance_marker")
	if markers.is_empty():
		print("FAIL: no world marker spawned at the ready-check spot -- players have nothing to actually see")
		get_tree().quit(1)
		return
	# Loose tolerance, not is_equal_approx's tight default -- _target_spot
	# travels through an actual RPC (even for this call_local host case),
	# which round-trips Vector3s through float32 network encoding.
	if (markers[0] as Node3D).global_position.distance_to(mgr._target_spot) > 0.01:
		print("FAIL: marker isn't positioned at the actual target spot")
		get_tree().quit(1)
		return
	print("World marker spawned at the target spot.")

	# A cast landing right on the spot should join instead of scheduling a
	# normal bite.
	rod._cast_landed(mgr._target_spot, 0.5)
	await get_tree().process_frame

	if not _joined or not mgr._participants.has(1):
		print("FAIL: cast on the spot didn't register as joining")
		get_tree().quit(1)
		return
	if rod.state != Rod.CastState.BIG_FISH_EVENT:
		print("FAIL: rod didn't transition to BIG_FISH_EVENT state (state=%s)" % rod.state)
		get_tree().quit(1)
		return
	if bite_mgr._pending.has(1):
		print("FAIL: a normal bite got scheduled anyway -- should have been swallowed by the join")
		get_tree().quit(1)
		return
	print("Joined the event; no normal bite scheduled; rod in BIG_FISH_EVENT state.")

	# Close the ready check.
	mgr._phase_timer = 0.01
	mgr._process(0.02)
	if not _event_active or mgr._phase != mgr.Phase.ACTIVE:
		print("FAIL: event never went active after the ready check closed")
		get_tree().quit(1)
		return
	print("Event active with 1 participant.")

	await get_tree().process_frame  # queue_free() is deferred, not immediate
	if not get_tree().get_nodes_in_group("big_fish_disturbance_marker").is_empty():
		print("FAIL: world marker should be cleared once the event goes active")
		get_tree().quit(1)
		return
	print("World marker cleared once active.")

	# Simulate holding + correctly answering every QTE for up to ~30s of
	# simulated time -- should be plenty to reach and hold the soft-max band.
	var minigame_ui := get_tree().root.get_node("GameRoot/UILayer/BigFishEventMinigame")
	var checked_qte_label := false
	mgr._request_report_holding(true)
	var simulated := 0.0
	while mgr._phase == mgr.Phase.ACTIVE and simulated < 30.0:
		mgr._update_active(0.1)
		simulated += 0.1
		var p: Dictionary = mgr._participants.get(1, {})
		if p.get("qte_active", false):
			# Was hardcoded to always show "!" -- players had no way to know
			# which key to press. Confirm it shows the actual required key.
			if not checked_qte_label:
				checked_qte_label = true
				var nodes: Dictionary = minigame_ui._bar_nodes.get(1, {})
				var qte_label: Label = nodes.get("qte_label")
				var expected: String = minigame_ui.QTE_PROMPTS[p["qte_prompt"]]["label"]
				if qte_label == null or qte_label.text != expected:
					print("FAIL: QTE label shows '%s', expected the actual required key '%s'" %
						[qte_label.text if qte_label else "<null>", expected])
					get_tree().quit(1)
					return
				print("QTE label correctly shows the required key: '%s'" % expected)
			mgr._request_report_qte_hit()

	if _resolved_success != true:
		print("FAIL: event never resolved as a success (resolved_success=%s, phase=%s)" % [_resolved_success, mgr._phase])
		get_tree().quit(1)
		return
	print("Event resolved as a success after %.1fs simulated." % simulated)

	if rod.state != Rod.CastState.IDLE:
		print("FAIL: rod didn't return to IDLE after the event resolved (state=%s)" % rod.state)
		get_tree().quit(1)
		return
	if livewell.big_fish_slot == null:
		print("FAIL: no fish landed in the reserved big-fish slot")
		get_tree().quit(1)
		return

	var big_fish: CaughtFish = livewell.big_fish_slot
	print("Big fish caught: species=%s value=%d (was_big_fish_event=%s)" %
		[big_fish.species.species_id, big_fish.final_value, big_fish.was_big_fish_event])
	if not big_fish.was_big_fish_event:
		print("FAIL: big fish catch not flagged was_big_fish_event -- 3x multiplier wouldn't apply")
		get_tree().quit(1)
		return

	# Confirm rod actually works again (fully released from the event).
	rod.start_charge()
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: couldn't cast again after the event resolved (state=%s)" % rod.state)
		get_tree().quit(1)
		return

	print("--- Big Fish Event success test PASSED ---")
	get_tree().quit()


func _wait_for_scene(scene_id: StringName, timeout: float = 3.0) -> bool:
	var waited := 0.0
	while NetworkManager._current_scene_id != scene_id and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return NetworkManager._current_scene_id == scene_id
