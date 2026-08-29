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

# ── Line tangling signals ───────────────────────────────────────────────────────
## Host-authoritative (TangleManager), broadcast to every peer.

## Two different players' lines crossed while both were WAITING_BITE.
signal tangle_started(peer_a: int, peer_b: int)

## Tug-of-war rope moved (mash from either side). Positive favors peer_a.
signal tangle_rope_updated(peer_a: int, peer_b: int, rope: float)

## Tangle resolved -- winner keeps their cast (no state change needed),
## loser's line snaps (Rod listens and resets itself to IDLE).
signal tangle_resolved(winner_peer_id: int, loser_peer_id: int)

# ── Capsize signals ──────────────────────────────────────────────────────────
## Host-authoritative (CapsizeManager), broadcast to every peer.

## The boat has capsized -- everyone needs to swim to a corner. required is
## how many distinct corners need claiming (scales with player count).
signal capsize_started(required: int)

## One corner got claimed. claimed_count/required for a simple progress readout.
signal capsize_corner_claimed(corner_index: int, peer_id: int, claimed_count: int, required: int)

## Enough corners claimed -- boat's righted, everyone's back to normal.
signal capsize_resolved()

# ── Big Fish Event signals ───────────────────────────────────────────────────
## Host-authoritative (BigFishEventManager), broadcast to every peer.

## Boat shakes -- cast at target_spot within duration seconds to join.
signal big_fish_ready_check_started(target_spot: Vector3, duration: float)

## A player's cast landed on the spot in time -- they're in.
signal big_fish_participant_joined(peer_id: int)

## Nobody cast in before the ready check closed -- event's over, no penalty.
signal big_fish_event_fizzled()

## Ready check closed with at least one participant -- the shared minigame starts.
signal big_fish_event_active(participant_ids: Array, duration: float)

## Continuous bar/QTE state for every participant while active. Dictionary
## keyed by peer_id -> {pos, holding, qte_active, qte_prompt, locked_in, ...}
## -- see BigFishEventManager._participants for the exact shape.
signal big_fish_state_updated(participants: Dictionary)

## One participant missed their QTE -- bigger hit to them, smaller shared
## hit to every other still-active participant (BigFishEventManager already
## applied both before this fires; UI-only signal for feedback/flash).
signal big_fish_qte_missed(peer_id: int)

## Event's done -- true if everyone locked in before the time limit, false
## if it ran out first (capsize + lose 2 biggest fish already applied by
## the time this fires).
signal big_fish_event_resolved(success: bool)
