class_name CastMeter
extends Control

## Local power meter visualization. Reads from EventBus, doesn't drive Rod.
## Show on cast_charge_started, update on cast_charge_updated,
## hide on cast_landed or cast_failed.

var _fill: ColorRect = null


func _ready() -> void:
	_build_ui()
	hide()  # only visible while charging

	EventBus.cast_charge_started.connect(_on_charge_started)
	EventBus.cast_charge_updated.connect(_on_charge_updated)
	EventBus.cast_landed.connect(_on_cast_ended_landed)
	EventBus.cast_failed.connect(_on_cast_ended_failed)


func _build_ui() -> void:
	# Anchor to bottom-center of the screen.
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Control defaults to MOUSE_FILTER_STOP, which swallows mouse motion --
	# left unset here this (and every child below) could freeze FPS look
	# solid any time it's visible, same bug class found and fixed in
	# LivewellDisplay. IGNORE everywhere; nothing in this meter is clickable.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Container: 40 px wide, 200 px tall, centered horizontally, just above bottom edge.
	var bar_width  := 40.0
	var bar_height := 200.0
	var margin_bottom := 24.0

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
	add_child(bg)

	# Fill rect — grows upward from the bottom of the track.
	_fill = ColorRect.new()
	_fill.color = Color(1.0, 1.0, 1.0, 0.9)
	_fill.size = Vector2(bar_width, 0.0)  # starts empty
	_fill.position = Vector2(0.0, bar_height)  # anchored to bottom of bg
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_fill)


func _on_charge_started(caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	_set_fill(0.0)
	show()


func _on_charge_updated(power: float, caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	_set_fill(power)


func _on_cast_ended_landed(_endpoint: Vector3, _flight_seconds: float, caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	hide()


func _on_cast_ended_failed(_reason: StringName, caster_peer_id: int) -> void:
	if caster_peer_id != multiplayer.get_unique_id():
		return
	hide()


func _set_fill(power: float) -> void:
	if _fill == null:
		return
	var bar_height: float = _fill.get_parent().size.y
	var fill_h := bar_height * clampf(power, 0.0, 1.0)
	_fill.size = Vector2(_fill.size.x, fill_h)
	_fill.position = Vector2(0.0, bar_height - fill_h)  # grow upward
