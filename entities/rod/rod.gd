class_name Rod
extends Node3D

enum CastState { IDLE, CHARGING, ANIMATING, WAITING_BITE, REELING, BIG_FISH_EVENT }

@export var max_cast_distance: float = 30.0  ## meters from rod tip
@export var min_cast_distance: float = 3.0
@export var charge_time_to_full: float = 1.5  ## seconds of hold to reach max power

## GDD Casting: landing preview, shown only to the charging player, purely
## client-side (no networking -- every client already has the same static
## map geometry to raycast against locally).
const LANDING_PREVIEW_RADIUS: float = 0.5
const LANDING_PREVIEW_Y_OFFSET: float = 0.02  ## just above the surface, avoids z-fighting
const LANDING_PREVIEW_VALID_COLOR: Color = Color(0.2, 0.9, 1.0, 0.85)
const LANDING_PREVIEW_INVALID_COLOR: Color = Color(0.95, 0.15, 0.15, 0.85)

var state: CastState = CastState.IDLE
var charge_start_time: float = 0.0
var current_power: float = 0.0      ## 0.0–1.0, NOT replicated
var owner_peer_id: int = 0          ## set by EquipmentSlot on equip
var player_camera: Camera3D = null  ## set by EquipmentSlot on equip

## False while stowed on the back (EquipmentSlot.unequip_rod(), e.g. holding
## a caught fish) -- the Rod node stays alive and in the tree either way, so
## its own _process would otherwise keep responding to "cast" input even
## while not actually in the player's hand.
var is_equipped: bool = true

## True while the local player is standing in a Livewell's InteractionZone --
## blocks starting a cast so pressing 1-5 to throw a fish overboard (or just
## looking around near the livewell) doesn't also fire the rod.
var _near_livewell: bool = false

## True while THIS rod's owner has an open hook-set window (GDD Bite
## Detection -- a shadow just struck, press "cast" within a short window to
## set the hook). Set/cleared by BiteEventManager's broadcasts, gated to
## this rod's own owner since every peer mirrors every rod.
var _hook_window_open: bool = false

## Lazily built the first time this rod's own local owner starts charging --
## every peer mirrors every rod, but only the owner's own client ever builds
## or shows one (see _process's owner gate below).
var _landing_preview: MeshInstance3D = null
var _landing_preview_material: StandardMaterial3D = null


func _ready() -> void:
	EventBus.livewell_proximity_changed.connect(_on_livewell_proximity_changed)
	EventBus.tangle_resolved.connect(_on_tangle_resolved)
	EventBus.bite_hook_window_opened.connect(_on_hook_window_opened)
	EventBus.bite_hook_window_missed.connect(_on_hook_window_closed)
	EventBus.bite_started.connect(_on_hook_window_closed_from_bite)

	# Not owner-gated -- detection must fire for every peer's local mirror of
	# every rod (same reasoning as LureAnimator's line-collider tracking).
	# Only the HOST's own detection actually does anything (guarded inside).
	var line_collider := get_node("LineCollider") as Area3D
	line_collider.area_entered.connect(_on_line_area_entered)


func _on_livewell_proximity_changed(_livewell: Livewell, in_range: bool) -> void:
	_near_livewell = in_range


func _on_hook_window_opened(caster_peer_id: int, _duration: float) -> void:
	if caster_peer_id == owner_peer_id:
		_hook_window_open = true


func _on_hook_window_closed(caster_peer_id: int) -> void:
	if caster_peer_id == owner_peer_id:
		_hook_window_open = false


func _on_hook_window_closed_from_bite(_fish_data: FishData, caster_peer_id: int) -> void:
	_on_hook_window_closed(caster_peer_id)


func _is_owner_swimming() -> bool:
	var player: Player = NetworkManager.spawned_players.get(owner_peer_id)
	return player != null and player.is_swimming


