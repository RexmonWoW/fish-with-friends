class_name LivewellDisplay
extends Control

## Proximity popup for a Livewell: shows each slot's fish stats while the
## local player is standing in a Livewell's InteractionZone, and lets them
## press 1-5 to throw that slot's fish overboard and free it up.
## GDD: proximity-based FPS look + prompt, any player can grab any fish,
## no confirmation. This does proximity only (no look/raycast targeting yet).

const ROW_HEIGHT: float = 22.0
const PANEL_WIDTH: float = 360.0
const PANEL_TOP_MARGIN: float = 60.0

var _current_livewell: Livewell = null
var _panel_bg: ColorRect = null
var _slot_labels: Array = []  # Array of Label, size Livewell.MAX_SLOTS


func _ready() -> void:
	_build_ui()
	hide()
	EventBus.livewell_proximity_changed.connect(_on_proximity_changed)
	EventBus.livewell_updated.connect(_on_livewell_updated)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)

	var panel_height := ROW_HEIGHT * (Livewell.MAX_SLOTS + 1) + 16.0

	_panel_bg = ColorRect.new()
	_panel_bg.color = Color(0.05, 0.05, 0.05, 0.75)
	_panel_bg.size = Vector2(PANEL_WIDTH, panel_height)
	_panel_bg.position = Vector2(-PANEL_WIDTH * 0.5, PANEL_TOP_MARGIN)
	_panel_bg.anchor_left = 0.5
	_panel_bg.anchor_right = 0.5
	add_child(_panel_bg)

	for i in range(Livewell.MAX_SLOTS):
		var label := Label.new()
		label.position = Vector2(12.0, 8.0 + i * ROW_HEIGHT)
		label.size = Vector2(PANEL_WIDTH - 24.0, ROW_HEIGHT)
		_panel_bg.add_child(label)
		_slot_labels.append(label)

	var hint := Label.new()
	hint.position = Vector2(12.0, 8.0 + Livewell.MAX_SLOTS * ROW_HEIGHT)
	hint.size = Vector2(PANEL_WIDTH - 24.0, ROW_HEIGHT)
	hint.modulate = Color(0.8, 0.8, 0.8)
	hint.text = "Press 1-5 to throw a fish overboard"
	_panel_bg.add_child(hint)


func _on_proximity_changed(livewell: Livewell, in_range: bool) -> void:
	if in_range:
		_current_livewell = livewell
		_refresh()
		show()
	elif livewell == _current_livewell:
		_current_livewell = null
		hide()


func _on_livewell_updated(livewell: Livewell) -> void:
	if livewell == _current_livewell:
		_refresh()


func _refresh() -> void:
	if _current_livewell == null:
		return
	for i in range(Livewell.MAX_SLOTS):
		var fish: CaughtFish = _current_livewell.slots[i]
		if fish == null:
			_slot_labels[i].text = "%d. (empty)" % (i + 1)
		else:
			_slot_labels[i].text = "%d. %s — %.1f in — $%d — caught by %s" % [
				i + 1, fish.species.display_name, fish.size, fish.final_value,
				fish.caught_by_player_name
			]


func _unhandled_input(event: InputEvent) -> void:
	if _current_livewell == null or not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	var index := (event as InputEventKey).keycode - KEY_1
	if index < 0 or index >= Livewell.MAX_SLOTS:
		return
	if _current_livewell.slots[index] != null:
		_current_livewell.request_remove_fish(index)
