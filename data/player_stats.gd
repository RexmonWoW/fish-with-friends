class_name PlayerStats
extends Resource

## Per-player run stats -- every number the Per-Run Shop sells (see
## ShopCatalog/ShopCounter), pulled out of the minigame scripts that used
## to hard-code them.
##
## Plain Resource, no node references or other unserializable state --
## this is also exactly what a run save will persist per Steam ID (see
## GDD Run Saves). Owned by Player (Player.stats). Rod caches its own
## reference on equip (same pattern as player_camera) since it reads
## cast range every frame while charging (the landing preview); other
## systems just look up the owning Player fresh, since they only need
## stats once per cast/reel, not every frame.

@export_group("Casting")
## GDD Per-Run Shop: cast range's 3 tiers are 60/80/100% of this -- the
## "old max" cast range used to be a flat const on Rod, kept here as the
## reference point tiers are computed against. Not itself a stat anyone
## reads directly for gameplay -- max_cast_distance below is.
const FULL_CAST_RANGE: float = 30.0

## index = tier: 0 (default, not purchasable) through 3 (100%, maxed).
## Lives here, not on ShopCatalog, since it's what max_cast_distance below
## actually MEANS, not just a shop price detail -- ShopCatalog reads this
## table rather than keeping its own copy.
const CAST_RANGE_TIER_FRACTIONS: Array[float] = [0.4, 0.6, 0.8, 1.0]

## GDD Casting: "default cast range is short -- 40% of the old max."
## Deliberate, not a nerf to undo -- paired with spatial rarity, rod range
## upgrades are the game's main progression axis, not a stat tweak.
@export var max_cast_distance: float = 12.0  ## meters from rod tip

## GDD Per-Run Shop: how many of cast range's 3 tiers have been bought.
## max_cast_distance is kept in sync with this (see ShopCounter) rather
## than derived from it on read, so it stays a plain number every existing
## reader (Rod, ReelMinigame) can keep using without knowing tiers exist.
@export var cast_range_tier: int = 0

@export_group("Reel Mechanic")
## The "easiest fish" end of ReelMinigame's difficulty curve -- the "_HARD"
## end (hardest fish) stays a fixed const for now, not a stat; only named
## here because these are the four GDD called out as sellable.
@export var reel_zone_height: float = 0.28
@export var reel_zone_shrink_per_miss: float = 0.05
@export var reel_fill_rate: float = 0.35          ## progress/sec while overlapping
@export var reel_qte_window: float = 1.1          ## seconds to react to a QTE prompt

## GDD Per-Run Shop: "Line strength -- missed QTE shrinks the zone less" /
## "Reel upgrade -- bigger catch zone." One-time purchases, not tiered --
## ShopCatalog checks these before selling either again.
@export var line_strength_upgraded: bool = false
@export var reel_upgraded: bool = false

@export_group("Bite Pacing")
@export var bite_hook_window_seconds: float = 1.0   ## time to react once a shadow strikes
@export var bite_spook_pause_seconds: float = 1.5   ## pause before the next shadow search after a miss
@export var bite_call_radius_base: float = 4.0      ## starting search radius for a wandering shadow
@export var bite_call_radius_growth_per_sec: float = 12.0  ## how fast a blind cast's search radius grows
@export var bite_call_radius_max: float = 10.0      ## hard cap -- see spatial rarity, GDD Bite Detection

## GDD Per-Run Shop: "Bait -- fish bite faster for one round," consumable.
## How many of THIS player's remaining rounds it's still active for --
## decremented at round end (RunState._end_round), each purchase adds one
## more round rather than just resetting to 1, so buying ahead stacks.
@export var bait_rounds_remaining: int = 0
