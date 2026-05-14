extends Control

@onready var status_label: Label  = $StatusLabel
@onready var host_button: Button  = $VBoxContainer/HostButton
@onready var solo_button: Button  = $VBoxContainer/SoloButton
@onready var join_button: Button  = $VBoxContainer/JoinButton
@onready var quit_button: Button  = $VBoxContainer/QuitButton

## Tracks which button was last pressed so _on_lobby_created knows
## whether to open the invite overlay.
var _hosting_with_invite: bool = false


func _ready() -> void:
	join_button.disabled = true

	# Button signals.
	solo_button.pressed.connect(_on_solo_button_pressed)
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

	# Steam / network signals.
	SteamManager.lobby_created.connect(_on_lobby_created)
	SteamManager.lobby_joined.connect(_on_lobby_joined)
	SteamManager.lobby_create_failed.connect(_on_lobby_create_failed)
	SteamManager.lobby_join_failed.connect(_on_lobby_join_failed)
	NetworkManager.spawned_local_player.connect(_on_spawned_local_player)

	if not SteamManager.init_steam():
		status_label.text = "Steam not running — launch via Steam."
		solo_button.disabled = true
		host_button.disabled = true


# ── Button handlers ────────────────────────────────────────────────────────────

func _on_solo_button_pressed() -> void:
	_hosting_with_invite = false
	status_label.text = "Creating lobby..."
	_set_buttons_disabled(true)
	NetworkManager.host_lobby()


func _on_host_button_pressed() -> void:
	_hosting_with_invite = true
	status_label.text = "Creating lobby..."
	_set_buttons_disabled(true)
	NetworkManager.host_lobby()


func _on_join_button_pressed() -> void:
	status_label.text = "Joining..."


func _on_quit_button_pressed() -> void:
	get_tree().quit()


# ── SteamManager / NetworkManager callbacks ────────────────────────────────────

func _on_lobby_created(_lobby_id: int) -> void:
	if _hosting_with_invite:
		status_label.text = "Lobby ready! Inviting friends..."
		SteamManager.open_invite_overlay()
	else:
		status_label.text = "Lobby ready! Starting solo..."


func _on_lobby_joined(_lobby_id: int) -> void:
	status_label.text = "Joined lobby! Waiting for game..."


func _on_lobby_create_failed(reason: String) -> void:
	status_label.text = "Failed to create lobby: %s" % reason
	_set_buttons_disabled(false)


func _on_lobby_join_failed(reason: String) -> void:
	status_label.text = "Failed to join: %s" % reason
	_set_buttons_disabled(false)


func _on_spawned_local_player(_player: Player) -> void:
	hide()


# ── Helpers ────────────────────────────────────────────────────────────────────

func _set_buttons_disabled(disabled: bool) -> void:
	solo_button.disabled = disabled
	host_button.disabled = disabled
