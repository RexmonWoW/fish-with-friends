class_name Lobby
extends Node3D

## Bare-bones walkable pre-round space. NOT a Map -- no fishing happens
## here, so none of Map's contract (Livewell, Boat, water_surface) applies.
## Just spawn points and a trigger to start the round. The real GDD lobby
## (shop counter, mirror, trophy case, ready-up dock) is a future dispatch;
## this only covers "walk around, then head out to fish."

@onready var spawn_points: Node3D = $PlayerSpawnPoints
@onready var start_trigger: Area3D = $StartTrigger


func _ready() -> void:
	start_trigger.body_entered.connect(_on_start_trigger_entered)


## Same signature as Map.get_spawn_point() so NetworkManager can treat
## whatever's currently loaded (lobby or a real map) the same way.
func get_spawn_point(player_index: int) -> Marker3D:
	var idx := clampi(player_index, 0, spawn_points.get_child_count() - 1)
	return spawn_points.get_child(idx) as Marker3D


func _on_start_trigger_entered(body: Node) -> void:
	var player := body as Player
	if player == null or player.peer_id != multiplayer.get_unique_id():
		return
	NetworkManager.request_start_round()
