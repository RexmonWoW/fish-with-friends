class_name CastMeter
extends Control

## Local power meter visualization. Reads from Rod, doesn't drive it.
## Listens to EventBus signals: cast_charge_started, cast_charge_updated, cast_released.

func _ready() -> void:
	hide()  # only visible when charging
