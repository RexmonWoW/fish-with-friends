class_name DebugConsole
extends Control

## Dev-only text console for fast-forwarding through rounds/days during
## playtesting -- toggled with the backtick key. Commands only actually DO
## anything on the host (RunState is host-authoritative); a client can open
## it and type, but nothing happens, same trust model as the rest of this
## project's debug/test tooling.

var _input: LineEdit = null
var _log: Label = null

const PANEL_SIZE: Vector2 = Vector2(560, 110)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	# Centered, with an opaque background -- a bare Label/LineEdit tucked in
	# a screen corner with no backing panel was easy to miss entirely
	# against the game behind it. PRESET_CENTER anchors every child's
	# origin to the screen's center point regardless of resolution, so the
	# math below (half the panel size) is resolution-independent.
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.05, 0.05, 0.9)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -PANEL_SIZE / 2.0
	panel.custom_minimum_size = PANEL_SIZE
	panel.size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var title := Label.new()
	title.text = "DEBUG CONSOLE"
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = -PANEL_SIZE / 2.0 + Vector2(16, 10)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	add_child(title)

	_log = Label.new()
	_log.set_anchors_preset(Control.PRESET_CENTER)
	_log.position = -PANEL_SIZE / 2.0 + Vector2(16, 36)
	_log.custom_minimum_size = Vector2(PANEL_SIZE.x - 32, 24)
	_log.add_theme_font_size_override("font_size", 16)
	_log.add_theme_color_override("font_color", Color.WHITE)
	add_child(_log)

	_input = LineEdit.new()
	_input.set_anchors_preset(Control.PRESET_CENTER)
	_input.position = -PANEL_SIZE / 2.0 + Vector2(16, 66)
	_input.custom_minimum_size = Vector2(PANEL_SIZE.x - 32, 28)
	_input.placeholder_text = "skip_round / skip_day / set_time <seconds> / add_money <amount>"
	_input.text_submitted.connect(_on_submitted)
	add_child(_input)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug_console"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	visible = not visible
	# STOP while open so typing doesn't leak through to gameplay; IGNORE
	# while closed so it never sits in the way of the FPS-look mouse motion
	# fix already applied to every other overlay in this codebase.
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	if visible:
		_input.grab_focus()
	else:
		_input.release_focus()


func _on_submitted(text: String) -> void:
	_input.clear()
	_run_command(text.strip_edges())


func _run_command(command: String) -> void:
	var parts := command.split(" ", false)
	if parts.is_empty():
		return

	match parts[0]:
		"skip_round":
			RunState.debug_skip_round()
			_log_line("Skipping round...")
		"skip_day":
			RunState.debug_skip_day()
			_log_line("Skipping to end of day...")
		"set_time":
			if parts.size() < 2 or not parts[1].is_valid_float():
				_log_line("usage: set_time <seconds>")
				return
			RunState.debug_set_time_remaining(float(parts[1]))
			_log_line("Time remaining set to %ss." % parts[1])
		"add_money":
			if parts.size() < 2 or not parts[1].is_valid_int():
				_log_line("usage: add_money <amount>")
				return
			RunState.debug_add_money(int(parts[1]))
			_log_line("Added $%s to the shared pot." % parts[1])
		_:
			_log_line("Unknown command: %s" % parts[0])


func _log_line(text: String) -> void:
	_log.text = text
