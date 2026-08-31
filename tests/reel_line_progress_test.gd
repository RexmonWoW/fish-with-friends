extends Node

## Headless check for GDD Reel Mechanic: the real bobber/line reels in
## toward the rod tip as the angler's private Stardew progress rises, and
## back out as it falls -- broadcast via ReelFightManager, visible to every
## peer's LureAnimator (not gated to the angler's own machine). "Doesn't
## need to be exact" per direction, so this only checks the bobber ends up
## meaningfully closer/farther, not any precise position.
##
## Drives the real ReelMinigame's _progress directly (same trick
## player_display_name_test.gd already uses) and re-asserts it every frame
## for a bit to hold roughly steady against its own fill/drain math without
## tripping a real catch/snap -- there's no clean way to "pause" the private
## minigame from outside, so this out-fights it instead.

func _ready() -> void:
	print("--- Reel line progress test ---")

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
	var scene_waited := 0.0
	while NetworkManager._current_scene_id != &"lake" and scene_waited < 3.0:
		await get_tree().process_frame
		scene_waited += get_process_delta_time()
	if NetworkManager._current_scene_id != &"lake":
		print("FAIL: never reached the lake")
		get_tree().quit(1)
		return
	await get_tree().process_frame

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	var lure := rod.get_node("LureAnimator") as LureAnimator
	var rod_tip := rod.get_node("RodTip") as Marker3D

	EventBus.bite_hook_window_opened.connect(func(peer_id, _duration):
		if peer_id != 1:
			return
		var bite_manager := get_tree().get_first_node_in_group("bite_event_manager")
		if bite_manager:
			bite_manager.request_hook_set()
	)

	rod.start_charge()
	await get_tree().create_timer(0.2).timeout
	rod.release_cast()

	var waited := 0.0
	while rod.state != Rod.CastState.REELING and waited < 12.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if rod.state != Rod.CastState.REELING:
		print("FAIL: never reached REELING")
		get_tree().quit(1)
		return

	var dist_at_start := lure.get_bobber_position().distance_to(rod_tip.global_position)
	print("Bobber-to-rod-tip distance at reel start: %.2f" % dist_at_start)

	var reel := get_tree().root.get_node("GameRoot/UILayer/ReelMinigame")

	# ── Hold progress around 0.65 for a bit -- long enough for the eased ──
	# ── broadcast position to visibly close in, not long enough to finish. ──
	var held := 0.0
	while held < 1.5:
		reel._progress = 0.65
		await get_tree().process_frame
		held += get_process_delta_time()
		if rod.state != Rod.CastState.REELING:
			print("FAIL: reel finished early while holding mid-progress (state=%s)" % rod.state)
			get_tree().quit(1)
			return

	var dist_mid := lure.get_bobber_position().distance_to(rod_tip.global_position)
	print("Bobber-to-rod-tip distance held near 0.65 progress: %.2f" % dist_mid)
	if dist_mid >= dist_at_start * 0.85:
		print("FAIL: bobber didn't meaningfully reel IN as progress rose")
		get_tree().quit(1)
		return

	# ── Now hold it low -- the line should pay back out toward the anchor. ──
	held = 0.0
	while held < 1.5:
		reel._progress = 0.15
		await get_tree().process_frame
		held += get_process_delta_time()
		if rod.state != Rod.CastState.REELING:
			print("FAIL: reel finished early while holding low progress (state=%s)" % rod.state)
			get_tree().quit(1)
			return

	var dist_low := lure.get_bobber_position().distance_to(rod_tip.global_position)
	print("Bobber-to-rod-tip distance held near 0.15 progress: %.2f" % dist_low)
	if dist_low <= dist_mid * 1.15:
		print("FAIL: bobber didn't meaningfully reel back OUT as progress fell")
		get_tree().quit(1)
		return

	print("--- Reel line progress test PASSED ---")
	get_tree().quit()
