class_name Player
extends RigidBody3D

## One player body. Spawned by PlayerSpawner for every peer including the host.
## Movement is client-authoritative — each client moves their own body locally.
## Host still owns fish spawns, livewell, catches, bite events.
##
## Architecture rule (from General): physics chaos is for movement only.
## Body and camera have SEPARATE orientations — body soft-follows camera yaw,
## but a shove to the body NEVER affects camera direction, cast aim, or reel input.

var peer_id: int = 0

## True while swimming during a capsize (CapsizeManager -> enter_swim_physics/
## exit_swim_physics). Free XZ movement, no gravity, no jump -- GDD's capsize
## minigame doesn't need real depth/diving, just "swim to a corner." Only
## ever set for the LOCAL player -- see enter_swim_physics()'s comment.
var is_swimming: bool = false

## True on every peer's mirror of EVERY currently-swimming player (not just
## the local one) -- purely visual (model pose + bob), so unlike is_swimming
## it's driven directly by the EventBus broadcast, not scoped to "my own
## player." Capsize is an "everyone at once" event, so every peer should see
## every player enter/exit the swim pose the same way GDD's "full equipment
## visibility to other players at all times" already applies to held items.
var _swim_visual_active: bool = false

# Node references — assigned in _ready, used by EquipmentSlot and Minigame Logic.
@onready var body_pivot: Node3D        = $BodyPivot
@onready var camera_rig: Node3D       = $CameraRig
@onready var camera_pitch: Node3D     = $CameraRig/CameraPitch
@onready var camera: Camera3D         = $CameraRig/CameraPitch/Camera3D
@onready var equipment_slot: EquipmentSlot = $EquipmentSlot

# ── Tunables ──────────────────────────────────────────────────────────────────
@export var mouse_sensitivity: float   = 0.002
@export var body_yaw_follow_speed: float = 8.0
@export var move_force: float          = 1600.0
@export var max_speed: float           = 5.0
@export var jump_force: float          = 400.0


func _ready() -> void:
	# Physics body should not tip over.
	lock_rotation = true

	# Runs on EVERY peer for EVERY spawned Player instance (not owner-gated)
	# -- see _swim_visual_active's doc comment above.
	EventBus.capsize_started.connect(func(_required): _apply_swim_visual(true))
	EventBus.capsize_resolved.connect(func(): _apply_swim_visual(false))


## Called by PlayerSpawner immediately after this node is added to the scene.
## Sets up peer ownership, equipment, and multiplayer authority.
func setup_for_peer(id: int) -> void:
	peer_id = id

	# Client-authoritative: each peer replicates their own player.
	$PlayerSync.set_multiplayer_authority(id)

	# Hand the peer ID to EquipmentSlot so the rod gets the right owner.
	equipment_slot.setup_for_peer(id)

	_tint_body_for_peer(id)

	# Local player only: capture the mouse and activate THIS player's camera.
	# Nothing ever made a camera "current" before -- harmless with one
	# player (Godot defaults the sole Camera3D to current), but with two+
	# players every machine has multiple Camera3D nodes and Godot picks
	# whichever activated first (the host's) for every viewport, which is
	# exactly "both machines see through player one's camera."
	if peer_id == multiplayer.get_unique_id():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		camera.current = true


## Deterministic per-peer color (same trick as Livewell's per-species tint)
## so players are actually distinguishable from each other, not just visible.
func _tint_body_for_peer(id: int) -> void:
	var body_mesh := body_pivot.get_node_or_null("PlayerModel/BodyMesh") as MeshInstance3D
	if body_mesh == null:
		return
	var hue := float(hash(id) % 360) / 360.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(hue, 0.55, 0.85)
	body_mesh.set_surface_override_material(0, material)


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id():
		return

	# Esc releases mouse; click recaptures.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return

	# Camera rotation from mouse delta.
	# CRITICAL: only camera_rig and camera_pitch rotate here — NEVER body_pivot.
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_rig.rotation.y -= event.relative.x * mouse_sensitivity
		camera_pitch.rotation.x -= event.relative.y * mouse_sensitivity
		camera_pitch.rotation.x = clampf(camera_pitch.rotation.x, -PI / 2.0 * 0.95, PI / 2.0 * 0.95)


