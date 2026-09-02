extends Node

## Headless check for GDD Casting's landing preview (casting rework step 1):
## the preview marker must use the EXACT SAME aim->landing math as a real
## cast (Rod._compute_aim_point + WaterValidator), never a reimplementation
## that could quietly drift out of sync with what release_cast() actually
## does. Also checks the blocked/invalid look and that it hides outside
## CHARGING.
##
## Run with:
##   godot --headless --path . res://tests/landing_preview_test.tscn

var _real_landed: bool = false
var _real_landed_pos: Vector3 = Vector3.ZERO
var _real_is_dead_cast: bool = false


func _ready() -> void:
	print("--- Landing preview test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	EventBus.cast_landed.connect(_on_cast_landed)

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

	var rod: Rod = player.equipment_slot.equipped_item as Rod

	# ── Valid case: default spawn facing reliably reaches open water at a ──
	# ── range of powers (see cast_angle_smoke_test) -- no rotation needed. ──
	rod.start_charge()
	rod.current_power = 0.6
	rod._update_landing_preview()

	if rod._landing_preview == null or not rod._landing_preview.visible:
		print("FAIL: preview never appeared while charging toward water")
		get_tree().quit(1)
		return
	if rod._landing_preview_material.albedo_color != Rod.LANDING_PREVIEW_VALID_COLOR:
		print("FAIL: preview shown as invalid/blocked while aimed at real water")
		get_tree().quit(1)
		return
	var preview_pos: Vector3 = rod._landing_preview.global_position
	print("Valid preview shown at ", preview_pos)

	# Same aim/power, for real this time -- resolves synchronously (host/solo cast).
	rod.release_cast()
	await get_tree().process_frame

	if not _real_landed:
		print("FAIL: test setup problem -- the real cast at the same aim didn't land on water")
		get_tree().quit(1)
		return
	# Preview draws itself a small offset above the surface -- compare the
	# same way _update_landing_preview built it, not raw equality.
	var expected := _real_landed_pos + Vector3(0.0, Rod.LANDING_PREVIEW_Y_OFFSET, 0.0)
	if preview_pos.distance_to(expected) > 0.01:
		print("FAIL: preview position %s didn't match the real cast's landing point %s -- preview math has drifted from the real thing" %
			[preview_pos, _real_landed_pos])
		get_tree().quit(1)
		return
	print("Preview position matched the real cast's landing point exactly.")

	# Let the lure's flight finish (LureAnimator only advances ANIMATING ->
	# WAITING_BITE once the arc tween completes) -- request_cancel_cast()
	# is a no-op outside CHARGING/WAITING_BITE, so cancelling too early
	# would silently do nothing and strand the rod at ANIMATING.
	var flight_waited := 0.0
	while rod.state == Rod.CastState.ANIMATING and flight_waited < 2.0:
		await get_tree().process_frame
		flight_waited += get_process_delta_time()
	if rod.state != Rod.CastState.WAITING_BITE:
		print("FAIL: test setup problem -- rod never reached WAITING_BITE after the valid cast (state=%s)" % rod.state)
		get_tree().quit(1)
		return

	rod.request_cancel_cast()
	await get_tree().process_frame

	# ── Invalid case: aim at the boat deck, not water (same trick ──
	# ── cast_reject_softlock_test uses -- power 0.1 -> min_cast_distance ──
	# ── dominates, short cast lands on the deck instead of real water). ──
	# GDD Casting: this is no longer a rejection -- it's a dead cast that
	# lands and lies there, so the preview reads it as "blocked" the same
	# way it reads any other obstructed path (via the shared sweep), not by
	# watching for a cast_failed that no longer fires for this case.
	_real_landed = false
	_real_is_dead_cast = false
	player.camera_rig.rotation.y = PI
	await get_tree().process_frame  # let the transform propagate

	rod.start_charge()
	rod.current_power = 0.1
	rod._update_landing_preview()

	if not rod._landing_preview.visible:
		print("FAIL: preview didn't appear for the blocked aim")
		get_tree().quit(1)
		return
	if rod._landing_preview_material.albedo_color != Rod.LANDING_PREVIEW_INVALID_COLOR:
		print("FAIL: preview shown as valid while aimed at the deck, not water")
		get_tree().quit(1)
		return
	var blocked_preview_pos: Vector3 = rod._landing_preview.global_position
	print("Invalid preview correctly shown blocked when aimed at the deck.")

	rod.release_cast()
	await get_tree().process_frame
	if not _real_landed or not _real_is_dead_cast:
		print("FAIL: test setup problem -- the real cast at the deck wasn't a dead cast (landed=%s is_dead_cast=%s)" %
			[_real_landed, _real_is_dead_cast])
		get_tree().quit(1)
		return
	print("Real cast at the same aim landed as a dead cast too, matching the preview's blocked state.")

	var blocked_expected := _real_landed_pos + Vector3(0.0, Rod.LANDING_PREVIEW_Y_OFFSET, 0.0)
	if blocked_preview_pos.distance_to(blocked_expected) > 0.01:
		print("FAIL: blocked preview position %s didn't match the real dead cast's landing point %s" %
			[blocked_preview_pos, _real_landed_pos])
		get_tree().quit(1)
		return
	print("Blocked preview position matched the real dead cast's landing point exactly.")

	# Let the dead cast's own flight finish before cancelling, same reason
	# as the valid case above -- request_cancel_cast() is a no-op outside
	# CHARGING/WAITING_BITE.
	var dead_flight_waited := 0.0
	while rod.state == Rod.CastState.ANIMATING and dead_flight_waited < 2.0:
		await get_tree().process_frame
		dead_flight_waited += get_process_delta_time()
	if rod.state != Rod.CastState.WAITING_BITE:
		print("FAIL: test setup problem -- rod never reached WAITING_BITE after the dead cast (state=%s)" % rod.state)
		get_tree().quit(1)
		return

	# ── Hides once charging ends. ──
	rod.request_cancel_cast()
	await get_tree().process_frame
	await get_tree().process_frame
	if rod._landing_preview.visible:
		print("FAIL: preview stayed visible after leaving CHARGING")
		get_tree().quit(1)
		return
	print("Preview hides once charging ends.")

	print("--- Landing preview test PASSED ---")
	get_tree().quit()


func _on_cast_landed(endpoint: Vector3, _flight: float, _pid: int, is_dead_cast: bool) -> void:
	_real_landed = true
	_real_landed_pos = endpoint
	_real_is_dead_cast = is_dead_cast
