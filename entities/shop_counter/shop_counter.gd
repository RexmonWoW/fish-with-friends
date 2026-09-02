class_name ShopCounter
extends Node3D

## GDD Per-Run Shop / Lobby: "Counter for upgrades and consumables." Lives
## in the lobby only (the shop is between-day furniture, not a fishing map
## fixture) -- self-contained the same way Livewell is (physical object +
## proximity + its own host-authoritative RPCs, no separate manager node).
## Only the counter and its interaction are built here -- mirror/trophy
## case are a future dispatch (GDD Lobby), cosmetics don't exist yet so
## there'd be nothing for a mirror to show.
##
## Purchases are host-authoritative (GDD: "the one place in this codebase
## where a desync would actually corrupt run state, not just look wrong").
## A client never deducts from the shared pot locally -- it asks, the host
## validates against ShopCatalog + RunState.try_spend_from_pot, applies the
## effect, and broadcasts the result to everyone (not just the requester --
## the crew shops together, a bystander needs to see a purchase land live
## too).


func _ready() -> void:
	add_to_group("shop_counter")
	var zone: Area3D = $InteractionZone
	zone.body_entered.connect(_on_body_entered)
	zone.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	var player := body as Player
	if player == null or player.peer_id != multiplayer.get_unique_id():
		return
	EventBus.shop_proximity_changed.emit(self, true)


func _on_body_exited(body: Node) -> void:
	var player := body as Player
	if player == null or player.peer_id != multiplayer.get_unique_id():
		return
	EventBus.shop_proximity_changed.emit(self, false)


# ── Purchases (host-authoritative) ──────────────────────────────────────────────

## Client entry point -- ShopDisplay UI calls this on a buy click.
## target_peer_id is ignored for crew-wide items (fish_finder).
func request_purchase(item_id: StringName, target_peer_id: int) -> void:
	_request_purchase.rpc(item_id, target_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _request_purchase(item_id: StringName, target_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var requester_peer_id := 1 if sender == 0 else sender

	var result := _try_resolve_purchase(item_id, target_peer_id)
	_notify_purchase_resolved.rpc(
		requester_peer_id, item_id, target_peer_id, result["success"], result["reason"]
	)


## Validates + applies a purchase, host-side only (caller already guards
## is_server()). Returns {"success": bool, "reason": StringName}. Never
## partially applies -- the spend (try_spend_from_pot) only succeeds
## atomically, and the effect only ever runs after that succeeds.
func _try_resolve_purchase(item_id: StringName, target_peer_id: int) -> Dictionary:
	if not (item_id in ShopCatalog.ITEMS):
		return {"success": false, "reason": &"unknown_item"}

	var target: Player = null
	if ShopCatalog.target_for(item_id) == ShopCatalog.Target.PLAYER:
		target = NetworkManager.spawned_players.get(target_peer_id)
		if target == null:
			return {"success": false, "reason": &"no_target"}

	var price: Variant = ShopCatalog.get_price(item_id, target.stats if target else null)
	if price == null:
		return {"success": false, "reason": &"unavailable"}

	if not RunState.try_spend_from_pot(price as int):
		return {"success": false, "reason": &"cant_afford"}

	_apply_purchase(item_id, target)
	return {"success": true, "reason": &""}


## Mutates whatever this item affects and broadcasts the change -- price
## was already validated/spent by the caller, this always succeeds.
func _apply_purchase(item_id: StringName, target: Player) -> void:
	match item_id:
		&"cast_range":
			target.stats.cast_range_tier += 1
			target.stats.max_cast_distance = (
				PlayerStats.FULL_CAST_RANGE
				* PlayerStats.CAST_RANGE_TIER_FRACTIONS[target.stats.cast_range_tier]
			)
			NetworkManager.broadcast_player_stats(target.peer_id, target.stats)
		&"line_strength":
			target.stats.line_strength_upgraded = true
			target.stats.reel_zone_shrink_per_miss *= ShopCatalog.LINE_STRENGTH_SHRINK_MULTIPLIER
			NetworkManager.broadcast_player_stats(target.peer_id, target.stats)
		&"reel_upgrade":
			target.stats.reel_upgraded = true
			target.stats.reel_zone_height += ShopCatalog.REEL_UPGRADE_ZONE_HEIGHT_BONUS
			NetworkManager.broadcast_player_stats(target.peer_id, target.stats)
		&"bait":
			target.stats.bait_rounds_remaining += ShopCatalog.BAIT_ROUNDS_PER_PURCHASE
			NetworkManager.broadcast_player_stats(target.peer_id, target.stats)
		&"fish_finder":
			RunState.set_fish_finder_purchased()


@rpc("authority", "call_local", "reliable")
func _notify_purchase_resolved(
	requester_peer_id: int, item_id: StringName, target_peer_id: int, success: bool, reason: StringName
) -> void:
	EventBus.purchase_resolved.emit(requester_peer_id, item_id, target_peer_id, success, reason)
