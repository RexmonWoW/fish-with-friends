class_name LureAnimator
extends Node3D

## Animates the lure through a parabolic arc from rod tip to landing point,
## then leaves it floating there as a bobber (with a line back to the rod
## tip) until the reel resolves. Visual-only. Listens to EventBus.cast_landed;
## plays/shows for this rod's owner only.

signal lure_landed

# Lure/bobber visual — small sphere placeholder. Art and Polish will replace.
var _lure_mesh: MeshInstance3D = null
var _line_mesh: MeshInstance3D = null
var _active_tween: Tween = null
var _is_out: bool = false  ## true from cast_landed until Rod.state returns to IDLE
var _anchor_position: Vector3 = Vector3.ZERO  ## world-space landing spot, once landed

# Tunable apex height as a fraction of horizontal distance. Was 0.3, which
# combined with the too-high rod tip (see player.tscn AttachPoint_Hand fix)
# made casts look like they launched straight up rather than out over the
# water -- 0.12 gives a flatter, more cast-like arc for typical distances.
const APEX_FRACTION: float = 0.12


func _ready() -> void:
	_build_lure_visual()
	_build_line_visual()
	hide()  # invisible until a cast is in-flight/out
	EventBus.cast_landed.connect(_on_cast_landed)


func _build_lure_visual() -> void:
	_lure_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	_lure_mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.15, 0.15)  # red bobber top, placeholder
	_lure_mesh.set_surface_override_material(0, material)
	add_child(_lure_mesh)


func _build_line_visual() -> void:
	_line_mesh = MeshInstance3D.new()
	_line_mesh.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 0.85, 0.85, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# ImmediateMesh starts with zero surfaces (none drawn yet), and
	# set_surface_override_material requires an existing surface index --
	# material_override applies regardless of surface count.
	_line_mesh.material_override = material
	add_child(_line_mesh)


func _on_cast_landed(endpoint: Vector3, flight_seconds: float, caster_peer_id: int) -> void:
	# Only animate for our own rod.
	var rod := get_parent() as Rod
	if rod == null or rod.owner_peer_id != caster_peer_id:
		return

	var rod_tip := rod.get_node("RodTip") as Marker3D
	var start_pos := rod_tip.global_position if rod_tip else global_position
	_is_out = true
	play_arc(start_pos, endpoint, flight_seconds)


func play_arc(start_pos: Vector3, end_pos: Vector3, duration: float) -> void:
	# Kill any arc already in-flight.
	if _active_tween:
		_active_tween.kill()

	global_position = start_pos
	show()

	var horizontal_dist := Vector2(end_pos.x - start_pos.x, end_pos.z - start_pos.z).length()
	var apex_height: float = horizontal_dist * APEX_FRACTION

	_active_tween = create_tween()
	# Drive progress 0 → 1 via a single interpolated value, sampled each frame.
	_active_tween.tween_method(
		func(t: float) -> void:
			# Lerp XZ linearly, Y parabolically (apex at t = 0.5).
			var pos := start_pos.lerp(end_pos, t)
			pos.y += apex_height * 4.0 * t * (1.0 - t)  # standard parabola through 0,apex,0
			global_position = pos,
		0.0, 1.0, duration
	)
	_active_tween.tween_callback(_on_arc_complete)


func _on_arc_complete() -> void:
	_active_tween = null
	_anchor_position = global_position
	# Stays visible, floating at the landing point as a bobber, until the
	# reel resolves (see _process below) -- doesn't hide here anymore.
	lure_landed.emit()
	var rod := get_parent() as Rod
	# Only advance state if the rod is still exactly where this tween left
	# it (ANIMATING) -- something else (a capsize mid-flight, a cancel)
	# could have already moved it on by the time this callback fires, and
	# unconditionally stomping back to WAITING_BITE would undo that.
	if rod and rod.state == Rod.CastState.ANIMATING:
		rod.state = Rod.CastState.WAITING_BITE
		# The lines may have already been overlapping mid-flight (this
		# rod's own area_entered fired then, correctly ignored since state
		# wasn't WAITING_BITE yet) -- re-check now that it actually counts.
		rod.check_line_overlaps_for_tangle()


func _process(_delta: float) -> void:
	if not _is_out:
		return

	var rod := get_parent() as Rod
	if rod == null:
		return

	# Poll Rod's own state rather than listening for reel_finished/cast_failed
	# -- those currently only fire host-side (see PROGRESS.md open questions),
	# whereas Rod.state is reset optimistically on the owning client already.
	if rod.state == Rod.CastState.IDLE:
		_is_out = false
		hide()
		_set_line_collider_active(rod, false)
		return

	if _active_tween == null:
		# Re-assert the anchor every frame rather than trusting it to stay
		# put on its own -- this node is parented under Rod, which is now
		# rigidly camera-attached (see player.tscn's AttachPoint_Hand fix).
		# A bobber that's only ever positioned once, as a child of something
		# that keeps moving, drifts along with it: turning your camera was
		# dragging the "landed" bobber around like it was rigidly welded to
		# the rod instead of floating independently at a fixed water spot.
		global_position = _anchor_position

	var rod_tip := rod.get_node("RodTip") as Marker3D
	if rod_tip:
		_update_line(rod_tip.global_position, global_position)
		# Deliberately NOT gated to the rod's owner (unlike input handling) --
		# this must update identically for every peer's local mirror of this
		# rod, since tangle detection runs host-side against whichever line
		# collider exists in the HOST's own copy of the scene. An owner-gate
		# here would silently disable tangling for every non-host player's
		# line, the same class of bug the water-validation regression was.
		_update_line_collider(rod_tip.global_position, global_position)


func _update_line(from_pos: Vector3, to_pos: Vector3) -> void:
	var immediate := _line_mesh.mesh as ImmediateMesh
	immediate.clear_surfaces()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate.surface_add_vertex(_line_mesh.to_local(from_pos))
	immediate.surface_add_vertex(_line_mesh.to_local(to_pos))
	immediate.surface_end()


## Keeps Rod/LineCollider (an Area3D) spanning the actual line so tangle
## detection (two different players' colliders overlapping) reflects where
## the line really is, not a fixed idle shape sitting at the rod's origin.
func _update_line_collider(from_pos: Vector3, to_pos: Vector3) -> void:
	var rod := get_parent() as Rod
	if rod == null:
		return
	var collider := rod.get_node_or_null("LineCollider") as Area3D
	if collider == null:
		return

	var diff := to_pos - from_pos
	var length := diff.length()
	if length < 0.05:
		_set_line_collider_active(rod, false)
		return
	_set_line_collider_active(rod, true)

	var shape_node := collider.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	capsule.height = length
	# Playtest: "very hard to tangle your line with someone else's" -- the
	# line itself renders razor-thin, but detection doesn't need to match
	# that; this radius is purely a gameplay generosity knob, no visual
	# downside to widening it. Was 0.05 (two lines needed to cross within
	# 10cm combined to register at all).
	capsule.radius = 0.4

	# Orient so local Y (CapsuleShape3D's long axis) points along the line.
	var y_axis := diff.normalized()
	var reference := Vector3.RIGHT if absf(y_axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x_axis := y_axis.cross(reference).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	collider.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), (from_pos + to_pos) * 0.5)


func _set_line_collider_active(rod: Rod, active: bool) -> void:
	var collider := rod.get_node_or_null("LineCollider") as Area3D
	if collider == null:
		return
	collider.monitoring = active
	collider.monitorable = active
