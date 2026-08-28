extends Node

## Owns the MultiplayerAPI lifecycle on top of GodotSteam's SteamMultiplayerPeer.
## Drives player spawn/despawn and map loading. Listens to SteamManager for lobby events.

# ── Signals ────────────────────────────────────────────────────────────────────
signal spawned_local_player(player: Player)
signal peer_player_spawned(peer_id: int, player: Player)
signal peer_player_despawned(peer_id: int)
signal run_ended(reason: String)

# ── Map registry ───────────────────────────────────────────────────────────────
## Lazy-loaded paths — no preload so a missing file never causes a parse error.
## Art and Polish drops lake.tscn at this path and it loads automatically.
const MAP_PATHS: Dictionary = {
	&"lake": "res://scenes/maps/lake.tscn",
}

# ── State ──────────────────────────────────────────────────────────────────────
var spawned_players: Dictionary = {}  ## peer_id (int) → Player node

var _player_spawner: MultiplayerSpawner = null


func _ready() -> void:
	SteamManager.lobby_created.connect(_on_lobby_created)
	SteamManager.lobby_joined.connect(_on_lobby_joined)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# MultiplayerSpawner needs spawn_function set on EVERY peer, not just the
	# host -- when the host's spawn() call replicates to a client, the client
	# runs this SAME callback locally to reconstruct the node. This used to
	# only get wired up in host-only code paths, so a joining client's own
	# spawner had nothing to run and every spawn (including their own
	# player) silently failed to construct on their machine.
	_get_spawner()


# ── Public API ─────────────────────────────────────────────────────────────────

func host_lobby() -> void:
	SteamManager.create_lobby(4)


