class_name RunEndScreen
extends Control

## GDD: "On run end: lose screen shows final score, everyone disconnects,
## click to return to main menu." Shown when RunState broadcasts a missed
## quota, or when NetworkManager reports a connection-level end (host
## disconnected, connect failed) -- same screen, different message. Doesn't
## disconnect on its own; only the button does, matching "click to return."

var _title_label: Label = null
var _body_label: Label = null
var _menu_button: Button = null


func _ready() -> void:
	_build_ui()
	hide()

	RunState.run_over.connect(_on_run_over)
	NetworkManager.run_ended.connect(_on_connection_run_ended)
	_menu_button.pressed.connect(_on_menu_button_pressed)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.75)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(-160, -90)
	vbox.custom_minimum_size = Vector2(320, 180)
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 32)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_body_label)

	_menu_button = Button.new()
	_menu_button.text = "Return to Menu"
	vbox.add_child(_menu_button)


func _on_run_over(final_day: int, final_money: int) -> void:
	_title_label.text = "Run Over"
	_body_label.text = "Missed the quota on day %d.\nFinal total: $%d." % [final_day, final_money]
	show()


func _on_connection_run_ended(reason: String) -> void:
	_title_label.text = "Disconnected"
	match reason:
		"host_disconnected":
			_body_label.text = "The host disconnected."
		"connection_failed":
			_body_label.text = "Couldn't connect."
		_:
			_body_label.text = "Connection lost."
	show()


func _on_menu_button_pressed() -> void:
	hide()
	NetworkManager.disconnect_from_lobby()
	var main_menu := get_tree().root.get_node_or_null("GameRoot/UILayer/MainMenu")
	if main_menu and main_menu.has_method("reset_and_show"):
		main_menu.call("reset_and_show")
