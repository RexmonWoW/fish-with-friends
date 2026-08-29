class_name BigFishEventManager
extends Node

## Host-authoritative. GDD Big Fish Event (Lake map only): random chance to
## trigger during a round; a ready-check window where players cast at the
## shaking spot to join; then a shared minigame -- hold to rise, periodic
## QTEs, a miss hurts everyone (bigger hit to whoever missed, smaller
## shared hit to the rest), a soft-max band that has to be held for a
## couple seconds to lock in. Success once everyone's locked in before the
## time limit; fail if the timer runs out first -- costs the crew their 2
## biggest (by value) livewell fish and capsizes the boat for real
## (CapsizeManager, built earlier this session).
##
## Placeholder tunables below (trigger frequency, join radius, event
## duration, miss penalties, soft-max band/hold time) aren't specified
## precisely in GDD -- reasonable starting points, flagged in PROGRESS.md
## for real balancing.

const CHECK_INTERVAL: float = 30.0     ## how often to roll for a trigger
const TRIGGER_CHANCE: float = 0.08     ## probability per check
const READY_CHECK_DURATION: float = 18.0  ## GDD: placeholder ~15-20s
const JOIN_RADIUS: float = 4.0         ## how close a cast must land to the spot
const EVENT_TIME_LIMIT: float = 45.0   ## overall time limit once active

const RISE_ACCEL: float = 2.0
const FALL_ACCEL: float = 1.4
const MAX_SPEED: float = 1.4

const QTE_MIN_INTERVAL: float = 3.0
const QTE_MAX_INTERVAL: float = 6.0
const QTE_WINDOW: float = 1.1

const MISS_PENALTY_SELF: float = 0.22   ## bigger hit to whoever missed
const MISS_PENALTY_OTHERS: float = 0.08 ## smaller shared hit to everyone else active

const SOFT_MAX_BAND: float = 0.9   ## top 10% counts as "near-max"
const LOCK_IN_HOLD_TIME: float = 2.0  ## seconds held in the band to lock in

## Index into QTE_PROMPTS (ui/big_fish_event_minigame.gd owns the matching
## key/label table -- kept in sync manually, same as ReelMinigame/
## TangleMinigame each owning their own UI constants independently).
const PROMPT_COUNT: int = 5

enum Phase { INACTIVE, READY_CHECK, ACTIVE }

var _phase: Phase = Phase.INACTIVE
var _target_spot: Vector3 = Vector3.ZERO
var _phase_timer: float = 0.0
var _next_check_timer: float = CHECK_INTERVAL
var _participants: Dictionary = {}  ## peer_id (int) -> Dictionary of bar/QTE state
var _center: Vector3 = Vector3.ZERO  ## where ready-check spots roll around -- set via setup()


func _ready() -> void:
	if not multiplayer.is_server():
		return
	add_to_group("big_fish_event_manager")


## Called by the map (Lake -- extends Node, no transform of its own, so the
## center to roll ready-check spots around is handed in rather than read
## from a global_position that doesn't exist here). Same wiring shape as
## CapsizeManager.setup(corner_markers).
func setup(center: Vector3) -> void:
	_center = center


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not _is_round_active():
		return

	match _phase:
		Phase.INACTIVE:
			_next_check_timer -= delta
			if _next_check_timer <= 0.0:
				_next_check_timer = CHECK_INTERVAL
				if randf() < TRIGGER_CHANCE:
					_start_ready_check()
		Phase.READY_CHECK:
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_end_ready_check()
		Phase.ACTIVE:
			_update_active(delta)


func _is_round_active() -> bool:
	var map := NetworkManager.get_current_map()
	return map != null and map.map_id == &"lake"


func _start_ready_check() -> void:
	var map := NetworkManager.get_current_map()
	if map == null:
		return
	# Somewhere in open water, well past the boat's own footprint.
	var angle := randf() * TAU
	var radius := randf_range(8.0, 15.0)
	var probe := _center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	var water_point: Variant = WaterValidator.find_water_point(probe, map)
	if water_point == null:
		return  # bad luck this check, try again next interval

	_target_spot = water_point
	_participants.clear()
	_phase = Phase.READY_CHECK
	_phase_timer = READY_CHECK_DURATION
	_notify_ready_check_started.rpc(_target_spot, READY_CHECK_DURATION)


