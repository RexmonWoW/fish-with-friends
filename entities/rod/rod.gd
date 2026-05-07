class_name Rod
extends Node3D

enum CastState { IDLE, CHARGING, ANIMATING, REELING }

@export var max_cast_distance: float = 30.0  ## meters from rod tip
@export var min_cast_distance: float = 3.0
@export var charge_time_to_full: float = 1.5  ## seconds of hold to reach max power

var state: CastState = CastState.IDLE
var charge_start_time: float = 0.0
var current_power: float = 0.0  ## 0.0 to 1.0
var owner_peer_id: int = 0  ## set when rod is spawned for a player

# Local input handlers (called by player_input.gd)
func start_charge() -> void: pass
func release_cast() -> void: pass  # sends RPC to host

# Host-only entry point
@rpc("any_peer", "call_local", "reliable")
func _request_cast(cam_origin: Vector3, cam_forward: Vector3, power: float) -> void: pass

# Host-only validation
func _validate_and_land_cast(cam_origin: Vector3, cam_forward: Vector3, power: float) -> void: pass

# Broadcast to all clients (called by host after validation)
@rpc("authority", "call_local", "reliable")
func _cast_landed(endpoint: Vector3, lure_flight_seconds: float) -> void: pass

# Failed cast (out of bounds, hit dry land, etc.)
@rpc("authority", "call_local", "reliable")
func _cast_failed(reason: StringName) -> void: pass
