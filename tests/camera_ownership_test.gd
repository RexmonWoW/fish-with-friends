extends Node

## Headless check for "both machines see through player one's camera":
## nothing ever called camera.current = true for the LOCAL player
## specifically. Invisible with one player (Godot auto-activates the sole
## Camera3D), but with two Camera3D nodes in the tree -- exactly what every
## real multiplayer machine has -- Godot picks whichever activated first
## (the host's) for every viewport. Spawns a second, non-local player
## locally (same tree, different peer_id) to reproduce the two-camera
## situation without needing a real second machine.
##
## Requires Steam to be running (host_lobby() goes through SteamManager).

func _ready() -> void:
	print("--- Camera ownership test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(local_player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("Local player (peer 1) camera.current: ", local_player.camera.current)
	if not local_player.camera.current:
		print("FAIL: local player's own camera was never activated")
		get_tree().quit(1)
		return

	# Simulate a second peer's player existing locally, same as every real
	# machine sees once someone else joins.
	NetworkManager._spawn_player_for_peer(2)
	await get_tree().process_frame
	await get_tree().process_frame

	var other_player: Player = NetworkManager.spawned_players.get(2)
	if other_player == null:
		print("FAIL: second player never registered")
		get_tree().quit(1)
		return

	print("Other player (peer 2) camera.current: ", other_player.camera.current)
	if other_player.camera.current:
		print("FAIL: a non-local player's camera was activated too")
		get_tree().quit(1)
		return

	print("Local player camera still current: ", local_player.camera.current)
	if not local_player.camera.current:
		print("FAIL: local player's camera got deactivated by the second spawn")
		get_tree().quit(1)
		return

	print("--- Camera ownership test PASSED ---")
	get_tree().quit()