## Called by BiteEventManager's cast_landed handler BEFORE it schedules a
## normal bite -- checked first (not "schedule then cancel") so this
## doesn't depend on which system's listener happens to run first. Returns
## true if this cast joined the event instead of becoming a normal bite.
func try_join(peer_id: int, endpoint: Vector3) -> bool:
	if _phase != Phase.READY_CHECK:
		return false
	if _participants.has(peer_id):
		return false
	if endpoint.distance_to(_target_spot) > JOIN_RADIUS:
		return false

	_participants[peer_id] = {
		"pos": 0.0,
		"vel": 0.0,
		"holding": false,
		"qte_active": false,
		"qte_timer": randf_range(QTE_MIN_INTERVAL, QTE_MAX_INTERVAL),
		"qte_prompt": -1,
		"lock_timer": 0.0,
		"locked_in": false,
	}

	var rod := _rod_for_peer(peer_id)
	if rod:
		rod._set_big_fish_event_state.rpc(true)

	_notify_participant_joined.rpc(peer_id)
	return true


func _end_ready_check() -> void:
	if _participants.is_empty():
		_phase = Phase.INACTIVE
		_notify_event_fizzled.rpc()
		return

	_phase = Phase.ACTIVE
	_phase_timer = EVENT_TIME_LIMIT
	_notify_event_active.rpc(_participants.keys(), EVENT_TIME_LIMIT)


func _update_active(delta: float) -> void:
	_phase_timer -= delta

	for peer_id in _participants.keys():
		var p: Dictionary = _participants[peer_id]
		if p["locked_in"]:
			continue

		if p["holding"]:
			p["vel"] = clampf(p["vel"] + RISE_ACCEL * delta, -MAX_SPEED, MAX_SPEED)
		else:
			p["vel"] = clampf(p["vel"] - FALL_ACCEL * delta, -MAX_SPEED, MAX_SPEED)
		p["pos"] = clampf(p["pos"] + p["vel"] * delta, 0.0, 1.0)

		if p["qte_active"]:
			p["qte_timer"] -= delta
			if p["qte_timer"] <= 0.0:
				_apply_miss(peer_id)
		else:
			p["qte_timer"] -= delta
			if p["qte_timer"] <= 0.0:
				p["qte_active"] = true
				p["qte_timer"] = QTE_WINDOW
				p["qte_prompt"] = randi() % PROMPT_COUNT

		if p["pos"] >= SOFT_MAX_BAND:
			p["lock_timer"] += delta
			if p["lock_timer"] >= LOCK_IN_HOLD_TIME:
				p["locked_in"] = true
		else:
			# Falling out of the band cancels the LOCK-IN countdown, not the
			# bar's whole progress (GDD) -- pos itself is untouched here.
			p["lock_timer"] = 0.0

	_broadcast_state()

	if _all_locked_in():
		_finish_event(true)
	elif _phase_timer <= 0.0:
		_finish_event(false)


func _apply_miss(missed_peer_id: int) -> void:
	for peer_id in _participants.keys():
		var p: Dictionary = _participants[peer_id]
		if p["locked_in"]:
			continue
		if peer_id == missed_peer_id:
			p["pos"] = maxf(p["pos"] - MISS_PENALTY_SELF, 0.0)
			p["qte_active"] = false
			p["qte_prompt"] = -1
			p["qte_timer"] = randf_range(QTE_MIN_INTERVAL, QTE_MAX_INTERVAL)
		else:
			p["pos"] = maxf(p["pos"] - MISS_PENALTY_OTHERS, 0.0)
	_notify_qte_missed.rpc(missed_peer_id)


func _all_locked_in() -> bool:
	for p in _participants.values():
		if not p["locked_in"]:
			return false
	return true


func _broadcast_state() -> void:
	_notify_state_update.rpc(_participants)


func _finish_event(success: bool) -> void:
	var final_participant_ids: Array = _participants.keys()
	_phase = Phase.INACTIVE
	_participants.clear()

	for peer_id in final_participant_ids:
		var rod := _rod_for_peer(peer_id)
		if rod:
			rod._set_big_fish_event_state.rpc(false)

	if success:
		_award_big_fish(final_participant_ids)
	else:
		_apply_fail_penalty()

	_notify_event_resolved.rpc(success)


