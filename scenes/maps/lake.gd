class_name LakeMap
extends Map

func _init() -> void:
	map_id = &"lake"
	uses_boat = true

func _ready() -> void:
	super._ready()
	$PlayableArea/BiteEventManager.current_map_id = map_id
