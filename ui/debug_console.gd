class_name DebugConsole
extends Control

## Dev-only text console for fast-forwarding through rounds/days during
## playtesting -- toggled with the backtick key. Commands only actually DO
## anything on the host (RunState is host-authoritative); a client can open
## it and type, but nothing happens, same trust model as the rest of this
## project's debug/test tooling.

var _input: LineEdit = null
var _log: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	_log = Label.new()
	_log.position = Vector2(8, -56)
	_log.add_theme_font_size_override("font_size", 14)
	add_child(_log)

	_input = LineEdit.new()
	_input.position = Vector2(8, -28)
	_input.custom_minimum_size = Vector2(440, 24)
	_input.placeholder_text = "skip_round / skip_day / set_time <seconds>"
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
		_:
			_log_line("Unknown command: %s" % parts[0])


func _log_line(text: String) -> void:
	_log.text = text
