class_name TangleManager
extends Node

## Host-authoritative. GDD Line Tangling: two different players' lines
## crossing (Rod.LineCollider overlap while both WAITING_BITE, detected in
## Rod._on_line_area_entered) starts a tug of war here. Winner keeps their
## cast untouched; loser's line snaps (their Rod resets to IDLE, listening
## for tangle_resolved itself).
##
## Tug of war: a shared "rope" value in [-1, 1], positive favors whichever
## peer is stored as "a" for that tangle. Each mash nudges it toward the
## masher's side; first to +-1 wins. A timer breaks a stalemate.

const MASH_STRENGTH: float = 0.09
const WIN_THRESHOLD: float = 1.0
const TIME_LIMIT: float = 6.0

var _next_tangle_id: int = 1
var _tangles: Dictionary = {}        # tangle_id -> {a: int, b: int, rope: float}
var _peer_to_tangle: Dictionary = {} # peer_id -> tangle_id
var _timers: Dictionary = {}         # tangle_id -> Timer


func _ready() -> void:
	if not multiplayer.is_server():
		return
	add_to_group("tangle_manager")


## Called by Rod (any peer, but only ever acts on the host -- see Rod
## ._on_line_area_entered, which already guards is_server() before calling).
func start_tangle(peer_a: int, peer_b: int) -> void:
	if not multiplayer.is_server():
		return
	if _peer_to_tangle.has(peer_a) or _peer_to_tangle.has(peer_b):
		return  # one of them is already tangled with someone

	var tangle_id := _next_tangle_id
	_next_tangle_id += 1
	_tangles[tangle_id] = {"a": peer_a, "b": peer_b, "rope": 0.0}
	_peer_to_tangle[peer_a] = tangle_id
	_peer_to_tangle[peer_b] = tangle_id

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = TIME_LIMIT
	add_child(timer)
	timer.timeout.connect(func() -> void:
		_finish_tangle(tangle_id)
		timer.queue_free()
	)
	_timers[tangle_id] = timer
	timer.start()

	_notify_tangle_started.rpc(peer_a, peer_b)


@rpc("authority", "call_local", "reliable")
func _notify_tangle_started(peer_a: int, peer_b: int) -> void:
	EventBus.tangle_started.emit(peer_a, peer_b)


## Client entry point -- TangleMinigame UI calls this on mash input.
func request_mash() -> void:
	_request_mash.rpc()


@rpc("any_peer", "call_local", "reliable")
func _request_mash() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := 1 if sender == 0 else sender
	_apply_mash(peer_id)


func _apply_mash(peer_id: int) -> void:
	if not _peer_to_tangle.has(peer_id):
		return
	var tangle_id: int = _peer_to_tangle[peer_id]
	var t: Dictionary = _tangles[tangle_id]
	var delta := MASH_STRENGTH if peer_id == t["a"] else -MASH_STRENGTH
	t["rope"] = clampf(t["rope"] + delta, -WIN_THRESHOLD, WIN_THRESHOLD)

	_notify_rope_updated.rpc(t["a"], t["b"], t["rope"])

	if absf(t["rope"]) >= WIN_THRESHOLD:
		_finish_tangle(tangle_id)


@rpc("authority", "call_local", "reliable")
func _notify_rope_updated(peer_a: int, peer_b: int, rope: float) -> void:
	EventBus.tangle_rope_updated.emit(peer_a, peer_b, rope)


func _finish_tangle(tangle_id: int) -> void:
	if not _tangles.has(tangle_id):
		return
	var t: Dictionary = _tangles[tangle_id]
	var peer_a: int = t["a"]
	var peer_b: int = t["b"]
	var rope: float = t["rope"]

	var winner: int
	var loser: int
	if rope > 0.0:
		winner = peer_a
		loser = peer_b
	elif rope < 0.0:
		winner = peer_b
		loser = peer_a
	else:
		# Exact tie at timeout (nobody mashed at all) -- coinflip.
		winner = peer_a if randf() < 0.5 else peer_b
		loser = peer_b if winner == peer_a else peer_a

	_peer_to_tangle.erase(peer_a)
	_peer_to_tangle.erase(peer_b)
	_tangles.erase(tangle_id)
	_timers.erase(tangle_id)

	var bite_manager: Node = get_tree().get_first_node_in_group("bite_event_manager")
	if bite_manager:
		bite_manager.cancel_pending_bite(loser)

	_notify_tangle_resolved.rpc(winner, loser)


@rpc("authority", "call_local", "reliable")
func _notify_tangle_resolved(winner_peer_id: int, loser_peer_id: int) -> void:
	EventBus.tangle_resolved.emit(winner_peer_id, loser_peer_id)
