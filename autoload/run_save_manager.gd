extends Node

## Host-authoritative save/load for GDD Run Saves. No slot-picker UI yet
## (phase 2) -- driven by DebugConsole commands for now (save_run/
## load_run/list_saves) so the save itself can be proven working first.
##
## Saves are per-slot files under user://saves/ using Godot's own Resource
## serialization (ResourceSaver/ResourceLoader) -- RunSave is a plain
## Resource and PlayerStats nests inside it the same way CaughtFish.species
## already nests a FishData reference, no custom encoding needed.

const SAVE_DIR: String = "user://saves"
const SLOT_COUNT: int = 4

## Which slot the CURRENT run is tied to -- set by a successful load_run()
## or the first save_run() to an empty slot, -1 if this run has never
## touched a slot (nothing for _on_day_summary's autosave to write into
## yet -- phase 2's picker will always set one up front at creation).
var _active_slot: int = -1

## SteamID64 -> PlayerStats for the currently active save's FULL roster,
## including anyone not connected right now -- kept in memory so an absent
## player's upgrades survive a save/load cycle without needing them
## online. Refreshed from live Player.stats at save time for whoever IS
## connected; untouched for whoever isn't (GDD: "their upgrades wait").
var _roster_stats: Dictionary = {}       # int (SteamID64) -> PlayerStats
var _roster_names: Dictionary = {}       # int (SteamID64) -> String


func _ready() -> void:
	if not multiplayer.is_server():
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	RunState.day_summary.connect(_on_day_summary)
	NetworkManager.peer_player_spawned.connect(_on_peer_player_spawned)


## GDD Run Saves: "Autosave at day end." Only actually writes anything for
## a run already tied to a slot -- see _active_slot's own doc comment.
func _on_day_summary(_day: int, _earned: int, _total: int, _quota: int, _passed: bool) -> void:
	if _active_slot != -1:
		save_to_slot(_active_slot)


## GDD: "someone new joining a co-op save starts bare and catches up" --
## only applies saved state for a Steam ID that's already IN this save's
## roster (i.e. someone who played this slot before), never invents an
## entry for a stranger just because they happened to connect.
func _on_peer_player_spawned(peer_id: int, player: Player) -> void:
	if not multiplayer.is_server():
		return
	var steam_id := SteamManager.get_steam_id_for_peer(peer_id)
	if steam_id == 0 or not _roster_stats.has(steam_id):
		return
	player.stats = _roster_stats[steam_id]
	NetworkManager.broadcast_player_stats(peer_id, player.stats)


# ── Save ─────────────────────────────────────────────────────────────────────

## Host-only. GDD: "Save at day boundaries only, in the lobby. Never mid-
## round." Enforced here, not just left to callers -- the whole point of
## driving this from debug commands for phase 1 is to prove the REAL rule
## holds, not to bypass it. Returns {"success": bool, "reason": StringName}.
func save_to_slot(slot: int) -> Dictionary:
	if not multiplayer.is_server():
		return {"success": false, "reason": &"not_host"}
	if slot < 0 or slot >= SLOT_COUNT:
		return {"success": false, "reason": &"bad_slot"}
	if NetworkManager._current_scene_id != &"lobby":
		return {"success": false, "reason": &"not_in_lobby"}

	var session_is_coop := _session_is_coop()
	var existing := _load_raw(slot)
	if existing != null and existing.is_coop != session_is_coop:
		return {"success": false, "reason": &"type_mismatch"}

	# Refresh the roster with whoever's actually here right now; anyone not
	# connected keeps whatever was already in memory (loaded from this slot,
	# or from a slot we've been playing all along).
	for peer_id in NetworkManager.spawned_players:
		var steam_id := SteamManager.get_steam_id_for_peer(peer_id)
		if steam_id == 0:
			continue
		var player: Player = NetworkManager.spawned_players[peer_id]
		_roster_stats[steam_id] = player.stats
		_roster_names[steam_id] = SteamManager.get_display_name_for_peer(peer_id)

	var save := RunSave.new()
	save.save_version = RunSave.CURRENT_VERSION
	save.is_coop = session_is_coop
	save.game_mode = RunState.game_mode
	save.created_at_unix = existing.created_at_unix if existing != null else Time.get_unix_time_from_system()
	save.last_played_unix = Time.get_unix_time_from_system()
	save.day_number = RunState.day_number
	save.current_quota = RunState.current_quota
	save.total_money_earned = RunState.total_money_earned
	save.has_fish_finder = RunState.has_fish_finder
	save.player_count_multiplier = RunState.player_count_multiplier
	save.player_stats_by_steam_id = _roster_stats.duplicate()
	save.player_names_by_steam_id = _roster_names.duplicate()

	var err := ResourceSaver.save(save, _path_for(slot))
	if err != OK:
		return {"success": false, "reason": &"write_failed"}

	_active_slot = slot
	return {"success": true, "reason": &""}


# ── Load ─────────────────────────────────────────────────────────────────────

