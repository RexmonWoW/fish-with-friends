class_name ReelMinigame
extends Control

## Stardew-style reel minigame (GDD Reel Mechanic), local-only: runs entirely
## on the peer who owns the bite, exactly like CastMeter reads EventBus
## rather than driving Rod directly.
##
## Hold "cast" (left mouse -- free during REELING since you can't start a
## new cast while reeling; Rod's own state guards make this safe) to push
## the catch zone up; release and it falls. Keep the fish icon inside the
## zone to fill the catch meter before it drains to 0.
##
## QTE layer: the fish periodically "runs," prompting a key press (space or
## an arrow) within a short window. Miss it and the catch zone shrinks a
## little (death spiral); miss MAX_MISSES times and the line snaps (fish
## gone). Zero misses on a successful catch = perfect catch, passed through
## to BiteEventManager for the GDD value bonus.

## "Base" values below are what the easiest (lowest-value) fish plays like.
## "Hard" values are what the hardest (highest-value) fish plays like. Every
## real reel lerps between the two by the hooked fish's own FishData.
## base_value (see _difficulty_t/_apply_difficulty) -- "fish should be
## harder to catch the more value they'll have," by request. Not tied to
## whatever species happen to exist today (VALUE_FOR_MIN/MAX_DIFFICULTY
## below) so a future higher-tier fish added later automatically lands
## harder without needing to rebalance existing species.
##
## The base ends of ZONE_HEIGHT, ZONE_SHRINK_PER_MISS, FILL_RATE, and
## QTE_WINDOW moved to PlayerStats (data/player_stats.gd) -- the numbers a
## Per-Run Shop upgrade would actually sell. The "_HARD" ends stay fixed
## consts for now; only the easy end is a stat.
const ZONE_HEIGHT_HARD: float = 0.15
const MIN_ZONE_HEIGHT: float = 0.10
const RISE_ACCEL: float = 2.6
const FALL_ACCEL: float = 1.8
const MAX_ZONE_SPEED: float = 1.6
const FISH_SPEED: float = 0.5          ## units of [0,1] per second toward its target
const FISH_SPEED_HARD: float = 1.0
const FISH_RETARGET_MIN: float = 0.4   ## seconds
const FISH_RETARGET_MAX: float = 1.4
const DRAIN_RATE: float = 0.22         ## progress/sec while not overlapping
const DRAIN_RATE_HARD: float = 0.34

## GDD: "cast distance should matter" -- a far cast takes noticeably longer
## to reel in. Scales the fill rate stat down by how far the landing spot
## was from the angler at fight start, full speed at close range down to
## this fraction at max cast distance (PlayerStats.max_cast_distance).
## Placeholder, tune-by-feel like every other constant here -- stacks
## independently with the fish-value difficulty scaling above (that one
## never touches fill rate at all).
const FILL_RATE_MULTIPLIER_AT_MAX_DISTANCE: float = 0.65

const QTE_MIN_INTERVAL: float = 2.2
const QTE_MIN_INTERVAL_HARD: float = 1.2
const QTE_MAX_INTERVAL: float = 4.5
const QTE_MAX_INTERVAL_HARD: float = 2.4
const QTE_WINDOW_HARD: float = 0.65
const QTE_FISH_BOLT_SPEED: float = 2.5 ## fish speed multiplier while a QTE is active
const MAX_MISSES: int = 3

const VALUE_FOR_MIN_DIFFICULTY: float = 5.0    ## at/below this base_value, plays at the "base" tunables
const VALUE_FOR_MAX_DIFFICULTY: float = 150.0  ## at/above this base_value, plays at the "hard" tunables

## Each prompt accepts either key -- WASD is what most players reach for
## instinctively (it's otherwise unused during REELING since movement is
## locked while a cast is out), arrows still work too.
const QTE_PROMPTS: Array[Dictionary] = [
	{"keys": [KEY_SPACE], "label": "SPACE"},
	{"keys": [KEY_UP, KEY_W], "label": "W"},
	{"keys": [KEY_DOWN, KEY_S], "label": "S"},
	{"keys": [KEY_LEFT, KEY_A], "label": "A"},
	{"keys": [KEY_RIGHT, KEY_D], "label": "D"},
]

var _rod: Rod = null
var _active: bool = false

