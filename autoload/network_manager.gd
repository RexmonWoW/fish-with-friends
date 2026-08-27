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
	pass  ## Client connected — host replicates map and spawns our Player.


func _on_connection_failed() -> void:
	run_ended.emit("connection_failed")


func _on_server_disconnected() -> void:
	run_ended.emit("host_disconnected")


# ── Spawn helpers (host-only) ──────────────────────────────────────────────────

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

	spawned_players[peer_id] = player
	peer_player_spawned.emit(peer_id, player)

	if peer_id == multiplayer.get_unique_id():
		spawned_local_player.emit(player)
