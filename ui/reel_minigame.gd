class_name ReelMinigame
extends Control

## First-slice Stardew-style reel minigame (GDD Reel Mechanic).
## Local-only: runs entirely on the peer who owns the bite, exactly like
## CastMeter reads EventBus rather than driving Rod directly. QTE / line
## tangling / perfect-catch bonus are not implemented yet -- this closes
## the WAITING_BITE -> IDLE loop so casting is repeatable.
##
## Hold "jump" to push the catch zone up; release and it falls. Keep the
## fish icon inside the zone to fill the catch meter before it drains to 0.

const ZONE_HEIGHT: float = 0.28
const RISE_ACCEL: float = 2.6
const FALL_ACCEL: float = 1.8
const MAX_ZONE_SPEED: float = 1.6
const FISH_SPEED: float = 0.5          ## units of [0,1] per second toward its target
const FISH_RETARGET_MIN: float = 0.4   ## seconds
const FISH_RETARGET_MAX: float = 1.4
const FILL_RATE: float = 0.35          ## progress/sec while overlapping
const DRAIN_RATE: float = 0.22         ## progress/sec while not overlapping

var _rod: Rod = null
var _active: bool = false

var _zone_pos: float = 0.5
var _zone_vel: float = 0.0
var _fish_pos: float = 0.5
var _fish_target: float = 0.5
var _fish_retarget_timer: float = 0.0
var _progress: float = 0.5

# UI pieces, built procedurally like CastMeter.
var _bar_bg: ColorRect = null
var _zone_rect: ColorRect = null
var _fish_rect: ColorRect = null
var _progress_fill: ColorRect = null

const BAR_WIDTH: float = 60.0
const BAR_HEIGHT: float = 260.0
const PROGRESS_WIDTH: float = 16.0


func _ready() -> void:
	_build_ui()
	hide()
	EventBus.bite_started.connect(_on_bite_started)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.1, 0.1, 0.1, 0.7)
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_bg.position = Vector2(-BAR_WIDTH - 80.0, -BAR_HEIGHT * 0.5)
	_bar_bg.anchor_left = 1.0
	_bar_bg.anchor_right = 1.0
	_bar_bg.anchor_top = 0.5
	_bar_bg.anchor_bottom = 0.5
	add_child(_bar_bg)

	_fish_rect = ColorRect.new()
	_fish_rect.color = Color(0.9, 0.75, 0.1, 1.0)
	_fish_rect.size = Vector2(BAR_WIDTH, 10.0)
	_bar_bg.add_child(_fish_rect)

	_zone_rect = ColorRect.new()
	_zone_rect.color = Color(1.0, 1.0, 1.0, 0.35)
	_zone_rect.size = Vector2(BAR_WIDTH, BAR_HEIGHT * ZONE_HEIGHT)
	_bar_bg.add_child(_zone_rect)

	var progress_bg := ColorRect.new()
	progress_bg.color = Color(0.1, 0.1, 0.1, 0.7)
	progress_bg.size = Vector2(PROGRESS_WIDTH, BAR_HEIGHT)
	progress_bg.position = Vector2(-PROGRESS_WIDTH - 16.0, 0.0)
	_bar_bg.add_child(progress_bg)

	_progress_fill = ColorRect.new()
	_progress_fill.color = Color(0.2, 0.85, 0.3, 0.9)
	_progress_fill.size = Vector2(PROGRESS_WIDTH, 0.0)
	progress_bg.add_child(_progress_fill)


func _on_bite_started(fish_data: FishData, caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return

	var player: Player = NetworkManager.spawned_players.get(caster_peer_id)
	if player == null:
		return
	var rod := player.equipment_slot.equipped_item as Rod
	if rod == null or rod.state != Rod.CastState.WAITING_BITE:
		return

	_rod = rod
	_rod.state = Rod.CastState.REELING
	_zone_pos = 0.5
	_zone_vel = 0.0
	_fish_pos = 0.5
	_fish_target = 0.5
	_fish_retarget_timer = 0.0
	_progress = 0.5
	_active = true
	show()


func _process(delta: float) -> void:
	if not _active:
		return

	_update_zone(delta)
	_update_fish(delta)
	_update_progress(delta)
	_update_visuals()

	if _progress >= 1.0:
		_finish(true)
	elif _progress <= 0.0:
		_finish(false)


func _update_zone(delta: float) -> void:
	if Input.is_action_pressed("jump"):
		_zone_vel += RISE_ACCEL * delta
	else:
		_zone_vel -= FALL_ACCEL * delta
	_zone_vel = clampf(_zone_vel, -MAX_ZONE_SPEED, MAX_ZONE_SPEED)

	_zone_pos = clampf(_zone_pos + _zone_vel * delta, 0.0, 1.0)
	if _zone_pos == 0.0 or _zone_pos == 1.0:
		_zone_vel = 0.0


func _update_fish(delta: float) -> void:
	_fish_retarget_timer -= delta
	if _fish_retarget_timer <= 0.0:
		_fish_target = randf_range(0.0, 1.0)
		_fish_retarget_timer = randf_range(FISH_RETARGET_MIN, FISH_RETARGET_MAX)

	var diff := _fish_target - _fish_pos
	var step := FISH_SPEED * delta
	if absf(diff) <= step:
		_fish_pos = _fish_target
	else:
		_fish_pos += step * signf(diff)


func _update_progress(delta: float) -> void:
	var zone_half := ZONE_HEIGHT * 0.5
	var overlapping := absf(_fish_pos - _zone_pos) <= zone_half
	_progress += (FILL_RATE if overlapping else -DRAIN_RATE) * delta
	_progress = clampf(_progress, 0.0, 1.0)


func _update_visuals() -> void:
	# All positions are 0 (bottom) .. 1 (top); UI y grows downward.
	_zone_rect.position = Vector2(
		0.0, BAR_HEIGHT * (1.0 - _zone_pos) - _zone_rect.size.y * 0.5
	)
	_fish_rect.position = Vector2(
		0.0, BAR_HEIGHT * (1.0 - _fish_pos) - _fish_rect.size.y * 0.5
	)

	var progress_bg_height: float = _progress_fill.get_parent().size.y
	var fill_h := progress_bg_height * _progress
	_progress_fill.size = Vector2(PROGRESS_WIDTH, fill_h)
	_progress_fill.position = Vector2(0.0, progress_bg_height - fill_h)


func _finish(success: bool) -> void:
	_active = false
	hide()
	if _rod:
		_rod.state = Rod.CastState.IDLE  # optimistic, same pattern as Rod.release_cast
		_rod.request_reel_resolution(success)
	_rod = null
