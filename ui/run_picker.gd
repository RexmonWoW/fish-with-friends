class_name RunPicker
extends Control

## GDD Run Saves phase 2: the 4-slot picker at lobby creation. Host-only --
## same trust model as the shop and debug console (RunSaveManager's own
## functions are all host-gated anyway, but there's no point ever showing
## this to a client who can't act on it). Plain, functional UI built
## procedurally like every other overlay in this codebase.
##
## Shows itself automatically whenever the local (host) player spawns into
## a fresh lobby with no slot chosen yet (RunSaveManager._active_slot ==
## -1) -- covers both a brand-new app session and every run after the
## first (NetworkManager.disconnect_from_lobby resets _active_slot for
## exactly this). No close/cancel button by design: GDD frames this as a
## step at lobby creation, not an optional dialog.
##
## Solo/co-op eligibility is read live off who's actually connected right
## now, not a pre-declared intent -- the "Host & Invite Friends" button
## already opens the Steam overlay before this ever matters, so by the
## time the host interacts with a row, real crew composition is usually
## already known. Refreshes live as peers join/leave while it's open, so
## a co-op slot goes from grayed-out to loadable the moment a friend
## connects, no need to reopen anything.

const PANEL_SIZE: Vector2 = Vector2(640.0, 560.0)

var _panel: Control = null
var _session_label: Label = null
var _rows_container: VBoxContainer = null
var _status_label: Label = null

var _confirming_delete_slot: int = -1


func _ready() -> void:
	_build_ui()
	_panel.hide()

	NetworkManager.spawned_local_player.connect(_on_spawned_local_player)
	NetworkManager.peer_player_spawned.connect(_on_crew_changed)
	NetworkManager.peer_player_despawned.connect(_on_crew_changed)


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = -PANEL_SIZE * 0.5
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var title := Label.new()
	title.text = "CHOOSE A RUN"
	title.add_theme_font_size_override("font_size", 24)
	content.add_child(title)

	_session_label = Label.new()
	_session_label.add_theme_font_size_override("font_size", 14)
	_session_label.modulate = Color(0.8, 0.9, 0.8)
	content.add_child(_session_label)

	content.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 400)
	content.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 12)
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.modulate = Color(1.0, 0.7, 0.7)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	content.add_child(_status_label)


func _on_spawned_local_player(_player: Player) -> void:
	if not multiplayer.is_server():
		return
	if NetworkManager._current_scene_id != &"lobby":
		return
	if RunSaveManager._active_slot != -1:
		return
	_open()


func _on_crew_changed(_peer_id: int, _player: Player = null) -> void:
	if _panel.visible:
		_refresh()


func _open() -> void:
	_confirming_delete_slot = -1
	_status_label.text = ""
	_panel.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh()


func _close() -> void:
	_panel.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _refresh() -> void:
	var is_coop := NetworkManager.spawned_players.size() > 1
	_session_label.text = "Playing: %s (%d here right now)" % \
		["Co-op" if is_coop else "Solo", NetworkManager.spawned_players.size()]

	for child in _rows_container.get_children():
		child.queue_free()

	for slot in range(RunSaveManager.SLOT_COUNT):
		_rows_container.add_child(_build_slot_row(slot, is_coop))


func _build_slot_row(slot: int, session_is_coop: bool) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var save := RunSaveManager.peek_slot(slot)

	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	row.add_child(buttons)

	if save == null:
		label.text = "Slot %d -- empty" % slot
		buttons.add_child(_build_new_run_button(slot, &"quota", "New Quota Run"))
		buttons.add_child(_build_new_run_button(slot, &"casual", "New Casual Run"))
		row.add_child(HSeparator.new())
		return row

	var kind := "Co-op" if save.is_coop else "Solo"
	var mode := "Casual" if save.game_mode == &"casual" else "Quota"
	var crew := ", ".join(save.player_names_by_steam_id.values())
	if crew.is_empty():
		crew = "(no crew recorded)"
	var last_played := Time.get_datetime_string_from_unix_time(save.last_played_unix, true)
	label.text = "Slot %d -- %s, %s, day %d, $%d in the pot\nCrew: %s\nLast played: %s" % \
		[slot, kind, mode, save.day_number, save.total_money_earned, crew, last_played]

	if _confirming_delete_slot == slot:
		var confirm_label := Label.new()
		confirm_label.text = "Really delete this save?"
		confirm_label.modulate = Color(1.0, 0.7, 0.7)
		row.add_child(confirm_label)

		var yes_button := Button.new()
		yes_button.text = "Yes, Delete"
		yes_button.pressed.connect(func(): _on_delete_confirmed(slot))
		buttons.add_child(yes_button)

		var cancel_button := Button.new()
		cancel_button.text = "Cancel"
		cancel_button.pressed.connect(func(): _on_delete_cancelled())
		buttons.add_child(cancel_button)

		row.add_child(HSeparator.new())
		return row

	var version_ok := save.save_version == RunSave.CURRENT_VERSION
	var type_ok := save.is_coop == session_is_coop

	var load_button := Button.new()
	if not version_ok:
		load_button.text = "Load (outdated save version)"
		load_button.disabled = true
	elif not type_ok:
		load_button.text = "Load (needs %s)" % ("co-op" if save.is_coop else "solo")
		load_button.disabled = true
	else:
		load_button.text = "Load"
		load_button.pressed.connect(func(): _on_load_pressed(slot))
	buttons.add_child(load_button)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.pressed.connect(func(): _on_delete_pressed(slot))
	buttons.add_child(delete_button)

	row.add_child(HSeparator.new())
	return row


func _build_new_run_button(slot: int, game_mode: StringName, label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func(): _on_new_run_pressed(slot, game_mode))
	return button


func _on_new_run_pressed(slot: int, game_mode: StringName) -> void:
	var result: Dictionary = RunSaveManager.start_new_run(slot, game_mode)
	if result["success"]:
		_close()
	else:
		_status_label.text = "Couldn't start a new run: %s" % result["reason"]
		_refresh()


func _on_load_pressed(slot: int) -> void:
	var result: Dictionary = RunSaveManager.load_from_slot(slot)
	if result["success"]:
		_close()
	else:
		_status_label.text = "Couldn't load slot %d: %s" % [slot, result["reason"]]
		_refresh()


func _on_delete_pressed(slot: int) -> void:
	_confirming_delete_slot = slot
	_refresh()


func _on_delete_cancelled() -> void:
	_confirming_delete_slot = -1
	_refresh()


func _on_delete_confirmed(slot: int) -> void:
	var result: Dictionary = RunSaveManager.delete_slot(slot)
	_confirming_delete_slot = -1
	if not result["success"]:
		_status_label.text = "Couldn't delete slot %d: %s" % [slot, result["reason"]]
	_refresh()
