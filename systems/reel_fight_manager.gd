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
## where it landed toward the angler, broadcast so every nearby peer sees
## the same fight -- "doesn't need to be exact" per direction, so this is
## deliberately simpler than it sounds: just an eased position every tick,
## plus a quick sideways tug while a QTE is active (report_kick). Same
## "unreliable, self-correcting" broadcast every other continuous sync in
## this codebase already uses (e.g. Big Fish Event's own collective-
## progress broadcast).
##
## Playtest: closing toward the ROD TIP specifically (rather than the
## player) meant just looking around while reeling -- the rod is camera-
## attached -- visibly dragged the bobber along with it, "floaty, moves
## with the rod." Closing toward the player's own position instead stays
## put under camera movement; only actually walking (or real progress)
## moves it.
const PROGRESS_SMOOTH_RATE: float = 3.0

## "The fish tugs left or right" while a QTE is active (GDD) -- a sideways
## offset perpendicular to the anchor-to-player line, decaying back to
## nothing over KICK_DURATION. Reported once per QTE start (see
## ReelMinigame._start_qte), not a magnitude stream.
const KICK_DURATION: float = 0.4
const KICK_STRENGTH: float = 0.4

## Review: broadcasting every physics tick (~60Hz) was needlessly chatty --
## the Bobber's own lerp smoothing already hides the gaps between updates,
## so there's no visual cost to sending them less often. Easing itself
## still runs every tick (below) for a smooth internal display_progress;
## only how often the RESULT goes out over the wire is throttled.
const BROADCAST_INTERVAL: float = 1.0 / 12.0  ## ~12Hz

## Playtest: "yanks in the instant a fight starts" -- ReelMinigame's own
## _progress starts at 0.5, not 0.0, but this used to map progress 0..1
## straight onto anchor..angler, so the bobber jumped to roughly halfway
## reeled-in the moment the fight began. Matches ReelMinigame._progress's
## own starting value -- display is remapped below so THIS corresponds to
## the landing spot (t = 0), not wherever the raw 0..1 progress number
## happens to sit.
const START_PROGRESS: float = 0.5

## "Let the fish take line" -- when progress drops below START_PROGRESS
## (the fish pulling back), the bobber drags back out past the anchor
## instead of clamping dead at it. Capped to a modest overshoot rather
## than a full linear projection (progress hitting 0.0 would otherwise
## fling it a full anchor-to-angler distance out).
const MIN_DISPLAY_T: float = -0.15

var _fights: Dictionary = {}  # peer_id (int) -> {anchor, progress, display_progress, kick_dir, kick_timer}
var _broadcast_timer: float = 0.0

## True while _fights had at least one entry as of the last tick -- lets
## the empty-transition below fire exactly once (see _process's doc
## comment on why that final broadcast matters).
var _was_active: bool = false


func _ready() -> void:
	# Every peer needs its own local node in this group -- ReelMinigame looks
	# itself up the same way (pass-37 lesson: gating this on is_server() left
	# every non-host client's own lookup returning null).
	add_to_group("reel_fight_manager")


## Called by BiteEventManager (host-only) the moment a bite fires -- needs
## the real landing spot, which bite_started's public signal doesn't carry.
func start_fight(peer_id: int, anchor: Vector3) -> void:
	_fights[peer_id] = {
		"anchor": anchor, "progress": START_PROGRESS, "display_progress": START_PROGRESS,
		"kick_dir": 0.0, "kick_timer": 0.0,
	}


## Read-only, safe on any peer -- lets ReelMinigame look up the real landing
## spot for GDD's cast-distance-scales-fill-rate rule without needing it
## threaded through bite_started's own signal signature.
func get_fight_anchor(peer_id: int) -> Variant:
	return _fights[peer_id]["anchor"] if _fights.has(peer_id) else null


