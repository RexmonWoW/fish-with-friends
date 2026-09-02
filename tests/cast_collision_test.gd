extends Node

## Headless check for GDD Casting's cast collision (steps 2-3 of the
## casting rework): the swept arc reacts to the first thing it hits, a
## non-water hit is a dead cast that just lies there (no bounce physics --
## the earlier bounce-physics attempt didn't work out and was parked), and
## hitting a player bonks them.
##
## 1. Casting at a teammate bonks them -- knockback broadcast to their own
##    client, bobber drops at their feet as a dead cast (no bite sequence).
## 2. Casting at the deck is a dead cast too -- lands and lies exactly where
##    the sweep hit, no floating, no bounce, reaches WAITING_BITE (not stuck
##    at ANIMATING), cancels/recasts like any other cast.
## 3. Regression for the WaterValidator caveat: its water-height snap
##    deliberately re-casts PAST a Player body (so a teammate standing at
##    your landing spot can't block a water landing) -- the COLLISION sweep
##    must NOT inherit that behavior, or a player standing directly in the
##    path could never be bonked; a normal cast over open water still isn't
##    affected by a player standing well clear of that path.
## 4. A real water landing still isn't a dead cast, and still schedules a
##    real bite sequence -- the sibling case to all of the above.

## Member, not local -- GDScript lambdas capture local variables BY VALUE,
## not by reference, so a lambda assigning to a local would silently mutate
## its own captured copy, not these (bit cast_reject_softlock_test once
## already before being fixed the same way). Plain instance-property
## access, no capture involved.
var _bonk_impulse: Vector3 = Vector3.ZERO
var _bonk_fired: bool = false
var _bonk_hit_peer_id: int = 0
var _got_landed: bool = false
var _got_dead_cast: bool = false
var _got_endpoint: Vector3 = Vector3.ZERO


