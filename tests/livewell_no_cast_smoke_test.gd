extends Node

## Headless check for two things reported from a playtest:
## 1. Casting should be blocked while standing at the livewell (previously
##    nothing stopped you from accidentally firing the rod there).
## 2. The rod tip should sit at a sane height near the player, not far
##    above their head (AttachPoint_Hand was Y=1.2 relative to the
##    capsule's CENTER -- ~2.1m off the ground on a 1.8m-tall capsule).

func _ready() -> void:
	print("--- Livewell no-cast / rod height smoke test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	var rod_tip := rod.get_node("RodTip") as Marker3D

	var height_above_player := rod_tip.global_position.y - player.global_position.y
	print("Rod tip height above player origin: %.2f" % height_above_player)
	if height_above_player > 1.0:
		print("FAIL: rod tip is still floating way above the player (%.2f)" % height_above_player)
		get_tree().quit(1)
		return

	# Move the player into the livewell's InteractionZone (same spot the
	# livewell interaction test uses) and give physics/proximity a moment.
	player.global_position = Vector3(0.0, 1.5, 0.0)
	player.linear_velocity = Vector3.ZERO

	var waited := 0.0
	while not rod._near_livewell and waited < 3.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()

	if not rod._near_livewell:
		print("FAIL: Rod never learned it was near the livewell")
		get_tree().quit(1)
		return

	print("Attempting to cast while at the livewell...")
	rod.start_charge()
	if rod.state == Rod.CastState.CHARGING:
		print("FAIL: casting started while standing at the livewell")
		get_tree().quit(1)
		return
	print("Cast correctly blocked (state=%s)." % rod.state)

	# Step away and confirm casting works normally again.
	player.global_position = Vector3(-1.2, 0.5, -1.8)
	waited = 0.0
	while rod._near_livewell and waited < 3.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()

	rod.start_charge()
	if rod.state != Rod.CastState.CHARGING:
		print("FAIL: casting didn't work again after leaving the livewell")
		get_tree().quit(1)
		return

	print("--- Livewell no-cast / rod height smoke test PASSED ---")
	get_tree().quit()
