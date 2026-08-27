class_name BiteEventManager
extends Node

## Host-only. Owns the bite event lifecycle.
## Listens for cast_landed, waits flight_seconds + bite_delay,
## spawns a Fish entity, emits bite_started.
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

	EventBus.bite_started.emit(fish_data, caster_peer_id)


func _cancel_pending(caster_peer_id: int) -> void:
	if _pending.has(caster_peer_id):
		var t: Timer = _pending[caster_peer_id]
		t.queue_free()
		_pending.erase(caster_peer_id)


## Called by Rod (host-side) once the owning client's local reel minigame
## has finished. On success, builds a CaughtFish and adds it to the map's
## Livewell before despawning the live Fish either way.
func resolve_reel(caster_peer_id: int, success: bool) -> void:
	if _active_fish.has(caster_peer_id):
		var fish: Fish = _active_fish[caster_peer_id]
		if is_instance_valid(fish):
			if success:
				_add_catch_to_livewell(fish, caster_peer_id)
			fish.queue_free()
		_active_fish.erase(caster_peer_id)
	EventBus.reel_finished.emit(success, caster_peer_id)


func _add_catch_to_livewell(fish: Fish, caster_peer_id: int) -> void:
	var livewell := get_tree().get_first_node_in_group("livewell") as Livewell
	if livewell == null:
		push_warning("BiteEventManager: no Livewell in scene, catch discarded.")
		return

	var special_attrs: Array[StringName] = []
	var caught := FishFactory.create_caught_fish(
		fish.species,
		caster_peer_id,
		"Player %d" % caster_peer_id,  ## TODO: real display name once Steam persona lookup is wired
		current_map_id,
		fish.was_perfect,
		special_attrs,
		fish.hazards_active,
		false
	)

	if livewell.add_fish(caught) == -1:
		push_warning("BiteEventManager: livewell full, catch discarded (peer %d)." % caster_peer_id)
