class_name Rod
extends Node3D

enum CastState { IDLE, CHARGING, ANIMATING, WAITING_BITE, REELING }

@export var max_cast_distance: float = 30.0  ## meters from rod tip
@export var min_cast_distance: float = 3.0
@export var charge_time_to_full: float = 1.5  ## seconds of hold to reach max power

var state: CastState = CastState.IDLE
var charge_start_time: float = 0.0
var current_power: float = 0.0      ## 0.0–1.0, NOT replicated
var owner_peer_id: int = 0          ## set by EquipmentSlot on equip
var player_camera: Camera3D = null  ## set by EquipmentSlot on equip

## Set by the host when a map is loaded. Passed to WaterValidator.
var current_map: Node3D = null


# ── Local input stubs (Minigame Logic fills these in) ─────────────────────────

func start_charge() -> void:
	pass

func release_cast() -> void:
	# Minigame Logic completes this. When ready it should call:
	#   _request_cast.rpc(player_camera.global_transform.origin,
	#                     -player_camera.global_transform.basis.z,
	#                     current_power)
	pass


# ── RPC 1: Client → Host ───────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func _request_cast(cam_origin: Vector3, cam_forward: Vector3, power: float) -> void:
	# Only the host validates. Clients receive this via call_local but exit here.
	if not multiplayer.is_server():
		return

	# get_remote_sender_id() returns 0 when the host calls locally — treat as peer 1.
	var sender := multiplayer.get_remote_sender_id()
	var effective_sender := 1 if sender == 0 else sender
	if effective_sender != owner_peer_id:
		return  # Wrong rod — reject silently.

	power = clampf(power, 0.0, 1.0)
	_validate_and_land_cast(cam_origin, cam_forward, power)


# ── Host-only validation (not an RPC) ─────────────────────────────────────────

func _validate_and_land_cast(cam_origin: Vector3, cam_forward: Vector3, power: float) -> void:
	var direction := cam_forward.normalized()
	var distance := maxf(power * max_cast_distance, min_cast_distance)
	var endpoint := cam_origin + direction * distance

	if not WaterValidator.is_valid_water(endpoint, current_map):
		_cast_failed.rpc(&"invalid_water")
		return

	_cast_landed.rpc(endpoint, 0.5)  # 0.5 s lure flight — placeholder


# ── RPC 2: Host → All clients, cast confirmed ─────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _cast_landed(endpoint: Vector3, lure_flight_seconds: float) -> void:
	state = CastState.ANIMATING
	EventBus.cast_landed.emit(endpoint, lure_flight_seconds, owner_peer_id)


# ── RPC 3: Host → All clients, cast rejected ──────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _cast_failed(reason: StringName) -> void:
	state = CastState.IDLE
	EventBus.cast_failed.emit(reason, owner_peer_id)
