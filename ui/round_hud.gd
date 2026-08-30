class_name RoundHud
extends Control

## Placeholder round/day HUD -- a 5-min countdown while a round's active,
## a running money/quota readout, and a brief pass/fail message whenever a
## round or day wraps up. Real Art & Polish treatment (a real timer graphic,
## a proper day-transition screen) is a future dispatch, same convention as
## CastMeter/LivewellDisplay. Reads RunState directly rather than driving it.

var _timer_label: Label = null
var _money_label: Label = null
var _summary_label: Label = null

var _time_remaining: float = 0.0
var _counting_down: bool = false
var _summary_timer: float = 0.0


func _ready() -> void:
	_build_ui()
	_timer_label.hide()
	_summary_label.hide()

	RunState.round_started.connect(_on_round_started)
	RunState.round_ended.connect(_on_round_ended)
	RunState.round_sold.connect(_on_round_sold)
	RunState.day_summary.connect(_on_day_summary)
	# Livewell contents count toward quota progress before they're actually
	# sold at day end (see RunState.get_projected_total) -- refresh the
	# readout live as fish are caught/thrown overboard, not just at
	# round/day boundaries, or the display sits flat all day and progress
	# is invisible until it suddenly jumps at the end.
	EventBus.livewell_updated.connect(_on_livewell_updated)

	_update_money_label()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 28)
	_timer_label.position = Vector2(16, 8)
	add_child(_timer_label)

	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 18)
	_money_label.position = Vector2(16, 48)
	add_child(_money_label)

	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 22)
	_summary_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_summary_label.position = Vector2(-220, 80)
	_summary_label.custom_minimum_size = Vector2(440, 60)
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_summary_label)


func _process(delta: float) -> void:
	if _counting_down:
		_time_remaining = maxf(_time_remaining - delta, 0.0)
		_update_timer_label()

	if _summary_timer > 0.0:
		_summary_timer -= delta
		if _summary_timer <= 0.0:
			_summary_label.hide()


func _on_round_started(_round_number: int, _day_number: int, duration_seconds: float) -> void:
	_time_remaining = duration_seconds
	_counting_down = true
	_timer_label.show()
	_update_timer_label()
	_update_money_label()


## Fires for EVERY round. Doesn't show a message itself -- a mid-day round
## is followed by _on_round_sold, and the last round of a day by
## _on_day_summary, each owning the message for its own case.
func _on_round_ended(_round_number: int, _day_number: int) -> void:
	_counting_down = false
	_timer_label.hide()


## Mid-day round end (round 1 -> round 2): the catch already sold and
## banked, same as heading back to shore between trips.
func _on_round_sold(round_number: int, _day_number: int, earned: int, total: int) -> void:
	_update_money_label()
	_show_summary("Round %d complete — sold $%d (total $%d). Head back out for round %d!" %
		[round_number, earned, total, round_number + 1])


func _on_day_summary(day_number: int, earned: int, total: int, quota: int, passed: bool) -> void:
	_update_money_label()
	if passed:
		_show_summary("Day %d complete! Earned $%d (total $%d) — quota $%d met. Day %d starting." %
			[day_number, earned, total, quota, day_number + 1])
	else:
		_show_summary("Day %d complete. Earned $%d (total $%d) — quota $%d NOT met." %
			[day_number, earned, total, quota])


func _update_timer_label() -> void:
	var total_seconds := int(ceil(_time_remaining))
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	_timer_label.text = "%d:%02d" % [minutes, seconds]


func _on_livewell_updated(_livewell: Livewell) -> void:
	_update_money_label()


func _update_money_label() -> void:
	var livewell_value := RunState.get_livewell_value()
	var projected := RunState.total_money_earned + livewell_value
	_money_label.text = "$%d / $%d quota ($%d in livewell)" % [projected, RunState.current_quota, livewell_value]


func _show_summary(text: String) -> void:
	_summary_label.text = text
	_summary_label.show()
	_summary_timer = 5.0
