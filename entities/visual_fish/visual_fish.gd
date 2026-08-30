class_name VisualFish
extends Node3D

## Placeholder "shadow" fish for GDD Bite Detection: a shadow approaches the
## landed bobber and strikes, size hinting at species/rarity. Purely
## visual/local -- VisualFishSpawner broadcasts spawn/despawn once (not a
## per-frame position sync), and every peer's own instance independently
## tweens from the same start/target/duration, same pattern LureAnimator
## already uses for the cast arc. No gameplay logic lives here;
## BiteEventManager alone decides when it "struck" (a host-side timer, not
## by inspecting this node), so a client's tween running slightly out of
## sync with the host's own copy has no gameplay consequence.
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

@export var species: FishData

var _mesh: MeshInstance3D = null
var _tween: Tween = null


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


## Swims from start_pos to target_pos over duration seconds, then holds at
## target_pos (the "struck" pose -- BiteEventManager's own host-side timer
## decides what happens next, this just keeps looking like it's there).
func swim_to(start_pos: Vector3, target_pos: Vector3, duration: float) -> void:
	global_position = start_pos
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "global_position", target_pos, duration)


## Flees off in a direction and despawns -- the "spooked" miss reaction.
func spook_away(direction: Vector3) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "global_position", global_position + direction.normalized() * 5.0, 0.5)
	_tween.tween_callback(queue_free)
