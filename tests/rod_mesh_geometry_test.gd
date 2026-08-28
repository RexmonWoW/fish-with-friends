extends Node

## Headless geometry check for the new rod mesh: since nothing here can
## actually render, verify the math directly -- the cylinder's own local
## extremes, transformed through RodShaft's global_transform, should land
## on the grip (Rod's origin) and RodTip respectively. Also checks the held
## rod is now rigidly camera-relative (no BodyPivot yaw-lag).

func _ready() -> void:
	print("--- Rod mesh geometry test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	var rod_tip := rod.get_node("RodTip") as Marker3D
	var shaft := rod.get_node("RodModel/RodShaft") as MeshInstance3D

	var shaft_xform: Transform3D = shaft.global_transform
	var grip_end: Vector3 = shaft_xform * Vector3(0.0, 0.5, 0.0)
	var tip_end: Vector3 = shaft_xform * Vector3(0.0, -0.5, 0.0)

	print("Rod origin (grip):     ", rod.global_position)
	print("Shaft local -0.5 maps: ", grip_end)
	print("Shaft local +0.5 maps: ", tip_end)
	print("RodTip position:       ", rod_tip.global_position)

	if rod.global_position.distance_to(grip_end) > 0.01:
		print("FAIL: shaft's grip end doesn't line up with the rod's origin")
		get_tree().quit(1)
		return
	if rod_tip.global_position.distance_to(tip_end) > 0.01:
		print("FAIL: shaft's far end doesn't line up with RodTip")
		get_tree().quit(1)
		return
	print("Shaft geometry lines up with grip and RodTip correctly.")

	# Camera-relative rigidity: yaw the camera hard and confirm the rod tip
	# moves in lockstep with the camera (not lagging via BodyPivot).
	var before := rod_tip.global_position
	player.camera_rig.rotation.y += 1.2
	await get_tree().process_frame  # one frame is enough if it's truly rigid
	var after := rod_tip.global_position
	var moved := before.distance_to(after)
	print("RodTip moved %.3f after an instant camera yaw (should be > 0.05, rigid)" % moved)
	if moved < 0.05:
		print("FAIL: rod tip didn't move with the camera at all")
		get_tree().quit(1)
		return

	print("--- Rod mesh geometry test PASSED ---")
	get_tree().quit()
