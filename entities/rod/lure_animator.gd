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
	# Stays visible, floating at the landing point as a bobber, until the
	# reel resolves (see _process below) -- doesn't hide here anymore.
	lure_landed.emit()
	var rod := get_parent() as Rod
	if rod:
		rod.state = Rod.CastState.WAITING_BITE


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
		return

	var rod_tip := rod.get_node("RodTip") as Marker3D
	if rod_tip:
		_update_line(rod_tip.global_position, global_position)


func _update_line(from_pos: Vector3, to_pos: Vector3) -> void:
	var immediate := _line_mesh.mesh as ImmediateMesh
	immediate.clear_surfaces()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate.surface_add_vertex(_line_mesh.to_local(from_pos))
	immediate.surface_add_vertex(_line_mesh.to_local(to_pos))
	immediate.surface_end()
