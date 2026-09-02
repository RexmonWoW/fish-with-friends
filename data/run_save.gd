class_name RunSave
extends Resource

## Persisted run state (GDD Run Saves). Plain Resource, no node references
## -- same pattern PlayerStats/FishData/CaughtFish already use, so
## PlayerStats nests inside this cleanly (ResourceSaver/ResourceLoader
## handle the nested references automatically, same as CaughtFish.species
## already nesting a FishData reference).
##
## Versioned, not migrated: CURRENT_VERSION bumps whenever this shape
## changes, and RunSaveManager discards anything that doesn't match rather
## than trying to upgrade it in place. The data shape is still changing
## weekly -- migration code would be wasted work.

const CURRENT_VERSION: int = 1

@export var save_version: int = CURRENT_VERSION

@export_group("Slot Identity")
## GDD: "Solo and co-op saves never mix." Fixed the moment a slot is first
## written, never changed after -- day-1 quota (and everything that
## compounds off it) is tuned against player_count_multiplier below, so a
## solo-tuned curve dropped into a co-op session (or the reverse) would be
## meaningless, not just mildly wrong.
@export var is_coop: bool = false
@export var game_mode: StringName = &"quota"  ## GDD Game Modes -- &"quota" or &"casual"
@export var created_at_unix: int = 0
@export var last_played_unix: int = 0

@export_group("Crew State")
@export var day_number: int = 1
@export var current_quota: int = 0
@export var total_money_earned: int = 0  ## the shared pot
@export var has_fish_finder: bool = false
## GDD: "fixed at creation and does not rescale." Record-keeping only --
## the quota growth formula (RunState._end_round) is self-contained off
## current_quota/surplus and never re-reads this after day 1, but it's
## real crew-state GDD calls out explicitly, and phase 2's slot picker
## will want it for display.
@export var player_count_multiplier: float = 1.0

@export_group("Crew Roster")
## SteamID64 (int) -> PlayerStats. GDD: "a player who isn't present
## doesn't block anything, their upgrades wait here." Whoever's connected
## at save time gets their live stats written back in; whoever isn't just
## keeps whatever was already here from the last time they were around.
@export var player_stats_by_steam_id: Dictionary = {}
## SteamID64 (int) -> String. Cached purely for phase 2's slot picker
## ("who's in the crew") -- cheap to capture alongside stats, no reason to
## make that UI re-derive it from scratch later.
@export var player_names_by_steam_id: Dictionary = {}
