class_name BiteEventManager
extends Node

## Host-authoritative. Owns the bite event lifecycle.
## Listens for cast_landed, waits flight_seconds + bite_delay,
## spawns a Fish entity, broadcasts bite_started to every peer.
## Minigame Logic owns the reel trigger — this script stops at the signal.

const BITE_DELAY: float = 2.0  # placeholder — real roll belongs to Minigame Logic

## Assign res://entities/fish/fish.tscn in the inspector.
@export var fish_scene: PackedScene

## Set this to the current map's StringName when a round starts.
## SpawnPool uses it to filter valid species.
var current_map_id: StringName = &""

## In-flight timers keyed by caster_peer_id so re-casts cancel the previous bite.
var _pending: Dictionary = {}  # int → Timer

## Fish currently on someone's line, keyed by caster_peer_id.
var _active_fish: Dictionary = {}  # int → Fish


func _ready() -> void:
	if not multiplayer.is_server():
		return
	add_to_group("bite_event_manager")  ## Rod looks this up to resolve a reel.
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

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = flight_seconds + BITE_DELAY
	add_child(timer)
	timer.timeout.connect(func() -> void:
		_fire_bite(endpoint, caster_peer_id)
		_pending.erase(caster_peer_id)
		timer.queue_free()
	)
	_pending[caster_peer_id] = timer
	timer.start()


func _fire_bite(endpoint: Vector3, caster_peer_id: int) -> void:
	var fish_data: FishData = SpawnPool.roll_species(current_map_id)
	if fish_data == null:
		push_warning("BiteEventManager: SpawnPool returned null for map '%s'" % current_map_id)
		return

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

	# Broadcast, not a local emit -- otherwise only the host ever sees their
	# own bite_started, and a joining client's ReelMinigame never appears.
	_notify_bite.rpc(fish_data, caster_peer_id)


@rpc("authority", "call_local", "reliable")
func _notify_bite(fish_data: FishData, caster_peer_id: int) -> void:
	EventBus.bite_started.emit(fish_data, caster_peer_id)


func _cancel_pending(caster_peer_id: int) -> void:
	if _pending.has(caster_peer_id):
		var t: Timer = _pending[caster_peer_id]
		t.queue_free()
		_pending.erase(caster_peer_id)


## Called by TangleManager (host-side) when a tangle-loser's line snaps --
## cancels their pending bite timer and despawns any fish already on their
## line. A tangle can currently only start while both rods are WAITING_BITE
## (see Rod._on_line_area_entered), so an active fish shouldn't normally
## coexist with one, but cheap to clean up either way rather than assume.
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
