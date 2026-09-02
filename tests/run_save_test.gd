extends Node

## Headless check for GDD Run Saves phase 1 (the save itself, no picker UI
## yet -- driven directly through RunSaveManager, same as the debug
## console commands will). Covers: a real save/load round-trip (crew state
## + the host's own real PlayerStats, via their real resolvable Steam ID),
## an absent crewmate's stats surviving a re-save (injected directly since
## a locally-spawned test peer has no real second Steam connection to
## resolve -- see NetworkManager._spawn_player_for_peer's own doc comment),
## solo/co-op type-mismatch rejection, version-mismatch rejection, and the
## "never mid-round" guard.

func _ready() -> void:
	print("--- Run save test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player1: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if NetworkManager._current_scene_id != &"lobby":
		print("FAIL: test setup problem -- expected to start in the lobby")
		get_tree().quit(1)
		return

	var host_steam_id := SteamManager.get_steam_id_for_peer(1)
	if host_steam_id == 0:
		print("FAIL: test setup problem -- couldn't resolve the host's own Steam ID (is Steam running?)")
		get_tree().quit(1)
		return
	print("Host Steam ID resolved: %d" % host_steam_id)

	const SLOT := 0

	# ── Save: real crew state + the host's real (mutated) PlayerStats. ──
	RunState.day_number = 3
	RunState.current_quota = 250
	RunState.total_money_earned = 180
	RunState.has_fish_finder = true
	RunState.player_count_multiplier = 1.0
	player1.stats.bait_rounds_remaining = 3
	player1.stats.cast_range_tier = 2

	var save_result: Dictionary = RunSaveManager.save_to_slot(SLOT)
	if not save_result["success"]:
		print("FAIL: save_to_slot failed unexpectedly: %s" % save_result["reason"])
		get_tree().quit(1)
		return
	print("Saved to slot %d." % SLOT)

	# ── Inject a fake "absent crewmate" into the roster, then re-save. ──
	# ── Their entry must survive even though they're not connected. ──
	const FAKE_ABSENT_STEAM_ID := 76500000000000123
	var absent_stats := PlayerStats.new()
	absent_stats.cast_range_tier = 1
	RunSaveManager._roster_stats[FAKE_ABSENT_STEAM_ID] = absent_stats
	RunSaveManager._roster_names[FAKE_ABSENT_STEAM_ID] = "AbsentBuddy"

	save_result = RunSaveManager.save_to_slot(SLOT)
	if not save_result["success"]:
		print("FAIL: re-save with an absent crewmate failed: %s" % save_result["reason"])
		get_tree().quit(1)
		return
	print("Re-saved with an absent crewmate in the roster.")

	# ── Blow away in-memory state to prove the LOAD actually restores it, ──
	# ── not just that it never left. ──
	RunState.day_number = 1
	RunState.current_quota = 999
	RunState.total_money_earned = 0
	RunState.has_fish_finder = false
	player1.stats = PlayerStats.new()
	RunSaveManager._roster_stats.clear()
	RunSaveManager._roster_names.clear()
	RunSaveManager._active_slot = -1

	var load_result: Dictionary = RunSaveManager.load_from_slot(SLOT)
	if not load_result["success"]:
		print("FAIL: load_from_slot failed unexpectedly: %s" % load_result["reason"])
		get_tree().quit(1)
		return
	await get_tree().process_frame

	if RunState.day_number != 3 or RunState.current_quota != 250 or RunState.total_money_earned != 180 or not RunState.has_fish_finder:
		print("FAIL: crew state didn't restore correctly (day=%d quota=%d money=%d fish_finder=%s)" %
			[RunState.day_number, RunState.current_quota, RunState.total_money_earned, RunState.has_fish_finder])
		get_tree().quit(1)
		return
	print("Crew state restored correctly: day=%d quota=%d pot=%d fish_finder=true" %
		[RunState.day_number, RunState.current_quota, RunState.total_money_earned])

	if player1.stats.bait_rounds_remaining != 3 or player1.stats.cast_range_tier != 2:
		print("FAIL: host's own PlayerStats didn't restore correctly (bait=%d tier=%d)" %
			[player1.stats.bait_rounds_remaining, player1.stats.cast_range_tier])
		get_tree().quit(1)
		return
	print("Host's own PlayerStats restored correctly (already connected at load time).")

	if not RunSaveManager._roster_stats.has(FAKE_ABSENT_STEAM_ID):
		print("FAIL: the absent crewmate's saved stats didn't survive the save/load round-trip")
		get_tree().quit(1)
		return
	var restored_absent: PlayerStats = RunSaveManager._roster_stats[FAKE_ABSENT_STEAM_ID]
	if restored_absent.cast_range_tier != 1:
		print("FAIL: absent crewmate's restored stats are wrong (tier=%d)" % restored_absent.cast_range_tier)
		get_tree().quit(1)
		return
	print("Absent crewmate's stats survived the round-trip untouched, waiting for them to come back.")

	# ── list_saves / describe_slots reflects what's actually on disk. ──
	var descriptions := RunSaveManager.describe_slots()
	if descriptions.size() != RunSaveManager.SLOT_COUNT:
		print("FAIL: describe_slots should return exactly SLOT_COUNT entries, got %d" % descriptions.size())
		get_tree().quit(1)
		return
	if not descriptions[SLOT].contains("day 3"):
		print("FAIL: slot %d's description doesn't mention day 3: %s" % [SLOT, descriptions[SLOT]])
		get_tree().quit(1)
		return
	print("Slot description: %s" % descriptions[SLOT])
	if not descriptions[1].contains("empty"):
		print("FAIL: an untouched slot should describe itself as empty, got: %s" % descriptions[1])
		get_tree().quit(1)
		return
	print("Untouched slot correctly reports empty.")

	# ── Solo/co-op type mismatch: a second (locally-spawned) player makes ──
	# ── this session read as co-op; loading the solo save must be refused. ──
	NetworkManager._spawn_player_for_peer(2)
	await get_tree().process_frame
	await get_tree().process_frame

	var mismatch_result: Dictionary = RunSaveManager.load_from_slot(SLOT)
	if mismatch_result["success"] or mismatch_result["reason"] != &"type_mismatch":
		print("FAIL: loading a solo save into a now-coop session should be refused as type_mismatch, got %s" % [mismatch_result])
		get_tree().quit(1)
		return
	print("Solo save correctly refused to load into a co-op session.")

	var second_player: Player = NetworkManager.spawned_players[2]
	if second_player.stats.cast_range_tier != 0:
		print("FAIL: the new (unrelated) second player shouldn't have inherited anyone's saved stats, got tier=%d" %
			second_player.stats.cast_range_tier)
		get_tree().quit(1)
		return
	print("A stranger joining doesn't inherit anyone's saved stats -- starts bare, per GDD.")

	# ── Version mismatch: hand-corrupt the file's version, confirm refusal. ──
	var stale := ResourceLoader.load(RunSaveManager._path_for(SLOT), "RunSave", ResourceLoader.CACHE_MODE_IGNORE) as RunSave
	stale.save_version = RunSave.CURRENT_VERSION + 1
	stale.is_coop = true  # match the current (now co-op) session so type-mismatch doesn't mask this check
	ResourceSaver.save(stale, RunSaveManager._path_for(SLOT))

	var version_result: Dictionary = RunSaveManager.load_from_slot(SLOT)
	if version_result["success"] or version_result["reason"] != &"version_mismatch":
		print("FAIL: a future-versioned save should be refused as version_mismatch, got %s" % [version_result])
		get_tree().quit(1)
		return
	print("Mismatched save version correctly refused, no migration attempted.")

	# ── Never mid-round: start a real round, confirm save/load are both refused. ──
	NetworkManager.request_start_round()
	var scene_waited := 0.0
	while NetworkManager._current_scene_id != &"lake" and scene_waited < 3.0:
		await get_tree().process_frame
		scene_waited += get_process_delta_time()
	if NetworkManager._current_scene_id != &"lake":
		print("FAIL: test setup problem -- never reached the lake")
		get_tree().quit(1)
		return

	var midround_save: Dictionary = RunSaveManager.save_to_slot(SLOT)
	var midround_load: Dictionary = RunSaveManager.load_from_slot(SLOT)
	if midround_save["success"] or midround_save["reason"] != &"not_in_lobby":
		print("FAIL: saving mid-round should be refused as not_in_lobby, got %s" % [midround_save])
		get_tree().quit(1)
		return
	if midround_load["success"] or midround_load["reason"] != &"not_in_lobby":
		print("FAIL: loading mid-round should be refused as not_in_lobby, got %s" % [midround_load])
		get_tree().quit(1)
		return
	print("Save and load both correctly refused mid-round.")

	print("--- Run save test PASSED ---")
	get_tree().quit()
