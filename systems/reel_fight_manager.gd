class_name ReelFightManager
extends Node

## Host-authoritative. GDD Reel Mechanic: the actual minigame (Stardew-style
## bar -- hold to raise a zone, keep it over a drifting fish icon, periodic
## QTE prompts, miss counter/death spiral) still runs entirely on the
## angler's own client (ui/reel_minigame.gd) -- that stays each player's
## own private control, not a second control surface for anyone else.
##
## What this adds: the angler's own self-reported progress (0..1, see
## report_progress) moves the REAL bobber along the water's surface from
## where it landed toward the rod tip, broadcast so every nearby peer sees
## the same fight -- "doesn't need to be exact" per direction, so this is
## deliberately simpler than it sounds: no bob, no per-QTE kick, just an
## eased position every tick. Same "unreliable, self-correcting" broadcast
## every other continuous sync in this codebase already uses (e.g. Big Fish
## Event's own collective-progress broadcast).

## How fast the displayed position eases toward the angler's raw reported
## progress -- not instant, so a twitchy Stardew fill/drain frame doesn't
## snap the world bobber around.
const PROGRESS_SMOOTH_RATE: float = 3.0

var _fights: Dictionary = {}  # peer_id (int) -> {anchor: Vector3, progress: float, display_progress: float}


func _ready() -> void:
	# Every peer needs its own local node in this group -- ReelMinigame looks
	# itself up the same way (pass-37 lesson: gating this on is_server() left
	# every non-host client's own lookup returning null).
	add_to_group("reel_fight_manager")


## Called by BiteEventManager (host-only) the moment a bite fires -- needs
## the real landing spot, which bite_started's public signal doesn't carry.
func start_fight(peer_id: int, anchor: Vector3) -> void:
	_fights[peer_id] = {"anchor": anchor, "progress": 0.0, "display_progress": 0.0}


## Called by BiteEventManager once the fight is over, one way or another
## (caught, escaped, tangled away, disconnected) -- just drops it from the
## active set, the caller already handles the rest.
func cancel_fight(peer_id: int) -> void:
	_fights.erase(peer_id)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _fights.is_empty():
		return

	var payload: Dictionary = {}
	for peer_id in _fights:
		var f: Dictionary = _fights[peer_id]
		f["display_progress"] = lerpf(
			f["display_progress"], f["progress"], clampf(PROGRESS_SMOOTH_RATE * delta, 0.0, 1.0)
		)
		var pos: Variant = _compute_bobber_world_position(peer_id, f)
		if pos != null:
			payload[peer_id] = pos
	if not payload.is_empty():
		_notify_fight_state.rpc(payload)


func _compute_bobber_world_position(peer_id: int, f: Dictionary) -> Variant:
	var player: Player = NetworkManager.spawned_players.get(peer_id)
	if player == null:
		return null
	var rod := player.equipment_slot.equipped_item as Rod
	var rod_tip := (rod.get_node_or_null("RodTip") as Marker3D) if rod else null
	var near_point: Vector3 = rod_tip.global_position if rod_tip else player.global_position

	var anchor: Vector3 = f["anchor"]
	var t: float = f["display_progress"]
	# XZ closes toward the rod tip as progress builds; Y stays pinned to the
	# anchor's original (water-surface) height -- the bobber reels in ALONG
	# the water, it never lifts off it.
	var xz := Vector2(anchor.x, anchor.z).lerp(Vector2(near_point.x, near_point.z), t)
	return Vector3(xz.x, anchor.y, xz.y)


@rpc("authority", "call_local", "unreliable")
func _notify_fight_state(positions: Dictionary) -> void:
	EventBus.reel_fight_state_updated.emit(positions)


## Called every frame by the angler's own ReelMinigame while it's active.
func report_progress(progress: float) -> void:
	_request_report_progress.rpc(progress)


@rpc("any_peer", "call_local", "unreliable")
func _request_report_progress(progress: float) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _sender_peer_id()
	if _fights.has(peer_id):
		_fights[peer_id]["progress"] = clampf(progress, 0.0, 1.0)


func _sender_peer_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return 1 if sender == 0 else sender