## Cached once per reel (looked up on start, not every frame) -- reports
## this client's own progress so the world bobber (host-driven, visible to
## every nearby peer) reels in/out along with this private UI.
var _reel_fight_manager: Node = null

## Per-reel, computed from the hooked fish's value (and, for fill rate,
## cast distance too) in _try_start_reel -- see the BASE/HARD const pairs
## above and PlayerStats for where the "base" ends now come from. Defaults
## here are never actually read (always overwritten before _active goes
## true) -- just documenting what they'll be lerped from.
var _fish_speed: float = FISH_SPEED
var _drain_rate: float = DRAIN_RATE
var _qte_min_interval: float = QTE_MIN_INTERVAL
var _qte_max_interval: float = QTE_MAX_INTERVAL
var _qte_window: float = 0.0
var _fill_rate: float = 0.0

## While the local player is tangled (see EventBus.tangle_started/resolved),
## a bite that fires mid-tangle shouldn't pop the reel up on top of the
## tangle UI -- both would fight over the same "cast" input. Detection only
## ever starts a NEW tangle between two WAITING_BITE rods (Rod
## ._on_line_area_entered), so a bite can still legitimately fire while a
## tangle is already in progress; this just holds it until the tangle clears.
var _local_player_tangled: bool = false
var _deferred_bite: FishData = null

var _zone_pos: float = 0.5
var _zone_vel: float = 0.0
var _zone_height: float = 0.0  ## never actually read -- see the block comment above
var _fish_pos: float = 0.5
var _fish_target: float = 0.5
var _fish_retarget_timer: float = 0.0
var _progress: float = 0.5

var _qte_active: bool = false
var _qte_timer: float = 0.0
var _qte_keys: Array = [KEY_SPACE]
var _qte_next_in: float = 0.0
var _miss_count: int = 0

# UI pieces, built procedurally like CastMeter.
var _bar_bg: ColorRect = null
var _zone_rect: ColorRect = null
var _fish_rect: ColorRect = null
var _progress_fill: ColorRect = null
var _qte_label: Label = null
var _miss_label: Label = null

const BAR_WIDTH: float = 60.0
const BAR_HEIGHT: float = 260.0
const PROGRESS_WIDTH: float = 16.0


func _ready() -> void:
	_build_ui()
	hide()
	EventBus.bite_started.connect(_on_bite_started)
	EventBus.tangle_started.connect(_on_tangle_started)
	EventBus.tangle_resolved.connect(_on_tangle_resolved_global)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	# Control defaults to MOUSE_FILTER_STOP, which swallows mouse motion --
	# this sits near screen-center where MOUSE_MODE_CAPTURED pins the
	# (invisible) cursor, same bug class found and fixed in LivewellDisplay.
	# IGNORE on every node here; nothing in this minigame is clicked with
	# the mouse (it's all "cast"-hold and QTE key input).
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.1, 0.1, 0.1, 0.7)
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_bg.position = Vector2(-BAR_WIDTH - 80.0, -BAR_HEIGHT * 0.5)
	_bar_bg.anchor_left = 1.0
	_bar_bg.anchor_right = 1.0
	_bar_bg.anchor_top = 0.5
	_bar_bg.anchor_bottom = 0.5
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_bg)

	_fish_rect = ColorRect.new()
	_fish_rect.color = Color(0.9, 0.75, 0.1, 1.0)
	_fish_rect.size = Vector2(BAR_WIDTH, 10.0)
	_fish_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_fish_rect)

	_zone_rect = ColorRect.new()
	_zone_rect.color = Color(1.0, 1.0, 1.0, 0.35)
	_zone_rect.size = Vector2(BAR_WIDTH, BAR_HEIGHT * 0.28)  # placeholder -- hidden until _try_start_reel sets the real height
	_zone_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_zone_rect)

	var progress_bg := ColorRect.new()
	progress_bg.color = Color(0.1, 0.1, 0.1, 0.7)
	progress_bg.size = Vector2(PROGRESS_WIDTH, BAR_HEIGHT)
	progress_bg.position = Vector2(-PROGRESS_WIDTH - 16.0, 0.0)
	progress_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(progress_bg)

	_progress_fill = ColorRect.new()
	_progress_fill.color = Color(0.2, 0.85, 0.3, 0.9)
	_progress_fill.size = Vector2(PROGRESS_WIDTH, 0.0)
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bg.add_child(_progress_fill)

	_qte_label = Label.new()
	_qte_label.add_theme_font_size_override("font_size", 28)
	_qte_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	_qte_label.position = Vector2(-160.0, BAR_HEIGHT * 0.5 - 20.0)
	_qte_label.size = Vector2(120.0, 40.0)
	_qte_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qte_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qte_label.hide()
	_bar_bg.add_child(_qte_label)

	_miss_label = Label.new()
	_miss_label.add_theme_font_size_override("font_size", 14)
	_miss_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_miss_label.position = Vector2(-160.0, BAR_HEIGHT + 8.0)
	_miss_label.size = Vector2(120.0, 24.0)
	_miss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_miss_label)


