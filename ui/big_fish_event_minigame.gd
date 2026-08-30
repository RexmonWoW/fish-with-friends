class_name BigFishEventMinigame
extends Control

## Placeholder UI for the Big Fish Event (GDD item 9). Shows a ready-check
## banner ("cast at the shaking spot!"), then, once active, one bar per
## participant with their name underneath -- visible to EVERYONE, not just
## participants, per GDD. Doesn't drive any game logic; BigFishEventManager
## is host-authoritative, this only reflects its broadcasts and reports the
## LOCAL participant's own hold/QTE input back to it.

const BAR_WIDTH: float = 40.0
const BAR_HEIGHT: float = 160.0
const BAR_SPACING: float = 70.0

## Same key/label table as ReelMinigame's QTE_PROMPTS, indexed the same way
## BigFishEventManager broadcasts qte_prompt -- kept in sync manually since
## each minigame owns its own UI constants independently (no shared base).
const QTE_PROMPTS: Array[Dictionary] = [
	{"keys": [KEY_SPACE], "label": "SPACE"},
	{"keys": [KEY_UP, KEY_W], "label": "W"},
	{"keys": [KEY_DOWN, KEY_S], "label": "S"},
	{"keys": [KEY_LEFT, KEY_A], "label": "A"},
	{"keys": [KEY_RIGHT, KEY_D], "label": "D"},
]

var _banner_label: Label = null
var _bars_root: Control = null
var _bar_nodes: Dictionary = {}  ## peer_id -> {bg, fill, name_label, qte_label}

var _is_local_participant: bool = false
var _local_qte_prompt: int = -1
var _banner_timer: float = 0.0

## World-space marker at the ready-check spot -- the banner alone gave no
## way to actually FIND "the disturbance" it kept telling players to cast
## at. Not parented under this Control (a 2D UI node); lives directly in
## the 3D scene, tracked here just so this script can spawn/despawn it in
## step with the same broadcasts it already reacts to.
var _marker: Node3D = null
var _marker_mesh: MeshInstance3D = null
var _marker_base_position: Vector3 = Vector3.ZERO
var _marker_time: float = 0.0


func _ready() -> void:
	_build_ui()
	hide()
	EventBus.big_fish_ready_check_started.connect(_on_ready_check_started)
	EventBus.big_fish_participant_joined.connect(_on_participant_joined)
	EventBus.big_fish_event_fizzled.connect(_on_fizzled)
	EventBus.big_fish_event_active.connect(_on_event_active)
	EventBus.big_fish_state_updated.connect(_on_state_updated)
	EventBus.big_fish_event_resolved.connect(_on_event_resolved)
	# Safety net: this UI (and its world marker) should never legitimately
	# outlive the round it started in -- if it somehow does, a round
	# boundary is the one signal guaranteed to still fire and clean it up.
	RunState.round_ended.connect(_on_round_boundary)


func _on_round_boundary(_round_number: int, _day_number: int) -> void:
	_is_local_participant = false
	_local_qte_prompt = -1
	_clear_bars()
	_clear_marker()
	hide()


