class_name BiteEventManager
extends Node

## Host-authoritative. Owns the bite event lifecycle (GDD Bite Detection):
## fish are a standing ambient population (VisualFishSpawner) that swims
## around continuously instead of biting on an invisible timer. Casting near
## one calls it -- it breaks off and swims to the landed bobber; casting
## where nothing's nearby isn't a dead cast, this just keeps polling for a
## wandering shadow to drift into range (see CALL_RADIUS_GROWTH_PER_SEC).
## Arrival opens a short hook-set window; miss it and the fish spooks back
## off to wander again (still out there, callable by anyone). Hook-set
## success drops into the existing Reel Mechanic exactly as before -- this
## rework only changes what happens BEFORE bite_started fires, not what
## happens after.

const HOOK_WINDOW_SECONDS: float = 1.0      ## how long the player has to set the hook once struck
const SPOOK_PAUSE_SECONDS: float = 1.5      ## pause before looking for another shadow after a miss

## "Aiming well gets a faster, more certain bite; aiming blind means waiting
## on whatever wanders by" (GDD) -- rather than a hard "nothing nearby, no
## bite," the radius VisualFishSpawner.try_call_for() searches within grows
## the longer a caster's been waiting, so a blind cast is never truly dead,
## just slower and less precise. Capped at CALL_RADIUS_MAX -- GDD's spatial
## rarity ("a shadow across the lake never comes to you... gives the water a
## readable shape") only means something if waiting long enough can't
## eventually reach literally everything, the way an uncapped grow rate did.
const CALL_RADIUS_BASE: float = 4.0
const CALL_RADIUS_GROWTH_PER_SEC: float = 12.0
const CALL_RADIUS_MAX: float = 10.0  ## conservative placeholder, tune by feel

## Assign res://entities/fish/fish.tscn in the inspector.
@export var fish_scene: PackedScene

## Set this to the current map's StringName when a round starts.
## SpawnPool uses it to filter valid species.
var current_map_id: StringName = &""

## True while a caster has an in-flight bite attempt (shadow approaching,
## or waiting on a hook-set window) -- same name/shape tests already poke
## directly (e.g. "a normal bite got scheduled anyway"), just no longer
## backed by literal Timer objects now that the sequence spans multiple
## stages via an awaited coroutine.
var _pending: Dictionary = {}  # int → true

## Bumped every time a new sequence starts for a peer; an in-flight
## _run_bite_sequence() call checks its own captured id against this after
## every await and quietly stops if they no longer match -- the same
## "only proceed if nothing else already moved this on" guard used
## elsewhere in this codebase (e.g. LureAnimator._on_arc_complete).
var _sequence_id: Dictionary = {}  # int → int
var _next_sequence_id: int = 0

## True while a hook-set window is currently open for that peer --
## request_hook_set() only counts while this is true.
var _hook_open: Dictionary = {}  # int → bool
var _hook_set: Dictionary = {}  # int → bool, set by a successful request_hook_set()

## Fish currently on someone's line, keyed by caster_peer_id.
var _active_fish: Dictionary = {}  # int → Fish


func _ready() -> void:
	# Every peer needs its own local node in this group -- Rod looks this up
	# on whichever client owns the rod (any peer, not just the host) to
	# resolve a hook-set press. Gating add_to_group itself on is_server()
	# left every non-host client's own lookup returning null and the press
	# silently dropped (same pass-37 lesson as ReelFightManager/
	# VisualFishSpawner). Only the actual host-authoritative behavior stays
	# behind the is_server() check.
	add_to_group("bite_event_manager")
	if not multiplayer.is_server():
		return
	EventBus.cast_landed.connect(_on_cast_landed)


# ── Internal ───────────────────────────────────────────────────────────────────

func _on_cast_landed(endpoint: Vector3, flight_seconds: float, caster_peer_id: int) -> void:
	# A cast landing on an active Big Fish Event's ready-check spot joins
	# that instead of becoming a normal bite -- checked first (not
	# "schedule then cancel") so this doesn't depend on which system's
	# cast_landed listener happens to run first.
	var big_fish: Node = get_tree().get_first_node_in_group("big_fish_event_manager")
	if big_fish and big_fish.try_join(caster_peer_id, endpoint):
		return

	_cancel_pending(caster_peer_id)
	_run_bite_sequence(caster_peer_id, endpoint, flight_seconds)


