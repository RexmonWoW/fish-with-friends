extends Node

## Headless check for GDD Bite Detection: a shadow (VisualFish, via
## VisualFishSpawner) approaches the landed bobber and strikes, opening a
## short hook-set window. Missing it spooks the shadow and rolls in
## another after a pause; setting the hook feeds into the existing bite/
## reel flow completely unchanged (same species, same bite_started shape).
##
## Runs against BiteEventManager's real timers (host-side production code,
## nothing a test can fast-forward) -- genuinely takes several real seconds
## to cover the full miss-then-retry cycle. Not ideal, but faster/more
## honest than faking the timing.

var _hook_windows_opened: int = 0
var _hook_windows_missed: int = 0
var _bite_fired: Variant = null  # FishData once bite_started fires, else null


func _ready() -> void:
	print("--- Bite detection test ---")

	EventBus.bite_hook_window_opened.connect(func(pid, _d):
		if pid == 1:
			_hook_windows_opened += 1
	)
	EventBus.bite_hook_window_missed.connect(func(pid):
		if pid == 1:
			_hook_windows_missed += 1
	)
	EventBus.bite_started.connect(func(fd, pid):
		if pid == 1:
			_bite_fired = fd
	)

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

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	var bite_mgr := get_tree().get_first_node_in_group("bite_event_manager")

	# ── Cast lands -- a real, visible shadow should appear before anything else. ──
	var endpoint := Vector3(5.0, -0.5, 5.0)
	rod._cast_landed(endpoint, 0.01)

	var shadows: Array = []
	var spawn_wait := 0.0
	while shadows.is_empty() and spawn_wait < 1.0:
		await get_tree().process_frame
		spawn_wait += get_process_delta_time()
		shadows = get_tree().get_nodes_in_group("visual_fish")
	if shadows.is_empty():
		print("FAIL: no shadow (VisualFish) spawned after the cast landed")
		get_tree().quit(1)
		return
	print("Shadow spawned: ", shadows[0])

	if _hook_windows_opened != 0:
		print("FAIL: hook window opened before the shadow even had time to approach")
		get_tree().quit(1)
		return

	# ── Let the shadow strike -- ignore the window (miss it on purpose). ──
	var opened_wait := 0.0
	while _hook_windows_opened < 1 and opened_wait < bite_mgr.SHADOW_APPROACH_SECONDS + 2.0:
		await get_tree().process_frame
		opened_wait += get_process_delta_time()
	if _hook_windows_opened != 1:
		print("FAIL: hook window never opened after the shadow's approach")
		get_tree().quit(1)
		return
	print("Hook window opened after the shadow struck.")

	# Let it time out unanswered.
	var missed_wait := 0.0
	while _hook_windows_missed < 1 and missed_wait < bite_mgr.HOOK_WINDOW_SECONDS + 1.0:
		await get_tree().process_frame
		missed_wait += get_process_delta_time()
	if _hook_windows_missed != 1:
		print("FAIL: missing the window never fired bite_hook_window_missed")
		get_tree().quit(1)
		return
	print("Missed the window -- shadow spooked.")

	if rod.state != Rod.CastState.WAITING_BITE:
		print("FAIL: rod should still be WAITING_BITE after a miss (another shadow rolls in) -- got %s" % rod.state)
		get_tree().quit(1)
		return

	# ── Another shadow should roll in after the pause -- this time, set the hook. ──
	var retry_wait := 0.0
	while _hook_windows_opened < 2 and retry_wait < bite_mgr.SPOOK_PAUSE_SECONDS + bite_mgr.SHADOW_APPROACH_SECONDS + 2.0:
		await get_tree().process_frame
		retry_wait += get_process_delta_time()
	if _hook_windows_opened != 2:
		print("FAIL: no second shadow rolled in after the miss")
		get_tree().quit(1)
		return
	print("A second shadow struck -- setting the hook this time.")

	bite_mgr.request_hook_set()
	await get_tree().process_frame

	if _bite_fired == null:
		print("FAIL: setting the hook never fired bite_started")
		get_tree().quit(1)
		return
	print("bite_started fired: species=%s" % (_bite_fired as FishData).species_id)

	# The existing (unchanged) reel flow reacts to bite_started synchronously
	# -- ReelMinigame._on_bite_started already advanced the rod straight to
	# REELING by this point, proving the hook-set fed cleanly into it.
	if rod.state != Rod.CastState.REELING:
		print("FAIL: hook-set should have fed straight into the existing reel flow (REELING) -- got %s" % rod.state)
		get_tree().quit(1)
		return
	print("Fed cleanly into the existing reel flow (rod is REELING).")

	var remaining_shadows := get_tree().get_nodes_in_group("visual_fish")
	if not remaining_shadows.is_empty():
		print("FAIL: shadow should be despawned once the hook is set")
		get_tree().quit(1)
		return
	print("Shadow despawned once the hook was set.")

	print("--- Bite detection test PASSED ---")
	get_tree().quit()


func _wait_for_scene(scene_id: StringName, timeout: float = 3.0) -> bool:
	var waited := 0.0
	while NetworkManager._current_scene_id != scene_id and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return NetworkManager._current_scene_id == scene_id