func _build_ui() -> void:
	# Keep this node's own FULL_RECT anchors from the .tscn -- self-
	# overriding them here (as this used to, and as CapsizeMinigame did
	# until it sent that panel's label off-screen) risks collapsing the
	# rect children anchor themselves against. Children anchor themselves
	# directly below.
	#
	# Control defaults to MOUSE_FILTER_STOP -- see LivewellDisplay/CastMeter/
	# ReelMinigame/TangleMinigame, same fix needed everywhere a panel might
	# sit over the captured cursor.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_banner_label = Label.new()
	_banner_label.add_theme_font_size_override("font_size", 24)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_label.position = Vector2(-260.0, 120.0)
	_banner_label.custom_minimum_size = Vector2(520.0, 60.0)
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label.hide()
	add_child(_banner_label)

	_bars_root = Control.new()
	_bars_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bars_root.position = Vector2(-300.0, 190.0)
	_bars_root.custom_minimum_size = Vector2(600.0, BAR_HEIGHT + 40.0)
	_bars_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bars_root)


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner_label.hide()

	if _marker_mesh != null:
		_marker_time += delta
		var pulse := 1.0 + sin(_marker_time * 3.0) * 0.25
		_marker_mesh.scale = Vector3(pulse, 1.0, pulse)
		var bob := sin(_marker_time * 2.0) * 0.08
		_marker.global_position = _marker_base_position + Vector3(0.0, bob, 0.0)

	if not _is_local_participant:
		return

	if Input.is_action_just_pressed(&"cast"):
		_report_holding(true)
	if Input.is_action_just_released(&"cast"):
		_report_holding(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_participant or _local_qte_prompt < 0:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var prompt: Dictionary = QTE_PROMPTS[_local_qte_prompt]
	if (event as InputEventKey).keycode in prompt["keys"]:
		_local_qte_prompt = -1
		var mgr := _get_manager()
		if mgr:
			mgr.report_qte_hit()


func _report_holding(is_holding: bool) -> void:
	var mgr := _get_manager()
	if mgr:
		mgr.report_holding(is_holding)


func _get_manager() -> Node:
	return get_tree().get_first_node_in_group("big_fish_event_manager")


# ── EventBus reactions ───────────────────────────────────────────────────────────

func _on_ready_check_started(target_spot: Vector3, duration: float) -> void:
	_is_local_participant = false
	_clear_bars()
	show()
	_show_banner("A BIG FISH IS OUT THERE! Cast at the disturbance to join in!", duration)
	_spawn_marker(target_spot)


func _on_participant_joined(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_is_local_participant = true
	_show_banner("%s is in!" % SteamManager.get_display_name_for_peer(peer_id), 2.0)


func _on_fizzled() -> void:
	_show_banner("Nobody joined in time -- the big fish got away.", 4.0)
	_is_local_participant = false
	_clear_marker()
	await get_tree().create_timer(4.0).timeout
	if not visible:
		return
	hide()


func _on_event_active(participant_ids: Array, _duration: float) -> void:
	_banner_label.hide()
	_clear_bars()
	_clear_marker()
	for peer_id in participant_ids:
		_add_bar(peer_id)


func _on_state_updated(participants: Dictionary) -> void:
	var my_id := multiplayer.get_unique_id()
	for peer_id in participants.keys():
		var p: Dictionary = participants[peer_id]
		_update_bar(peer_id, p)
		if peer_id == my_id:
			_local_qte_prompt = p["qte_prompt"] if not p["locked_in"] else -1


func _on_event_resolved(success: bool) -> void:
	_is_local_participant = false
	_local_qte_prompt = -1
	_clear_marker()  # safety net -- should already be cleared once active started
	if success:
		_show_banner("CAUGHT IT! Big fish is in the livewell.", 5.0)
	else:
		_show_banner("Time's up -- the boat capsizes!", 5.0)
	await get_tree().create_timer(5.0).timeout
	if not visible:
		return
	hide()
	_clear_bars()


# ── Bars ─────────────────────────────────────────────────────────────────────────

func _add_bar(peer_id: int) -> void:
	if _bar_nodes.has(peer_id):
		return

	var index := _bar_nodes.size()
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.7)
	bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bg.position = Vector2(index * BAR_SPACING, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars_root.add_child(bg)

	var fill := ColorRect.new()
	fill.color = Color(0.9, 0.75, 0.1, 0.9)
	fill.size = Vector2(BAR_WIDTH, 0.0)
	fill.position = Vector2(0.0, BAR_HEIGHT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)

	var name_label := Label.new()
	name_label.text = SteamManager.get_display_name_for_peer(peer_id)
	name_label.position = Vector2(-10.0, BAR_HEIGHT + 4.0)
	name_label.custom_minimum_size = Vector2(BAR_WIDTH + 20.0, 20.0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(name_label)

	var qte_label := Label.new()
	qte_label.text = "!"
	qte_label.add_theme_font_size_override("font_size", 22)
	qte_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	qte_label.position = Vector2(0.0, -28.0)
	qte_label.custom_minimum_size = Vector2(BAR_WIDTH, 24.0)
	qte_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qte_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qte_label.hide()
	bg.add_child(qte_label)

	_bar_nodes[peer_id] = {"bg": bg, "fill": fill, "name_label": name_label, "qte_label": qte_label}


func _update_bar(peer_id: int, p: Dictionary) -> void:
	if not _bar_nodes.has(peer_id):
		_add_bar(peer_id)
	var nodes: Dictionary = _bar_nodes[peer_id]

	var fill: ColorRect = nodes["fill"]
	var pos: float = p["pos"]
	var fill_h := BAR_HEIGHT * pos
	fill.size = Vector2(BAR_WIDTH, fill_h)
	fill.position = Vector2(0.0, BAR_HEIGHT - fill_h)
	fill.color = Color(0.3, 0.9, 0.3, 0.9) if p["locked_in"] else Color(0.9, 0.75, 0.1, 0.9)

	var qte_label: Label = nodes["qte_label"]
	if p["qte_active"] and not p["locked_in"]:
		qte_label.show()
	else:
		qte_label.hide()


# ── Ready-check world marker ─────────────────────────────────────────────────────
## Placeholder "something's disturbing the water" marker -- a pulsing ring,
## simple/swappable like every other placeholder visual in this codebase
## (bobber, rod, livewell fish). Real splash/disturbance VFX is Art &
## Polish's.

func _spawn_marker(pos: Vector3) -> void:
	_clear_marker()
	_marker_base_position = pos
	_marker = Node3D.new()
	_marker.add_to_group("big_fish_disturbance_marker")  ## lookup for tests
	get_tree().root.add_child(_marker)
	_marker.global_position = pos

	_marker_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.85
	_marker_mesh.mesh = torus

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.85, 0.2, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(1.0, 0.7, 0.1)
	material.emission_energy_multiplier = 1.5
	_marker_mesh.set_surface_override_material(0, material)

	_marker.add_child(_marker_mesh)
	_marker_time = 0.0


func _clear_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	_marker_mesh = null


func _clear_bars() -> void:
	for nodes in _bar_nodes.values():
		var bg: ColorRect = nodes["bg"]
		if is_instance_valid(bg):
			bg.queue_free()
	_bar_nodes.clear()


func _show_banner(text: String, duration: float) -> void:
	_banner_label.text = text
	_banner_label.show()
	_banner_timer = duration
