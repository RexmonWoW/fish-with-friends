extends Node

## Headless check for the ambient-population rework of GDD Bite Detection:
## fish are a standing wandering population that exists before/without any
## casting (not spawned per-cast), casting near one calls it to the bobber,
## a miss sends it back to wandering (still out there, not despawned), and
## only a successful hook-set ever removes one for good.
##
## Runs against BiteEventManager's real timers and VisualFishSpawner's real
## random ambient placement (host-side production code, nothing a test can
## fast-forward) -- genuinely takes several real seconds, including relying
## on the real growing call-radius to prove a "blind" cast isn't a dead one.

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
	await get_tree().process_frame

	var rod: Rod = player.equipment_slot.equipped_item as Rod

	# ── Ambient population exists BEFORE any cast -- the core of this rework. ──
	var shadows := get_tree().get_nodes_in_group("visual_fish")
	if shadows.size() != VisualFishSpawner.AMBIENT_COUNT:
		print("FAIL: expected %d standing ambient shadows before any cast, got %d" % [VisualFishSpawner.AMBIENT_COUNT, shadows.size()])
		get_tree().quit(1)
		return
	print("Standing ambient population confirmed: %d shadows, none of them cast-triggered." % shadows.size())

	# ── Cast somewhere blind -- not aimed at any particular shadow -- and ──
	# ── confirm it's not a dead cast even so (growing call radius). ──
	var endpoint := Vector3(5.0, -0.5, 5.0)
	rod._cast_landed(endpoint, 0.01, false)

	var opened_wait := 0.0
	while _hook_windows_opened < 1 and opened_wait < 12.0:
		await get_tree().process_frame
		opened_wait += get_process_delta_time()
	if _hook_windows_opened != 1:
		print("FAIL: a blind cast never got called at all -- shouldn't be a dead cast")
		get_tree().quit(1)
		return
	print("Blind cast still got a shadow called in after %.1fs (not a dead cast)." % opened_wait)

	if get_tree().get_nodes_in_group("visual_fish").size() != VisualFishSpawner.AMBIENT_COUNT:
		print("FAIL: calling a shadow shouldn't change the population count")
		get_tree().quit(1)
		return

	# ── Ignore the window (miss it on purpose). ──
	var missed_wait := 0.0
	while _hook_windows_missed < 1 and missed_wait < rod.stats.bite_hook_window_seconds + 1.0:
		await get_tree().process_frame
		missed_wait += get_process_delta_time()
	if _hook_windows_missed != 1:
		print("FAIL: missing the window never fired bite_hook_window_missed")
		get_tree().quit(1)
		return
	print("Missed the window -- shadow spooked.")

	if get_tree().get_nodes_in_group("visual_fish").size() != VisualFishSpawner.AMBIENT_COUNT:
		print("FAIL: a missed hook-set shouldn't despawn the shadow -- it should still be out there wandering")
		get_tree().quit(1)
		return
	print("Shadow still exists after a miss (resumed wandering, not despawned).")

	if rod.state != Rod.CastState.WAITING_BITE:
		print("FAIL: rod should still be WAITING_BITE after a miss -- got %s" % rod.state)
		get_tree().quit(1)
		return

	# ── Another shadow (or the same one again) should get called eventually -- ──
	# ── this time, set the hook. ──
	var retry_wait := 0.0
	while _hook_windows_opened < 2 and retry_wait < 12.0:
		await get_tree().process_frame
		retry_wait += get_process_delta_time()
	if _hook_windows_opened != 2:
		print("FAIL: no shadow got called in for the retry")
		get_tree().quit(1)
		return
	print("A shadow struck again -- setting the hook this time.")

	var bite_mgr := get_tree().get_first_node_in_group("bite_event_manager")
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

	# ── Caught shadow is despawned for good; the rest of the population stays. ──
	var remaining := get_tree().get_nodes_in_group("visual_fish").size()
	if remaining != VisualFishSpawner.AMBIENT_COUNT - 1:
		print("FAIL: expected exactly one shadow gone (caught), got %d remaining (started with %d)" % [remaining, VisualFishSpawner.AMBIENT_COUNT])
		get_tree().quit(1)
		return
	print("Caught shadow despawned for good; the rest of the ambient population is untouched.")

	print("--- Bite detection test PASSED ---")
	get_tree().quit()


func _wait_for_scene(scene_id: StringName, timeout: float = 3.0) -> bool:
	var waited := 0.0
	while NetworkManager._current_scene_id != scene_id and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return NetworkManager._current_scene_id == scene_id
