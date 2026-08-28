class_name TangleMinigame
extends Control

## GDD Line Tangling: shown to both involved players when their lines
## cross. Mash "cast" (left mouse -- free during a tangle since both
## rods are WAITING_BITE, not charging/reeling) to pull the rope toward
## your side; first to the edge wins. Purely a display + input relay --
## TangleManager (host-authoritative) owns the actual simulation.

const BAR_WIDTH: float = 320.0
const BAR_HEIGHT: float = 36.0

var _active: bool = false
var _am_peer_a: bool = false  ## whether the local player is "a" for this tangle

var _bar_bg: ColorRect = null
var _marker: ColorRect = null
var _label: Label = null


func _ready() -> void:
	_build_ui()
	hide()
	EventBus.tangle_started.connect(_on_tangle_started)
	EventBus.tangle_rope_updated.connect(_on_rope_updated)
	EventBus.tangle_resolved.connect(_on_tangle_resolved)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_bg.position = Vector2(-BAR_WIDTH * 0.5, 100.0)
	_bar_bg.anchor_left = 0.5
	_bar_bg.anchor_right = 0.5
	add_child(_bar_bg)

	_marker = ColorRect.new()
	_marker.color = Color(0.9, 0.8, 0.2, 1.0)
	_marker.size = Vector2(6.0, BAR_HEIGHT)
	_bar_bg.add_child(_marker)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-BAR_WIDTH * 0.5, -28.0)
	_label.size = Vector2(BAR_WIDTH, 24.0)
	_label.text = "TANGLED! Mash to pull free!"
	_bar_bg.add_child(_label)


func _on_tangle_started(peer_a: int, peer_b: int) -> void:
	var my_id := multiplayer.get_unique_id()
	if my_id != peer_a and my_id != peer_b:
		return
	_am_peer_a = my_id == peer_a
	_active = true
	_set_rope_visual(0.0)
	show()


func _on_rope_updated(peer_a: int, peer_b: int, rope: float) -> void:
	if not _active:
		return
	var my_id := multiplayer.get_unique_id()
	if my_id != peer_a and my_id != peer_b:
		return
	# Normalize so positive always means "the local player is winning,"
	# regardless of whether they're stored as a or b host-side.
	_set_rope_visual(rope if _am_peer_a else -rope)


func _on_tangle_resolved(winner_peer_id: int, loser_peer_id: int) -> void:
	if not _active:
		return
	var my_id := multiplayer.get_unique_id()
	if my_id != winner_peer_id and my_id != loser_peer_id:
		return
	_active = false
	_label.text = "You won the tangle!" if my_id == winner_peer_id else "Line snapped!"
	# Leave the result up briefly instead of vanishing instantly.
	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(hide)


func _set_rope_visual(local_rope: float) -> void:
	var t := (clampf(local_rope, -1.0, 1.0) + 1.0) * 0.5  # 0..1
	_marker.position.x = t * (BAR_WIDTH - _marker.size.x)


func _process(_delta: float) -> void:
	if not _active:
		return
	# "cast" (left mouse) is free during a tangle -- both rods are
	# WAITING_BITE, not charging/reeling, so it means nothing else right
	# now (same reuse pattern as the reel's rise control). Edge-triggered
	# (is_action_just_pressed), not held -- mashing means repeated discrete
	# presses, not "hold the button and win instantly."
	if Input.is_action_just_pressed("cast"):
		_request_mash()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	# Space also works (unlike the reel's QTE layer, nothing else uses it
	# during a tangle). event.echo excludes OS key-repeat -- each mash
	# needs an actual discrete press.
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_SPACE:
			_request_mash()


func _request_mash() -> void:
	var tangle_manager: Node = get_tree().get_first_node_in_group("tangle_manager")
	if tangle_manager:
		tangle_manager.request_mash()
