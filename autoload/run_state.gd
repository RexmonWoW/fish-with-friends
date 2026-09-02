extends Node

## Host-authoritative day/round/quota state for the run. Same broadcast shape
## as the rest of the codebase (host computes, broadcasts the result via a
## reliable "authority" RPC so every peer's local copy matches) -- see
## Livewell/TangleManager/BiteEventManager for the same pattern.
##
## GDD: 2 rounds = 1 day, 5-min rounds, money quota due every 2 rounds, run
## ends on a missed quota. Quota Scaling (GDD): day 1 = BASE_QUOTA *
## player-count multiplier; every day after, next_quota = round(previous_quota
## * 1.35 + surplus * 0.5), where surplus is how much total_money_earned
## cleared the previous quota by (0 if you just barely passed) -- climbs
## faster the more you clear it by, so one big haul doesn't buy several free
## days. BASE_QUOTA and the 1.35/0.5 constants are GDD's own placeholders,
## still pending real balancing.
## Quota is paid OUT of the pot at the end of each passed day -- only the
## surplus (this day's own total_money_earned minus what it owed) carries
## into the next day, so total_money_earned is per-day, not cumulative
## across the whole run.
## Fish sell at the end of EVERY round now, not just at day's end -- heading
## back to shore between rounds, per direction 2026-08-30 (previously the
## livewell carried unsold fish from round 1 into round 2). The quota
## pass/fail check still only happens once both rounds of a day are banked.
## total_money_earned IS the Per-Run Shop's shared pot -- see try_spend_from_pot.

signal round_started(round_number: int, day_number: int, duration_seconds: float)
signal round_ended(round_number: int, day_number: int)
signal round_time_synced(seconds_remaining: float)
signal round_sold(round_number: int, day_number: int, earned: int, total_money: int)
signal day_summary(day_number: int, earned: int, total_money: int, quota: int, passed: bool)
signal run_over(final_day: int, final_money: int)

## Emitted whenever the shared pot changes for a reason OTHER than the
## round/day broadcasts above (a shop purchase, or the debug money cheat)
## -- those already carry the new total themselves. GDD Per-Run Shop /
## Economy: ShopDisplay listens to refresh prices/afford-checks live as
## the crew spends, RoundHud listens to keep its money readout current.
signal pot_changed(new_total: int)

const ROUND_DURATION_SECONDS: float = 300.0  ## GDD: 5 min boat round
const ROUNDS_PER_DAY: int = 2

## GDD's own starting-point placeholders (see Quota Scaling section).
const BASE_QUOTA: int = 100
const QUOTA_DAILY_GROWTH: float = 1.35
const QUOTA_SURPLUS_FACTOR: float = 0.5

const PLAYER_COUNT_MULTIPLIER: Dictionary = {1: 1.0, 2: 1.6, 3: 2.1, 4: 2.5}

var day_number: int = 1
var round_number: int = 1  ## 1 or 2, within the current day
var total_money_earned: int = 0  ## cumulative across the whole run, never resets mid-run
var current_quota: int = 0

## GDD Boat Upgrade: Fish Finder -- crew-wide (unlike everything else the
## shop sells, which is per-player PlayerStats), so it lives here instead.
var has_fish_finder: bool = false

## GDD Run Saves: "the player-count multiplier the run was created with...
## fixed at creation and does not rescale." Set once in reset_for_new_run()
## (or restored verbatim by RunSaveManager on load) and never recomputed
## after -- the quota growth formula below is already self-contained off
## current_quota/surplus and never re-reads this past day 1, so this is
## really just record-keeping (RunSave persists it, phase 2's slot picker
## will want it), but it's real crew state GDD calls out explicitly.
var player_count_multiplier: float = 1.0

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
	player_count_multiplier = _compute_player_count_multiplier()
	current_quota = _compute_day1_quota()
	has_fish_finder = false
	_round_active = false
	_day_earned_so_far = 0


## Host-only. GDD Run Saves: restores crew-level economy state from a
## loaded save and broadcasts it to every peer -- same "host computes,
## broadcasts the result" pattern as everywhere else in this file.
## RunSaveManager calls this rather than setting these fields directly, so
## a load is never just the host's own local view. Deliberately separate
## from _notify_round_started -- that one means "a round with a real timer
## is starting," which isn't true here (a load happens sitting in the
## lobby, round_number/round timer untouched).
func restore_crew_state(day: int, quota: int, money: int, fish_finder: bool, multiplier: float) -> void:
	if not multiplayer.is_server():
		return
	_notify_crew_state_restored.rpc(day, quota, money, fish_finder, multiplier)


