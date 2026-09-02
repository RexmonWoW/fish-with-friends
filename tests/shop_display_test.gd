extends Node

## Headless check for the ShopDisplay visibility bug found in playtest:
## _ready() hid the ROOT Control and nothing ever showed it again, so both
## _hint_label and _panel stayed invisible on screen regardless of their
## own visible flag -- a hidden parent hides its children no matter what.
## Checks is_visible_in_tree() (the actually-rendered state, respecting
## ancestors), not just .visible (which would have stayed true the whole
## time and missed this exact bug).

func _ready() -> void:
	print("--- Shop display test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)
	NetworkManager.host_lobby()


func _on_local_player_spawned(_player: Player) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var shop_display := get_tree().root.get_node_or_null("GameRoot/UILayer/ShopDisplay") as ShopDisplay
	if shop_display == null:
		print("FAIL: ShopDisplay not found under UILayer")
		get_tree().quit(1)
		return

	var shop := get_tree().get_first_node_in_group("shop_counter")
	if shop == null:
		print("FAIL: no ShopCounter found in the lobby")
		get_tree().quit(1)
		return

	# ── Proximity: the hint must actually render, not just report .visible. ──
	EventBus.shop_proximity_changed.emit(shop, true)
	await get_tree().process_frame

	if not shop_display._hint_label.is_visible_in_tree():
		print("FAIL: hint label not actually visible on screen after entering range (is_visible_in_tree=false)")
		get_tree().quit(1)
		return
	print("Hint label actually renders on entering shop range.")

	# ── Opening the panel: same check, this is the actual reported bug. ──
	shop_display._open()
	await get_tree().process_frame

	if not shop_display._panel.is_visible_in_tree():
		print("FAIL: shop panel not actually visible on screen after opening (is_visible_in_tree=false) -- the reported bug")
		get_tree().quit(1)
		return
	print("Shop panel actually renders when opened.")

	# ── The actual playtest bug: content rendered OUTSIDE the panel's own ──
	# ── box (a doubled-up manual offset), not just off-screen entirely -- ──
	# ── is_visible_in_tree() alone can't catch that, only real geometry can. ──
	if shop_display._rows_container.get_child_count() == 0:
		print("FAIL: test setup problem -- no item rows built after opening")
		get_tree().quit(1)
		return
	var bg_rect: Rect2 = shop_display._panel_bg.get_global_rect()
	var rows_rect: Rect2 = shop_display._rows_container.get_global_rect()
	if not bg_rect.encloses(rows_rect):
		print("FAIL: item rows render outside the panel box -- bg_rect=%s rows_rect=%s" % [bg_rect, rows_rect])
		get_tree().quit(1)
		return
	print("Item rows render inside the panel's own box: bg_rect=%s rows_rect=%s" % [bg_rect, rows_rect])

	# ── Closing: panel hides, hint comes back (still in range). ──
	shop_display._close()
	await get_tree().process_frame

	if shop_display._panel.is_visible_in_tree():
		print("FAIL: shop panel still visible after closing")
		get_tree().quit(1)
		return
	if not shop_display._hint_label.is_visible_in_tree():
		print("FAIL: hint label should still be visible after closing (still in range)")
		get_tree().quit(1)
		return
	print("Closing hides the panel and brings the hint back.")

	# ── Leaving range hides the hint too. ──
	EventBus.shop_proximity_changed.emit(shop, false)
	await get_tree().process_frame

	if shop_display._hint_label.is_visible_in_tree():
		print("FAIL: hint label still visible after leaving range")
		get_tree().quit(1)
		return
	print("Leaving range hides the hint.")

	print("--- Shop display test PASSED ---")
	get_tree().quit()
