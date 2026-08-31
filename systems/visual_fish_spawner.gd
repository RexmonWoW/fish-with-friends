class_name VisualFishSpawner
extends Node

## Host-authoritative. GDD Bite Detection rework: fish are a standing
## ambient population that swims around continuously (ShadowWander), not
## spawned per-cast. Casting near one calls it -- it breaks off to swim to
## the bobber; casting where nothing's currently nearby isn't a dead cast,
## BiteEventManager just keeps polling try_call_for() every frame until a
## wandering shadow drifts into range (see its own growing-radius comment).
## Once called, a shadow is exclusively that caster's until it's released
## (missed hook window -- back to wandering, free again) or caught
## (despawned for good, a replacement rolls in after a delay to keep the
## population up).
##
## Every peer runs this same script (spawned in every map, not host-only),
## since every client needs its own local mirror of the ambient population
## to render -- only the host branch actually simulates/decides anything.
## Spawn/call/release/despawn are each broadcast ONCE; between those,
## every peer's own VisualFish independently follows ShadowWander's shared
## deterministic formula, so the whole ambient population needs zero
## ongoing position sync no matter how many shadows are out there.

const VISUAL_FISH_SCENE: PackedScene = preload("res://entities/visual_fish/visual_fish.tscn")

const AMBIENT_COUNT: int = 6
const HOME_MIN_DIST: float = 4.0   ## from the map center (Livewell), roughly boat's edge
const HOME_MAX_DIST: float = 20.0  ## comfortably inside max_cast_distance (30, see Rod)
const SWIM_SPEED: float = 2.0           ## m/s, called shadow swimming to a bobber
const MIN_CALL_TRAVEL_SECONDS: float = 0.6
## A shadow called from way out in the escalating-radius search (see
## BiteEventManager.CALL_RADIUS_GROWTH_PER_SEC) still needs to arrive in a
## bounded, testable time -- capped rather than derived purely from
## distance/SWIM_SPEED, so it reads as an eager dash once called instead of
## an actual multi-second swim proportional to however far the search had
## to widen.
const MAX_CALL_TRAVEL_SECONDS: float = 3.0
const RESPAWN_DELAY_SECONDS: float = 5.0  ## after a catch, before a replacement rolls in

enum ShadowState { WANDERING, CALLED }

## Set directly by the map (current_map_id, same pattern as
## BiteEventManager) before setup() runs -- SpawnPool needs it to roll a
## valid species per map.
var current_map_id: StringName = &""

var _center: Vector3 = Vector3.ZERO
var _next_id: int = 1

## Host-only source of truth. id -> {species, home, seed, spawn_t,
## target_pos, called_by (-1 = free), state}.
var _shadows: Dictionary = {}

## Every peer's own local mirror -- id -> VisualFish. Needed so the _notify_*
## RPCs (which only carry an id) know which node to move.
var _local_fish: Dictionary = {}


func _ready() -> void:
	# Every peer needs its own local node in this group -- same lesson as
	## TangleManager/CapsizeManager/BigFishEventManager (pass 37): gating
	## add_to_group on is_server() left every non-host client's own lookup
	## returning null.
	add_to_group("visual_fish_spawner")


## Called by the map once, host and client alike -- center is the ambient
## population's rough home base (Livewell's position, same reference point
## BigFishEventManager uses). Only the host actually rolls/spawns anything.
func setup(center: Vector3) -> void:
	_center = center
	if not multiplayer.is_server():
		return
	for _i in AMBIENT_COUNT:
		_spawn_new_ambient()


func _spawn_new_ambient() -> void:
	var species: FishData = SpawnPool.roll_species(current_map_id)
	if species == null:
		push_warning("VisualFishSpawner: SpawnPool returned null for map '%s'" % current_map_id)
		return
	var home: Variant = _roll_home_point()
	if home == null:
		return  # bad luck this probe -- population may end up slightly under AMBIENT_COUNT, acceptable
	var id := _next_id
	_next_id += 1
	var seed := randf() * TAU
	var spawn_t := Time.get_ticks_msec() / 1000.0
	_shadows[id] = {
		"species": species, "home": home, "seed": seed, "spawn_t": spawn_t,
		"target_pos": Vector3.ZERO, "called_by": -1, "state": ShadowState.WANDERING,
	}
	_notify_spawn_ambient.rpc(id, species, home, seed, spawn_t)


func _roll_home_point() -> Variant:
	var map := NetworkManager.get_current_map()
	if map == null:
		return null
	for _attempt in range(6):
		var angle := randf() * TAU
		var dist := randf_range(HOME_MIN_DIST, HOME_MAX_DIST)
		var probe := _center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var water_point: Variant = WaterValidator.find_water_point(probe, map)
		if water_point != null:
			return water_point
	return null


@rpc("authority", "call_local", "reliable")
func _notify_spawn_ambient(id: int, species: FishData, home: Vector3, seed: float, spawn_t: float) -> void:
	var fish := VISUAL_FISH_SCENE.instantiate() as VisualFish
	fish.species = species
	get_tree().root.add_child(fish)
	fish.start_wandering(home, seed, spawn_t)
	_local_fish[id] = fish