@rpc("authority", "call_local", "reliable")
func _notify_crew_state_restored(day: int, quota: int, money: int, fish_finder: bool, multiplier: float) -> void:
	day_number = day
	current_quota = quota
	total_money_earned = money
	has_fish_finder = fish_finder
	player_count_multiplier = multiplier


## Host-only. Called once the lake finishes loading for a round.
func start_round() -> void:
	if not multiplayer.is_server():
		return
	_time_remaining = ROUND_DURATION_SECONDS
	_round_active = true
	_notify_round_started.rpc(round_number, day_number, ROUND_DURATION_SECONDS, current_quota, total_money_earned)


@rpc("authority", "call_local", "reliable")
func _notify_round_started(r: int, d: int, duration: float, quota: int, money: int) -> void:
	round_number = r
	day_number = d
	current_quota = quota
	# Quota-paid-out (see _end_round) only ever mutates the host's own copy
	# directly, not through a broadcast of its own -- carried here instead,
	# since every peer needs the corrected total before the next day's HUD
	# readout means anything.
	total_money_earned = money
	round_started.emit(r, d, duration)


func _end_round() -> void:
	_notify_round_ended.rpc(round_number, day_number)
	_expire_round_consumables()

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
		# Quota gets paid out of the pot at day end -- only the profit
		# carries into the next day, rather than every day's earnings
		# piling up forever on top of an ever-rising quota bar. Runs after
		# _notify_day_summary above, which already reported the real
		# pre-payment total earned this day.
		total_money_earned = surplus
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


# ── Per-Run Shop (GDD Per-Run Shop / Economy) ───────────────────────────────────
## Host-authoritative purchases -- ShopCounter validates an item/price
## against ShopCatalog, then spends here BEFORE applying any stat effect,
## so a failed spend can never leave an effect applied with nothing paid.

## Host-only. Deducts amount from the shared pot -- false (no mutation, no
## broadcast) if the pot can't cover it. This is the one place in the
## codebase where a client-side desync would actually corrupt run state
## rather than just look wrong, so the deduction only ever happens here,
## never speculatively on a requesting client.
func try_spend_from_pot(amount: int) -> bool:
	if not multiplayer.is_server():
		return false
	if amount <= 0 or total_money_earned < amount:
		return false
	total_money_earned -= amount
	_notify_pot_changed.rpc(total_money_earned)
	return true


@rpc("authority", "call_local", "reliable")
func _notify_pot_changed(new_total: int) -> void:
	total_money_earned = new_total
	pot_changed.emit(new_total)


## Host-only. GDD Boat Upgrade: Fish Finder is crew-wide, unlike everything
## else the shop sells -- caller (ShopCounter) has already spent the price
## via try_spend_from_pot before calling this.
func set_fish_finder_purchased() -> void:
	if not multiplayer.is_server():
		return
	has_fish_finder = true
	_notify_fish_finder_purchased.rpc()


@rpc("authority", "call_local", "reliable")
func _notify_fish_finder_purchased() -> void:
	has_fish_finder = true


## GDD Per-Run Shop: "Bait -- fish bite faster for one round," consumable.
## Ticks down whoever has some active by one round at round end, broadcasts
## their updated stats the same way a purchase would so every peer's own
## mirror stays correct.
func _expire_round_consumables() -> void:
	if not multiplayer.is_server():
		return
	for player in NetworkManager.spawned_players.values():
		var p := player as Player
		if p.stats.bait_rounds_remaining > 0:
			p.stats.bait_rounds_remaining -= 1
			NetworkManager.broadcast_player_stats(p.peer_id, p.stats)


# ── Debug console (testing only) ────────────────────────────────────────────────
## Fast-forwarding for playtests -- e.g. the Big Fish Event only triggers in
## the last ~90s of the day's second round (BigFishEventManager), otherwise
## a long sit through most of two 5-min rounds per attempt. Host-only, same
## as every other RunState mutation; a client typing a command is a no-op.

func debug_skip_round() -> void:
	if not multiplayer.is_server() or not _round_active:
		return
	_time_remaining = 0.01


## No _round_active gate (unlike the time cheats) -- the pot exists in the
## lobby between rounds too, which is exactly where the shop lives and
## where this is actually useful for testing it.
func debug_add_money(amount: int) -> void:
	if not multiplayer.is_server():
		return
	total_money_earned += amount
	_notify_pot_changed.rpc(total_money_earned)


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


func _compute_player_count_multiplier() -> float:
	var player_count := clampi(NetworkManager.spawned_players.size(), 1, 4)
	return PLAYER_COUNT_MULTIPLIER.get(player_count, 1.0)


func _compute_day1_quota() -> int:
	return int(round(float(BASE_QUOTA) * player_count_multiplier))
