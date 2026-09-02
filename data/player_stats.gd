class_name PlayerStats
extends Resource

## Per-player run stats -- every number a Per-Run Shop upgrade would
## eventually sell, pulled out of the minigame scripts that used to hard-
## code them. This pass is groundwork only: move the numbers, wire the
## systems to read them instead, no balance changes and no shop yet
## (except the cast range default -- see below, that one's deliberate).
##
## Plain Resource, no node references or other unserializable state --
## this is also exactly what a run save will persist per Steam ID (see
## GDD Run Saves). Owned by Player (Player.stats). Rod caches its own
## reference on equip (same pattern as player_camera) since it reads
## cast range every frame while charging (the landing preview); other
## systems just look up the owning Player fresh, since they only need
## stats once per cast/reel, not every frame.

@export_group("Casting")
## GDD Casting: "default cast range is short -- 40% of the old max."
## Deliberate, not a nerf to undo -- paired with spatial rarity, rod range
## upgrades are the game's main progression axis, not a stat tweak. Was a
## flat 30.0 before this pass.
@export var max_cast_distance: float = 12.0  ## meters from rod tip

@export_group("Reel Mechanic")
## The "easiest fish" end of ReelMinigame's difficulty curve -- the "_HARD"
## end (hardest fish) stays a fixed const for now, not a stat; only named
## here because these are the four GDD called out as sellable.
@export var reel_zone_height: float = 0.28
@export var reel_zone_shrink_per_miss: float = 0.05
@export var reel_fill_rate: float = 0.35          ## progress/sec while overlapping
@export var reel_qte_window: float = 1.1          ## seconds to react to a QTE prompt

@export_group("Bite Pacing")
@export var bite_hook_window_seconds: float = 1.0   ## time to react once a shadow strikes
@export var bite_spook_pause_seconds: float = 1.5   ## pause before the next shadow search after a miss
@export var bite_call_radius_base: float = 4.0      ## starting search radius for a wandering shadow
@export var bite_call_radius_growth_per_sec: float = 12.0  ## how fast a blind cast's search radius grows
@export var bite_call_radius_max: float = 10.0      ## hard cap -- see spatial rarity, GDD Bite Detection