## Host-side query -- called every frame by BiteEventManager while a caster
## has no shadow yet. Returns {} if nothing's in range, otherwise claims the
## nearest free wandering shadow for peer_id and returns its species/id/the
## real swim duration to reach anchor from wherever it actually is.
## effective_radius lets the caller widen the search the longer it's been
## waiting (GDD: "isn't a dead cast... still gets called eventually") --
## the growth rate itself lives on BiteEventManager, this just applies
## whatever radius it's handed.
func try_call_for(peer_id: int, anchor: Vector3, effective_radius: float) -> Dictionary:
	if not multiplayer.is_server():
		return {}
	var best_id := -1
	var best_dist := effective_radius
	var best_pos := Vector3.ZERO
	for id in _shadows:
		var s: Dictionary = _shadows[id]
		if s["state"] != ShadowState.WANDERING or s["called_by"] != -1:
			continue
		var pos: Vector3 = ShadowWander.position_at(s["home"], s["seed"], s["spawn_t"])
		var dist := pos.distance_to(anchor)
		if dist < best_dist:
			best_dist = dist
			best_id = id
			best_pos = pos
	if best_id == -1:
		return {}

	var s: Dictionary = _shadows[best_id]
	s["called_by"] = peer_id
	s["state"] = ShadowState.CALLED
	s["target_pos"] = anchor
	var duration := clampf(best_pos.distance_to(anchor) / SWIM_SPEED, MIN_CALL_TRAVEL_SECONDS, MAX_CALL_TRAVEL_SECONDS)
	_notify_call.rpc(best_id, best_pos, anchor, duration)
	return {"id": best_id, "species": s["species"], "duration": duration}


@rpc("authority", "call_local", "reliable")
func _notify_call(id: int, from_pos: Vector3, to_pos: Vector3, duration: float) -> void:
	var fish: VisualFish = _local_fish.get(id)
	if fish:
		fish.swim_to(from_pos, to_pos, duration)


## Missed hook window -- shadow spooks off and resumes ambient wandering,
## free for anyone (including the same caster again) to call once more.
## Re-homed to wherever it fled to rather than snapping back to its
## original home, so the wander loop it resumes doesn't visually teleport.
func release_shadow(id: int) -> void:
	if not _shadows.has(id):
		return
	var s: Dictionary = _shadows[id]
	var seed: float = s["seed"]
	var angle := randf() * TAU
	var flee_target: Vector3 = (s["target_pos"] as Vector3) + Vector3(cos(angle), 0.0, sin(angle)) * VisualFish.FLEE_DISTANCE
	# Scheduled for when the flee tween actually finishes (not "now"), so
	# ShadowWander.position_at(new_home, seed, spawn_t) lands exactly on
	# flee_target at that moment on every peer regardless of each one's own
	# RPC arrival latency -- see VisualFish.spook_and_resume's doc comment.
	var future_spawn_t := Time.get_ticks_msec() / 1000.0 + VisualFish.FLEE_DURATION
	var new_home := flee_target - ShadowWander.offset_at(seed, 0.0)

	s["home"] = new_home
	s["spawn_t"] = future_spawn_t
	s["called_by"] = -1
	s["state"] = ShadowState.WANDERING

	_notify_release.rpc(id, flee_target, new_home, seed, future_spawn_t)


@rpc("authority", "call_local", "reliable")
func _notify_release(id: int, flee_target: Vector3, new_home: Vector3, seed: float, spawn_t: float) -> void:
	var fish: VisualFish = _local_fish.get(id)
	if fish:
		fish.spook_and_resume(flee_target, new_home, seed, spawn_t)


## Hook set successfully -- this shadow is caught, gone for good. A
## replacement rolls in elsewhere after a delay so the ambient population
## recovers instead of slowly draining to zero over a session.
func catch_shadow(id: int) -> void:
	if not _shadows.has(id):
		return
	_shadows.erase(id)
	_notify_despawn.rpc(id)
	get_tree().create_timer(RESPAWN_DELAY_SECONDS).timeout.connect(_spawn_new_ambient, CONNECT_ONE_SHOT)


@rpc("authority", "call_local", "reliable")
func _notify_despawn(id: int) -> void:
	var fish: VisualFish = _local_fish.get(id)
	if fish and is_instance_valid(fish):
		fish.queue_free()
	_local_fish.erase(id)


## Called by BiteEventManager when a caster's own attempt is canceled some
## other way (recast, tangle loss, disconnect) while a shadow is still
## called for them -- same effect as a miss, releases it back to wandering.
## A no-op if nothing's currently called for that peer (e.g. still waiting
## on one to wander into range).
func cancel_call(peer_id: int) -> void:
	for id in _shadows:
		var s: Dictionary = _shadows[id]
		if s["called_by"] == peer_id:
			release_shadow(id)
			return
