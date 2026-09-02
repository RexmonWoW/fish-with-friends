extends Node

## Headless check for GDD Per-Run Shop: host-authoritative purchases --
## a client never deducts from the shared pot locally, only the host does,
## and the result (success or a specific failure reason) broadcasts to
## everyone. Covers a player-scoped item (cast range, tiered + eventually
## maxed), a crew-wide item (fish finder), a consumable (bait), and the
## can't-afford rejection leaving state untouched.

var _resolved: Array = []  # each entry: [requester_peer_id, item_id, target_peer_id, success, reason]


func _ready() -> void:
	print("--- Shop purchase test ---")

	EventBus.purchase_resolved.connect(func(requester, item_id, target, success, reason):
		_resolved.append([requester, item_id, target, success, reason])
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

	if NetworkManager._current_scene_id != &"lobby":
		print("FAIL: expected to land in the lobby (that's where the shop lives), got %s" % NetworkManager._current_scene_id)
		get_tree().quit(1)
		return

	var shop := get_tree().get_first_node_in_group("shop_counter")
	if shop == null:
		print("FAIL: no ShopCounter found in the lobby")
		get_tree().quit(1)
		return

	RunState.total_money_earned = 500

	# ── Cast range: player-scoped, tiered. ──
	var price_tier1: int = ShopCatalog.CAST_RANGE_TIER_PRICES[0]
	var pot_before := RunState.total_money_earned
	_resolved.clear()
	shop.request_purchase(&"cast_range", player1.peer_id)
	await get_tree().process_frame

	if _resolved.is_empty() or not _resolved[0][3]:
		print("FAIL: cast_range purchase for player1 didn't succeed: %s" % [_resolved])
		get_tree().quit(1)
		return
	if player1.stats.cast_range_tier != 1:
		print("FAIL: cast_range_tier should be 1 after one purchase, got %d" % player1.stats.cast_range_tier)
		get_tree().quit(1)
		return
	var expected_distance := PlayerStats.FULL_CAST_RANGE * PlayerStats.CAST_RANGE_TIER_FRACTIONS[1]
	if absf(player1.stats.max_cast_distance - expected_distance) > 0.01:
		print("FAIL: max_cast_distance should be %.1f at tier 1, got %.1f" % [expected_distance, player1.stats.max_cast_distance])
		get_tree().quit(1)
		return
	if RunState.total_money_earned != pot_before - price_tier1:
		print("FAIL: pot should have dropped by the tier-1 price (%d), went from %d to %d" %
			[price_tier1, pot_before, RunState.total_money_earned])
		get_tree().quit(1)
		return
	print("Cast range tier 1 purchased for player1: tier=%d distance=%.1f pot=%d" %
		[player1.stats.cast_range_tier, player1.stats.max_cast_distance, RunState.total_money_earned])

	# Buy the remaining two tiers to confirm it actually maxes out.
	shop.request_purchase(&"cast_range", player1.peer_id)
	await get_tree().process_frame
	shop.request_purchase(&"cast_range", player1.peer_id)
	await get_tree().process_frame
	if player1.stats.cast_range_tier != 3:
		print("FAIL: should be at tier 3 (maxed) after 3 purchases, got %d" % player1.stats.cast_range_tier)
		get_tree().quit(1)
		return
	if absf(player1.stats.max_cast_distance - PlayerStats.FULL_CAST_RANGE) > 0.01:
		print("FAIL: max_cast_distance should equal FULL_CAST_RANGE at tier 3, got %.1f" % player1.stats.max_cast_distance)
		get_tree().quit(1)
		return

	_resolved.clear()
	shop.request_purchase(&"cast_range", player1.peer_id)
	await get_tree().process_frame
	if _resolved.is_empty() or _resolved[0][3] or _resolved[0][4] != &"unavailable":
		print("FAIL: a 4th cast_range purchase should fail as unavailable (maxed), got %s" % [_resolved])
		get_tree().quit(1)
		return
	print("Cast range correctly maxes out at tier 3 -- further purchases rejected as unavailable.")

	# ── Can't afford: pot too low, nothing should change. ──
	NetworkManager._spawn_player_for_peer(2)
	await get_tree().process_frame
	await get_tree().process_frame
	var player2: Player = NetworkManager.spawned_players[2]

	RunState.total_money_earned = 5  # well below any real price
	var tier_before := player2.stats.cast_range_tier
	_resolved.clear()
	shop.request_purchase(&"cast_range", player2.peer_id)
	await get_tree().process_frame
	if _resolved.is_empty() or _resolved[0][3] or _resolved[0][4] != &"cant_afford":
		print("FAIL: an unaffordable purchase should fail as cant_afford, got %s" % [_resolved])
		get_tree().quit(1)
		return
	if player2.stats.cast_range_tier != tier_before or RunState.total_money_earned != 5:
		print("FAIL: a rejected purchase must leave state untouched (tier=%d pot=%d)" %
			[player2.stats.cast_range_tier, RunState.total_money_earned])
		get_tree().quit(1)
		return
	print("Unaffordable purchase correctly rejected, no partial state change.")

	# ── Bait: consumable, stacks. ──
	RunState.total_money_earned = 500
	_resolved.clear()
	shop.request_purchase(&"bait", player2.peer_id)
	await get_tree().process_frame
	shop.request_purchase(&"bait", player2.peer_id)
	await get_tree().process_frame
	if player2.stats.bait_rounds_remaining != 2:
		print("FAIL: two bait purchases should stack to 2 rounds remaining, got %d" % player2.stats.bait_rounds_remaining)
		get_tree().quit(1)
		return
	print("Bait purchases stack correctly: %d rounds remaining." % player2.stats.bait_rounds_remaining)

	# ── Fish finder: crew-wide, one-time. ──
	if RunState.has_fish_finder:
		print("FAIL: test setup problem -- fish finder already marked purchased")
		get_tree().quit(1)
		return
	_resolved.clear()
	shop.request_purchase(&"fish_finder", 0)  # target ignored for crew-wide items
	await get_tree().process_frame
	if _resolved.is_empty() or not _resolved[0][3]:
		print("FAIL: fish_finder purchase didn't succeed: %s" % [_resolved])
		get_tree().quit(1)
		return
	if not RunState.has_fish_finder:
		print("FAIL: RunState.has_fish_finder should be true after purchase")
		get_tree().quit(1)
		return
	print("Fish finder purchased -- crew-wide flag set.")

	_resolved.clear()
	shop.request_purchase(&"fish_finder", 0)
	await get_tree().process_frame
	if _resolved.is_empty() or _resolved[0][3] or _resolved[0][4] != &"unavailable":
		print("FAIL: a second fish_finder purchase should fail as unavailable (already owned), got %s" % [_resolved])
		get_tree().quit(1)
		return
	print("Fish finder correctly can't be bought twice.")

	print("--- Shop purchase test PASSED ---")
	get_tree().quit()