func _physics_process(delta: float) -> void:
	if peer_id != multiplayer.get_unique_id():
		return

	if is_swimming:
		_apply_movement_impulse(_get_move_direction(), delta)
		linear_velocity.y = 0.0  # stay level at the surface, no gravity drift
		_soft_follow_body_yaw(delta)
		return

	# Planted while a cast is out -- no walking/jumping around with a taut
	# line. Camera look and the rod's own inputs (charge/reel) still work.
	var rod := equipment_slot.equipped_item as Rod
	var can_move := rod == null or rod.state == Rod.CastState.IDLE

	if can_move:
		_apply_movement_impulse(_get_move_direction(), delta)
	_soft_follow_body_yaw(delta)

	if can_move and Input.is_action_just_pressed("jump") and _is_grounded():
		apply_central_impulse(Vector3.UP * jump_force)


func _process(_delta: float) -> void:
	if _swim_visual_active:
		_update_swim_bob()

	if peer_id != multiplayer.get_unique_id():
		return
	# Reuses the "cast" input, same as EquipmentSlot repurposing "toss_fish"
	# for tossing back a held fish -- while swimming there's no rod in play
	# at all (Rod._process gates on is_swimming), so no conflict.
	if is_swimming and Input.is_action_just_pressed(&"cast"):
		_try_claim_nearest_corner()


func _try_claim_nearest_corner() -> void:
	var capsize_manager: Node = get_tree().get_first_node_in_group("capsize_manager")
	if capsize_manager == null:
		return
	var index: int = capsize_manager.get_nearest_corner_index(global_position)
	if index == -1:
		return
	capsize_manager.request_claim_corner(index)


## Physics-only. Called by CapsizeManager, on the LOCAL player only --
## global_position/movement is client-authoritative per player, so the host
## can't just flip this remotely and have it stick, same reasoning as
## _reposition_local_player() in NetworkManager. Visual pose is separate
## (_apply_swim_visual below), since every peer needs to see every player
## swimming, not just their own.
func enter_swim_physics() -> void:
	is_swimming = true
	gravity_scale = 0.0
	linear_velocity = Vector3.ZERO


func exit_swim_physics() -> void:
	is_swimming = false
	gravity_scale = 1.0
	linear_velocity = Vector3.ZERO


## Tilts the placeholder capsule to a horizontal "swimming" pose instead of
## just walking-on-the-water upright -- real swim animation is Art &
## Polish's, this is just enough to read as "swimming" rather than nothing
## changing at all. Runs for every player on every peer (see
## _swim_visual_active), and separately stows/unstows the rod to the back
## attach point while active, same as holding a fish does.
func _apply_swim_visual(swimming: bool) -> void:
	_swim_visual_active = swimming
	var model := body_pivot.get_node_or_null("PlayerModel") as Node3D
	if model:
		model.rotation.x = -PI / 2.0 if swimming else 0.0
		model.position.y = 0.0
	if swimming:
		equipment_slot.stow_rod_for_swim()
	else:
		equipment_slot.unstow_rod_after_swim()


func _update_swim_bob() -> void:
	var model := body_pivot.get_node_or_null("PlayerModel") as Node3D
	if model == null:
		return
	model.position.y = sin(Time.get_ticks_msec() / 1000.0 * 2.0) * 0.05


# ── Movement helpers ──────────────────────────────────────────────────────────

func _get_move_direction() -> Vector3:
	var forward := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var strafe  := Input.get_action_strength("move_right")   - Input.get_action_strength("move_left")

	if forward == 0.0 and strafe == 0.0:
		return Vector3.ZERO

	# Local direction — movement follows camera look, not body orientation.
	var local_dir := Vector3(strafe, 0.0, -forward).normalized()
	var world_dir := camera_rig.global_transform.basis * local_dir
	world_dir.y = 0.0
	if world_dir.length_squared() > 0.0001:
		world_dir = world_dir.normalized()
	return world_dir


func _apply_movement_impulse(direction: Vector3, delta: float) -> void:
	if direction == Vector3.ZERO:
		return

	apply_central_impulse(direction * move_force * delta)

	# Clamp horizontal speed.
	var horiz := Vector2(linear_velocity.x, linear_velocity.z)
	if horiz.length() > max_speed:
		horiz = horiz.normalized() * max_speed
		linear_velocity = Vector3(horiz.x, linear_velocity.y, horiz.y)


func _soft_follow_body_yaw(delta: float) -> void:
	# Body yaw lags behind camera — bumps don't affect camera direction.
	body_pivot.rotation.y = lerp_angle(
		body_pivot.rotation.y,
		camera_rig.rotation.y,
		body_yaw_follow_speed * delta
	)


func _is_grounded() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * 1.0
	)
	query.exclude = [self]
	var result := space.intersect_ray(query)
	return not result.is_empty()
