extends Node

## Host-authoritative day/round/quota state for the run. Same broadcast shape
## as the rest of the codebase (host computes, broadcasts the result via a
## reliable "authority" RPC so every peer's local copy matches) -- see
## Livewell/TangleManager/BiteEventManager for the same pattern.
##
## GDD: 2 rounds = 1 day, 5-min rounds, money quota due every 2 rounds
## (cumulative across days, never resets), run ends on a missed quota.
## Quota Scaling (GDD): day 1 = BASE_QUOTA * player-count multiplier; every
## day after, next_quota = round(previous_quota * 1.15 + surplus * 0.4),
## where surplus is how much the cumulative total cleared the previous
## quota by (0 if you just barely passed) -- climbs faster the more you
## clear it by, so one big haul doesn't buy several free days. BASE_QUOTA
## and the 1.15/0.4 constants are GDD's own placeholders, still pending
## real balancing.
## Fish sell at the end of EVERY round now, not just at day's end -- heading
## back to shore between rounds, per direction 2026-08-30 (previously the
## livewell carried unsold fish from round 1 into round 2). The quota
## pass/fail check still only happens once both rounds of a day are banked.

signal round_started(round_number: int, day_number: int, duration_seconds: float)
signal round_ended(round_number: int, day_number: int)
signal round_time_synced(seconds_remaining: float)
signal round_sold(round_number: int, day_number: int, earned: int, total_money: int)
signal day_summary(day_number: int, earned: int, total_money: int, quota: int, passed: bool)
signal run_over(final_day: int, final_money: int)

const ROUND_DURATION_SECONDS: float = 300.0  ## GDD: 5 min boat round
const ROUNDS_PER_DAY: int = 2

## GDD's own starting-point placeholders (see Quota Scaling section).
const BASE_QUOTA: int = 100
const QUOTA_DAILY_GROWTH: float = 1.15
const QUOTA_SURPLUS_FACTOR: float = 0.4

const PLAYER_COUNT_MULTIPLIER: Dictionary = {1: 1.0, 2: 1.6, 3: 2.1, 4: 2.5}

var day_number: int = 1
var round_number: int = 1  ## 1 or 2, within the current day
var total_money_earned: int = 0  ## cumulative across the whole run, never resets mid-run
var current_quota: int = 0

var _time_remaining: float = 0.0
var _round_active: bool = false  ## host-only: is the round timer actually ticking
var _day_earned_so_far: int = 0  ## sum of each round's sale within the current day, reported in day_summary


func _process(delta: float) -> void:
	if not _round_active or not multiplayer.is_server():
		return
	_time_remaining -= delta
	if _time_remaining <= 0.0:
		_round_active = false
		_end_round()


## Called by NetworkManager whenever a NEW run starts (host_lobby or joining
## a lobby) so a previous run's state doesn't leak into the next one.
func reset_for_new_run() -> void:
	day_number = 1
	round_number = 1
	total_money_earned = 0
	current_quota = _compute_day1_quota()
	_round_active = false
	_day_earned_so_far = 0


## Host-only. Called once the lake finishes loading for a round.
func start_round() -> void:
	if not multiplayer.is_server():
		return
	_time_remaining = ROUND_DURATION_SECONDS
	_round_active = true
	_notify_round_started.rpc(round_number, day_number, ROUND_DURATION_SECONDS, current_quota)


@rpc("authority", "call_local", "reliable")
func _notify_round_started(r: int, d: int, duration: float, quota: int) -> void:
	round_number = r
	day_number = d
	current_quota = quota
	round_started.emit(r, d, duration)


func _end_round() -> void:
	_notify_round_ended.rpc(round_number, day_number)

	# Sell whatever's in the livewell every round -- heading back to shore --
	# and bank it immediately. The quota pass/fail check still only happens
	# once both rounds of a day are in, below. Also sells any fish still
	# HELD (caught but never stored with E) -- otherwise it just silently
	# carried forward into the next round instead of being part of the sale.
	var earned := _sell_all_livewells() + _sell_held_fish()
	total_money_earned += earned
	_day_earned_so_far += earned

	if round_number < ROUNDS_PER_DAY:
		var finished_round := round_number
		round_number += 1
		_notify_round_sold.rpc(finished_round, day_number, earned, total_money_earned)
		NetworkManager.return_to_lobby_between_rounds()
		return

	var day_earned := _day_earned_so_far
	_day_earned_so_far = 0
	var passed := total_money_earned >= current_quota
	var finished_day := day_number

	_notify_day_summary.rpc(finished_day, day_earned, total_money_earned, current_quota, passed)

	if passed:
		var surplus := maxi(total_money_earned - current_quota, 0)
		current_quota = int(round(float(current_quota) * QUOTA_DAILY_GROWTH + float(surplus) * QUOTA_SURPLUS_FACTOR))
		day_number += 1
		round_number = 1
		NetworkManager.return_to_lobby_between_rounds()
	else:
		_notify_run_over.rpc(finished_day, total_money_earned)