func _ready() -> void:
	print("--- Cast collision test ---")

	EventBus.player_bonked.connect(func(hit_peer_id, impulse):
		_bonk_fired = true
		_bonk_hit_peer_id = hit_peer_id
		_bonk_impulse = impulse
	)
	EventBus.cast_landed.connect(func(endpoint, _flight, pid, is_dead_cast):
		if pid == 1:
			_got_landed = true
			_got_dead_cast = is_dead_cast
			_got_endpoint = endpoint
	)

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player1: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.request_start_round()
	if not await _wait_for_scene(&"lake"):
		print("FAIL: never reached the lake")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager._spawn_player_for_peer(2)
	await get_tree().process_frame
	await get_tree().process_frame

	var player2: Player = NetworkManager.spawned_players[2]
	var rod1: Rod = player1.equipment_slot.equipped_item as Rod
	var bite_mgr := get_tree().get_first_node_in_group("bite_event_manager")

	# ── Bonk, and the WaterValidator player-exclusion caveat. ──
	# player2 stands where a normal cast would otherwise reach open water if
	# it passed clean through them -- proving the sweep actually stops AT
	# them instead of inheriting WaterValidator's "skip past players" habit
	# (correct for find_water_point's OWN job, wrong here). Short/low cast
	# (power 0.0 -> min_cast_distance=3.0 dominates) keeps the arc's apex
	# low enough to actually clip a standing player instead of sailing over
	# their head. Well clear of the Livewell (~(0, 0.4, 0)) -- standing on
	# top of it blocks casting entirely (Rod._near_livewell).
	var target := Vector3(5.0, 0.5, -3.0)
	player2.global_position = target
	player1.global_position = Vector3(5.0, 0.5, 0.0)
	player1.camera_rig.rotation.y = 0.0  # facing -Z, toward player2
	await get_tree().physics_frame
	await get_tree().physics_frame

	rod1.start_charge()
	rod1.current_power = 0.0
	rod1.release_cast()
	await get_tree().process_frame

	if not _got_landed or not _got_dead_cast:
		print("FAIL: test setup problem -- casting straight at player2 didn't register as a dead cast at all (landed=%s dead=%s)" %
			[_got_landed, _got_dead_cast])
		get_tree().quit(1)
		return
	if _got_endpoint.distance_to(target) > 1.0:
		print("FAIL: dead cast should have dropped at player2's feet (%s), landed at %s instead" % [target, _got_endpoint])
		get_tree().quit(1)
		return
	print("Cast toward player2 registered as a dead cast dropped at their feet -- the sweep didn't pass through them.")

	var waited := 0.0
	while not _bonk_fired and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not _bonk_fired:
		print("FAIL: player_bonked never fired")
		get_tree().quit(1)
		return
	if _bonk_hit_peer_id != player2.peer_id:
		print("FAIL: bonk hit the wrong peer (got %d, expected %d)" % [_bonk_hit_peer_id, player2.peer_id])
		get_tree().quit(1)
		return
	if _bonk_impulse.length() < 1.0:
		print("FAIL: bonk impulse suspiciously small/zero (%s)" % _bonk_impulse)
		get_tree().quit(1)
		return
	print("Bonk knockback fired at the right peer: impulse=%s" % _bonk_impulse)

	var settle_waited := 0.0
	while rod1.state == Rod.CastState.ANIMATING and settle_waited < 3.0:
		await get_tree().process_frame
		settle_waited += get_process_delta_time()
	if rod1.state != Rod.CastState.WAITING_BITE:
		print("FAIL: rod1 didn't settle into WAITING_BITE after the bonk (state=%s)" % rod1.state)
		get_tree().quit(1)
		return
	if bite_mgr._pending.has(1):
		print("FAIL: a bite sequence got scheduled for a bonk -- should be a dead cast, nothing bites")
		get_tree().quit(1)
		return
	print("Bonk landed as a dead cast -- no bite sequence scheduled.")

	rod1.request_cancel_cast()
	await get_tree().process_frame

	# ── Dead cast on solid ground (the deck), no player involved. ──
	_got_landed = false
	_got_dead_cast = false
	_bonk_fired = false
	# Along the hull's own long axis (z -3..3) so a 3-unit (min_cast_distance)
	# cast stays entirely on the deck instead of running off either edge
	# into open water -- unlike the bonk setup above, nothing here is
	# boat-relative anymore since player1 got moved for that.
	player1.global_position = Vector3(0.0, 0.5, -2.8)
	player1.camera_rig.rotation.y = PI  # facing +Z, along the deck
	await get_tree().physics_frame

	rod1.start_charge()
	rod1.current_power = 0.1  # min_cast_distance dominates -- stays on the deck
	rod1.release_cast()
	await get_tree().process_frame

	if not _got_landed or not _got_dead_cast:
		print("FAIL: casting at the deck didn't register as a dead cast (landed=%s dead=%s)" % [_got_landed, _got_dead_cast])
		get_tree().quit(1)
		return
	if _bonk_fired:
		print("FAIL: a plain deck hit shouldn't fire a bonk -- nobody was there")
		get_tree().quit(1)
		return
	# Playtest history: "hovers way above the boat" from an earlier (now
	# parked) attempt -- confirms a dead cast on solid ground settles at
	# the sweep's real hit height, not floating at aim/camera height.
	if _got_endpoint.y > 2.0:
		print("FAIL: dead cast settled way too high above the deck (y=%.2f) -- floating, not a real hit" % _got_endpoint.y)
		get_tree().quit(1)
		return
	print("Dead cast on the deck settled at a real height (y=%.2f), not floating." % _got_endpoint.y)

	var deck_settle_waited := 0.0
	while rod1.state == Rod.CastState.ANIMATING and deck_settle_waited < 3.0:
		await get_tree().process_frame
		deck_settle_waited += get_process_delta_time()
	if rod1.state != Rod.CastState.WAITING_BITE:
		print("FAIL: rod1 soft-locked after the deck dead cast (state=%s)" % rod1.state)
		get_tree().quit(1)
		return
	if bite_mgr._pending.has(1):
		print("FAIL: a bite sequence got scheduled for a dead cast on the deck")
		get_tree().quit(1)
		return
	print("Deck dead cast reached WAITING_BITE cleanly, no bite scheduled.")

	rod1.request_cancel_cast()
	await get_tree().process_frame
	if rod1.state != Rod.CastState.IDLE:
		print("FAIL: couldn't cancel the deck dead cast back to IDLE (state=%s)" % rod1.state)
		get_tree().quit(1)
		return
	print("Deck dead cast canceled back to IDLE.")

	# ── Sibling case: a real water landing still isn't a dead cast. ──
	_got_landed = false
	_got_dead_cast = false
	player1.camera_rig.rotation.y = 0.0  # back to facing open water
	await get_tree().physics_frame

	rod1.start_charge()
	rod1.current_power = 0.6
	rod1.release_cast()
	await get_tree().process_frame

	if not _got_landed or _got_dead_cast:
		print("FAIL: a normal cast over open water should land as a real (non-dead) cast (landed=%s dead=%s)" %
			[_got_landed, _got_dead_cast])
		get_tree().quit(1)
		return
	print("Normal water cast still lands as a real cast, not a dead one.")

	rod1.request_cancel_cast()
	await get_tree().process_frame

	# ── Coverage for the sweep's step-count scaling -- a long cast at the ──
	# ── same thin deck should still register as a real "solid" hit, not ──
	# ── skip clean over it (see rod.gd's own doc comment). ──
	var map := NetworkManager.get_current_map()
	var far_start := Vector3(0.0, 0.5, 28.0)
	var deck_target := Vector3(0.0, 0.15, 0.0)
	var long_hit: Dictionary = rod1._sweep_arc_for_collision(far_start, deck_target, map)
	if long_hit["type"] != "solid":
		print("FAIL: a long cast swept clean through the deck instead of hitting it (type=%s)" % long_hit["type"])
		get_tree().quit(1)
		return
	print("Long-distance cast correctly still hits the (thin) deck instead of skipping over it.")

	print("--- Cast collision test PASSED ---")
	get_tree().quit()


func _wait_for_scene(scene_id: StringName, timeout: float = 3.0) -> bool:
	var waited := 0.0
	while NetworkManager._current_scene_id != scene_id and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return NetworkManager._current_scene_id == scene_id
