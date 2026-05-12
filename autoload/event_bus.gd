extends Node

# ── Cast lifecycle ─────────────────────────────────────────────────────────────

## Emitted on all clients when a cast lands on valid water.
## Listeners: lure animator, BiteEventManager.
signal cast_landed(endpoint: Vector3, flight_seconds: float, caster_peer_id: int)

## Emitted on all clients when a cast is rejected (dry land, out of bounds, etc.)
signal cast_failed(reason: StringName, caster_peer_id: int)

# ── Bite lifecycle ─────────────────────────────────────────────────────────────

## Emitted by BiteEventManager (host only) when a fish bites.
## Minigame Logic listens to this to trigger the reel minigame.
signal bite_started(fish_data: FishData, caster_peer_id: int)

# ── Cast charge (local-only, emitted by Minigame Logic) ───────────────────────

## Emitted when the local player starts holding the cast button.
signal cast_charge_started(caster_peer_id: int)

## Emitted every frame while the local player is charging.
signal cast_charge_updated(power: float, caster_peer_id: int)
