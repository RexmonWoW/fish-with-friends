class_name Map
extends Node3D

## Base class every map extends. Declares the contract every map must satisfy.
## Architecture rules:
##   - Boat is OPTIONAL per map (Ice Lake uses icehouse instead).
##   - Livewell is REQUIRED in every map's PlayableArea.
##   - PlayerSpawnPoints must have 4 Marker3D children (unused slots remain empty for solo).
##   - Water surface(s) must be in group "water_surface" so WaterValidator can find them.

@export var map_id: StringName = &""       ## e.g. &"lake", &"ocean", &"ice_lake"
@export var uses_boat: bool = true         ## false for Ice Lake (icehouse instead)

@onready var environment: Node3D   = $Environment
@onready var playable_area: Node3D = $PlayableArea
@onready var livewell: Node3D      = $PlayableArea/Livewell
@onready var spawn_points: Node3D  = $PlayableArea/PlayerSpawnPoints
@onready var lighting: Node3D      = $Lighting


func _ready() -> void:
	_validate_contract()


func _validate_contract() -> void:
	## Fail loud at scene load — no silent breakage three systems later.
	assert(map_id != &"", "Map missing map_id")
	assert(livewell != null, "Map missing required PlayableArea/Livewell node")
	assert(spawn_points != null, "Map missing PlayableArea/PlayerSpawnPoints")
	assert(spawn_points.get_child_count() >= 4,
		"Map needs 4 PlayerSpawnPoints (Marker3D each)")
	if uses_boat:
		assert(has_node("PlayableArea/Boat"),
			"Map declares uses_boat=true but PlayableArea/Boat is missing")


func get_spawn_point(player_index: int) -> Marker3D:
	var idx := clampi(player_index, 0, 3)
	return spawn_points.get_child(idx) as Marker3D
