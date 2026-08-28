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


# ── Local input (only runs for the rod owner) ─────────────────────────────────

func start_charge() -> void:
	if state != CastState.IDLE:
		return
	state = CastState.CHARGING
	charge_start_time = Time.get_ticks_msec() / 1000.0
	current_power = 0.0
	EventBus.cast_charge_started.emit(owner_peer_id)


func release_cast() -> void:
	if state != CastState.CHARGING:
		return
	if player_camera == null:
		push_warning("Rod: release_cast called but player_camera not assigned.")
		state = CastState.IDLE
		return
	var cam_origin := player_camera.global_transform.origin
	var cam_forward := -player_camera.global_transform.basis.z
	_request_cast.rpc(cam_origin, cam_forward, current_power)
	state = CastState.ANIMATING  # optimistic local state


func _process(_delta: float) -> void:
	# Only run for the local owner of this rod.
	if owner_peer_id == 0 or owner_peer_id != multiplayer.get_unique_id():
		return

	if state == CastState.CHARGING:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - charge_start_time
		current_power = clampf(elapsed / charge_time_to_full, 0.0, 1.0)
		EventBus.cast_charge_updated.emit(current_power, owner_peer_id)

	if Input.is_action_just_pressed("cast"):
		start_charge()

	if Input.is_action_just_released("cast"):
		release_cast()


# ── RPC 1: Client → Host ──────────────────────────────────────────────────────

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
	# Cast distance is horizontal reach, not full 3D look-direction distance --
	# otherwise aiming down at the water (as any player naturally would while
	# fishing) sends the endpoint's Y far below the surface and the water
	# raycast below never reaches it. GDD: aim direction + power -> distance,
	# not literal 3D line-of-sight.
	var horizontal := Vector3(cam_forward.x, 0.0, cam_forward.z)
	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3(0.0, 0.0, -1.0)  # looking straight up/down — fall back
	var direction := horizontal.normalized()

	var distance := maxf(power * max_cast_distance, min_cast_distance)
	var aim_point := Vector3(cam_origin.x, cam_origin.y, cam_origin.z) + direction * distance

	# Snap to the actual water surface height, not the aim point's height --
	# otherwise the lure/bobber ends up floating at eye level instead of
	# sitting on the water.
	var water_point = WaterValidator.find_water_point(aim_point, current_map)
	if water_point == null:
		_cast_failed.rpc(&"invalid_water")
		return

	_cast_landed.rpc(water_point, 0.5)  # 0.5 s lure flight — placeholder


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


# ── RPC 4: Client → Host, local reel minigame resolved ─────────────────────────
## Reel itself runs entirely client-side (ReelMinigame). This just tells the
## host to despawn the Fish it's holding for this rod. The owning client
## already reset its own state to IDLE optimistically before calling this.

func request_reel_resolution(success: bool, was_perfect: bool) -> void:
	_request_reel_resolution.rpc(success, was_perfect)


@rpc("any_peer", "call_local", "reliable")
func _request_reel_resolution(success: bool, was_perfect: bool) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()
	var effective_sender := 1 if sender == 0 else sender
	if effective_sender != owner_peer_id:
		return  # Wrong rod — reject silently.

	var bite_manager: Node = get_tree().get_first_node_in_group("bite_event_manager")
	if bite_manager:
		bite_manager.resolve_reel(owner_peer_id, success, was_perfect)
