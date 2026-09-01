class_name CapsizeManager
extends Node

## Host-authoritative. GDD Capsize Minigame: everyone swims to a corner of
## the boat and interacts; number of corners needed scales 1:1 with player
## count (1 player = 1 corner ... 4 players = 4 corners, per GDD's table),
## capped at however many corner markers the boat actually has. Once every
## required corner is claimed, the boat rights itself and everyone's back
## to normal.
##
## Triggered by the Big Fish Event's failure path -- not built yet.
## start_capsize() is a public host-only entry point; for now tests (and
## soon the Big Fish Event) call it directly, same as other systems this
## session were built and proven before the thing that triggers them
## existed yet (e.g. line tangling before round/day/quota).

## Playtest: "only one side works" -- corner markers tilt with the boat
## visual, so a full-3D distance check put the raised side's corners out
## of a water-level swimmer's vertical reach while the dipped side stayed
## fine. Measured in XZ only now, with a separate, generous vertical
## tolerance -- a swimmer near a corner horizontally should be able to
## claim it regardless of how far the boat's current tilt has moved that
## corner up or down.
const INTERACT_RADIUS: float = 1.2  ## XZ distance to a corner counts as "there"
const INTERACT_VERTICAL_TOLERANCE: float = 2.5

## GDD Capsize Minigame: "physically tumble into the water. Funny is the
## goal." Real impulse instead of a teleport -- mass 70 (Player.tscn), so
## these give roughly a 5.7 m/s outward / 6.4 m/s upward launch. Placeholder
## tunables, not final numbers (see PROGRESS.md).
const TOSS_HORIZONTAL_IMPULSE: float = 400.0
const TOSS_VERTICAL_IMPULSE: float = 450.0

## How long real gravity/movement gets to carry the toss before swim mode
## (gravity_scale = 0.0, locked level at the surface) takes over and the
## safety-net check runs.
const TOSS_SETTLE_SECONDS: float = 1.3

var _active: bool = false
var _required_corners: int = 0
var _claimed_by: Dictionary = {}  # corner_index (int) -> peer_id (int)
var _corner_markers: Array = []   # Marker3D, populated via setup()
var _hull: PhysicsBody3D = null   # populated via setup(), used to mask collision during a toss


func _ready() -> void:
	if not multiplayer.is_server():
		return
	add_to_group("capsize_manager")


## Called by the map (every peer, deterministically -- same pattern as
## BiteEventManager.current_map_id in lake.gd) so corner positions are
## available locally on every peer, not just the host. Local peers use this
## read-only for get_nearest_corner_index(); only the host ever mutates
## _claimed_by/_active.
func setup(corner_markers: Array, hull: PhysicsBody3D = null) -> void:
	_corner_markers = corner_markers
	_hull = hull


func is_active() -> bool:
	return _active


## Read-only, safe on any peer -- lets a swimming player's own input
## handler (Player._process) figure out which corner they're close enough
## to try claiming, without needing host-only state.
func get_nearest_corner_index(from_position: Vector3) -> int:
	var best_index := -1
	var best_dist := INTERACT_RADIUS
	for i in range(_corner_markers.size()):
		var corner: Marker3D = _corner_markers[i]
		var corner_pos := corner.global_position
		if absf(from_position.y - corner_pos.y) > INTERACT_VERTICAL_TOLERANCE:
			continue
		var dist := _xz_distance(from_position, corner_pos)
		if dist < best_dist:
			best_dist = dist
			best_index = i
	return best_index


static func _xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func start_capsize() -> void:
	if not multiplayer.is_server():
		return
	if _active:
		return
	_active = true
	_claimed_by.clear()
	_required_corners = clampi(NetworkManager.spawned_players.size(), 1, _corner_markers.size())
	_notify_capsize_started.rpc(_required_corners)


@rpc("authority", "call_local", "reliable")
func _notify_capsize_started(required: int) -> void:
	# Emitted first -- every Player instance on every peer listens to this
	# directly for the VISUAL swim pose (see Player._apply_swim_visual), not
	# just whoever's local. Physics (movement/gravity) stays local-only below.
	EventBus.capsize_started.emit(required)
	var local_player: Player = NetworkManager.spawned_players.get(multiplayer.get_unique_id())
	if local_player:
		_toss_into_water(local_player)


## GDD Capsize Minigame: launches the LOCAL player outward/up with a real
## impulse and lets them physically tumble into the water under normal
## gravity, instead of teleporting them there -- movement is client-
## authoritative per player, so the host can't move someone else's player
## and have it stick, same reasoning NetworkManager._reposition_local_player()
## already uses.
##
## Deliberately does NOT call enter_swim_physics() yet -- swim mode's
## gravity_scale = 0.0 would kill the arc dead the instant it engaged.
## Normal gravity/movement gets TOSS_SETTLE_SECONDS to carry the tumble;
## swim mode (and the safety-net check below) only takes over after that.
func _toss_into_water(player: Player) -> void:
	var center := _boat_center()
	var base_away := player.global_position - center
	base_away.y = 0.0
	if base_away.length_squared() < 0.01:
		base_away = Vector3.FORWARD
	base_away = base_away.normalized()

	# The hull can otherwise block the launch outright (or eat most of its
	# speed shoving through it) if the toss direction clips it -- masked for
	# the same window the ballistic phase gets, restored once swim mode
	# takes over.
	if _hull:
		player.add_collision_exception_with(_hull)

	var impulse := base_away * TOSS_HORIZONTAL_IMPULSE + Vector3.UP * TOSS_VERTICAL_IMPULSE
	player.apply_capsize_toss(impulse)

	var timer := get_tree().create_timer(TOSS_SETTLE_SECONDS)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(player):
			return
		player.enter_swim_physics()
		if _hull:
			player.remove_collision_exception_with(_hull)
		_ensure_player_in_water(player)
	)


