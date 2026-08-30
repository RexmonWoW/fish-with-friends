class_name CapsizeMinigame
extends Control

## Placeholder UI for the Capsize Minigame (GDD item 10): shown to every
## player while the boat's capsized, tracks how many of the required
## corners have been claimed. Doesn't drive any game logic itself --
## CapsizeManager is host-authoritative, this just reflects its broadcasts.

var _label: Label = null
var _required: int = 0
var _claimed: int = 0


func _ready() -> void:
	_build_ui()
	hide()

	EventBus.capsize_started.connect(_on_capsize_started)
	EventBus.capsize_corner_claimed.connect(_on_corner_claimed)
	EventBus.capsize_resolved.connect(_on_capsize_resolved)


func _build_ui() -> void:
	# Keep this node's own FULL_RECT anchors from the .tscn -- self-
	# overriding them here (as this used to) collapsed the rect in a way
	# that sent the label off-screen. Anchor the label itself instead.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.add_theme_font_size_override("font_size", 26)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(420, 60)
	_label.position = Vector2(-210, 80)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _on_capsize_started(required: int) -> void:
	_required = required
	_claimed = 0
	_update_label()
	show()


func _on_corner_claimed(_corner_index: int, _peer_id: int, claimed_count: int, required: int) -> void:
	_claimed = claimed_count
	_required = required
	_update_label()


func _on_capsize_resolved() -> void:
	hide()


func _update_label() -> void:
	_label.text = "CAPSIZED! Swim to a corner and press cast to help right the boat! (%d / %d)" % [_claimed, _required]
