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

const INTERACT_RADIUS: float = 1.2  ## how close to a corner counts as "there"

var _active: bool = false
var _required_corners: int = 0
var _claimed_by: Dictionary = {}  # corner_index (int) -> peer_id (int)
var _corner_markers: Array = []   # Marker3D, populated via setup()


func _ready() -> void:
	if not multiplayer.is_server():
		return
	add_to_group("capsize_manager")


## Called by the map (every peer, deterministically -- same pattern as
## BiteEventManager.current_map_id in lake.gd) so corner positions are
## available locally on every peer, not just the host. Local peers use this
## read-only for get_nearest_corner_index(); only the host ever mutates
## _claimed_by/_active.
func setup(corner_markers: Array) -> void:
	_corner_markers = corner_markers


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
		var dist := from_position.distance_to(corner.global_position)
		if dist < best_dist:
			best_dist = dist
			best_index = i
	return best_index


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
		local_player.enter_swim_physics()
		_toss_into_water(local_player)


## Free-swim physics alone isn't enough -- a player capsized while standing
## on the boat deck just sits there unable to move, blocked by the Hull's
## own collision (reported as "can't move, you're just on the ground
## sideways"). Repositions the LOCAL player only, same as
## NetworkManager._reposition_local_player() -- movement is client-
## authoritative per player, so the host can't move someone else's player
## and have it stick. Pushed radially outward from the boat's center (where
## they already happen to be standing relative to it), not toward any
## specific point -- simple and direction-agnostic works for any trigger,
## not just the Big Fish Event.
func _toss_into_water(player: Player) -> void:
	var center := _boat_center()
	var away := player.global_position - center
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()

	var probe := center + away * (_boat_radius() + 4.0)
	var map := NetworkManager.get_current_map()
	var water_point: Variant = WaterValidator.find_water_point(probe, map)
	player.global_position = water_point if water_point != null else probe


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
	if player.global_position.distance_to(corner.global_position) > INTERACT_RADIUS:
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
