extends Node

## Single source of truth for Steam state.
## Wraps GodotSteam Steam API calls.
## NetworkManager listens to our signals to drive the MultiplayerAPI.

# ── Signals ────────────────────────────────────────────────────────────────────
signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)
signal lobby_create_failed(reason: String)
signal lobby_join_failed(reason: String)

# ── State ──────────────────────────────────────────────────────────────────────
var current_lobby_id: int = 0  ## 0 = no active lobby
var is_host: bool = false


func _ready() -> void:
	# Wire up GodotSteam callbacks.
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)

	# If the game was launched via a Steam invite (user wasn't already in-game),
	# the lobby ID is passed on the command line as: +connect_lobby <id>
	_check_launch_command_line()
	
func _process(_delta: float) -> void:
	Steam.run_callbacks()


# ── Public API ─────────────────────────────────────────────────────────────────

func init_steam() -> bool:
	## Defensive init — project settings already call this at startup via
	## initialization/initialize_on_startup, but we call it explicitly here
	## so the return value is available to callers.
	return Steam.isSteamRunning()


func create_lobby(max_players: int = 4) -> void:
	## LOBBY_TYPE_INVISIBLE = invite-only. Friends join via Steam overlay only.
	Steam.createLobby(Steam.LOBBY_TYPE_INVISIBLE, max_players)


func open_invite_overlay() -> void:
	if current_lobby_id == 0:
		push_warning("SteamManager: tried to open invite overlay with no active lobby.")
		return
	Steam.activateGameOverlayInviteDialog(current_lobby_id)


func leave_lobby() -> void:
	if current_lobby_id == 0:
		return
	Steam.leaveLobby(current_lobby_id)
	current_lobby_id = 0
	is_host = false


# ── Steam callbacks ────────────────────────────────────────────────────────────

func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != Steam.RESULT_OK:
		lobby_create_failed.emit("Steam error code: %d" % result)
		return
	current_lobby_id = lobby_id
	is_host = true
	lobby_created.emit(lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	## Fires when we join a lobby. Steam fires this for BOTH:
	##  - lobbies we created (immediately after lobby_created)
	##  - lobbies we joined via invite
	## We only emit our `lobby_joined` signal in the second case — otherwise
	## NetworkManager would try to become a client of its own host.
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_join_failed.emit("Join response: %d" % response)
		return
	# Skip if this is our own lobby (we already handled it in _on_lobby_created).
	if is_host and lobby_id == current_lobby_id:
		return
	current_lobby_id = lobby_id
	is_host = false
	lobby_joined.emit(lobby_id)


func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	## Fires when user accepts a Steam overlay invite while the game is already running.
	Steam.joinLobby(lobby_id)


# ── Launch command line (accepted invite before game was running) ───────────────

func _check_launch_command_line() -> void:
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "+connect_lobby" and i + 1 < args.size():
			var lobby_id := int(args[i + 1])
			if lobby_id > 0:
				Steam.joinLobby(lobby_id)
			break