## One cast's full bite sequence, host-only: wait for the lure to actually
## land, then cycle waiting-for-a-shadow / hook-set-window attempts until
## the player successfully sets the hook (-> the existing bite_started/reel
## flow, unchanged) or the sequence is canceled some other way (recast,
## tangle loss, disconnect -- _cancel_pending() bumps _sequence_id so this
## just quietly stops mattering).
func _run_bite_sequence(caster_peer_id: int, endpoint: Vector3, flight_seconds: float) -> void:
	var my_sequence := _next_sequence_id
	_next_sequence_id += 1
	_sequence_id[caster_peer_id] = my_sequence
	_pending[caster_peer_id] = true

	await get_tree().create_timer(flight_seconds).timeout
	if _sequence_id.get(caster_peer_id, -1) != my_sequence:
		return

	var spawner: Node = get_tree().get_first_node_in_group("visual_fish_spawner")
	if spawner == null:
		push_warning("BiteEventManager: no VisualFishSpawner found -- no bite possible.")
		_pending.erase(caster_peer_id)
		return

	while true:
		# Poll for a wandering shadow within range, widening the search the
		# longer this particular attempt (this shadow, this hook window) has
		# been waiting -- see CALL_RADIUS_GROWTH_PER_SEC's doc comment above.
		# Not a dead cast even if nothing's nearby yet, but capped so it's
		# never a dead cast that ALSO quietly stops meaning where you aimed.
		var call_result: Dictionary = {}
		var waited := 0.0
		while call_result.is_empty():
			var radius := minf(CALL_RADIUS_BASE + CALL_RADIUS_GROWTH_PER_SEC * waited, CALL_RADIUS_MAX)
			call_result = spawner.try_call_for(caster_peer_id, endpoint, radius)
			if not call_result.is_empty():
				break
			await get_tree().process_frame
			waited += get_process_delta_time()
			if _sequence_id.get(caster_peer_id, -1) != my_sequence:
				return

		var shadow_id: int = call_result["id"]
		var species: FishData = call_result["species"]
		var travel_duration: float = call_result["duration"]

		await get_tree().create_timer(travel_duration).timeout
		if _sequence_id.get(caster_peer_id, -1) != my_sequence:
			spawner.cancel_call(caster_peer_id)
			return

		# Struck -- open the hook-set window and wait for either a
		# successful request_hook_set() or the window running out,
		# whichever comes first. Polled per-frame rather than a flat
		# await so a press near the start of the window resolves
		# immediately instead of sitting through the whole thing.
		_hook_open[caster_peer_id] = true
		_hook_set[caster_peer_id] = false
		_notify_hook_window.rpc(caster_peer_id, HOOK_WINDOW_SECONDS)

		var elapsed := 0.0
		while elapsed < HOOK_WINDOW_SECONDS and not _hook_set.get(caster_peer_id, false):
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			if _sequence_id.get(caster_peer_id, -1) != my_sequence:
				spawner.cancel_call(caster_peer_id)
				return

		_hook_open[caster_peer_id] = false

		if _hook_set.get(caster_peer_id, false):
			spawner.catch_shadow(shadow_id)
			_pending.erase(caster_peer_id)
			_fire_bite(endpoint, caster_peer_id, species)
			return

		# Missed -- shadow spooks back to wandering (still out there, free
		# for anyone to call again), brief pause, then look for the next one.
		spawner.release_shadow(shadow_id)
		_notify_hook_missed.rpc(caster_peer_id)

		await get_tree().create_timer(SPOOK_PAUSE_SECONDS).timeout
		if _sequence_id.get(caster_peer_id, -1) != my_sequence:
			return


@rpc("authority", "call_local", "reliable")
func _notify_hook_window(caster_peer_id: int, duration: float) -> void:
	EventBus.bite_hook_window_opened.emit(caster_peer_id, duration)


@rpc("authority", "call_local", "reliable")
func _notify_hook_missed(caster_peer_id: int) -> void:
	EventBus.bite_hook_window_missed.emit(caster_peer_id)


## Called by Rod (any peer, host validates the sender) when the local
## player presses during their own open hook-set window.
func request_hook_set() -> void:
	_request_hook_set.rpc()


@rpc("any_peer", "call_local", "reliable")
func _request_hook_set() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := 1 if sender == 0 else sender
	if not _hook_open.get(peer_id, false):
		return  # too early, too late, or never opened -- silently ignored
	_hook_set[peer_id] = true