func _award_big_fish(participant_ids: Array) -> void:
	var livewell := get_tree().get_first_node_in_group("livewell") as Livewell
	if livewell == null:
		return
	var map := NetworkManager.get_current_map()
	var map_id: StringName = map.map_id if map else &"lake"
	var species: FishData = SpawnPool.roll_species(map_id)
	if species == null:
		return

	var sorted_ids: Array = participant_ids.duplicate()
	sorted_ids.sort()
	var credit_peer_id: int = sorted_ids[0] if not sorted_ids.is_empty() else 1

	# Team catch -- no single participant "caught" it, credited to "The
	# Crew" rather than picking one name arbitrarily. was_big_fish_event
	# passes true so FishFactory applies its existing 3x multiplier.
	var caught := FishFactory.create_caught_fish(
		species, credit_peer_id, "The Crew", map_id, false, [], [], true
	)
	livewell.add_big_fish(caught)


func _apply_fail_penalty() -> void:
	_remove_two_biggest_fish()
	var capsize_manager: Node = get_tree().get_first_node_in_group("capsize_manager")
	if capsize_manager:
		capsize_manager.start_capsize()


## "2 biggest fish" -- by value, per explicit decision (GDD doesn't say
## size vs value). Removes the 2 highest-final_value occupied slots.
func _remove_two_biggest_fish() -> void:
	var livewell := get_tree().get_first_node_in_group("livewell") as Livewell
	if livewell == null:
		return

	var indices: Array = []
	for i in range(Livewell.MAX_SLOTS):
		if livewell.slots[i] != null:
			indices.append(i)
	indices.sort_custom(func(a, b): return livewell.slots[a].final_value > livewell.slots[b].final_value)

	for i in range(mini(2, indices.size())):
		livewell.remove_fish(indices[i])


func _rod_for_peer(peer_id: int) -> Rod:
	var player: Player = NetworkManager.spawned_players.get(peer_id)
	if player == null:
		return null
	return player.equipment_slot.equipped_item as Rod


# ── Broadcast RPCs (host -> everyone) ───────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _notify_ready_check_started(target_spot: Vector3, duration: float) -> void:
	EventBus.big_fish_ready_check_started.emit(target_spot, duration)


@rpc("authority", "call_local", "reliable")
func _notify_participant_joined(peer_id: int) -> void:
	EventBus.big_fish_participant_joined.emit(peer_id)


@rpc("authority", "call_local", "reliable")
func _notify_event_fizzled() -> void:
	EventBus.big_fish_event_fizzled.emit()


@rpc("authority", "call_local", "reliable")
func _notify_event_active(participant_ids: Array, duration: float) -> void:
	EventBus.big_fish_event_active.emit(participant_ids, duration)


## Continuous state while active -- unreliable on purpose (this fires every
## host tick while a handful of bars are live; the next tick self-corrects
## any dropped packet, so paying for guaranteed delivery/ordering here
## would just add latency for no benefit, unlike the discrete one-shot
## events above).
@rpc("authority", "call_local", "unreliable")
func _notify_state_update(participants: Dictionary) -> void:
	EventBus.big_fish_state_updated.emit(participants)


@rpc("authority", "call_local", "reliable")
func _notify_qte_missed(peer_id: int) -> void:
	EventBus.big_fish_qte_missed.emit(peer_id)


@rpc("authority", "call_local", "reliable")
func _notify_event_resolved(success: bool) -> void:
	EventBus.big_fish_event_resolved.emit(success)


# ── Request RPCs (any peer -> host) ─────────────────────────────────────────────

func report_holding(is_holding: bool) -> void:
	_request_report_holding.rpc(is_holding)


@rpc("any_peer", "call_local", "reliable")
func _request_report_holding(is_holding: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _sender_peer_id()
	if _participants.has(peer_id):
		_participants[peer_id]["holding"] = is_holding


func report_qte_hit() -> void:
	_request_report_qte_hit.rpc()


@rpc("any_peer", "call_local", "reliable")
func _request_report_qte_hit() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _sender_peer_id()
	if not _participants.has(peer_id):
		return
	var p: Dictionary = _participants[peer_id]
	if not p["qte_active"]:
		return
	p["qte_active"] = false
	p["qte_prompt"] = -1
	p["qte_timer"] = randf_range(QTE_MIN_INTERVAL, QTE_MAX_INTERVAL)


func _sender_peer_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return 1 if sender == 0 else sender
