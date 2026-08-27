class_name Livewell
extends Node3D

## Shared, 5 slots. Host-authoritative state.
## Each map places its own Livewell in its PlayableArea.
## Negotiation UI for a full livewell and per-slot visual fish display are
## still a future dispatch. Proximity display + throw-overboard (any player
## can pull any fish to free a slot) are wired via LivewellDisplay UI.

const MAX_SLOTS: int = 5

## Placeholder capsule size range -- swaps for a real model later. Scaled
## between these by where the fish's rolled size falls in its species'
## min_size..max_size range.
const VISUAL_MIN_LENGTH: float = 0.14
const VISUAL_MAX_LENGTH: float = 0.34
const VISUAL_RADIUS_RATIO: float = 0.22  # capsule radius as a fraction of its length

var slots: Array = []                ## Array of CaughtFish (or null for empty slots)
var big_fish_slot: CaughtFish = null ## Reserved slot for big fish event catches

@onready var fish_display: Node3D = $FishDisplay

var _visuals: Array = []  ## Array of MeshInstance3D (or null), parallel to slots.


func _ready() -> void:
	slots.resize(MAX_SLOTS)
	_visuals.resize(MAX_SLOTS)
	add_to_group("livewell")  ## Systems can find any livewell via group lookup

	var zone: Area3D = $InteractionZone
	zone.body_entered.connect(_on_body_entered)
	zone.body_exited.connect(_on_body_exited)


## Host-authoritative. Returns the slot index the fish landed in, or -1 if
## every slot is full (caller decides what to do -- MVP just discards it).
func add_fish(fish: CaughtFish) -> int:
	for i in range(MAX_SLOTS):
		if slots[i] == null:
			slots[i] = fish
			_spawn_visual(i, fish)
			EventBus.livewell_updated.emit(self)
			return i
	return -1


## Host-authoritative. Removes and returns the fish at index (throw overboard
## or sell-at-end-of-day both go through this). Null if the slot was empty
## or out of range.
func remove_fish(index: int) -> CaughtFish:
	if index < 0 or index >= MAX_SLOTS:
		return null
	var fish: CaughtFish = slots[index]
	if fish != null:
		slots[index] = null
		_clear_visual(index)
		EventBus.livewell_updated.emit(self)
	return fish


func is_full() -> bool:
	return not slots.has(null)


# ── Interaction (throw a fish overboard to free a slot) ────────────────────────
## GDD: any player can grab any fish and throw it overboard, no confirmation.

func request_remove_fish(index: int) -> void:
	_request_remove_fish.rpc(index)


@rpc("any_peer", "call_local", "reliable")
func _request_remove_fish(index: int) -> void:
	if not multiplayer.is_server():
		return
	remove_fish(index)


# ── Proximity (local-only, drives LivewellDisplay UI) ───────────────────────────

func _on_body_entered(body: Node) -> void:
	var player := body as Player
	if player == null or player.peer_id != multiplayer.get_unique_id():
		return
	EventBus.livewell_proximity_changed.emit(self, true)


func _on_body_exited(body: Node) -> void:
	var player := body as Player
	if player == null or player.peer_id != multiplayer.get_unique_id():
		return
	EventBus.livewell_proximity_changed.emit(self, false)


# ── Visuals ──────────────────────────────────────────────────────────────────
## Placeholder capsule per slot, parented to that slot's Marker3D. Not
## networked yet -- see PROGRESS.md open questions on livewell replication.
## Swimming/animated fish is a planned follow-up; this is static placement.
## Sized by the fish's rolled size relative to its species' min/max, tinted
## by species (same species always gets the same color) -- just for visual
## variety until real models exist.

func _spawn_visual(index: int, fish: CaughtFish) -> void:
	_clear_visual(index)

	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	var length := _visual_length_for(fish)
	capsule.height = length
	capsule.radius = length * VISUAL_RADIUS_RATIO
	mesh_instance.mesh = capsule
	# Capsules stand upright by default; lay it on its side like a resting fish.
	mesh_instance.rotation.z = PI / 2.0

	var material := StandardMaterial3D.new()
	material.albedo_color = _color_for_species(fish.species.species_id)
	mesh_instance.set_surface_override_material(0, material)

	fish_display.get_child(index).add_child(mesh_instance)
	_visuals[index] = mesh_instance


func _visual_length_for(fish: CaughtFish) -> float:
	var species := fish.species
	var size_range := species.max_size - species.min_size
	var t := 0.5 if size_range <= 0.0 else clampf(
		(fish.size - species.min_size) / size_range, 0.0, 1.0
	)
	return lerpf(VISUAL_MIN_LENGTH, VISUAL_MAX_LENGTH, t)


func _color_for_species(species_id: StringName) -> Color:
	# Deterministic per species -- same species always looks the same.
	var hue := float(hash(species_id) % 360) / 360.0
	return Color.from_hsv(hue, 0.6, 0.85)


func _clear_visual(index: int) -> void:
	var existing = _visuals[index]
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	_visuals[index] = null
