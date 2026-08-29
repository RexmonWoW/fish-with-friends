class_name EquipmentSlot
extends Node

## Manages what the player is holding / has stowed.
## On spawn: always equips rod (MVP behaviour).
## After a successful catch, the rod is stowed (not freed) and a held-fish
## visual takes its place until the player tosses it back or stores it in a
## livewell -- see equip_fish()/unequip_fish()/re_equip_rod() below.

@export var rod_scene: PackedScene  ## Assign res://entities/rod/rod.tscn in inspector.

var equipped_item: Node3D = null  ## Currently in hand.
var stowed_item: Node3D = null    ## On back (the rod, while a fish is held).
var _owner_peer_id: int = 0
var _held_fish: CaughtFish = null


## Called by Player.setup_for_peer() immediately after spawn.
func setup_for_peer(peer_id: int) -> void:
	_owner_peer_id = peer_id
	equip_rod()  # MVP: always spawn with rod in hand.


func _process(_delta: float) -> void:
	# Only the local owner acts on their own held fish.
	if _owner_peer_id == 0 or _owner_peer_id != multiplayer.get_unique_id():
		return
	if _held_fish == null:
		return
	# Toss back works anywhere, no livewell needed -- storing/swapping (1-5)
	# is handled by LivewellDisplay, which is already proximity-gated.
	if Input.is_action_just_pressed("cast"):
		request_toss_held_fish()


## Instances the rod, parents it to the hand attachment point,
## and sets the rod's ownership + camera reference.
func equip_rod() -> void:
	if rod_scene == null:
		push_error("EquipmentSlot: rod_scene not assigned in inspector.")
		return

	var rod: Rod = rod_scene.instantiate() as Rod
	if rod == null:
		push_error("EquipmentSlot: rod_scene did not produce a Rod node.")
		return

	# Parent to hand attachment point. Camera-relative (not BodyPivot) so the
	# held rod tracks the camera rigidly -- BodyPivot only soft-follows
	# camera yaw with a lag (so physics bumps don't yank the view), which
	# made a held rod + its line visibly swing/lag on every turn.
	var hand: Marker3D = get_parent().get_node("CameraRig/CameraPitch/AttachPoint_Hand")
	hand.add_child(rod)

	# Give the rod its owner so RPCs validate correctly.
	rod.owner_peer_id = _owner_peer_id

	# Give the rod a direct camera reference so it doesn't need a node-path lookup.
	# TODO: Minigame Logic may prefer a setter pattern — clean up if needed.
	var cam: Camera3D = get_parent().get_node_or_null("CameraRig/CameraPitch/Camera3D")
	rod.player_camera = cam

	equipped_item = rod


## Moves the rod from the hand to the back attachment point. Keeps the SAME
## node alive (not freed) so its state/identity survives -- used both for
## the storm map's planned unequip and for stowing while a fish is held.
func unequip_rod() -> void:
	if equipped_item == null:
		return

	var back: Marker3D = get_parent().get_node("BodyPivot/AttachPoint_Back")
	var rod := equipped_item as Rod

	equipped_item.get_parent().remove_child(equipped_item)
	back.add_child(equipped_item)
	if rod:
		rod.is_equipped = false  # stop responding to cast input while stowed

	stowed_item = equipped_item
	equipped_item = null


## Brings the previously-stowed rod back to the hand -- the SAME instance
## unequip_rod() stowed, not a freshly instanced one, so its state/owner/
## camera reference all survive the round trip.
func re_equip_rod() -> void:
	if stowed_item == null:
		return

	var hand: Marker3D = get_parent().get_node("CameraRig/CameraPitch/AttachPoint_Hand")
	var rod := stowed_item as Rod

	stowed_item.get_parent().remove_child(stowed_item)
	hand.add_child(stowed_item)
	if rod:
		rod.is_equipped = true

	equipped_item = stowed_item
	stowed_item = null


func has_rod_equipped() -> bool:
	return equipped_item != null


