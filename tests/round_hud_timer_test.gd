extends Node

## Headless check for a regression this session already caused once:
## RoundHud._process() briefly force-hid the timer if
## NetworkManager.get_current_map() was null, meant as a safety net against
## a dropped round_ended RPC. But round_started (which starts the
## countdown) is a broadcast that can reach a CLIENT before that client's
## OWN local map load has finished -- a completely normal race in this
## architecture, not a dropped packet -- so the very next frame the
## "safety net" immediately hid the timer again and never showed it for
## the rest of the round ("client can't see timer"). Confirms the
## countdown survives a _process() tick while the map isn't loaded yet.

func _ready() -> void:
	print("--- Round HUD timer test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	var round_hud := get_tree().root.get_node("GameRoot/UILayer/RoundHud")

	if NetworkManager.get_current_map() != null:
		print("FAIL: test setup problem -- expected no map loaded yet")
		get_tree().quit(1)
		return

	# Simulate round_started arriving before the local map finishes loading.
	round_hud._on_round_started(1, 1, 300.0)
	round_hud._process(0.1)
	round_hud._process(0.1)

	if not round_hud.get("_counting_down"):
		print("FAIL: timer stopped counting down just because the map wasn't loaded yet -- this is the 'client can't see timer' bug")
		get_tree().quit(1)
		return
	var timer_label: Label = round_hud.get("_timer_label")
	if not timer_label.visible:
		print("FAIL: timer label got hidden just because the map wasn't loaded yet")
		get_tree().quit(1)
		return
	print("Timer kept counting down and stayed visible while the map hadn't loaded yet.")

	print("--- Round HUD timer test PASSED ---")
	get_tree().quit()
