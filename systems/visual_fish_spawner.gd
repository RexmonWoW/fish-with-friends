class_name VisualFishSpawner
extends Node

## Host-authoritative broadcaster for the "shadow" fish used by Bite
## Detection (GDD). BiteEventManager owns the actual approach/strike/hook-
## window state machine (a host-side timer sequence) and calls into this
## purely to spawn/despawn the shared visual -- same division as other
## Manager/visual pairs in this codebase (e.g. BigFishEventManager owns
## state, BigFishEventMinigame owns rendering).
##
## Broadcasts ONCE per spawn (start/target/duration), not a per-frame
## position sync -- every peer's own VisualFish instance independently
## tweens from that, same pattern LureAnimator already uses for the cast
## arc. Satisfies GDD's "synced across players -- a real fish everyone can
## see" without needing continuous network traffic for something this
## simple.

const VISUAL_FISH_SCENE: PackedScene = preload("res://entities/visual_fish/visual_fish.tscn")

var _shadows: Dictionary = {}  # peer_id (int) -> VisualFish, this peer's OWN local mirror


func _ready() -> void:
	add_to_group("visual_fish_spawner")


## Broadcasts a new shadow for peer_id, swimming from start_pos toward
## target_pos over duration seconds. Clears any stale shadow for that peer
## first (shouldn't normally happen -- BiteEventManager despawns before
## spawning the next one -- but cheap to be sure).
func spawn_shadow(peer_id: int, species: FishData, start_pos: Vector3, target_pos: Vector3, duration: float) -> void:
	_clear_shadow.rpc(peer_id, false)
	_spawn_shadow.rpc(peer_id, species, start_pos, target_pos, duration)


@rpc("authority", "call_local", "reliable")
func _spawn_shadow(peer_id: int, species: FishData, start_pos: Vector3, target_pos: Vector3, duration: float) -> void:
	var fish := VISUAL_FISH_SCENE.instantiate() as VisualFish
	fish.species = species
	get_tree().root.add_child(fish)
	fish.swim_to(start_pos, target_pos, duration)
	_shadows[peer_id] = fish


## Despawns peer_id's current shadow -- spook=true flees it off first (a
## missed hook window), spook=false removes it immediately (struck
## successfully, or canceled some other way).
func despawn_shadow(peer_id: int, spook: bool) -> void:
	_clear_shadow.rpc(peer_id, spook)


@rpc("authority", "call_local", "reliable")
func _clear_shadow(peer_id: int, spook: bool) -> void:
	if not _shadows.has(peer_id):
		return
	var fish: VisualFish = _shadows[peer_id]
	_shadows.erase(peer_id)
	if not is_instance_valid(fish):
		return
	if spook:
		var direction := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		fish.spook_away(direction)
	else:
		fish.queue_free()
