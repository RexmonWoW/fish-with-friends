class_name Boat
extends Node3D

## Stationary boat. No driving, no anchor.
## Instanced by maps that have uses_boat = true.
## Does NOT own the livewell — that is the map's responsibility.
## Architecture stub — geometry and capsize corners come from Art and Polish.
##
## Purely visual "capsized" tilt on the hull MESH only -- not the Hull
## StaticBody3D's collision, and not this node's own CapsizeCorners
## children. Tilting either of those would fling players around
## unpredictably and move the swim-to targets; CapsizeManager already gets
## players into the water directly and deterministically, independent of
## this animation.

const TILT_ANGLE: float = -0.35  ## radians, ~20 degrees
const TILT_DURATION: float = 0.6

@onready var _hull_mesh: MeshInstance3D = $Hull/HullMesh


func _ready() -> void:
	EventBus.capsize_started.connect(func(_required): _set_tilt(TILT_ANGLE))
	EventBus.capsize_resolved.connect(func(): _set_tilt(0.0))


func _set_tilt(angle: float) -> void:
	var tween := create_tween()
	tween.tween_property(_hull_mesh, "rotation:z", angle, TILT_DURATION)
