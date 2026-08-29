extends Node

## Headless check for "camera locks up near the livewell" (and, by the same
## root cause, every other always-present UI overlay): Control defaults to
## MOUSE_FILTER_STOP, which swallows InputEventMouseMotion before it ever
## reaches Player._unhandled_input's FPS look code. LivewellDisplay's panel
## (a ColorRect, STOP by default) sat right where MOUSE_MODE_CAPTURED pins
## the cursor, silently freezing camera look any time a player stood near a
## livewell.
##
## A full input-simulation test (send a real InputEventMouseMotion, check
## the camera turned) was attempted first but proved unreliable in this
## --headless environment -- even a baseline motion event with no UI in the
## way never reached the camera, so a "camera didn't turn" result here
## can't be trusted to mean what it looks like it means. Verifies the
## actual mechanism instead: walks every UI overlay's live Control tree and
## confirms nothing defaults to MOUSE_FILTER_STOP, which is the property
## that actually causes the swallowing.

const OVERLAY_PATHS: Array[String] = [
	"GameRoot/UILayer/CastMeter",
	"GameRoot/UILayer/ReelMinigame",
	"GameRoot/UILayer/LivewellDisplay",
	"GameRoot/UILayer/TangleMinigame",
	"GameRoot/UILayer/RoundHud",
	"GameRoot/UILayer/CapsizeMinigame",
]


func _ready() -> void:
	print("--- Livewell/UI mouse-lock test ---")

	var game_root: Node = preload("res://scenes/root/game_root.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game_root)
	await get_tree().process_frame
	await get_tree().process_frame

	var any_bad := false
	for path in OVERLAY_PATHS:
		var root_node: Node = get_tree().root.get_node_or_null(path)
		if root_node == null:
			print("FAIL: %s not found" % path)
			any_bad = true
			continue
		var offenders: Array[String] = []
		_check_no_stop_filter(root_node as Control, path, offenders)
		if offenders.is_empty():
			print("OK   %s -- no STOP-filtered controls" % path)
		else:
			print("FAIL %s -- STOP-filtered controls found: %s" % [path, offenders])
			any_bad = true

	if any_bad:
		get_tree().quit(1)
		return

	print("--- Livewell/UI mouse-lock test PASSED ---")
	get_tree().quit()


## Recurses the Control tree under `node`, collecting the full path of any
## Control still on MOUSE_FILTER_STOP (the default that swallows mouse
## motion) into `offenders`.
func _check_no_stop_filter(node: Control, path: String, offenders: Array[String]) -> void:
	if node.mouse_filter == Control.MOUSE_FILTER_STOP:
		offenders.append(path)
	for child in node.get_children():
		if child is Control:
			_check_no_stop_filter(child as Control, path + "/" + child.name, offenders)
