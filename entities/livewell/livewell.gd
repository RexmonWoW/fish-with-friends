class_name Livewell
extends Node3D

## Shared, 5 slots. Host-authoritative state.
## Each map places its own Livewell in its PlayableArea.
## Negotiation UI for a full livewell, throw-overboard interaction, and
## per-slot visual fish display are still a future dispatch -- this covers
## the data-layer add/remove that BiteEventManager needs to close the loop.

const MAX_SLOTS: int = 5

## Placeholder capsule size -- swaps for a real model later.
const VISUAL_RADIUS: float = 0.05
const VISUAL_LENGTH: float = 0.22

## Rarity (FishData's @export_enum index) -> placeholder tint.
const RARITY_COLORS: Array[Color] = [
	Color(0.75, 0.75, 0.75), # Common
	Color(0.3, 0.8, 0.4),    # Uncommon
	Color(0.3, 0.5, 0.95),   # Rare
	Color(0.85, 0.55, 0.15), # Legendary
	Color(0.9, 0.2, 0.85),   # Mythic
]

var slots: Array = []                ## Array of CaughtFish (or null for empty slots)
var big_fish_slot: CaughtFish = null ## Reserved slot for big fish event catches

@onready var fish_display: Node3D = $FishDisplay

var _visuals: Array = []  ## Array of MeshInstance3D (or null), parallel to slots.


func _ready() -> void:
	slots.resize(MAX_SLOTS)
	_visuals.resize(MAX_SLOTS)
	add_to_group("livewell")  ## Systems can find any livewell via group lookup


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


# ── Visuals ──────────────────────────────────────────────────────────────────
## Placeholder capsule per slot, parented to that slot's Marker3D. Not
## networked yet -- see PROGRESS.md open questions on livewell replication.
## Swimming/animated fish is a planned follow-up; this is static placement.

func _spawn_visual(index: int, fish: CaughtFish) -> void:
	_clear_visual(index)

	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = VISUAL_RADIUS
	capsule.height = VISUAL_LENGTH
	mesh_instance.mesh = capsule
	# Capsules stand upright by default; lay it on its side like a resting fish.
	mesh_instance.rotation.z = PI / 2.0

	var rarity: int = clampi(fish.species.rarity, 0, RARITY_COLORS.size() - 1)
	var material := StandardMaterial3D.new()
	material.albedo_color = RARITY_COLORS[rarity]
	mesh_instance.set_surface_override_material(0, material)

	fish_display.get_child(index).add_child(mesh_instance)
	_visuals[index] = mesh_instance


func _clear_visual(index: int) -> void:
	var existing = _visuals[index]
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	_visuals[index] = null