func join_lobby(lobby_id: int) -> void:
	var host_steam_id := Steam.getLobbyOwner(lobby_id)
	var peer := SteamMultiplayerPeer.new()
	var err := peer.create_client(host_steam_id, 0)
	if err != OK:
		push_error("NetworkManager: SteamMultiplayerPeer.create_client failed: %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	_allow_resource_rpcs()


## Fish data (FishData species, CaughtFish catches) needs to travel over RPC
## so bites/livewell contents actually reach clients, not just the host --
## SceneMultiplayer refuses to decode Object/Resource arguments by default.
## Safe to allow here: lobbies are Steam-friends-only P2P (GDD), and the
## resources involved are plain @export data with no side-effecting code.
func _allow_resource_rpcs() -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer:
		scene_multiplayer.allow_object_decoding = true


func disconnect_from_lobby() -> void:
	multiplayer.multiplayer_peer = null
	SteamManager.leave_lobby()
	spawned_players.clear()


# ── Map helpers ────────────────────────────────────────────────────────────────

func _get_world() -> Node:
	return get_tree().root.get_node("GameRoot/NetworkRoot/World")


## Public so Rod/EquipmentSlot can resolve the active map for water validation.
func get_current_map() -> Map:
	return _get_current_map()


func _get_current_map() -> Map:
	var world := _get_world()
	if world == null or world.get_child_count() == 0:
		return null
	return world.get_child(0) as Map


func _load_map(map_id: StringName) -> void:
	if not MAP_PATHS.has(map_id):
		push_error("NetworkManager: unknown map_id '%s'" % map_id)
		return
	var path: String = MAP_PATHS[map_id]
	if not ResourceLoader.exists(path):
		push_warning("NetworkManager: map '%s' not yet built at '%s' — skipping load." % [map_id, path])
		return
	var scene: PackedScene = load(path)
	var instance := scene.instantiate()
	_get_world().add_child(instance)


# ── Map replication to clients ─────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _load_map_on_client(map_id: StringName) -> void:
	_load_map(map_id)


# ── Lobby event handlers ───────────────────────────────────────────────────────

func _on_lobby_created(lobby_id: int) -> void:
	var peer := SteamMultiplayerPeer.new()
	var err := peer.create_host(0)
	if err != OK:
		push_error("NetworkManager: SteamMultiplayerPeer.create_host failed: %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	_allow_resource_rpcs()

	_get_spawner()

	# Wait one frame so multiplayer.get_unique_id() returns 1 (host) reliably.
	await get_tree().process_frame

	# Load map BEFORE spawning — spawn points must exist first.
	_load_map(&"lake")

	_spawn_player_for_peer(multiplayer.get_unique_id())


func _on_lobby_joined(lobby_id: int) -> void:
	join_lobby(lobby_id)


# ── MultiplayerAPI callbacks ───────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	# Tell the joining peer which map to load.
	var current_map := _get_current_map()
	if current_map != null:
		_load_map_on_client.rpc_id(peer_id, current_map.map_id)

	# Catch the newly-connected peer up on everyone already spawned (the
	# host, plus any other clients who joined earlier) -- our own spawn
	# notification below only fires going forward.
	for existing_peer_id in spawned_players.keys():
		_notify_player_registered.rpc_id(peer_id, existing_peer_id)

	_spawn_player_for_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if spawned_players.has(peer_id):
		var player: Player = spawned_players[peer_id]
		player.queue_free()
		spawned_players.erase(peer_id)
		peer_player_despawned.emit(peer_id)


func _on_connected_to_server() -> void:
	pass  ## Client connected — host pushes the map RPC and spawns our Player
	## (replicated automatically once _get_spawner() has run, see _ready()).


func _on_connection_failed() -> void:
	run_ended.emit("connection_failed")


func _on_server_disconnected() -> void:
	run_ended.emit("host_disconnected")


# ── Spawn helpers ────────────────────────────────────────────────────────────
## _spawn_player_for_peer (triggering .spawn()) is host-only -- only the
## authority can originate a spawn. But the bookkeeping below (populating
## spawned_players, emitting peer_player_spawned/spawned_local_player) needs
## to run on EVERY peer. It used to live inline in _spawn_player_for_peer,
## which is only ever called host-side -- so a joining client's own
## spawned_players stayed empty forever (breaking anything that looked up
## NetworkManager.spawned_players, e.g. ReelMinigame) and spawned_local_player
## never fired for them (so MainMenu never hid, even though their Player
## node existed and worked underneath).
##
## First fix attempt routed this through MultiplayerSpawner's own "spawned"
## signal -- confirmed it does NOT fire for whoever originates .spawn()
## (only the return value carries the node there), but a second real 2-
## machine test showed the client STILL never registered even as a
## replication receiver, and it also never learned about the HOST's
## pre-existing player (a notification that only fires going forward can't
## retroactively catch up a late joiner). Replaced with an explicit
## broadcast RPC + a poll for the node actually existing locally, since RPCs
## are the one mechanism already proven reliable everywhere else in this
## codebase (bite_started, reel_finished, livewell add/remove).

func _get_spawner() -> void:
	if _player_spawner != null:
		return
	_player_spawner = get_tree().root.get_node_or_null(
		"GameRoot/NetworkRoot/PlayerSpawner"
	) as MultiplayerSpawner
	if _player_spawner == null:
		push_error("NetworkManager: could not find PlayerSpawner node.")
		return
	_player_spawner.spawn_function = Callable(self, "_spawn_player")


func _spawn_player(peer_id: int) -> Node:
	var scene := preload("res://entities/player/player.tscn")
	var player := scene.instantiate() as Player
	# Name must be unique and deterministic so MultiplayerSpawner can replicate it.
	player.name = str(peer_id)
	player.setup_for_peer.call_deferred(peer_id)

	# Position at the map's spawn point if a map is loaded.
	var map := _get_current_map()
	if map != null:
		var index := spawned_players.size()  # 0 for first player, 1 for second, etc.
		var spawn: Marker3D = map.get_spawn_point(index)
		if spawn != null:
			# Deferred so the node enters the tree before transform is set.
			player.set_deferred("global_transform", spawn.global_transform)

	return player


func _spawn_player_for_peer(peer_id: int) -> void:
	_get_spawner()
	if _player_spawner == null:
		return

	var player: Player = _player_spawner.spawn(peer_id) as Player
	if player == null:
		push_error("NetworkManager: spawner returned null for peer %d" % peer_id)
		return

	# The spawning peer (always the host) has the node right here from the
	# return value -- register directly rather than round-tripping an RPC
	# to itself.
	_register_spawned_player(peer_id, player)
	# Tell every OTHER peer this player now exists so they run the same
	# registration once their own replicated copy of the node shows up.
	_notify_player_registered.rpc(peer_id)


## Received by every peer (host included, but it already registered directly
## above and _register_when_ready's has() guard makes the call_local no-op).
@rpc("authority", "call_local", "reliable")
func _notify_player_registered(peer_id: int) -> void:
	_register_when_ready(peer_id)


## The MultiplayerSpawner replication that actually constructs the node and
## this RPC travel over separate channels with no guaranteed relative
## ordering, so don't assume the node is already there -- poll briefly.
func _register_when_ready(peer_id: int, attempts_left: int = 120) -> void:
	if spawned_players.has(peer_id):
		return

	var player := get_tree().root.get_node_or_null(
		"GameRoot/NetworkRoot/Players/%d" % peer_id
	) as Player
	if player != null:
		_register_spawned_player(peer_id, player)
		return

	if attempts_left <= 0:
		push_warning("NetworkManager: player %d's node never appeared after spawn notification" % peer_id)
		return

	await get_tree().process_frame
	_register_when_ready(peer_id, attempts_left - 1)


func _register_spawned_player(peer_id: int, player: Player) -> void:
	spawned_players[peer_id] = player
	peer_player_spawned.emit(peer_id, player)

	if peer_id == multiplayer.get_unique_id():
		spawned_local_player.emit(player)
