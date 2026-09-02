class_name ShopCatalog
extends RefCounted

## Stateless. Single source of truth for the Per-Run Shop's v1 item list
## (GDD Per-Run Shop) -- both ShopCounter's host-side purchase validation
## and the client-side ShopDisplay UI read prices/eligibility from here, so
## a displayed price can never disagree with what a real purchase actually
## costs. Only pricing/metadata/eligibility live here; ShopCounter owns
## actually APPLYING a purchase's effect once it's validated one against
## this catalog.
##
## Prices are placeholders (GDD: "tune so day 1's surplus buys roughly one
## thing, not three") -- see PROGRESS.md's tunables list.

enum Target { PLAYER, CREW }

## Order here is display order in the shop UI.
const ITEMS: Array[StringName] = [
	&"cast_range", &"line_strength", &"reel_upgrade", &"bait", &"fish_finder",
]

## Price to go FROM tier N TO tier N+1 -- index 0 is the price of the
## FIRST purchasable tier (tier 1, 60%), matching PlayerStats.
## CAST_RANGE_TIER_FRACTIONS' indices 1..3.
const CAST_RANGE_TIER_PRICES: Array[int] = [60, 90, 130]

const LINE_STRENGTH_PRICE: int = 50
## GDD: "missed QTE shrinks the zone less" -- halves reel_zone_shrink_per_miss.
const LINE_STRENGTH_SHRINK_MULTIPLIER: float = 0.5

const REEL_UPGRADE_PRICE: int = 50
## GDD: "bigger catch zone" -- flat bonus added to reel_zone_height (was
## 0.28 default, so roughly +29% at the easy end of the difficulty curve).
const REEL_UPGRADE_ZONE_HEIGHT_BONUS: float = 0.08

const BAIT_PRICE: int = 20
const BAIT_ROUNDS_PER_PURCHASE: int = 1

const FISH_FINDER_PRICE: int = 150


static func target_for(item_id: StringName) -> Target:
	return Target.CREW if item_id == &"fish_finder" else Target.PLAYER


static func display_name(item_id: StringName) -> String:
	match item_id:
		&"cast_range": return "Cast Range"
		&"line_strength": return "Line Strength"
		&"reel_upgrade": return "Reel Upgrade"
		&"bait": return "Bait"
		&"fish_finder": return "Fish Finder"
	return "???"


static func description(item_id: StringName) -> String:
	match item_id:
		&"cast_range": return "Reach further out -- the good fish are out deep."
		&"line_strength": return "A missed QTE costs less catch-zone."
		&"reel_upgrade": return "A bigger catch zone to work with."
		&"bait": return "Fish bite faster, for one round. Consumable."
		&"fish_finder": return "Crew-wide. Fish spawn closer, bite faster."
	return ""


## Price for the NEXT purchase of this item given the target's CURRENT
## state -- null if it can't be bought right now (maxed out, already
## owned). stats is the target PLAYER's PlayerStats; ignored for crew-wide
## items (pass null).
static func get_price(item_id: StringName, stats: PlayerStats) -> Variant:
	match item_id:
		&"cast_range":
			var tier: int = stats.cast_range_tier
			if tier >= CAST_RANGE_TIER_PRICES.size():
				return null  # already maxed at tier 3 (100%)
			return CAST_RANGE_TIER_PRICES[tier]
		&"line_strength":
			return null if stats.line_strength_upgraded else LINE_STRENGTH_PRICE
		&"reel_upgrade":
			return null if stats.reel_upgraded else REEL_UPGRADE_PRICE
		&"bait":
			return BAIT_PRICE  # always buyable -- stacks, no cap
		&"fish_finder":
			return null if RunState.has_fish_finder else FISH_FINDER_PRICE
	return null


## Short status string for the UI when an item can't be bought right now
## (get_price returned null) -- distinguishes "maxed" from "owned" so the
## crew isn't left guessing why a button's gone.
static func unavailable_reason(item_id: StringName, stats: PlayerStats) -> String:
	match item_id:
		&"cast_range":
			return "MAXED"
		&"line_strength", &"reel_upgrade":
			return "OWNED"
		&"fish_finder":
			return "OWNED"
	return ""
