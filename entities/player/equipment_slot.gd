class_name EquipmentSlot
extends Node

## Manages what the player is holding / has stowed.
## On spawn: always equips rod (MVP behaviour).
## Storm map unequip/re-equip handled later via unequip_rod() / equip_rod().

@export var rod_scene: PackedScene  ## Assign res://entities/rod/rod.tscn in inspector.

var equipped_item: Node3D = null  ## Currently in hand.
var stowed_item: Node3D = null    ## On back (not used in MVP).
var _owner_peer_id: int = 0


## Called by Player.setup_for_peer() immediately after spawn.
func setup_for_peer(peer_id: int) -> void:
	_owner_peer_id = peer_id
	equip_rod()  # MVP: always spawn with rod in hand.


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

	# Parent to hand attachment point.
	var hand: Marker3D = get_parent().get_node("BodyPivot/AttachPoint_Hand")
	hand.add_child(rod)

	# Give the rod its owner so RPCs validate correctly.
	rod.owner_peer_id = _owner_peer_id

	# Water validation needs the active map (null is fine — WaterValidator
	# allows all casts until a map is loaded).
	rod.current_map = NetworkManager.get_current_map()

	# Give the rod a direct camera reference so it doesn't need a node-path lookup.
	# TODO: Minigame Logic may prefer a setter pattern — clean up if needed.
	var cam: Camera3D = get_parent().get_node_or_null("CameraRig/CameraPitch/Camera3D")
	rod.player_camera = cam

	equipped_item = rod


## Moves the rod from the hand to the back attachment point.
## Not called in MVP, exists for storm map (put rod away before lightning).
func unequip_rod() -> void:
	if equipped_item == null:
		return

	var back: Marker3D = get_parent().get_node("BodyPivot/AttachPoint_Back")
	var rod := equipped_item

	equipped_item.get_parent().remove_child(rod)
	back.add_child(rod)

	stowed_item = rod
	equipped_item = null


func has_rod_equipped() -> bool:
	return equipped_item != null
