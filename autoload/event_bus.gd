extends Node

# ── Cast signals ───────────────────────────────────────────────────────────────

## Emitted locally when the rod owner starts charging a cast.
## Listeners: power meter UI (Art & Polish).
signal cast_charge_started(caster_peer_id: int)

## Emitted locally every frame while charging, with current power 0.0-1.0.
## Listeners: power meter UI (Art & Polish).
signal cast_charge_updated(power: float, caster_peer_id: int)

## Emitted on all peers when a cast lands in valid water.
## Listeners: lure animator (Art & Polish), BiteEventManager (host-only).
signal cast_landed(endpoint: Vector3, flight_seconds: float, caster_peer_id: int)

## Emitted on all peers when a cast is rejected by the host (dry land, out of range).
## Listeners: power meter UI reset (Minigame Logic / Art & Polish).
signal cast_failed(reason: StringName, caster_peer_id: int)

## Emitted on all peers when a fish bites a cast line.
## Listeners: reel minigame trigger (Minigame Logic).
signal bite_started(fish_data: FishData, caster_peer_id: int)

## Emitted host-side once BiteEventManager has despawned the fish for a
## resolved reel (caught or escaped). Informational -- Rod already resets
## itself to IDLE optimistically on the owning client.
signal reel_finished(success: bool, caster_peer_id: int)

# ── Livewell signals ───────────────────────────────────────────────────────────

## Emitted host-side whenever a Livewell's slots change (add or remove).
## Listeners: LivewellDisplay UI.
signal livewell_updated(livewell: Livewell)

## Emitted locally (per-peer, not networked) when the LOCAL player enters or
## exits a Livewell's InteractionZone. Listeners: LivewellDisplay UI.
signal livewell_proximity_changed(livewell: Livewell, in_range: bool)
