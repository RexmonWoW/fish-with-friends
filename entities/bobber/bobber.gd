class_name Bobber
extends Node3D

## GDD Reel Mechanic / Line Tangling: the physical lure/bobber a rod casts
## out. Its own independent node at the scene root -- NEVER parented to
## Rod/Player -- same as every other independent gameplay object in this
## codebase (Fish, VisualFish). Universal pattern in fishing games
## (Minecraft's and Terraria's bobbers are both standalone projectile
## entities, not attached to the player) for the same reason: parented
## under the camera-attached Rod, it had to fight the parent's transform
## every single frame just to stay in place, and during a fast camera
## swing that fight visibly lost ("goes everywhere" when swinging the
## camera -- almost certainly RigidBody3D physics interpolation smoothing
## the PARENT's rendered transform after this node's own corrective
## position was computed against the parent's pre-interpolation one). An
## unparented node has no parent transform to fight in the first place.
##
## Spawned by Rod/LureAnimator on cast_landed, one per owner, independently
## on every peer (same "one broadcast, replay locally" pattern the arc
## itself already used) -- despawned when the rod returns to IDLE.
## LureAnimator reads this node's global_position each frame to draw the
## cosmetic line and size the tangle-detection collider; authority for
## WHERE the bobber is hasn't changed at all, only where the node lives in
## the scene tree.

signal landed

## Set by whoever spawns this (LureAnimator) right after instantiating --
## matched against EventBus.reel_fight_state_updated's payload keys.
var owner_peer_id: int = 0

var _mesh: MeshInstance3D = null
var _active_tween: Tween = null
var _anchor_position: Vector3 = Vector3.ZERO
var _landed_at: float = 0.0  ## Time.get_ticks_msec()/1000 when the arc completed
var _drift_seed: float = 0.0

var _fight_position: Vector3 = Vector3.ZERO
var _has_fight_position: bool = false

## GDD Line Tangling: "Landed bobbers drift slowly in a random direction
## while waiting for a bite (small radius) -- makes lines crossing more
## common." Deterministic (seeded from the landing spot), not a true
## per-peer random walk -- every peer's own Bobber instance computes the
## identical drift offset from the same seed + elapsed time, no extra sync
## needed. Matters because tangle detection reads THIS node's own
## global_position (via LureAnimator) -- a host/client mismatch would mean
## what one machine sees crossing isn't what the host's own tangle check
## actually used.
const DRIFT_RADIUS: float = 0.5

## Playtest: "pops when it lands" -- sampling the drift sine at absolute
## elapsed engine time meant the very first sample right after landing was
## already some arbitrary non-zero offset, not a smooth start from the true
## landing point. Fixed at the root instead of papering over it with an
## easing lerp: drift magnitude ramps in linearly from zero over this many
## seconds of time SINCE LANDING (not absolute time), so it's genuinely
## zero the instant the bobber lands and eases into drifting.
const DRIFT_RAMP_SECONDS: float = 1.5

## Eases toward the broadcast reel-fight position instead of snapping to
## it, so the WAITING_BITE -> REELING transition glides rather than pops,
## and a sideways tug (ReelFightManager's QTE kick) reads as a flick
## instead of a jump cut. "Doesn't need to be exact" per direction.
const FIGHT_POSITION_SMOOTH_RATE: float = 6.0

# Tunable apex height as a fraction of horizontal distance -- matches the
# old cast-arc tuning (was 0.3, made casts look like they launched straight
# up rather than out over the water for typical distances).
const APEX_FRACTION: float = 0.12


func _ready() -> void:
	add_to_group("bobber")
	_build_visual()
	EventBus.reel_fight_state_updated.connect(_on_fight_state_updated)


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	_mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.15, 0.15)  # red bobber top, placeholder
	_mesh.set_surface_override_material(0, material)
	add_child(_mesh)


func play_arc(start_pos: Vector3, end_pos: Vector3, duration: float) -> void:
	if _active_tween:
		_active_tween.kill()

	global_position = start_pos

	_active_tween = create_tween()
	# Drive progress 0 → 1 via a single interpolated value, sampled each frame.
	_active_tween.tween_method(
		func(t: float) -> void:
			global_position = position_at(start_pos, end_pos, t),
		0.0, 1.0, duration
	)
	_active_tween.tween_callback(_on_arc_complete)


## The exact parabola play_arc draws, exposed so Rod's arc-collision sweep
## (GDD Casting: "the whole flight path is checked, not just the endpoint")
## can step along the SAME curve the bobber will actually be seen following
## -- a sweep using different math than the visual arc could hit (or miss)
## something the player never actually saw the bobber cross.
static func position_at(start_pos: Vector3, end_pos: Vector3, t: float) -> Vector3:
	var horizontal_dist := Vector2(end_pos.x - start_pos.x, end_pos.z - start_pos.z).length()
	var apex_height: float = horizontal_dist * APEX_FRACTION
	# Lerp XZ linearly, Y parabolically (apex at t = 0.5).
	var pos := start_pos.lerp(end_pos, t)
	pos.y += apex_height * 4.0 * t * (1.0 - t)  # standard parabola through 0,apex,0
	return pos


func _on_arc_complete() -> void:
	_active_tween = null
	_anchor_position = global_position
	_landed_at = Time.get_ticks_msec() / 1000.0
	_drift_seed = float(hash(_anchor_position) % 100000) / 100000.0 * TAU
	# Stays here, floating at the landing point, until the reel resolves
	# (see _process below) -- doesn't hide/despawn itself on landing.
	landed.emit()


## Review finding: this only ever SET the flag, never cleared it -- once a
## fight ended (peer no longer in the broadcast payload, e.g. resolve_reel/
## cancel_fight erased it host-side but other fights are still keeping the
## broadcast alive), the bobber kept rendering at its last-known fight
## position, frozen, instead of falling back to drift. Whichever it is
## this tick is the truth.
func _on_fight_state_updated(states: Dictionary) -> void:
	if states.has(owner_peer_id):
		_fight_position = states[owner_peer_id]
		_has_fight_position = true
	else:
		_has_fight_position = false


func _process(delta: float) -> void:
	if _has_fight_position:
		global_position = global_position.lerp(
			_fight_position, clampf(FIGHT_POSITION_SMOOTH_RATE * delta, 0.0, 1.0)
		)
	elif _active_tween == null:
		global_position = _anchor_position + _compute_drift()


## Two mismatched sine frequencies per axis reads as an organic, non-
## repeating wander rather than tracing a perfect circle, while staying a
## pure function of (seed, elapsed-since-landing) -- fully deterministic,
## no state to keep in sync across peers.
func _compute_drift() -> Vector3:
	var elapsed := Time.get_ticks_msec() / 1000.0 - _landed_at
	var ramp := clampf(elapsed / DRIFT_RAMP_SECONDS, 0.0, 1.0)
	var t := elapsed + _drift_seed
	var x := sin(t * 0.15) * 0.6 + sin(t * 0.37 + 1.3) * 0.4
	var z := cos(t * 0.19 + 0.7) * 0.6 + cos(t * 0.29) * 0.4
	return Vector3(x, 0.0, z) * DRIFT_RADIUS * ramp
