extends Node

## Headless check for "can players see each other": PlayerModel was
## completely empty (no mesh at all -- other players were literally
## invisible), and PlayerSync's replication config never included
## CameraRig/CameraPitch rotation, which matters now that the held rod is
## camera-relative -- without it, other peers would see a player's rod
## frozen facing whatever direction it spawned in, never matching where
## that player is actually aiming.

func _ready() -> void:
	print("--- Player visibility test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var body_mesh := player.body_pivot.get_node_or_null("PlayerModel/BodyMesh") as MeshInstance3D
	if body_mesh == null or body_mesh.mesh == null:
		print("FAIL: player has no body mesh -- would be invisible to others")
		get_tree().quit(1)
		return
	print("Body mesh present: ", body_mesh.mesh, " color: ", body_mesh.get_surface_override_material(0).albedo_color)

	var sync := player.get_node("PlayerSync") as MultiplayerSynchronizer
	var config := sync.replication_config
	var paths: Array[String] = []
	for prop in config.get_properties():
		paths.append(str(prop))
	print("Replicated properties: ", paths)

	var has_camera_yaw := paths.any(func(p): return p.find("CameraRig:rotation_degrees") != -1)
	var has_camera_pitch := paths.any(func(p): return p.find("CameraPitch:rotation_degrees") != -1)
	if not has_camera_yaw or not has_camera_pitch:
		print("FAIL: CameraRig/CameraPitch rotation isn't replicated -- other peers would see a frozen rod")
		get_tree().quit(1)
		return

	print("--- Player visibility test PASSED ---")
	get_tree().quit()
