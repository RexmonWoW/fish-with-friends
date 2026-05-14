extends Node

## Owns the MultiplayerAPI lifecycle on top of GodotSteam's SteamMultiplayerPeer.
## Drives player spawn/despawn. Listens to SteamManager for lobby events.

# ── Signals ────────────────────────────────────────────────────────────────────
signal spawned_local_player(player: Player)
signal peer_player_spawned(peer_id: int, player: Player)
signal peer_player_despawned(peer_id: int)
signal run_ended(reason: String)

# ── State ──────────────────────────────────────────────────────────────────────
var spawned_players: Dictionary = {}  ## peer_id (int) → Player node

var _player_spawner: MultiplayerSpawner = null


func _ready() -> void:
	# Listen to SteamManager lobby events.
	SteamManager.lobby_created.connect(_on_lobby_created)
	SteamManager.lobby_joined.connect(_on_lobby_joined)

	# MultiplayerAPI peer lifecycle.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ── Public API ─────────────────────────────────────────────────────────────────

func host_lobby() -> void:
	SteamManager.create_lobby(4)


func join_lobby(lobby_id: int) -> void:
	## Called after SteamManager fires lobby_joined with the resolved lobby ID.
	## We need the host's Steam ID to connect as a client.
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


# ── Lobby event handlers ───────────────────────────────────────────────────────

func _on_lobby_created(lobby_id: int) -> void:
	## We created the lobby — become the host peer.
	var peer := SteamMultiplayerPeer.new()
	var err := peer.create_host(0)  ## port 0 = let GodotSteam pick
	if err != OK:
		push_error("NetworkManager: SteamMultiplayerPeer.create_host failed: %d" % err)
		return
	multiplayer.multiplayer_peer = peer

	## Spawn the host's own player immediately — peer_connected won't fire for self.
	_get_spawner()
	## Wait one frame so multiplayer.get_unique_id() returns 1 (host) instead of 0.
	await get_tree().process_frame
	_spawn_player_for_peer(multiplayer.get_unique_id())


func _on_lobby_joined(lobby_id: int) -> void:
	## We joined someone else's lobby.
	join_lobby(lobby_id)


# ── MultiplayerAPI callbacks ───────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	## Only the host spawns players.
	if not multiplayer.is_server():
		return
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
	## Client successfully connected — host will spawn our Player via spawner.
	pass


func _on_connection_failed() -> void:
	run_ended.emit("connection_failed")


func _on_server_disconnected() -> void:
	## Host left — run is over.
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
	## Name must be unique and deterministic so MultiplayerSpawner can replicate it.
	player.name = str(peer_id)
	## Deferred so the node enters the scene tree before setup runs.
	player.setup_for_peer.call_deferred(peer_id)
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

	## Tell the menu (and anyone else listening) if this is our local player.
	if peer_id == multiplayer.get_unique_id():
		spawned_local_player.emit(player)
