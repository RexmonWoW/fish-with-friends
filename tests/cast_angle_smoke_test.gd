extends Node

## Headless repro for "casts sometimes don't go through": tests
## WaterValidator directly (no RPC/timer/tween pipeline in the way) across a
## range of camera pitches and powers, using the exact same endpoint math
## Rod._validate_and_land_cast uses. Hypothesis: the endpoint is
## cam_origin + full-3D-forward * distance, so pitching the camera down
## (as a player naturally would while fishing) sends the endpoint's Y well
## below the water surface, and WaterValidator's +-10 unit raycast around
## that (wrong) endpoint never reaches the actual water at y=0.

var _last_result: String = ""

func _ready() -> void:
	print("--- Cast angle smoke test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	EventBus.cast_landed.connect(func(_ep, _flight, _pid, is_dead_cast): _last_result = "dead" if is_dead_cast else "landed")
	EventBus.cast_failed.connect(func(reason, _pid): _last_result = "failed:" + str(reason))

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	var cam: Camera3D = player.camera_pitch.get_node("Camera3D")

	var pitches := [0.0, -0.3, -0.6, -0.9, -1.2]
	var powers := [0.3, 0.6, 1.0]

	var any_fail := false
	for pitch in pitches:
		player.camera_pitch.rotation.x = pitch
		await get_tree().process_frame  # let the transform propagate

		var cam_origin: Vector3 = cam.global_transform.origin
		var cam_forward: Vector3 = -cam.global_transform.basis.z
		for power in powers:
			_last_result = "(none)"
			# Call the real validation path, not a hand-copied formula.
			rod._validate_and_land_cast(cam_origin, cam_forward, power)
			await get_tree().process_frame

			print("pitch=%.2f power=%.2f result=%s" % [pitch, power, _last_result])
			if _last_result != "landed":
				any_fail = true

	if any_fail:
		print("--- Cast angle smoke test: CONFIRMED some aim/power combos wrongly reject ---")
	else:
		print("--- Cast angle smoke test: no rejections found ---")
	get_tree().quit()
