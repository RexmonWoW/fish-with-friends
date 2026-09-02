extends Node

## Headless check for the Big Fish Event's other outcomes:
## - Fizzle: nobody casts in before the ready check closes -- back to
##   inactive, no penalty.
## - Join radius: a cast too far from the target spot doesn't join, and a
##   normal bite still fires for it (the event shouldn't swallow every
##   cast during a ready check, only ones actually near the spot).
## - Fail: timeout with a participant not locked in -- costs the crew
##   their 2 biggest (by value) livewell fish and triggers a real capsize.

## Members, not locals -- see big_fish_event_success_test.gd's comment on
## why (GDScript lambdas capture locals by value).
var _fizzled: bool = false
var _resolved_success: Variant = null
var _capsize_started: bool = false


func _ready() -> void:
	print("--- Big Fish Event fail/fizzle/radius test ---")

	EventBus.big_fish_event_fizzled.connect(func(): _fizzled = true)
	EventBus.big_fish_event_resolved.connect(func(success): _resolved_success = success)
	EventBus.capsize_started.connect(func(_required): _capsize_started = true)

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

	# ── Fizzle: nobody joins. ──
	mgr._start_ready_check()
	mgr._phase_timer = 0.01
	mgr._process(0.02)

	if not _fizzled or mgr._phase != mgr.Phase.INACTIVE:
		print("FAIL: an unjoined ready check should have fizzled")
		get_tree().quit(1)
		return
	print("Fizzled correctly with no participants.")

	# ── Join radius: a cast far from the spot shouldn't join. ──
	mgr._start_ready_check()
	var far_point: Vector3 = mgr._target_spot + Vector3(50.0, 0.0, 0.0)
	rod._cast_landed(far_point, 0.5, false)
	await get_tree().process_frame

	if mgr._participants.has(1):
		print("FAIL: a cast 50 units from the spot registered as joining")
		get_tree().quit(1)
		return
	if not bite_mgr._pending.has(1):
		print("FAIL: a cast outside the join radius should still schedule a normal bite")
		get_tree().quit(1)
		return
	print("Out-of-radius cast correctly ignored by the event, normal bite still scheduled.")

	# Clean up that pending normal bite and the ready check before the fail scenario.
	bite_mgr.cancel_pending_bite(1)
	mgr._phase_timer = 0.01
	mgr._process(0.02)

	# ── Fail: join, don't lock in, let the timer run out. ──
	# Stock the livewell with fish of varying value first.
	var sunfish: FishData = load("res://data/fish/species/sunfish.tres")
	var values := [10, 999, 500, 20, 5]  # slot 1 and slot 2 are the 2 biggest
	for v in values:
		var filler := CaughtFish.new()
		filler.species = sunfish
		filler.size = 5.0
		filler.final_value = v
		livewell.add_fish(filler)
	await get_tree().process_frame

	mgr._start_ready_check()
	rod._cast_landed(mgr._target_spot, 0.5, false)
	await get_tree().process_frame
	if not mgr._participants.has(1):
		print("FAIL: test setup problem -- didn't join for the fail scenario")
		get_tree().quit(1)
		return

	mgr._phase_timer = 0.01
	mgr._process(0.02)  # closes the ready check, goes ACTIVE
	if mgr._phase != mgr.Phase.ACTIVE:
		print("FAIL: test setup problem -- event never went active")
		get_tree().quit(1)
		return

	# Never hold -- let the event timer run out with the bar still at 0.
	mgr._phase_timer = 0.01
	mgr._update_active(0.02)

	if mgr._phase != mgr.Phase.INACTIVE:
		print("FAIL: event should have resolved (failed) once the timer ran out")
		get_tree().quit(1)
		return
	if _resolved_success != false:
		print("FAIL: big_fish_event_resolved should have fired with success=false (got %s)" % _resolved_success)
		get_tree().quit(1)
		return
	print("Event timed out and resolved as a failure.")

	if not _capsize_started:
		print("FAIL: a failed event should have triggered a real capsize")
		get_tree().quit(1)
		return
	print("Capsize triggered.")

	var remaining: Array = []
	for i in range(Livewell.MAX_SLOTS):
		if livewell.slots[i] != null:
			remaining.append(livewell.slots[i].final_value)
	remaining.sort()
	print("Remaining livewell values: ", remaining)
	if remaining != [5, 10, 20]:
		print("FAIL: expected the 2 biggest-value fish (999, 500) removed, got remaining=%s" % remaining)
		get_tree().quit(1)
		return

	print("--- Big Fish Event fail/fizzle/radius test PASSED ---")
	get_tree().quit()


func _wait_for_scene(scene_id: StringName, timeout: float = 3.0) -> bool:
	var waited := 0.0
	while NetworkManager._current_scene_id != scene_id and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return NetworkManager._current_scene_id == scene_id
