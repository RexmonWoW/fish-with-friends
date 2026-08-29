class_name LivewellDisplay
extends Control

## Proximity + look popup for a Livewell. Standing in a Livewell's
## InteractionZone shows a hint panel, and whichever fish is nearest the
## player's view direction shows its stats -- GDD: "proximity-based FPS look
## + prompt," not a blanket dump of all 5 slots at once. Doesn't require
## precisely tracking one specific (swimming) fish, though -- the threshold
## below is generous on purpose, so casually glancing around near the
## livewell always keeps a reasonable fish targeted instead of needing to
## fight the swim motion for pixel-perfect aim.
##
## Interaction (only one thing held at a time, same rule as everywhere else
## in EquipmentSlot): E stores whatever's currently held into the first
## empty slot; 1-5 grabs that slot's fish into your (empty) hand, ready to
## toss (Q, anywhere) or store elsewhere. No direct "throw overboard" or
## "swap in place" anymore -- replacing a bad fish is grab-then-store, two
## explicit steps, not one overwrite. No confirmation on any of it, matching
## GDD's livewell philosophy.

const ROW_HEIGHT: float = 22.0
const PANEL_WIDTH: float = 360.0
const PANEL_TOP_MARGIN: float = 60.0
## How far off dead-center a fish can be (radians) and still count as
## "looked at." Generous on purpose (most of the forward hemisphere) --
## this is just to avoid picking a fish that's technically in the
## InteractionZone but behind the player, not to demand precise aim.
const LOOK_ANGLE_THRESHOLD: float = PI / 2.0  # 90 degrees

var _current_livewell: Livewell = null
var _looked_at_index: int = -1
var _panel_bg: ColorRect = null
var _info_label: Label = null
var _hint_label: Label = null


func _ready() -> void:
	_build_ui()
	hide()
	EventBus.livewell_proximity_changed.connect(_on_proximity_changed)
	EventBus.livewell_updated.connect(_on_livewell_updated)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	# Control defaults to MOUSE_FILTER_STOP, which swallows mouse motion --
	# this panel sits near screen-center where MOUSE_MODE_CAPTURED pins the
	# (invisible) cursor, so without this every peer's FPS look froze solid
	# any time they stood near a livewell. IGNORE on every node here, not
	# just the root -- a STOP-filtered child would still eat events routed
	# to it regardless of the parent's own setting.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_height := ROW_HEIGHT * 3 + 16.0

	_panel_bg = ColorRect.new()
	_panel_bg.color = Color(0.05, 0.05, 0.05, 0.75)
	_panel_bg.size = Vector2(PANEL_WIDTH, panel_height)
	_panel_bg.position = Vector2(-PANEL_WIDTH * 0.5, PANEL_TOP_MARGIN)
	_panel_bg.anchor_left = 0.5
	_panel_bg.anchor_right = 0.5
	_panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_bg)

	_info_label = Label.new()
	_info_label.position = Vector2(12.0, 8.0)
	_info_label.size = Vector2(PANEL_WIDTH - 24.0, ROW_HEIGHT * 2)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_bg.add_child(_info_label)

	_hint_label = Label.new()
	_hint_label.position = Vector2(12.0, 8.0 + ROW_HEIGHT * 2)
	_hint_label.size = Vector2(PANEL_WIDTH - 24.0, ROW_HEIGHT)
	_hint_label.modulate = Color(0.8, 0.8, 0.8)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_bg.add_child(_hint_label)


func _process(_delta: float) -> void:
	if _current_livewell == null:
		return
	_update_look_target()
	_update_hint()


func _on_proximity_changed(livewell: Livewell, in_range: bool) -> void:
	if in_range:
		_current_livewell = livewell
		show()
	elif livewell == _current_livewell:
		_current_livewell = null
		_looked_at_index = -1
		hide()


func _on_livewell_updated(livewell: Livewell) -> void:
	if livewell == _current_livewell:
		_refresh_info()


## Picks whichever occupied slot's (moving) fish is closest to dead-center
## of the local player's view, within LOOK_ANGLE_THRESHOLD. No real
## collision/raycast needed -- these are small placeholder visuals and the
## player's already proximity-gated into the InteractionZone to get here.
func _update_look_target() -> void:
	var local_player := _get_local_player()
	var new_index := -1

	if local_player != null:
		var cam: Camera3D = local_player.camera
		var cam_origin := cam.global_transform.origin
		var cam_forward := -cam.global_transform.basis.z

		var best_angle := LOOK_ANGLE_THRESHOLD
		for i in range(Livewell.MAX_SLOTS):
			if _current_livewell.slots[i] == null:
				continue
			var visual_pos: Variant = _current_livewell.get_visual_global_position(i)
			if visual_pos == null:
				continue
			var to_fish: Vector3 = (visual_pos as Vector3) - cam_origin
			if to_fish.length_squared() < 0.0001:
				continue
			var angle := cam_forward.angle_to(to_fish.normalized())
			if angle < best_angle:
				best_angle = angle
				new_index = i

	if new_index != _looked_at_index:
		_looked_at_index = new_index
		_refresh_info()


func _refresh_info() -> void:
	if _looked_at_index < 0:
		_info_label.text = "Look at a fish to see its details."
		return
	var fish: CaughtFish = _current_livewell.slots[_looked_at_index]
	if fish == null:
		_info_label.text = "Look at a fish to see its details."
		_looked_at_index = -1
		return
	_info_label.text = "%d. %s — %.1f in — $%d — caught by %s" % [
		_looked_at_index + 1, fish.species.display_name, fish.size, fish.final_value,
		fish.caught_by_player_name
	]


func _update_hint() -> void:
	var slot := _local_equipment_slot()
	if slot != null and slot.has_fish_held():
		_hint_label.text = "Holding a fish — press E to store it"
	else:
		_hint_label.text = "Press 1-5 to grab a fish (Q to toss, E to put back)"


func _unhandled_input(event: InputEvent) -> void:
	if _current_livewell == null or not visible:
		return

	var slot := _local_equipment_slot()

	if event.is_action_pressed(&"store_fish"):
		if slot != null and slot.has_fish_held():
			slot.request_store_held_fish()
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var index := (event as InputEventKey).keycode - KEY_1
	if index < 0 or index >= Livewell.MAX_SLOTS:
		return
	if slot != null and not slot.has_fish_held() and _current_livewell.slots[index] != null:
		slot.request_grab_from_livewell(index)


func _get_local_player() -> Player:
	return NetworkManager.spawned_players.get(multiplayer.get_unique_id())


func _local_equipment_slot() -> EquipmentSlot:
	var player := _get_local_player()
	if player == null:
		return null
	return player.equipment_slot
