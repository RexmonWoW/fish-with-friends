extends Node

func _ready() -> void:
	print("--- Autoload check ---")
	print("EventBus: ", EventBus)
	print("AudioManager: ", AudioManager)
	print("SteamManager: ", SteamManager)
	print("NetworkManager: ", NetworkManager)
	print("RunState: ", RunState)
	print("--- Steam check ---")
	print("Steam class exists: ", Steam != null)
	print("Steam running: ", Steam.isSteamRunning())
