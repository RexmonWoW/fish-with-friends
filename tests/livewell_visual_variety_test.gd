extends Node

## Headless check that livewell capsules actually vary by size/species now
## (previously fixed size, tinted only by rarity).

func _ready() -> void:
	print("--- Livewell visual variety test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# Players now land in the lobby first (bare-bones lobby); skip straight
	# to the lake for this test rather than walking into the StartTrigger.
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
	await get_tree().process_frame

	var livewell: Livewell = get_tree().get_first_node_in_group("livewell")

	var small_species: FishData = load("res://data/fish/species/bluegill.tres")
	var big_species: FishData = load("res://data/fish/species/catfish.tres")

	var small_fish := FishFactory.create_caught_fish(
		small_species, player.peer_id, "Player 1", &"lake", false, [], [], false
	)
	small_fish.size = small_species.min_size  # force smallest end

	var big_fish := FishFactory.create_caught_fish(
		big_species, player.peer_id, "Player 1", &"lake", false, [], [], false
	)
	big_fish.size = big_species.max_size  # force largest end

	livewell.add_fish(small_fish)
	livewell.add_fish(big_fish)

	var small_mesh: MeshInstance3D = livewell._visuals[0]
	var big_mesh: MeshInstance3D = livewell._visuals[1]
	var small_len: float = small_mesh.mesh.height
	var big_len: float = big_mesh.mesh.height
	var small_color: Color = small_mesh.get_surface_override_material(0).albedo_color
	var big_color: Color = big_mesh.get_surface_override_material(0).albedo_color

	print("Small (bluegill, min size) capsule length: ", small_len, " color: ", small_color)
	print("Big (catfish, max size) capsule length: ", big_len, " color: ", big_color)

	if not (big_len > small_len):
		print("FAIL: bigger fish did not get a bigger capsule")
		get_tree().quit(1)
		return
	if small_color.is_equal_approx(big_color):
		print("FAIL: different species got the same color")
		get_tree().quit(1)
		return

	print("--- Livewell visual variety test PASSED ---")
	get_tree().quit()
