extends Node

## Headless check that catches now carry a real Steam display name instead
## of the "Player <id>" placeholder. Solo/host testing only exercises the
## "this is me" path (SteamManager.get_display_name_for_peer for the local
## peer_id uses Steam.getPersonaName()) -- the "look up someone else via
## get_steam_id_for_peer_id + getFriendPersonaName" path can only really be
## proven against a real second peer, but at least confirms the self path
## and that the plumbing reaches CaughtFish correctly.

func _ready() -> void:
	print("--- Player display name test ---")
	print("Steam running: ", Steam.isSteamRunning())

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

	var name := SteamManager.get_display_name_for_peer(player.peer_id)
	print("get_display_name_for_peer(self): '%s'" % name)
	if name.begins_with("Player "):
		print("FAIL: fell back to the generic placeholder even for the local peer")
		get_tree().quit(1)
		return

	# Confirm it actually reaches CaughtFish via BiteEventManager, not just
	# the helper function in isolation.
	var rod: Rod = player.equipment_slot.equipped_item as Rod
	var livewell: Livewell = get_tree().get_first_node_in_group("livewell")

	rod.start_charge()
	await get_tree().create_timer(0.2).timeout
	rod.release_cast()

	var waited := 0.0
	while rod.state != Rod.CastState.REELING and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if rod.state != Rod.CastState.REELING:
		print("FAIL: never reached REELING")
		get_tree().quit(1)
		return

	var reel = get_tree().root.get_node("GameRoot/UILayer/ReelMinigame")
	reel._progress = 1.0
	await get_tree().process_frame

	var caught: CaughtFish = null
	for slot in livewell.slots:
		if slot != null:
			caught = slot
	if caught == null:
		print("FAIL: no catch landed in the livewell")
		get_tree().quit(1)
		return

	print("CaughtFish.caught_by_player_name: '%s'" % caught.caught_by_player_name)
	if caught.caught_by_player_name != name:
		print("FAIL: CaughtFish name doesn't match SteamManager's resolved name")
		get_tree().quit(1)
		return

	print("--- Player display name test PASSED ---")
	get_tree().quit()
