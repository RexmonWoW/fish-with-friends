class_name FishData
extends Resource

## Species template. Defines what a species IS.
## Authored as .tres files in res://data/fish/species/
## To add a new fish: right-click in that folder → New Resource → FishData.

@export var species_id: StringName        ## Internal ID, e.g. &"largemouth_bass". Must be unique.
@export var display_name: String          ## Player-facing, e.g. "Largemouth Bass"

@export_group("Size & Weight")
@export var min_size: float = 1.0         ## inches or whatever unit, your call
@export var max_size: float = 10.0
@export var min_weight: float = 0.5       ## pounds
@export var max_weight: float = 5.0

@export_group("Economy")
@export var base_value: int = 10          ## money before catch-time multipliers
@export_enum("Common", "Uncommon", "Rare", "Legendary", "Mythic") var rarity: int = 0

@export_group("Spawn Rules")
@export var valid_locations: Array[StringName] = []  ## e.g. [&"lake", &"swamp"] — controls where this species can spawn
@export_range(0.0, 1.0, 0.01) var spawn_weight: float = 1.0  ## relative spawn frequency within its rarity tier

@export_group("Visuals")
@export var model_scene: PackedScene      ## 3D model used in livewell display + catch animation
@export var icon: Texture2D               ## for HUD / inventory


func roll_size() -> float:
	return randf_range(min_size, max_size)


func roll_weight() -> float:
	return randf_range(min_weight, max_weight)
