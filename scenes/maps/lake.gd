class_name LakeMap
extends Map

func _init() -> void:
	map_id = &"lake"
	uses_boat = true

func _ready() -> void:
	super._ready()
	$PlayableArea/BiteEventManager.current_map_id = map_id

	var corners: Array = $PlayableArea/Boat/CapsizeCorners.get_children()
	$PlayableArea/CapsizeManager.setup(corners, $PlayableArea/Boat/Hull)

	$PlayableArea/BigFishEventManager.setup(livewell.global_position, corners)

	$PlayableArea/VisualFishSpawner.current_map_id = map_id
	$PlayableArea/VisualFishSpawner.setup(livewell.global_position)