func has_fish_held() -> bool:
	return _held_fish != null


func get_held_fish() -> CaughtFish:
	return _held_fish


# ── Holding a catch (host broadcasts, every peer's mirror updates) ─────────────
## GDD: catches used to auto-drop into the livewell (or silently discard it
## full). Now the player holds their catch and chooses -- toss it back
## (cast, anywhere) or store/swap it into a specific livewell slot
## (LivewellDisplay's 1-5, near the livewell) -- so there's less pure
## gamble, and a great catch can deliberately replace a weak one already in
## the livewell instead of just being discarded on a full well.

@rpc("authority", "call_local", "reliable")
func _receive_caught_fish(fish: CaughtFish) -> void:
	equip_fish(fish)


func equip_fish(fish: CaughtFish) -> void:
	unequip_rod()  # stow it, keep it alive for later
	_held_fish = fish

	var visual := _build_held_fish_visual(fish)
	var hand: Marker3D = get_parent().get_node("CameraRig/CameraPitch/AttachPoint_Hand")
	hand.add_child(visual)
	equipped_item = visual


func unequip_fish() -> void:
	if equipped_item != null:
		equipped_item.queue_free()
	equipped_item = null
	_held_fish = null


func _build_held_fish_visual(fish: CaughtFish) -> Node3D:
	# Same placeholder look/sizing as Livewell's slot visuals -- small
	# species-tinted capsule, scaled by where this fish's rolled size falls
	# in its species' min/max range. Real art is Art & Polish's, per the
	# rest of this project's placeholder geometry.
	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	var species := fish.species
	var size_range := species.max_size - species.min_size
	var t := 0.5 if size_range <= 0.0 else clampf(
		(fish.size - species.min_size) / size_range, 0.0, 1.0
	)
	var length := lerpf(0.14, 0.34, t)
	capsule.height = length
	capsule.radius = length * 0.22
	mesh_instance.mesh = capsule
	mesh_instance.rotation.z = PI / 2.0  # lay on its side, matches Livewell's convention

	var material := StandardMaterial3D.new()
	var hue := float(hash(species.species_id) % 360) / 360.0
	material.albedo_color = Color.from_hsv(hue, 0.6, 0.85)
	mesh_instance.set_surface_override_material(0, material)

	return mesh_instance


# ── Resolving a held fish (toss or store) ───────────────────────────────────────
## Both requests are sender-validated host-side, same shape as Rod's cast/
## reel RPCs, then broadcast so every peer's mirror unequips the fish and
## brings the stowed rod back at the same time.

func request_toss_held_fish() -> void:
	_request_toss_held_fish.rpc()


@rpc("any_peer", "call_local", "reliable")
func _request_toss_held_fish() -> void:
	if not multiplayer.is_server():
		return
	if not _valid_sender():
		return
	if _held_fish == null:
		return
	_broadcast_fish_resolved.rpc()


## Called by LivewellDisplay (host-authoritative caller path, same shape as
## Livewell.request_remove_fish) when the local player picks a slot (1-5)
## while holding a fish. index may point at an empty OR occupied slot --
## Livewell.replace_fish() overwrites either way, matching the livewell's
## existing "no confirmation, gone immediately" philosophy for whatever fish
## was there before.
func request_store_held_fish(index: int) -> void:
	_request_store_held_fish.rpc(index)


@rpc("any_peer", "call_local", "reliable")
func _request_store_held_fish(index: int) -> void:
	if not multiplayer.is_server():
		return
	if not _valid_sender():
		return
	if _held_fish == null:
		return

	var livewell: Node = get_tree().get_first_node_in_group("livewell")
	if livewell == null:
		return
	livewell.replace_fish(index, _held_fish)
	_broadcast_fish_resolved.rpc()


@rpc("authority", "call_local", "reliable")
func _broadcast_fish_resolved() -> void:
	unequip_fish()
	re_equip_rod()


func _valid_sender() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	var effective_sender := 1 if sender == 0 else sender
	return effective_sender == _owner_peer_id