@rpc("authority", "call_local", "reliable")
func _notify_round_ended(r: int, d: int) -> void:
	round_ended.emit(r, d)


@rpc("authority", "call_local", "reliable")
func _notify_round_sold(r: int, d: int, earned: int, total: int) -> void:
	total_money_earned = total
	round_sold.emit(r, d, earned, total)


@rpc("authority", "call_local", "reliable")
func _notify_day_summary(d: int, earned: int, total: int, quota: int, passed: bool) -> void:
	total_money_earned = total
	day_summary.emit(d, earned, total, quota, passed)


@rpc("authority", "call_local", "reliable")
func _notify_run_over(final_day: int, final_money: int) -> void:
	run_over.emit(final_day, final_money)


## Read-only preview of what's currently sitting in the livewell(s), unsold
## -- lets the HUD show real progress toward quota during a round instead of
## a number that only ever changes at day boundaries. Every peer's local
## Livewell.slots mirror is already kept in sync via the existing add/remove
## broadcast RPCs, so this is safe to compute locally on any peer, not just
## the host.
func get_livewell_value() -> int:
	var value := 0
	for livewell_node in get_tree().get_nodes_in_group("livewell"):
		var livewell := livewell_node as Livewell
		if livewell == null:
			continue
		for fish in livewell.slots:
			if fish != null:
				value += (fish as CaughtFish).final_value
	return value


## total_money_earned (banked/sold) + whatever's currently sitting unsold in
## the livewell -- what the player would actually clear if the day ended
## right now.
func get_projected_total() -> int:
	return total_money_earned + get_livewell_value()


func _sell_all_livewells() -> int:
	var earned := 0
	for livewell_node in get_tree().get_nodes_in_group("livewell"):
		var livewell := livewell_node as Livewell
		if livewell == null:
			continue
		for i in range(Livewell.MAX_SLOTS):
			var fish := livewell.remove_fish(i)
			if fish != null:
				earned += fish.final_value
		# The reserved Big Fish Event slot is separate from the 5 normal
		# slots and was never included here -- it just sat there forever,
		# never sold ("some of the ones in the livewell didn't sell").
		var big_fish := livewell.remove_big_fish()
		if big_fish != null:
			earned += big_fish.final_value
	return earned


func _sell_held_fish() -> int:
	var earned := 0
	for player in NetworkManager.spawned_players.values():
		earned += (player as Player).equipment_slot.sell_held_fish_for_round_end()
	return earned


# ── Debug console (testing only) ────────────────────────────────────────────────
## Fast-forwarding for playtests -- e.g. the Big Fish Event only triggers in
## the last ~90s of the day's second round (BigFishEventManager), otherwise
## a long sit through most of two 5-min rounds per attempt. Host-only, same
## as every other RunState mutation; a client typing a command is a no-op.

func debug_skip_round() -> void:
	if not multiplayer.is_server() or not _round_active:
		return
	_time_remaining = 0.01


## Also broadcasts the new time so every peer's HUD countdown -- which
## normally just ticks down locally from the duration given at round start,
## rather than re-syncing every frame -- actually reflects the jump instead
## of silently drifting from the real (server-authoritative) clock.
func debug_set_time_remaining(seconds: float) -> void:
	if not multiplayer.is_server() or not _round_active:
		return
	_time_remaining = maxf(seconds, 0.01)
	_notify_time_synced.rpc(_time_remaining)


@rpc("authority", "call_local", "reliable")
func _notify_time_synced(seconds: float) -> void:
	round_time_synced.emit(seconds)


## Ends the current round; if that was round 1, walks through the same
## NetworkManager.request_start_round() a player triggers at the lobby's
## StartTrigger so round 2 actually loads for real instead of skipping the
## transition, then ends round 2 too.
func debug_skip_day() -> void:
	if not multiplayer.is_server() or not _round_active:
		return
	if round_number < ROUNDS_PER_DAY:
		debug_skip_round()
		await round_ended
		await get_tree().create_timer(0.5).timeout
		NetworkManager.request_start_round()
		await round_started
		await get_tree().create_timer(0.2).timeout
	debug_skip_round()


func _compute_day1_quota() -> int:
	var player_count := clampi(NetworkManager.spawned_players.size(), 1, 4)
	var multiplier: float = PLAYER_COUNT_MULTIPLIER.get(player_count, 1.0)
	return int(round(float(BASE_QUOTA) * multiplier))