## Safety net: real physics can (rarely) carry a tossed player somewhere
## WaterValidator would reject -- into geometry, off the map edge -- where
## the old "can't move, stuck on the boat deck" bug class could resurface.
## Only repositions if wherever they actually landed isn't close to a real
## water surface; a normal toss that landed fine is left alone.
func _ensure_player_in_water(player: Player) -> void:
	var map := NetworkManager.get_current_map()
	var water_point: Variant = WaterValidator.find_water_point(player.global_position, map)
	if water_point != null and absf((water_point as Vector3).y - player.global_position.y) < 1.0:
		return  # already settled somewhere reasonable -- the toss did its job
	_reposition_to_safe_water_point(player)


## Exact same validated-probing fallback the toss unconditionally used to
## do every time -- now only reached when the physics toss actually needs
## rescuing. Tries up to 8 directions around the boat (starting with
## wherever the player already happens to be relative to it), not just
## one -- a single unvalidated probe could land off the map's edge or into
## other geometry depending on boat orientation.
func _reposition_to_safe_water_point(player: Player) -> void:
	var center := _boat_center()
	var base_away := player.global_position - center
	base_away.y = 0.0
	if base_away.length_squared() < 0.01:
		base_away = Vector3.FORWARD
	base_away = base_away.normalized()

	var map := NetworkManager.get_current_map()
	var clearance := _boat_radius() + 4.0

	for attempt in range(8):
		var direction := base_away.rotated(Vector3.UP, (TAU / 8.0) * attempt)
		var probe := center + direction * clearance
		var water_point: Variant = WaterValidator.find_water_point(probe, map)
		if water_point != null:
			# find_water_point returns the exact collision surface height --
			# placing the player's ORIGIN there embeds half their capsule
			# (radius 0.4) inside the solid water collision box underneath,
			# which the physics solver then has to spend time resolving
			# every step. Clear the surface by a real margin instead.
			player.global_position = (water_point as Vector3) + Vector3(0.0, 0.6, 0.0)
			return
	# All 8 directions failed (very unlikely) -- leave the player where
	# they already are rather than teleporting them somewhere unvalidated.
	# Swim mode's free movement still works from here even if the starting
	# spot isn't ideal.


func _boat_center() -> Vector3:
	if _corner_markers.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for marker in _corner_markers:
		sum += (marker as Marker3D).global_position
	return sum / _corner_markers.size()


func _boat_radius() -> float:
	var center := _boat_center()
	var max_dist := 0.0
	for marker in _corner_markers:
		max_dist = maxf(max_dist, center.distance_to((marker as Marker3D).global_position))
	return max_dist


func request_claim_corner(corner_index: int) -> void:
	_request_claim_corner.rpc(corner_index)


@rpc("any_peer", "call_local", "reliable")
func _request_claim_corner(corner_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := 1 if sender == 0 else sender
	_apply_claim(peer_id, corner_index)


## Host-internal, peer_id passed explicitly (same shape as TangleManager.
## _apply_mash) rather than resolved from RPC sender context -- keeps this
## directly callable/testable without needing a real per-peer RPC origin.
func _apply_claim(peer_id: int, corner_index: int) -> void:
	if not _active:
		return
	if corner_index < 0 or corner_index >= _corner_markers.size():
		return
	if _claimed_by.has(corner_index):
		return  # already claimed by someone
	if _claimed_by.values().has(peer_id):
		return  # one corner per player

	var player: Player = NetworkManager.spawned_players.get(peer_id)
	if player == null:
		return
	var corner: Marker3D = _corner_markers[corner_index]
	var corner_pos := corner.global_position
	if absf(player.global_position.y - corner_pos.y) > INTERACT_VERTICAL_TOLERANCE:
		return  # client-reported position, not actually close enough
	if _xz_distance(player.global_position, corner_pos) > INTERACT_RADIUS:
		return  # client-reported position, not actually close enough

	_claimed_by[corner_index] = peer_id
	_notify_corner_claimed.rpc(corner_index, peer_id, _claimed_by.size(), _required_corners)

	if _claimed_by.size() >= _required_corners:
		_finish_capsize()


@rpc("authority", "call_local", "reliable")
func _notify_corner_claimed(corner_index: int, peer_id: int, claimed_count: int, required: int) -> void:
	EventBus.capsize_corner_claimed.emit(corner_index, peer_id, claimed_count, required)


func _finish_capsize() -> void:
	_active = false
	_notify_capsize_resolved.rpc()


@rpc("authority", "call_local", "reliable")
func _notify_capsize_resolved() -> void:
	EventBus.capsize_resolved.emit()
	var local_player: Player = NetworkManager.spawned_players.get(multiplayer.get_unique_id())
	if local_player:
		local_player.exit_swim_physics()