## Called by BiteEventManager once the fight is over, one way or another
## (caught, escaped, tangled away, disconnected) -- just drops it from the
## active set, the caller already handles the rest.
func cancel_fight(peer_id: int) -> void:
	_fights.erase(peer_id)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if _fights.is_empty():
		# Review: once the LAST fight ended, this used to just go quiet --
		# no more broadcasts ever went out, so a Bobber that missed the
		# very last update (or has nothing left to hear from) stayed frozen
		# at its last fight position forever instead of falling back to
		# drift. One final broadcast (empty payload's fine, the receiving
		# end only cares that ITS peer_id is no longer in it) on the exact
		# transition into "nothing active" makes sure that guard actually
		# fires here too.
		if _was_active:
			_was_active = false
			_notify_fight_state.rpc({})
		return
	_was_active = true

	for peer_id in _fights:
		var f: Dictionary = _fights[peer_id]
		f["display_progress"] = lerpf(
			f["display_progress"], f["progress"], clampf(PROGRESS_SMOOTH_RATE * delta, 0.0, 1.0)
		)
		if f["kick_timer"] > 0.0:
			f["kick_timer"] = maxf(f["kick_timer"] - delta, 0.0)

	_broadcast_timer += delta
	if _broadcast_timer < BROADCAST_INTERVAL:
		return
	_broadcast_timer = 0.0

	var payload: Dictionary = {}
	for peer_id in _fights:
		var pos: Variant = _compute_bobber_world_position(peer_id, _fights[peer_id])
		if pos != null:
			payload[peer_id] = pos
	if not payload.is_empty():
		_notify_fight_state.rpc(payload)


func _compute_bobber_world_position(peer_id: int, f: Dictionary) -> Variant:
	var player: Player = NetworkManager.spawned_players.get(peer_id)
	if player == null:
		return null
	var near_point: Vector3 = player.global_position

	var anchor: Vector3 = f["anchor"]
	# Remapped so START_PROGRESS (where every fight begins) lands exactly on
	# the anchor (t=0) and 1.0 lands on the angler (t=1) -- see
	# START_PROGRESS's own doc comment. Progress dropping below where it
	# started extrapolates PAST the anchor (t < 0, "the fish takes line")
	# instead of clamping dead at it.
	var t := clampf((f["display_progress"] as float - START_PROGRESS) / (1.0 - START_PROGRESS), MIN_DISPLAY_T, 1.0)
	var anchor_xz := Vector2(anchor.x, anchor.z)
	var near_xz := Vector2(near_point.x, near_point.z)
	# XZ closes toward the angler as progress builds; Y stays pinned to the
	# anchor's original (water-surface) height -- the bobber reels in ALONG
	# the water, it never lifts off it.
	var xz := anchor_xz.lerp(near_xz, t)
	xz += _compute_kick(f, anchor_xz, near_xz)
	return Vector3(xz.x, anchor.y, xz.y)


## "The fish tugs left or right" while a QTE is active -- perpendicular to
## the anchor-to-angler line so it reads as a sideways dart regardless of
## which way the fight happens to be facing, linearly fading back to
## nothing over KICK_DURATION.
func _compute_kick(f: Dictionary, anchor_xz: Vector2, near_xz: Vector2) -> Vector2:
	var timer: float = f["kick_timer"]
	if timer <= 0.0:
		return Vector2.ZERO
	var line := near_xz - anchor_xz
	if line.length_squared() < 0.0001:
		line = Vector2.DOWN
	line = line.normalized()
	var perp := Vector2(-line.y, line.x)
	var kick_t := timer / KICK_DURATION  # 1.0 (just triggered) -> 0.0 (faded out)
	return perp * (f["kick_dir"] as float) * KICK_STRENGTH * kick_t


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


## Called by ReelMinigame the moment a QTE prompt starts firing -- reliable
## and discrete (not a per-frame stream like progress), so a real tug can't
## just get silently dropped like an unreliable packet could.
func report_kick() -> void:
	_request_report_kick.rpc()


@rpc("any_peer", "call_local", "reliable")
func _request_report_kick() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _sender_peer_id()
	if not _fights.has(peer_id):
		return
	var f: Dictionary = _fights[peer_id]
	f["kick_dir"] = -1.0 if randf() < 0.5 else 1.0
	f["kick_timer"] = KICK_DURATION


func _sender_peer_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return 1 if sender == 0 else sender
