extends Node

## Headless check: "fish should be harder to catch the more value they'll
## have." Forces a bite with a cheap species (bluegill, base_value=6) then a
## valuable one (golden_koi, base_value=120) and confirms the reel's actual
## tunables get harder for the valuable one -- smaller catch zone, faster
## fish movement, shorter QTE reaction window, faster progress drain.

func _ready() -> void:
	print("--- Reel difficulty test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.request_start_round()
	var waited := 0.0
	while NetworkManager._current_scene_id != &"lake" and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if NetworkManager._current_scene_id != &"lake":
		print("FAIL: never reached the lake")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame

	var rod: Rod = player.equipment_slot.equipped_item as Rod
	var reel := get_tree().root.get_node("GameRoot/UILayer/ReelMinigame")

	var cheap: FishData = load("res://data/fish/species/bluegill.tres")
	var pricey: FishData = load("res://data/fish/species/golden_koi.tres")
	if cheap.base_value >= pricey.base_value:
		print("FAIL: test setup problem -- bluegill isn't cheaper than golden_koi")
		get_tree().quit(1)
		return

	# ── Cheap fish: should land at (or very near) the easy baseline. ──
	rod.state = Rod.CastState.WAITING_BITE
	EventBus.bite_started.emit(cheap, 1)
	await get_tree().process_frame

	if rod.state != Rod.CastState.REELING:
		print("FAIL: test setup problem -- cheap-fish bite didn't start the reel")
		get_tree().quit(1)
		return

	var easy_zone: float = reel._zone_height
	var easy_speed: float = reel._fish_speed
	var easy_qte_window: float = reel._qte_window
	var easy_drain: float = reel._drain_rate
	print("Cheap fish (value=%d): zone=%.3f speed=%.3f qte_window=%.3f drain=%.3f" %
		[cheap.base_value, easy_zone, easy_speed, easy_qte_window, easy_drain])

	# Bail out of this reel without resolving it through the fish (avoids
	# needing a real Fish node alive on the host for _finish's RPC round
	# trip) -- just reset state directly, same as any other test that only
	# cares about the minigame's own numbers, not the catch outcome.
	reel._active = false
	rod.state = Rod.CastState.WAITING_BITE

	# ── Pricey fish: should land at (or very near) the hard end. ──
	EventBus.bite_started.emit(pricey, 1)
	await get_tree().process_frame

	if rod.state != Rod.CastState.REELING:
		print("FAIL: test setup problem -- pricey-fish bite didn't start the reel")
		get_tree().quit(1)
		return

	var hard_zone: float = reel._zone_height
	var hard_speed: float = reel._fish_speed
	var hard_qte_window: float = reel._qte_window
	var hard_drain: float = reel._drain_rate
	print("Pricey fish (value=%d): zone=%.3f speed=%.3f qte_window=%.3f drain=%.3f" %
		[pricey.base_value, hard_zone, hard_speed, hard_qte_window, hard_drain])

	if hard_zone >= easy_zone:
		print("FAIL: pricey fish's catch zone isn't smaller (harder) than the cheap fish's")
		get_tree().quit(1)
		return
	if hard_speed <= easy_speed:
		print("FAIL: pricey fish doesn't move faster (harder) than the cheap fish")
		get_tree().quit(1)
		return
	if hard_qte_window >= easy_qte_window:
		print("FAIL: pricey fish's QTE window isn't shorter (harder) than the cheap fish's")
		get_tree().quit(1)
		return
	if hard_drain <= easy_drain:
		print("FAIL: pricey fish doesn't drain progress faster (harder) than the cheap fish")
		get_tree().quit(1)
		return

	print("--- Reel difficulty test PASSED ---")
	get_tree().quit()