func _on_tangle_started(peer_a: int, peer_b: int) -> void:
	var my_id := multiplayer.get_unique_id()
	if my_id == peer_a or my_id == peer_b:
		_local_player_tangled = true


func _on_tangle_resolved_global(winner_peer_id: int, loser_peer_id: int) -> void:
	var my_id := multiplayer.get_unique_id()
	if my_id != winner_peer_id and my_id != loser_peer_id:
		return
	_local_player_tangled = false
	if _deferred_bite == null:
		return
	var fish_data := _deferred_bite
	_deferred_bite = null
	# If we lost, our own Rod already reset itself to IDLE on tangle_resolved
	# (Rod._on_tangle_resolved) -- _try_start_reel's own WAITING_BITE check
	# naturally drops the deferred bite in that case, nothing extra needed.
	_try_start_reel(fish_data, my_id)


func _on_bite_started(fish_data: FishData, caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	if _local_player_tangled:
		_deferred_bite = fish_data
		return
	_try_start_reel(fish_data, caster_peer_id)


func _try_start_reel(fish_data: FishData, caster_peer_id: int) -> void:
	var player: Player = NetworkManager.spawned_players.get(caster_peer_id)
	if player == null:
		return
	var rod := player.equipment_slot.equipped_item as Rod
	if rod == null or rod.state != Rod.CastState.WAITING_BITE:
		return

	_rod = rod
	_rod.state = Rod.CastState.REELING
	_reel_fight_manager = get_tree().get_first_node_in_group("reel_fight_manager")

	var stats := player.stats
	var t := _difficulty_t(fish_data)
	_fish_speed = lerpf(FISH_SPEED, FISH_SPEED_HARD, t)
	_drain_rate = lerpf(DRAIN_RATE, DRAIN_RATE_HARD, t)
	_qte_min_interval = lerpf(QTE_MIN_INTERVAL, QTE_MIN_INTERVAL_HARD, t)
	_qte_max_interval = lerpf(QTE_MAX_INTERVAL, QTE_MAX_INTERVAL_HARD, t)
	_qte_window = lerpf(stats.reel_qte_window, QTE_WINDOW_HARD, t)
	_fill_rate = stats.reel_fill_rate * lerpf(1.0, FILL_RATE_MULTIPLIER_AT_MAX_DISTANCE, _cast_distance_t(player))

	_zone_pos = 0.5
	_zone_vel = 0.0
	_zone_height = lerpf(stats.reel_zone_height, ZONE_HEIGHT_HARD, t)
	_fish_pos = 0.5
	_fish_target = 0.5
	_fish_retarget_timer = 0.0
	_progress = 0.5
	_qte_active = false
	_miss_count = 0
	_qte_next_in = randf_range(_qte_min_interval, _qte_max_interval)
	_active = true
	_qte_label.hide()
	_update_miss_label()
	show()


## 0.0 (easiest, at/below VALUE_FOR_MIN_DIFFICULTY) .. 1.0 (hardest, at/above
## VALUE_FOR_MAX_DIFFICULTY), linear between them based on the hooked fish's
## species-level base_value (size/perfect-catch multipliers aren't rolled
## yet at bite time, so base_value is the only value signal available here).
func _difficulty_t(fish_data: FishData) -> float:
	if fish_data == null:
		return 0.0
	return clampf(
		inverse_lerp(VALUE_FOR_MIN_DIFFICULTY, VALUE_FOR_MAX_DIFFICULTY, float(fish_data.base_value)),
		0.0, 1.0
	)


## 0.0 (landed right next to the angler) .. 1.0 (landed at/beyond max cast
## distance) -- reads the real landing spot from ReelFightManager rather
## than needing it threaded through bite_started's own signal. Missing
## fight data (manager not found, or this peer has no recorded anchor)
## falls back to 0.0 -- no distance penalty rather than guessing.
func _cast_distance_t(player: Player) -> float:
	if _reel_fight_manager == null:
		return 0.0
	var anchor: Variant = _reel_fight_manager.get_fight_anchor(player.peer_id)
	var max_distance := player.stats.max_cast_distance
	if anchor == null or max_distance <= 0.0:
		return 0.0
	var dist := player.global_position.distance_to(anchor as Vector3)
	return clampf(dist / max_distance, 0.0, 1.0)


func _process(delta: float) -> void:
	if not _active:
		return

	_update_zone(delta)
	_update_qte(delta)
	_update_fish(delta)
	_update_progress(delta)
	_update_visuals()

	if _reel_fight_manager:
		_reel_fight_manager.report_progress(_progress)

	if _progress >= 1.0:
		_finish(true)
	elif _progress <= 0.0:
		_finish(false)


func _update_zone(delta: float) -> void:
	if Input.is_action_pressed("cast"):
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

	var speed := _fish_speed * (QTE_FISH_BOLT_SPEED if _qte_active else 1.0)
	var diff := _fish_target - _fish_pos
	var step := speed * delta
	if absf(diff) <= step:
		_fish_pos = _fish_target
	else:
		_fish_pos += step * signf(diff)


func _update_progress(delta: float) -> void:
	var zone_half := _zone_height * 0.5
	var overlapping := absf(_fish_pos - _zone_pos) <= zone_half
	_progress += (_fill_rate if overlapping else -_drain_rate) * delta
	_progress = clampf(_progress, 0.0, 1.0)


# ── QTE layer ────────────────────────────────────────────────────────────────

func _update_qte(delta: float) -> void:
	if _qte_active:
		_qte_timer -= delta
		if _qte_timer <= 0.0:
			_on_qte_missed()
		return

	_qte_next_in -= delta
	if _qte_next_in <= 0.0:
		_start_qte()


func _start_qte() -> void:
	_qte_active = true
	_qte_timer = _qte_window
	var prompt: Dictionary = QTE_PROMPTS[randi() % QTE_PROMPTS.size()]
	_qte_keys = prompt["keys"]
	_qte_label.text = prompt["label"]
	_qte_label.show()
	# "The fish runs" -- bolt toward a fresh random spot at higher speed
	# while the prompt is up (see _update_fish's QTE_FISH_BOLT_SPEED).
	_fish_target = randf_range(0.0, 1.0)
	_fish_retarget_timer = _qte_window
	# Same moment, out in the world: a visible sideways tug on the real
	# bobber (GDD: the fish "tugs left or right" during a QTE).
	if _reel_fight_manager:
		_reel_fight_manager.report_kick()


func _on_qte_succeeded() -> void:
	_qte_active = false
	_qte_label.hide()
	_qte_next_in = randf_range(_qte_min_interval, _qte_max_interval)


func _on_qte_missed() -> void:
	_qte_active = false
	_qte_label.hide()
	_miss_count += 1
	_zone_height = maxf(_zone_height - _rod.stats.reel_zone_shrink_per_miss, MIN_ZONE_HEIGHT)
	_update_miss_label()

	if _miss_count >= MAX_MISSES:
		_finish(false)  # line snaps
		return

	_qte_next_in = randf_range(_qte_min_interval, _qte_max_interval)


func _update_miss_label() -> void:
	_miss_label.text = "Misses: %d/%d" % [_miss_count, MAX_MISSES]


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not _qte_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode in _qte_keys:
			_on_qte_succeeded()


# ── Visuals ──────────────────────────────────────────────────────────────────

func _update_visuals() -> void:
	# All positions are 0 (bottom) .. 1 (top); UI y grows downward.
	_zone_rect.size = Vector2(BAR_WIDTH, BAR_HEIGHT * _zone_height)
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
	var was_perfect := success and _miss_count == 0
	_active = false
	_qte_active = false
	_qte_label.hide()
	hide()
	if _rod:
		_rod.state = Rod.CastState.IDLE  # optimistic, same pattern as Rod.release_cast
		_rod.request_reel_resolution(success, was_perfect)
	_rod = null
	_reel_fight_manager = null