## Fires once per rod whose LineCollider newly overlaps another rod's --
## i.e. twice per actual tangle (each rod detects the other). TangleManager
## dedupes so only the first report starts anything.
func _on_line_area_entered(other_area: Area3D) -> void:
	if not multiplayer.is_server():
		return
	_try_start_tangle_with(other_area)


func _try_start_tangle_with(other_area: Area3D) -> void:
	var other_rod := other_area.get_parent() as Rod
	if other_rod == null or other_rod == self:
		return
	if other_rod.owner_peer_id == owner_peer_id:
		return
	if state != CastState.WAITING_BITE or other_rod.state != CastState.WAITING_BITE:
		return
	var tangle_manager: Node = get_tree().get_first_node_in_group("tangle_manager")
	if tangle_manager:
		tangle_manager.start_tangle(owner_peer_id, other_rod.owner_peer_id)


## Called by LureAnimator right as this rod transitions into WAITING_BITE.
## The one-shot area_entered signal above only fires on transitioning INTO
## overlap -- if the lines started overlapping earlier, while one or both
## rods were still ANIMATING (mid-flight, a real possibility now that the
## line's collision radius is generous rather than razor-thin), that
## "entered" event fired and got correctly rejected (not WAITING_BITE yet),
## but nothing re-checks once it actually WOULD pass, since the areas are
## already touching and no NEW "entered" event ever fires. Explicitly
## re-checking current overlaps here closes that gap.
func check_line_overlaps_for_tangle() -> void:
	if not multiplayer.is_server():
		return
	var collider := get_node_or_null("LineCollider") as Area3D
	if collider == null:
		return
	for area in collider.get_overlapping_areas():
		_try_start_tangle_with(area)


func _on_tangle_resolved(_winner_peer_id: int, loser_peer_id: int) -> void:
	if loser_peer_id != owner_peer_id:
		return
	state = CastState.IDLE  # line snapped -- LureAnimator polls state and hides itself


# ── Local input (only runs for the rod owner) ─────────────────────────────────

func start_charge() -> void:
	if state != CastState.IDLE or _near_livewell or not is_equipped:
		return
	if _is_owner_swimming():
		return
	# No fishing map loaded (e.g. still in the lobby) -- nothing to cast into.
	if NetworkManager.get_current_map() == null:
		return
	state = CastState.CHARGING
	charge_start_time = Time.get_ticks_msec() / 1000.0
	current_power = 0.0
	EventBus.cast_charge_started.emit(owner_peer_id)


func release_cast() -> void:
	if state != CastState.CHARGING:
		return
	if player_camera == null:
		push_warning("Rod: release_cast called but player_camera not assigned.")
		state = CastState.IDLE
		return
	var cam_origin := player_camera.global_transform.origin
	var cam_forward := -player_camera.global_transform.basis.z
	# Optimistic local state -- set BEFORE the RPC, not after. When the
	# caster IS the host (solo/host play), "any_peer, call_local" means
	# _request_cast's local invocation runs SYNCHRONOUSLY inline here,
	# including a rejection's _cast_failed.rpc() call resetting state back
	# to IDLE -- so setting ANIMATING after the call would silently clobber
	# that real result back to ANIMATING forever (a soft lock: stuck
	# "casting," can't move, can't start a new charge). Setting it first lets
	# whatever the call actually resolves to be the final value.
	state = CastState.ANIMATING
	_request_cast.rpc(cam_origin, cam_forward, current_power)


## Right-click while charging or waiting on a bite -- there was previously no
## way out of either state short of the charge/bite resolving on its own.
func request_cancel_cast() -> void:
	if state != CastState.CHARGING and state != CastState.WAITING_BITE:
		return
	_request_cancel_cast.rpc()


