class_name CastMeter
extends Control

## Local power meter visualization. Reads from EventBus, doesn't drive Rod.
## Show on cast_charge_started, update on cast_charge_updated,
## hide on cast_landed or cast_failed.
##
## This root Control stays visible the whole time (never hidden) -- the
## fill bar and the cancel hint each have their own independent visibility
## below it, since the hint needs to stay up through the whole waiting-for-
## a-bite window, well after the fill bar (charge-only) has hidden.

var _bar_container: Control = null
var _fill: ColorRect = null
var _cancel_hint: Label = null
var _hook_prompt: Label = null
var _local_rod: Rod = null  ## cached once found -- same node survives stow/re-equip cycles


func _ready() -> void:
	_build_ui()

	EventBus.cast_charge_started.connect(_on_charge_started)
	EventBus.cast_charge_updated.connect(_on_charge_updated)
	EventBus.cast_landed.connect(_on_cast_ended_landed)
	EventBus.cast_failed.connect(_on_cast_ended_failed)
	EventBus.bite_hook_window_opened.connect(_on_hook_window_opened)
	EventBus.bite_hook_window_missed.connect(_on_hook_window_closed)
	EventBus.bite_started.connect(_on_bite_started)


## Right-click cancels a charging or waiting cast (Rod.request_cancel_cast)
## -- otherwise there'd be no way to know that exists. Polls the local
## rod's state directly rather than wiring more EventBus signals, so it
## stays correct through charging AND the whole waiting-for-a-bite window.
func _process(_delta: float) -> void:
	if _local_rod == null:
		var player: Player = NetworkManager.spawned_players.get(multiplayer.get_unique_id())
		if player == null:
			return
		_local_rod = player.equipment_slot.equipped_item as Rod
		if _local_rod == null:
			return
	_cancel_hint.visible = (
		_local_rod.state == Rod.CastState.CHARGING or _local_rod.state == Rod.CastState.WAITING_BITE
	)


func _build_ui() -> void:
	# Keep this node's own FULL_RECT anchors from the .tscn -- self-
	# overriding them here (as this used to, and as other UI panels did
	# until it sent a label off-screen) risks collapsing the rect children
	# anchor themselves against. _bar_container gets its own FULL_RECT
	# below so bg's percentage anchors resolve against the real screen.
	#
	# Control defaults to MOUSE_FILTER_STOP, which swallows mouse motion --
	# left unset here this (and every child below) could freeze FPS look
	# solid any time it's visible, same bug class found and fixed in
	# LivewellDisplay. IGNORE everywhere; nothing in this meter is clickable.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Container: 40 px wide, 200 px tall, centered horizontally, just above bottom edge.
	var bar_width  := 40.0
	var bar_height := 200.0
	var margin_bottom := 24.0

	_bar_container = Control.new()
	_bar_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_container.hide()  # only visible while charging
	add_child(_bar_container)

	# Background track.
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.7)
	bg.size = Vector2(bar_width, bar_height)
	bg.position = Vector2(-bar_width * 0.5, -bar_height - margin_bottom)
	bg.anchor_left   = 0.5
	bg.anchor_right  = 0.5
	bg.anchor_top    = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_container.add_child(bg)

	# Fill rect — grows upward from the bottom of the track.
	_fill = ColorRect.new()
	_fill.color = Color(1.0, 1.0, 1.0, 0.9)
	_fill.size = Vector2(bar_width, 0.0)  # starts empty
	_fill.position = Vector2(0.0, bar_height)  # anchored to bottom of bg
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_fill)

	_cancel_hint = Label.new()
	_cancel_hint.text = "Right-click to cancel"
	_cancel_hint.add_theme_font_size_override("font_size", 14)
	_cancel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cancel_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cancel_hint.position = Vector2(-100.0, -margin_bottom - bar_height - 26.0)
	_cancel_hint.custom_minimum_size = Vector2(200.0, 20.0)
	_cancel_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cancel_hint.hide()
	add_child(_cancel_hint)

	# GDD Bite Detection: "press to set the hook in a short window" -- big
	# and centered since this is the one thing the player has to react to
	# fast, unlike the passive charge bar/cancel hint.
	_hook_prompt = Label.new()
	_hook_prompt.text = "SET THE HOOK! (click)"
	_hook_prompt.add_theme_font_size_override("font_size", 32)
	_hook_prompt.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_hook_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hook_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_hook_prompt.position = Vector2(-200.0, -60.0)
	_hook_prompt.custom_minimum_size = Vector2(400.0, 50.0)
	_hook_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hook_prompt.hide()
	add_child(_hook_prompt)


func _on_charge_started(caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	_set_fill(0.0)
	_bar_container.show()


func _on_charge_updated(power: float, caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	_set_fill(power)


func _on_cast_ended_landed(_endpoint: Vector3, _flight_seconds: float, caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	_bar_container.hide()


func _on_cast_ended_failed(_reason: StringName, caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	_bar_container.hide()


func _on_hook_window_opened(caster_peer_id: int, _duration: float) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	_hook_prompt.show()


func _on_hook_window_closed(caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	_hook_prompt.hide()


func _on_bite_started(_fish_data: FishData, caster_peer_id: int) -> void:
	_on_hook_window_closed(caster_peer_id)


func _set_fill(power: float) -> void:
	if _fill == null:
		return
	var bar_height: float = _fill.get_parent().size.y
	var fill_h := bar_height * clampf(power, 0.0, 1.0)
	_fill.size = Vector2(_fill.size.x, fill_h)
	_fill.position = Vector2(0.0, bar_height - fill_h)  # grow upward
