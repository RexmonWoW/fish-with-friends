class_name ShadowWander
extends RefCounted

## Stateless helper. GDD Bite Detection: an ambient shadow wanders
## continuously around a home point -- its position is a pure function of
## (home, seed, spawn_t) evaluated against the current engine time, so
## VisualFishSpawner (host, deciding whether a shadow is close enough to
## call) and every peer's own VisualFish (rendering it) independently
## compute the exact same position with zero ongoing network traffic. Same
## "one broadcast, independently-computed replay" pattern LureAnimator's
## bobber drift and ReelFightManager's own drift already use, just over a
## bigger, slower loop meant to read as active wandering rather than a
## bobber's small idle sway.

const RADIUS: float = 6.0


static func position_at(home: Vector3, seed: float, spawn_t: float) -> Vector3:
	var elapsed := Time.get_ticks_msec() / 1000.0 - spawn_t
	return home + offset_at(seed, elapsed)


## Split out from position_at so a shadow can be re-homed to wherever it
## currently sits without a visual pop (see VisualFishSpawner.release_shadow):
## new_home = current_position - offset_at(seed, 0.0) makes offset_at(seed, 0)
## cancel out exactly at the moment spawn_t resets to "now."
static func offset_at(seed: float, elapsed: float) -> Vector3:
	var t := elapsed + seed
	var x := sin(t * 0.10) * RADIUS * 0.6 + sin(t * 0.23 + 1.7) * RADIUS * 0.4
	var z := cos(t * 0.13 + 0.4) * RADIUS * 0.6 + cos(t * 0.19) * RADIUS * 0.4
	return Vector3(x, 0.0, z)
