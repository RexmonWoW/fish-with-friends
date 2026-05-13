class_name Player
extends RigidBody3D

## One player body. Spawned by PlayerSpawner for every peer including the host.
## Movement is client-authoritative — each client moves their own body locally.
## Host still owns fish spawns, livewell, catches, bite events.

var peer_id: int = 0

# Node references — assigned in _ready, used by EquipmentSlot and Minigame Logic.
@onready var body_pivot: Node3D = $BodyPivot
@onready var camera_rig: Node3D = $CameraRig
@onready var equipment_slot: EquipmentSlot = $EquipmentSlot


func _ready() -> void:
	# Physics body should not tip over.
	lock_rotation = true


## Called by PlayerSpawner immediately after this node is added to the scene.
## Sets up peer ownership, equipment, and multiplayer authority.
func setup_for_peer(id: int) -> void:
	peer_id = id

	# Client-authoritative: each peer replicates their own player.
	$PlayerSync.set_multiplayer_authority(id)

	# Hand the peer ID to EquipmentSlot so the rod gets the right owner.
	equipment_slot.setup_for_peer(id)


# ── Movement stubs (Minigame Logic implements) ────────────────────────────────

func _local_input_tick() -> void:
	pass  # TODO: Minigame Logic implements — WASD + mouse capture


func _apply_movement_impulse(_direction: Vector3) -> void:
	pass  # TODO: Minigame Logic implements — applies force to RigidBody3D
