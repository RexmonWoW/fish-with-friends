extends Node

## Headless smoke test for the casting pipeline (charge -> release -> RPC ->
## host validation -> cast_landed). Run directly with:
##   godot --headless --path . res://tests/cast_smoke_test.tscn
## Not wired into the real game flow -- drives NetworkManager/Rod directly
## since there's no display to click the menu buttons headlessly.

func _ready() -> void:
	print("--- Cast smoke test ---")
	print("Steam running: ", Steam.isSteamRunning())

	# NetworkManager hardcodes "GameRoot/NetworkRoot/World" paths under the
	# tree root, so instance the real game root rather than duplicating it.
	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	EventBus.cast_charge_started.connect(func(pid): print("cast_charge_started peer=", pid))
	EventBus.cast_charge_updated.connect(func(power, pid): print("cast_charge_updated power=%.2f peer=%d" % [power, pid]))
	EventBus.cast_landed.connect(func(endpoint, flight, pid): print("cast_landed endpoint=", endpoint, " flight=", flight, " peer=", pid))
	EventBus.cast_failed.connect(func(reason, pid): print("cast_failed reason=", reason, " peer=", pid))

	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	# setup_for_peer (equip + spawn-point placement) runs via call_deferred,
	# so give it a couple frames before reading the results.
	await get_tree().process_frame
	await get_tree().process_frame
	print("Local player spawned at ", player.global_position)
	var rod: Rod = player.equipment_slot.equipped_item as Rod
	print("Rod equipped: ", rod, " current_map: ", rod.current_map if rod else null)

	rod.start_charge()
	await get_tree().create_timer(0.75).timeout
	print("Charged power before release: %.2f" % rod.current_power)
	rod.release_cast()

	await get_tree().create_timer(1.5).timeout
	print("Rod state after release: ", rod.state)
	print("--- Cast smoke test complete ---")
	get_tree().quit()
