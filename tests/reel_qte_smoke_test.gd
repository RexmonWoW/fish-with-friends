extends Node

## Headless check of the QTE layer: missing QTEs shrinks the zone and snaps
## the line after MAX_MISSES, while a clean run (all QTEs hit) marks the
## catch perfect all the way through to the livewell entry.

func _ready() -> void:
	print("--- Reel QTE smoke test ---")

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
	var reel = get_tree().root.get_node("GameRoot/UILayer/ReelMinigame")
	var livewell: Livewell = get_tree().get_first_node_in_group("livewell")

	# ── Part A: 3 missed QTEs should shrink the zone each time and snap the line ──
	await _cast_and_wait_for_reel(rod)
	var starting_height: float = reel._zone_height

	for i in range(3):
		reel._start_qte()
		if not reel._qte_active:
			print("FAIL: QTE did not start")
			get_tree().quit(1)
			return
		reel._on_qte_missed()
		print("After miss %d: miss_count=%d zone_height=%.3f active=%s" % [
			i + 1, reel._miss_count, reel._zone_height, reel._active
		])

	if reel._active:
		print("FAIL: reel still active after 3 misses (line should have snapped)")
		get_tree().quit(1)
		return
	if reel._zone_height >= starting_height:
		print("FAIL: zone never shrank across 3 misses")
		get_tree().quit(1)
		return
	if rod.state != Rod.CastState.IDLE:
		print("FAIL: rod not back to IDLE after line snapped")
		get_tree().quit(1)
		return
	if livewell.slots.count(null) != Livewell.MAX_SLOTS:
		print("FAIL: a fish landed in the livewell despite the line snapping")
		get_tree().quit(1)
		return
	print("Part A passed: line snapped after 3 misses, no catch recorded.")

	# ── Part B: a clean run (QTE hit correctly) should mark the catch perfect ──
	await _cast_and_wait_for_reel(rod)

	reel._start_qte()
	var correct_key := InputEventKey.new()
	correct_key.pressed = true
	correct_key.keycode = reel._qte_keys[0]
	Input.parse_input_event(correct_key)
	await get_tree().process_frame

	if reel._qte_active:
		print("FAIL: correct key press did not resolve the QTE")
		get_tree().quit(1)
		return
	if reel._miss_count != 0:
		print("FAIL: a successful QTE was counted as a miss")
		get_tree().quit(1)
		return

	reel._progress = 1.0
	await get_tree().process_frame

	var caught: CaughtFish = null
	for slot in livewell.slots:
		if slot != null:
			caught = slot
	if caught == null or not caught.was_perfect_catch:
		print("FAIL: clean run wasn't recorded as a perfect catch (caught=%s)" % caught)
		get_tree().quit(1)
		return
	print("Part B passed: perfect catch recorded, value=%d" % caught.final_value)

	print("--- Reel QTE smoke test PASSED ---")
	get_tree().quit()


func _cast_and_wait_for_reel(rod: Rod) -> void:
	rod.start_charge()
	await get_tree().create_timer(0.2).timeout
	rod.release_cast()

	var waited := 0.0
	while rod.state != Rod.CastState.REELING and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()

	if rod.state != Rod.CastState.REELING:
		print("FAIL: never reached REELING")
		get_tree().quit(1)
