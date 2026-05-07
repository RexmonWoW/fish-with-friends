class_name VisualFish
extends Node3D

## Cosmetic fish. Host-authoritative position, synced to clients.
## Pure ambience — never causes bites, never converts to Fish.

@export var species: FishData


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	# TODO: wander/seek behavior — Minigame Logic chat owns this
	pass
