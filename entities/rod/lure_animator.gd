class_name LureAnimator
extends Node3D

## Owns the cosmetic line back to this rod's tip, and the LineCollider
## tangle detection reads. The bobber itself is a separate, independent
## Bobber node (entities/bobber/bobber.gd) spawned at the scene root on
## cast_landed -- NEVER parented here (see Bobber's own doc comment for
## why: a camera-attached parent fights back during fast camera movement).
## This node just tracks a reference to its rod's current bobber and draws
## the line to it each frame. Visual-only. Plays for every peer's own
## mirror of every rod (not owner-gated) -- same reasoning as the line/
## collider update below.

signal lure_landed

var _line_mesh: MeshInstance3D = null
var _bobber: Bobber = null
var _is_out: bool = false  ## true from cast_landed until Rod.state returns to IDLE


func _ready() -> void:
	_build_line_visual()
	hide()  # invisible until a cast is in-flight/out
	EventBus.cast_landed.connect(_on_cast_landed)


## Review finding: the only thing that ever freed the bobber was this
## node's own _process seeing rod.state == IDLE -- a disconnect mid-cast,
## or this Rod/LureAnimator itself leaving the tree some other way, left
## the bobber orphaned (parented under the map/root, nothing left to ever
## free it). Belt-and-suspenders with the map-parenting below, which
## cleans up the normal "round ends, map unloads" case on its own.
func _exit_tree() -> void:
	if _bobber and is_instance_valid(_bobber):
		_bobber.queue_free()
	_bobber = null


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

	if _bobber and is_instance_valid(_bobber):
		_bobber.queue_free()
	_bobber = Bobber.new()
	_bobber.owner_peer_id = caster_peer_id
	# Parented under the current map, not get_tree().root -- a round ending
	# (map unloads) then cleans up any still-out bobber on its own, same as
	# it already does for everything else IN that map. Falls back to root
	# only if there's genuinely no map loaded (shouldn't happen -- casting
	# itself requires one, see Rod.start_charge).
	var map := NetworkManager.get_current_map()
	(map if map else get_tree().root).add_child(_bobber)
	_bobber.landed.connect(_on_bobber_landed)
	_bobber.play_arc(start_pos, endpoint, flight_seconds)

	_is_out = true
	show()


func _on_bobber_landed() -> void:
	lure_landed.emit()
	var rod := get_parent() as Rod
	# Only advance state if the rod is still exactly where the arc left it
	# (ANIMATING) -- something else (a capsize mid-flight, a cancel) could
	# have already moved it on by the time this fires, and unconditionally
	# stomping back to WAITING_BITE would undo that.
	if rod and rod.state == Rod.CastState.ANIMATING:
		rod.state = Rod.CastState.WAITING_BITE
		# The lines may have already been overlapping mid-flight (this
		# rod's own area_entered fired then, correctly ignored since state
		# wasn't WAITING_BITE yet) -- re-check now that it actually counts.
		rod.check_line_overlaps_for_tangle()


## Public so tests (and anything else that needs the real bobber position,
## not just this line's endpoint) can read it without reaching into a
## private var.
func get_bobber_position() -> Vector3:
	return _bobber.global_position if _bobber and is_instance_valid(_bobber) else global_position


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
		if _bobber and is_instance_valid(_bobber):
			_bobber.queue_free()
		_bobber = null
		return

	if _bobber == null or not is_instance_valid(_bobber):
		return  # bobber hasn't landed/spawned yet this frame -- nothing to draw

	var rod_tip := rod.get_node("RodTip") as Marker3D
	if rod_tip:
		var bobber_pos := _bobber.global_position
		_update_line(rod_tip.global_position, bobber_pos)
		# Deliberately NOT gated to the rod's owner (unlike input handling) --
		# this must update identically for every peer's local mirror of this
		# rod, since tangle detection runs host-side against whichever line
		# collider exists in the HOST's own copy of the scene. An owner-gate
		# here would silently disable tangling for every non-host player's
		# line, the same class of bug the water-validation regression was.
		_update_line_collider(rod_tip.global_position, bobber_pos)


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
