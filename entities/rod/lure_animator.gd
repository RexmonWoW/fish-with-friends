class_name LureAnimator
extends Node3D

## Animates the lure through a parabolic arc from rod tip to landing point.
## Visual-only. Authority is the local rod node spawning this on receipt of _cast_landed RPC.

func play_arc(start_pos: Vector3, end_pos: Vector3, duration: float) -> void:
	# Tween parabolically. On finish, emit `lure_landed` signal.
	pass

signal lure_landed