## Host-only. Same "day boundaries only, in the lobby" rule as saving --
## loading mid-round would be just as incoherent (what would a round-in-
## progress even resume into?). Returns {"success": bool, "reason":
## StringName}.
func load_from_slot(slot: int) -> Dictionary:
	if not multiplayer.is_server():
		return {"success": false, "reason": &"not_host"}
	if slot < 0 or slot >= SLOT_COUNT:
		return {"success": false, "reason": &"bad_slot"}
	if NetworkManager._current_scene_id != &"lobby":
		return {"success": false, "reason": &"not_in_lobby"}

	var save := _load_raw(slot)
	if save == null:
		return {"success": false, "reason": &"empty_slot"}
	if save.save_version != RunSave.CURRENT_VERSION:
		return {"success": false, "reason": &"version_mismatch"}
	if save.is_coop != _session_is_coop():
		return {"success": false, "reason": &"type_mismatch"}

	RunState.restore_crew_state(
		save.day_number, save.current_quota, save.total_money_earned,
		save.has_fish_finder, save.player_count_multiplier, save.game_mode
	)

	_roster_stats = save.player_stats_by_steam_id.duplicate()
	_roster_names = save.player_names_by_steam_id.duplicate()
	_active_slot = slot

	# Anyone already connected (the host, at minimum) gets their saved
	# state applied immediately -- _on_peer_player_spawned only fires for
	# NEW connections from here on, it wouldn't otherwise catch whoever's
	# already here.
	for peer_id in NetworkManager.spawned_players:
		var steam_id := SteamManager.get_steam_id_for_peer(peer_id)
		if steam_id == 0 or not _roster_stats.has(steam_id):
			continue
		var player: Player = NetworkManager.spawned_players[peer_id]
		player.stats = _roster_stats[steam_id]
		NetworkManager.broadcast_player_stats(peer_id, player.stats)

	return {"success": true, "reason": &""}


# ── New run / delete (phase 2: the slot picker) ─────────────────────────────

## Host-only. GDD Run Saves phase 2: "Empty slots offer a new run." Resets
## RunState to fresh defaults, locks in solo/co-op off whoever's actually
## here right now and the chosen game mode, and writes an initial save
## immediately -- the slot's type isn't just claimed in memory until the
## first real day-end autosave.
func start_new_run(slot: int, game_mode: StringName) -> Dictionary:
	if not multiplayer.is_server():
		return {"success": false, "reason": &"not_host"}
	if slot < 0 or slot >= SLOT_COUNT:
		return {"success": false, "reason": &"bad_slot"}
	if NetworkManager._current_scene_id != &"lobby":
		return {"success": false, "reason": &"not_in_lobby"}
	if _load_raw(slot) != null:
		return {"success": false, "reason": &"slot_occupied"}

	RunState.reset_for_new_run(game_mode)
	_roster_stats.clear()
	_roster_names.clear()
	return save_to_slot(slot)


## Host-only. GDD: "Deleting/overwriting a slot should be possible without
## leaving the menu." A no-op success on an already-empty slot -- deleting
## nothing isn't an error.
func delete_slot(slot: int) -> Dictionary:
	if not multiplayer.is_server():
		return {"success": false, "reason": &"not_host"}
	if slot < 0 or slot >= SLOT_COUNT:
		return {"success": false, "reason": &"bad_slot"}

	var path := _path_for(slot)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			return {"success": false, "reason": &"delete_failed"}
	return {"success": true, "reason": &""}


## Public read-only peek at a slot's saved data for the picker's display --
## null for empty. Never mutates _active_slot/roster, unlike load_from_slot.
func peek_slot(slot: int) -> RunSave:
	return _load_raw(slot)


## Called by NetworkManager.disconnect_from_lobby() when a run fully ends,
## so the NEXT lobby's picker actually shows instead of silently
## continuing to autosave into the last run's slot.
func reset_active_run() -> void:
	_active_slot = -1
	_roster_stats.clear()
	_roster_names.clear()


# ── Listing (phase 1: debug console only, phase 2: the real slot picker) ───────

## One-line summary per slot, "empty" for a slot with no file yet. Doesn't
## require any particular scene -- purely reads whatever's on disk.
func describe_slots() -> Array[String]:
	var lines: Array[String] = []
	for slot in range(SLOT_COUNT):
		var save := _load_raw(slot)
		if save == null:
			lines.append("Slot %d: empty" % slot)
			continue
		var kind := "co-op" if save.is_coop else "solo"
		var crew := ", ".join(save.player_names_by_steam_id.values())
		if crew.is_empty():
			crew = "(no crew recorded)"
		lines.append(
			"Slot %d: %s, %s, day %d, $%d in the pot, crew: %s" %
			[slot, kind, save.game_mode, save.day_number, save.total_money_earned, crew]
		)
	return lines


func _session_is_coop() -> bool:
	return NetworkManager.spawned_players.size() > 1


func _path_for(slot: int) -> String:
	return "%s/slot_%d.tres" % [SAVE_DIR, slot]


## null if the slot is empty OR the file exists but isn't a real RunSave
## (corrupt, or from some future format ResourceLoader can't even parse) --
## both read the same as "nothing usable here" to every caller above.
func _load_raw(slot: int) -> RunSave:
	var path := _path_for(slot)
	if not FileAccess.file_exists(path):
		return null
	return ResourceLoader.load(path, "RunSave", ResourceLoader.CACHE_MODE_IGNORE) as RunSave