@rpc("any_peer", "call_local", "reliable")
func _request_cancel_cast() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var effective_sender := 1 if sender == 0 else sender
	if effective_sender != owner_peer_id:
		return  # Wrong rod -- reject silently.
	if state != CastState.CHARGING and state != CastState.WAITING_BITE:
		return  # Already resolved some other way -- nothing to cancel.
	if state == CastState.WAITING_BITE:
		var bite_manager: Node = get_tree().get_first_node_in_group("bite_event_manager")
		if bite_manager:
			bite_manager.cancel_pending_bite(owner_peer_id)
	_notify_cast_cancelled.rpc()


@rpc("authority", "call_local", "reliable")
func _notify_cast_cancelled() -> void:
	state = CastState.IDLE
	EventBus.cast_failed.emit(&"cancelled", owner_peer_id)  # hides CastMeter same as a rejection


## Force this rod back to IDLE regardless of what it was doing -- called
## when something ELSE interrupts the player (capsizing) rather than a
## normal cast resolution. Without this, a player mid-charge or mid-wait
## when the boat capsizes came back from swimming still stuck there, unable
## to cast again (start_charge() requires state == IDLE) -- "locked into
## the cast." Not an RPC: EquipmentSlot.stow_rod_for_swim() already runs
## identically on every peer off the same capsize broadcast (same reasoning
## as the swim visual pose needing no RPC of its own), so this doesn't
## either.
func force_cancel_cast() -> void:
	if state == CastState.IDLE or state == CastState.BIG_FISH_EVENT:
		return
	# Found while fixing a stale-fight-position bug: this only ever checked
	# WAITING_BITE, so capsizing mid-REELING left BiteEventManager's Fish
	# and ReelFightManager's fight entry both orphaned server-side forever
	# (this rod's own state still correctly went IDLE and freed the local
	# bobber, but the host-side bookkeeping never heard about it).
	if (state == CastState.WAITING_BITE or state == CastState.REELING) and multiplayer.is_server():
		var bite_manager: Node = get_tree().get_first_node_in_group("bite_event_manager")
		if bite_manager:
			bite_manager.cancel_pending_bite(owner_peer_id)
	state = CastState.IDLE


func _process(_delta: float) -> void:
	# Only run for the local owner of this rod.
	if owner_peer_id == 0 or owner_peer_id != multiplayer.get_unique_id():
		return
	# Stowed (holding a fish instead) -- don't react to "cast" input at all;
	# that's EquipmentSlot's toss-back input to handle while a fish is held.
	if not is_equipped:
		return
	# Swimming during a capsize -- "cast" means "claim the nearest corner"
	# there (Player._try_claim_nearest_corner), not fire the rod.
	if _is_owner_swimming():
		return

	if state == CastState.CHARGING:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - charge_start_time
		current_power = clampf(elapsed / charge_time_to_full, 0.0, 1.0)
		EventBus.cast_charge_updated.emit(current_power, owner_peer_id)
		_update_landing_preview()
	elif _landing_preview != null and _landing_preview.visible:
		_hide_landing_preview()

	if Input.is_action_just_pressed("cast"):
		# GDD Bite Detection: a shadow struck and the hook-set window is
		# open -- same button as casting itself, reused rather than a new
		# binding, since start_charge() is already a no-op outside IDLE.
		if state == CastState.WAITING_BITE and _hook_window_open:
			var bite_manager: Node = get_tree().get_first_node_in_group("bite_event_manager")
			if bite_manager:
				bite_manager.request_hook_set()
		else:
			start_charge()

	if Input.is_action_just_released("cast"):
		release_cast()

	if Input.is_action_just_pressed(&"cancel_cast"):
		request_cancel_cast()


# ── RPC 1: Client → Host ──────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func _request_cast(cam_origin: Vector3, cam_forward: Vector3, power: float) -> void:
	# Only the host validates. Clients receive this via call_local but exit here.
	if not multiplayer.is_server():
		return

	# get_remote_sender_id() returns 0 when the host calls locally — treat as peer 1.
	var sender := multiplayer.get_remote_sender_id()
	var effective_sender := 1 if sender == 0 else sender
	if effective_sender != owner_peer_id:
		return  # Wrong rod — reject silently.

	power = clampf(power, 0.0, 1.0)
	_validate_and_land_cast(cam_origin, cam_forward, power)


