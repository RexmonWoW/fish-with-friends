class_name VisualFish
extends Node3D

## Placeholder "shadow" fish for GDD Bite Detection. Purely visual/local --
## VisualFishSpawner is the host-authoritative source of truth (ambient
## population + who's called what) and broadcasts state changes once, not a
## per-frame position sync; every peer's own instance either follows the
## shared deterministic wander formula (ShadowWander, while ambient) or
## tweens toward a broadcast target (while called to a bobber), same pattern
## LureAnimator already uses for the cast arc.
##
## Simple size-scaled placeholder blob, same convention as every other
## placeholder mesh in this codebase (bobber, rod, livewell fish) -- real
## shadow/fish art is Art & Polish's.

## Same normalization range ReelMinigame/BigFishEventManager already use
## for value-driven scaling, so future higher-tier species scale sensibly
## with no rebalancing here.
const VALUE_FOR_MIN_SIZE: float = 5.0
const VALUE_FOR_MAX_SIZE: float = 150.0
const MIN_LENGTH: float = 0.5
const MAX_LENGTH: float = 1.6

const FLEE_DISTANCE: float = 2.0
const FLEE_DURATION: float = 0.4

@export var species: FishData

var _mesh: MeshInstance3D = null
var _tween: Tween = null

## True while this shadow is ambient (following ShadowWander every frame,
## see _process) rather than mid-tween toward/away from a bobber.
var _wandering: bool = false
var _wander_home: Vector3 = Vector3.ZERO
var _wander_seed: float = 0.0
var _wander_spawn_t: float = 0.0


func _ready() -> void:
	add_to_group("visual_fish")  ## lookup for tests
	_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	var length := _length_for_species()
	capsule.height = length
	capsule.radius = length * 0.3
	_mesh.mesh = capsule
	_mesh.rotation.z = PI / 2.0  # lay flat, matches Livewell's swimming-fish convention

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.02, 0.02, 0.05, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.set_surface_override_material(0, material)
	add_child(_mesh)


func _length_for_species() -> float:
	if species == null:
		return MIN_LENGTH
	var value_t := clampf(
		(float(species.base_value) - VALUE_FOR_MIN_SIZE) / (VALUE_FOR_MAX_SIZE - VALUE_FOR_MIN_SIZE),
		0.0, 1.0
	)
	return lerpf(MIN_LENGTH, MAX_LENGTH, value_t)


## Enters (or resumes) ambient wandering -- see ShadowWander's doc comment
## for why (home, seed, spawn_t) alone is enough for every peer to agree on
## where this shadow is without any further sync.
func start_wandering(home: Vector3, seed: float, spawn_t: float) -> void:
	if _tween:
		_tween.kill()
		_tween = null
	_wander_home = home
	_wander_seed = seed
	_wander_spawn_t = spawn_t
	_wandering = true
	global_position = ShadowWander.position_at(home, seed, spawn_t)


func _process(_delta: float) -> void:
	if _wandering:
		global_position = ShadowWander.position_at(_wander_home, _wander_seed, _wander_spawn_t)


## Called to a bobber (or leaving one) -- swims from start_pos to target_pos
## over duration seconds, then holds at target_pos. Stops following the
## wander formula for the duration of the tween.
func swim_to(start_pos: Vector3, target_pos: Vector3, duration: float) -> void:
	_wandering = false
	global_position = start_pos
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "global_position", target_pos, duration)


## Missed hook window: a quick flee flourish, then resumes ambient wandering
## re-homed to wherever it fled to. flee_target/new_home/seed/spawn_t are all
## computed host-side (VisualFishSpawner.release_shadow) and broadcast, not
## rolled locally -- every peer needs to land on the exact same numbers for
## ShadowWander's zero-pop re-home trick to actually be zero-pop everywhere,
## not just on whichever peer happened to roll the flee direction.
## Ambient shadows are semi-permanent now -- only a caught fish ever
## despawns for good, a miss just sends this one back to wandering.
func spook_and_resume(flee_target: Vector3, new_home: Vector3, seed: float, spawn_t: float) -> void:
	if _tween:
		_tween.kill()
	_wandering = false
	_tween = create_tween()
	_tween.tween_property(self, "global_position", flee_target, FLEE_DURATION)
	_tween.tween_callback(func() -> void: start_wandering(new_home, seed, spawn_t))
