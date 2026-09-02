class_name Crosshair
extends Control

## Placeholder aiming reticle -- a small centered plus, shown once the local
## player exists (i.e. actually in a round) and hidden in the main menu.
## Purely cosmetic, doesn't drive or read Rod/camera aim at all. Real art is
## Nick's later, same convention as every other placeholder visual here.

const ARM_LENGTH: float = 6.0
const GAP: float = 2.0
const THICKNESS: float = 2.0
const COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	hide()
	resized.connect(queue_redraw)
	NetworkManager.spawned_local_player.connect(_on_local_player_spawned)


func _on_local_player_spawned(_player: Player) -> void:
	show()
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_line(center + Vector2(-GAP - ARM_LENGTH, 0.0), center + Vector2(-GAP, 0.0), COLOR, THICKNESS)
	draw_line(center + Vector2(GAP, 0.0), center + Vector2(GAP + ARM_LENGTH, 0.0), COLOR, THICKNESS)
	draw_line(center + Vector2(0.0, -GAP - ARM_LENGTH), center + Vector2(0.0, -GAP), COLOR, THICKNESS)
	draw_line(center + Vector2(0.0, GAP), center + Vector2(0.0, GAP + ARM_LENGTH), COLOR, THICKNESS)