# ── Host-only validation (not an RPC) ─────────────────────────────────────────
## Resolves the active map fresh via NetworkManager on every call rather than
## caching a reference on the node -- a cached copy needs actively refreshing
## whenever the loaded map changes (e.g. lobby -> lake at round start), and
## since validation only ever runs here (host-side), a live lookup costs
## nothing and can't go stale. A per-node cache (the previous design) also
## can't be kept correct for peers other than whichever one is "local" to
## the machine doing the refreshing -- see PROGRESS.md.

func _validate_and_land_cast(cam_origin: Vector3, cam_forward: Vector3, power: float) -> void:
	var aim_point := _compute_aim_point(cam_origin, cam_forward, power)

	# Snap to the actual water surface height, not the aim point's height --
	# otherwise the lure/bobber ends up floating at eye level instead of
	# sitting on the water.
	var water_point = WaterValidator.find_water_point(aim_point, NetworkManager.get_current_map())
	if water_point == null:
		_cast_failed.rpc(&"invalid_water")
		return

	_cast_landed.rpc(water_point, 0.5)  # 0.5 s lure flight — placeholder


## Aim direction + power -> the flat aim point (camera height, not yet
## snapped to any surface). This is the one piece of math that decides
## where a cast is even aimed -- shared by the host's real validation above
## and the client-side landing preview below (_update_landing_preview) so
## the preview can never show a different point than a real cast would use.
## Safe to call on any peer: pure math, no map/physics access, no authority
## implications.
func _compute_aim_point(cam_origin: Vector3, cam_forward: Vector3, power: float) -> Vector3:
	# Cast distance is horizontal reach, not full 3D look-direction distance --
	# otherwise aiming down at the water (as any player naturally would while
	# fishing) sends the endpoint's Y far below the surface and the water
	# raycast below never reaches it. GDD: aim direction + power -> distance,
	# not literal 3D line-of-sight.
	var horizontal := Vector3(cam_forward.x, 0.0, cam_forward.z)
	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3(0.0, 0.0, -1.0)  # looking straight up/down — fall back
	var direction := horizontal.normalized()

	var distance := maxf(power * max_cast_distance, min_cast_distance)
	return Vector3(cam_origin.x, cam_origin.y, cam_origin.z) + direction * distance


# ── Landing preview (client-side only, GDD Casting) ────────────────────────────

func _ensure_landing_preview() -> void:
	if _landing_preview != null:
		return
	_landing_preview = MeshInstance3D.new()
	_landing_preview.top_level = true  # world-positioned, ignores this Rod's own transform
	_landing_preview.visible = false
	var disc := CylinderMesh.new()
	disc.top_radius = LANDING_PREVIEW_RADIUS
	disc.bottom_radius = LANDING_PREVIEW_RADIUS
	disc.height = 0.02
	_landing_preview.mesh = disc
	_landing_preview_material = StandardMaterial3D.new()
	_landing_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_landing_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_landing_preview.set_surface_override_material(0, _landing_preview_material)
	add_child(_landing_preview)


