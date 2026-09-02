class_name ShopDisplay
extends Control

## GDD Per-Run Shop / Lobby: proximity hint + the shop panel itself. Plain,
## functional UI built procedurally like every other overlay in this
## codebase (CastMeter, LivewellDisplay, ReelMinigame) -- real art is
## Nick's later.
##
## Purchases are host-authoritative (ShopCounter) -- this never touches
## RunState.total_money_earned or any PlayerStats field directly, only
## ever sends a request and redraws off whatever the host actually
## broadcasts back (EventBus.purchase_resolved, RunState.pot_changed, or a
## crewmate's stats arriving via NetworkManager._apply_player_stats).
##
## Opening the shop switches the mouse to visible so real Button clicks
## work -- same swap Player.gd already does for Esc -- and closes again
## (E, the Close button, or walking out of range) restores it captured.

const PANEL_SIZE: Vector2 = Vector2(560.0, 480.0)
const ROW_PADDING: float = 10.0

var _current_shop: Node = null
var _is_open: bool = false

var _hint_label: Label = null
var _panel_bg: ColorRect = null
var _panel: Control = null
var _pot_label: Label = null
var _rows_container: VBoxContainer = null


func _ready() -> void:
	_build_ui()
	hide()
	EventBus.shop_proximity_changed.connect(_on_proximity_changed)
	EventBus.purchase_resolved.connect(_on_purchase_resolved)
	RunState.pot_changed.connect(_on_pot_changed)


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_hint_label = Label.new()
	_hint_label.text = "Press E to shop"
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.position = Vector2(-100.0, -90.0)
	_hint_label.custom_minimum_size = Vector2(200.0, 24.0)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.hide()
	add_child(_hint_label)

	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	# STOP, unlike almost everything else in this codebase -- the shop
	# panel is the one UI that needs real mouse clicks (Buttons), and a
	# click landing on the background instead of a button must NOT fall
	# through to Player._unhandled_input's own "click recaptures the
	# mouse" handler, or shopping would yank the cursor back every miss-click.
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.hide()
	add_child(_panel)

	_panel_bg = ColorRect.new()
	_panel_bg.color = Color(0.05, 0.05, 0.05, 0.92)
	_panel_bg.size = PANEL_SIZE
	_panel_bg.position = -PANEL_SIZE * 0.5
	_panel_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(_panel_bg)

	var content := VBoxContainer.new()
	content.position = _panel_bg.position + Vector2(16.0, 12.0)
	content.custom_minimum_size = PANEL_SIZE - Vector2(32.0, 24.0)
	content.size = content.custom_minimum_size
	content.add_theme_constant_override("separation", 8)
	_panel_bg.add_child(content)

	var title := Label.new()
	title.text = "SHOP"
	title.add_theme_font_size_override("font_size", 24)
	content.add_child(title)

	_pot_label = Label.new()
	_pot_label.add_theme_font_size_override("font_size", 16)
	_pot_label.modulate = Color(0.8, 0.9, 0.8)
	content.add_child(_pot_label)

	content.add_child(HSeparator.new())

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 4)
	content.add_child(_rows_container)

	content.add_child(HSeparator.new())

	var close_button := Button.new()
	close_button.text = "Close (E)"
	close_button.custom_minimum_size = Vector2(120.0, 28.0)
	close_button.pressed.connect(_close)
	content.add_child(close_button)


func _unhandled_input(event: InputEvent) -> void:
	if _current_shop == null:
		return
	if event.is_action_pressed(&"interact"):
		if _is_open:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()


func _on_proximity_changed(shop: Node, in_range: bool) -> void:
	if in_range:
		_current_shop = shop
		_hint_label.show()
	elif shop == _current_shop:
		_current_shop = null
		_hint_label.hide()
		if _is_open:
			_close()


func _open() -> void:
	_is_open = true
	_hint_label.hide()
	_panel.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh()


func _close() -> void:
	_is_open = false
	_panel.hide()
	if _current_shop != null:
		_hint_label.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_purchase_resolved(requester_peer_id: int, item_id: StringName, _target_peer_id: int, success: bool, reason: StringName) -> void:
	if not success and requester_peer_id == multiplayer.get_unique_id():
		_pot_label.text = "Can't buy %s: %s" % [ShopCatalog.display_name(item_id), _reason_text(reason)]
		await get_tree().create_timer(2.0).timeout
	if _is_open:
		_refresh()


func _on_pot_changed(_new_total: int) -> void:
	if _is_open:
		_refresh()


func _reason_text(reason: StringName) -> String:
	match reason:
		&"cant_afford": return "the pot can't cover it"
		&"unavailable": return "maxed out or already owned"
		&"no_target": return "that player isn't here"
		_: return "something went wrong"


# ── Building the item list ──────────────────────────────────────────────────────

func _refresh() -> void:
	_pot_label.text = "$%d in the shared pot" % RunState.total_money_earned

	for child in _rows_container.get_children():
		child.queue_free()

	for item_id in ShopCatalog.ITEMS:
		_rows_container.add_child(_build_item_row(item_id))


func _build_item_row(item_id: StringName) -> Control:
	var row := VBoxContainer.new()

	var header := Label.new()
	header.text = "%s -- %s" % [ShopCatalog.display_name(item_id), ShopCatalog.description(item_id)]
	header.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(header)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	row.add_child(buttons)

	if ShopCatalog.target_for(item_id) == ShopCatalog.Target.CREW:
		buttons.add_child(_build_buy_button(item_id, 0, "Buy (crew)", null))
	else:
		for peer_id in NetworkManager.spawned_players:
			var player: Player = NetworkManager.spawned_players[peer_id]
			var label := "For %s" % SteamManager.get_display_name_for_peer(peer_id)
			buttons.add_child(_build_buy_button(item_id, peer_id, label, player.stats))

	return row


func _build_buy_button(item_id: StringName, target_peer_id: int, label: String, stats: PlayerStats) -> Button:
	var button := Button.new()
	var price: Variant = ShopCatalog.get_price(item_id, stats)

	if price == null:
		button.text = "%s (%s)" % [label, ShopCatalog.unavailable_reason(item_id, stats)]
		button.disabled = true
	else:
		var affordable: bool = RunState.total_money_earned >= (price as int)
		button.text = "%s -- $%d" % [label, price]
		button.disabled = not affordable
		if affordable:
			button.pressed.connect(func(): _on_buy_pressed(item_id, target_peer_id))

	button.custom_minimum_size = Vector2(160.0, 26.0)
	return button


func _on_buy_pressed(item_id: StringName, target_peer_id: int) -> void:
	if _current_shop == null:
		return
	_current_shop.request_purchase(item_id, target_peer_id)
