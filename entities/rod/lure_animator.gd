class_name LureAnimator
extends Node3D

## Animates the lure through a parabolic arc from rod tip to landing point.
## Visual-only. Listens to EventBus.cast_landed; plays arc for this rod's owner only.

signal lure_landed

# Lure visual — small sphere placeholder. Art and Polish will replace.
var _lure_mesh: MeshInstance3D = null
var _active_tween: Tween = null

# Tunable apex height as a fraction of horizontal distance.
const APEX_FRACTION: float = 0.3


func _ready() -> void:
	_build_lure_visual()
	hide()  # invisible until a cast is in-flight
	EventBus.cast_landed.connect(_on_cast_landed)


func _build_lure_visual() -> void:
	_lure_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	_lure_mesh.mesh = sphere
	add_child(_lure_mesh)


func _on_cast_landed(endpoint: Vector3, flight_seconds: float, caster_peer_id: int) -> void:
	# Only animate for our own rod.
	var rod := get_parent() as Rod
	if rod == null or rod.owner_peer_id != caster_peer_id:
		return

	var rod_tip := rod.get_node("RodTip") as Marker3D
	var start_pos := rod_tip.global_position if rod_tip else global_position
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
	hide()
	lure_landed.emit()
	# Tell the parent Rod we've landed so it can advance to WAITING_BITE.
	var rod := get_parent() as Rod
	if rod:
		rod.state = Rod.CastState.WAITING_BITE