## Runs every frame while THIS rod's own local owner is charging (see the
## owner gate at the top of _process). Reuses _compute_aim_point + the same
## WaterValidator every real cast uses, so it can never disagree with where
## release_cast() would actually land.
func _update_landing_preview() -> void:
	if player_camera == null:
		return
	_ensure_landing_preview()

	var cam_origin := player_camera.global_transform.origin
	var cam_forward := -player_camera.global_transform.basis.z
	var aim_point := _compute_aim_point(cam_origin, cam_forward, current_power)
	var map := NetworkManager.get_current_map()
	var water_point: Variant = WaterValidator.find_water_point(aim_point, map)

	if water_point != null:
		_landing_preview.global_position = (water_point as Vector3) + Vector3(0.0, LANDING_PREVIEW_Y_OFFSET, 0.0)
		_landing_preview_material.albedo_color = LANDING_PREVIEW_VALID_COLOR
	else:
		# Not water -- still show the blocked marker somewhere real instead
		# of floating at eye height. Visual-only fallback ray (any solid),
		# never used to decide the actual cast outcome -- that's step 2/3.
		var fallback: Variant = _find_any_surface_below(aim_point, map)
		var shown_pos: Vector3 = (fallback as Vector3) if fallback != null else aim_point
		_landing_preview.global_position = shown_pos + Vector3(0.0, LANDING_PREVIEW_Y_OFFSET, 0.0)
		_landing_preview_material.albedo_color = LANDING_PREVIEW_INVALID_COLOR

	_landing_preview.visible = true


func _hide_landing_preview() -> void:
	_landing_preview.visible = false


## Visual-only placement helper for the invalid-preview case -- straight
## down for ANY solid (deck, shore, whatever), not just water. Never feeds
## into a real cast's outcome.
func _find_any_surface_below(pos: Vector3, map: Node3D) -> Variant:
	if map == null:
		return null
	var space_state := map.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0.0, 10.0, 0.0), pos + Vector3(0.0, -10.0, 0.0)
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null
	return result.position as Vector3


# ── RPC 2: Host → All clients, cast confirmed ─────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _cast_landed(endpoint: Vector3, lure_flight_seconds: float) -> void:
	state = CastState.ANIMATING
	EventBus.cast_landed.emit(endpoint, lure_flight_seconds, owner_peer_id)


# ── RPC 3: Host → All clients, cast rejected ──────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _cast_failed(reason: StringName) -> void:
	state = CastState.IDLE
	EventBus.cast_failed.emit(reason, owner_peer_id)


# ── Big Fish Event (BigFishEventManager, host-only, calls this directly) ───────
## Every peer has a SEPARATE Rod instance, not shared memory -- setting
## .state host-side only changes the host's own local mirror, so joining/
## leaving the event needs to broadcast the same way _cast_landed does.

@rpc("authority", "call_local", "reliable")
func _set_big_fish_event_state(participating: bool) -> void:
	state = CastState.BIG_FISH_EVENT if participating else CastState.IDLE


# ── RPC 4: Client → Host, local reel minigame resolved ─────────────────────────
## Reel itself runs entirely client-side (ReelMinigame). This just tells the
## host to despawn the Fish it's holding for this rod. The owning client
## already reset its own state to IDLE optimistically before calling this.

func request_reel_resolution(success: bool, was_perfect: bool) -> void:
	_request_reel_resolution.rpc(success, was_perfect)


@rpc("any_peer", "call_local", "reliable")
func _request_reel_resolution(success: bool, was_perfect: bool) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()
	var effective_sender := 1 if sender == 0 else sender
	if effective_sender != owner_peer_id:
		return  # Wrong rod — reject silently.

	var bite_manager: Node = get_tree().get_first_node_in_group("bite_event_manager")
	if bite_manager:
		bite_manager.resolve_reel(owner_peer_id, success, was_perfect)

	# The owning client already reset ITS OWN local `state` to IDLE
	# optimistically, but that assignment is purely local -- every other
	# peer's separate mirror of this Rod never heard about it, so their
	# `state` stayed at WAITING_BITE forever and LureAnimator (which polls
	# `rod.state == IDLE` to decide when to hide the bobber/line) never
	# cleared it: the bobber and line just sat there on every other
	# player's screen after the cast was actually done. Broadcasting this
	# explicitly closes that gap -- harmless no-op for the owning client,
	# who's already at IDLE.
	_broadcast_reel_state_reset.rpc()


@rpc("authority", "call_local", "reliable")
func _broadcast_reel_state_reset() -> void:
	state = CastState.IDLE