func _fire_bite(endpoint: Vector3, caster_peer_id: int, fish_data: FishData) -> void:
	if fish_scene == null:
		push_error("BiteEventManager: fish_scene not assigned in inspector.")
		return

	var fish: Fish = fish_scene.instantiate() as Fish
	fish.species = fish_data
	fish.bound_to_peer_id = caster_peer_id
	# Must be inside the tree before global_position resolves against a parent.
	get_tree().root.add_child(fish)
	fish.global_position = endpoint
	_active_fish[caster_peer_id] = fish

	# GDD Reel Mechanic: the real bobber reels in as this fight progresses,
	# visible to every nearby peer -- needs the real landing spot, which the
	# public bite_started signal doesn't carry.
	var reel_fight_manager: Node = get_tree().get_first_node_in_group("reel_fight_manager")
	if reel_fight_manager:
		reel_fight_manager.start_fight(caster_peer_id, endpoint)

	# Broadcast, not a local emit -- otherwise only the host ever sees their
	# own bite_started, and a joining client's ReelMinigame never appears.
	_notify_bite.rpc(fish_data, caster_peer_id)


@rpc("authority", "call_local", "reliable")
func _notify_bite(fish_data: FishData, caster_peer_id: int) -> void:
	EventBus.bite_started.emit(fish_data, caster_peer_id)


func _cancel_pending(caster_peer_id: int) -> void:
	_sequence_id[caster_peer_id] = -1  # invalidates any in-flight _run_bite_sequence await
	_hook_open[caster_peer_id] = false
	_hook_set[caster_peer_id] = false
	_pending.erase(caster_peer_id)
	# Resets Rod's own per-owner _hook_window_open flag even if no window was
	# actually open (harmless/idempotent either way) -- without this, a
	# capsize or cancel interrupting an open window left that flag stuck
	# true client-side, since only bite_started/bite_hook_window_missed ever
	# clear it and neither fires on this path otherwise.
	_notify_hook_missed.rpc(caster_peer_id)
	var spawner: Node = get_tree().get_first_node_in_group("visual_fish_spawner")
	if spawner:
		spawner.cancel_call(caster_peer_id)  # no-op if nothing was called for them yet
	var reel_fight_manager: Node = get_tree().get_first_node_in_group("reel_fight_manager")
	if reel_fight_manager:
		reel_fight_manager.cancel_fight(caster_peer_id)  # no-op if no fight was active yet


## Called by TangleManager (host-side) when a tangle-loser's line snaps --
## cancels their in-flight bite attempt and despawns any fish already on
## their line. A tangle can currently only start while both rods are
## WAITING_BITE (see Rod._on_line_area_entered), so an active fish
## shouldn't normally coexist with a pending attempt, but cheap to clean up
## either way rather than assume.
func cancel_pending_bite(peer_id: int) -> void:
	_cancel_pending(peer_id)
	if _active_fish.has(peer_id):
		var fish: Fish = _active_fish[peer_id]
		if is_instance_valid(fish):
			fish.queue_free()
		_active_fish.erase(peer_id)


## Called by Rod (host-side) once the owning client's local reel minigame
## has finished. On success, builds a CaughtFish and hands it to the
## catching player to hold (EquipmentSlot.equip_fish, broadcast to every
## peer) rather than dropping it straight into the livewell -- the player
## then chooses to toss it back or store/swap it into a specific slot. Live
## Fish is despawned either way. was_perfect (zero QTE misses) drives
## FishFactory's value bonus.
func resolve_reel(caster_peer_id: int, success: bool, was_perfect: bool) -> void:
	if _active_fish.has(caster_peer_id):
		var fish: Fish = _active_fish[caster_peer_id]
		if is_instance_valid(fish):
			if success:
				fish.was_perfect = was_perfect
				_give_catch_to_player(fish, caster_peer_id)
			fish.queue_free()
		_active_fish.erase(caster_peer_id)
	var reel_fight_manager: Node = get_tree().get_first_node_in_group("reel_fight_manager")
	if reel_fight_manager:
		reel_fight_manager.cancel_fight(caster_peer_id)
	_notify_reel_finished.rpc(success, caster_peer_id)


@rpc("authority", "call_local", "reliable")
func _notify_reel_finished(success: bool, caster_peer_id: int) -> void:
	EventBus.reel_finished.emit(success, caster_peer_id)


func _give_catch_to_player(fish: Fish, caster_peer_id: int) -> void:
	var player: Player = NetworkManager.spawned_players.get(caster_peer_id)
	if player == null:
		push_warning("BiteEventManager: no Player found for peer %d, catch discarded." % caster_peer_id)
		return

	var special_attrs: Array[StringName] = []
	var caught := FishFactory.create_caught_fish(
		fish.species,
		caster_peer_id,
		SteamManager.get_display_name_for_peer(caster_peer_id),
		current_map_id,
		fish.was_perfect,
		special_attrs,
		fish.hazards_active,
		false
	)

	player.equipment_slot._receive_caught_fish.rpc(caught)
