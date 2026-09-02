extends Node

# ── Cast signals ───────────────────────────────────────────────────────────────

## Emitted locally when the rod owner starts charging a cast.
## Listeners: power meter UI (Art & Polish).
signal cast_charge_started(caster_peer_id: int)

## Emitted locally every frame while charging, with current power 0.0-1.0.
## Listeners: power meter UI (Art & Polish).
signal cast_charge_updated(power: float, caster_peer_id: int)

## Emitted on all peers when a cast lands anywhere -- water or not (GDD
## Casting: "no silent rejections, every cast visibly goes somewhere").
## is_dead_cast is true when the landing spot isn't real water (hit the
## boat/a railing/a player/etc, or missed everything and fell back to dry
## ground) -- it still lands and lies there, but nothing will ever bite it.
## Listeners: lure animator (Art & Polish), BiteEventManager (host-only,
## skips scheduling a bite for a dead cast).
signal cast_landed(endpoint: Vector3, flight_seconds: float, caster_peer_id: int, is_dead_cast: bool)

## Emitted on all peers when a cast's swept path hits another player (GDD
## Casting: "casting into a teammate = bonk"). Movement is client-
## authoritative per player, so only the hit player's own client actually
## applies the impulse to itself -- same pattern as the capsize toss.
signal player_bonked(hit_peer_id: int, impulse: Vector3)

## Emitted on all peers when a cast is rejected by the host (dry land, out of range).
## Listeners: power meter UI reset (Minigame Logic / Art & Polish).
signal cast_failed(reason: StringName, caster_peer_id: int)

## Emitted on all peers when a shadow fish strikes the line and the
## hook-set window opens (GDD Bite Detection). Listeners: CastMeter (hook
## prompt), Rod (accepts the hook-set input while this is open).
signal bite_hook_window_opened(caster_peer_id: int, duration: float)

## Emitted on all peers when a hook-set window closes without a successful
## hook-set -- the shadow spooked off. Listeners: same as above, to hide
## the prompt/stop accepting input until the next shadow strikes.
signal bite_hook_window_missed(caster_peer_id: int)

## Emitted on all peers when a fish bites a cast line (hook successfully
## set -- see bite_hook_window_opened above for what leads up to this).
## Listeners: reel minigame trigger (Minigame Logic).
signal bite_started(fish_data: FishData, caster_peer_id: int)

## Emitted host-side once BiteEventManager has despawned the fish for a
## resolved reel (caught or escaped). Informational -- Rod already resets
## itself to IDLE optimistically on the owning client.
signal reel_finished(success: bool, caster_peer_id: int)

## Emitted on all peers, unreliable, roughly every host tick while any
## reel fight is active. GDD Reel Mechanic: the private Stardew bar stays
## each angler's own control, but the real bobber's position is a synced
## display of it -- payload is {peer_id (int) -> Vector3}, one entry per
## angler currently reeling. Listeners: LureAnimator (moves that peer's
## bobber/line instead of leaving it drifting at anchor).
signal reel_fight_state_updated(states: Dictionary)

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
## time_remaining is the event's own overall countdown (EVENT_TIME_LIMIT),
## not any one participant's -- drives the collective progress/time UI.
signal big_fish_state_updated(participants: Dictionary, time_remaining: float)

## One participant missed their QTE -- bigger hit to them, smaller shared
## hit to every other still-active participant (BigFishEventManager already
## applied both before this fires; UI-only signal for feedback/flash).
signal big_fish_qte_missed(peer_id: int)

## Event's done -- true if everyone locked in before the time limit, false
## if it ran out first (capsize + lose 2 biggest fish already applied by
## the time this fires).
signal big_fish_event_resolved(success: bool)

# ── Per-Run Shop signals ─────────────────────────────────────────────────────
## GDD Per-Run Shop. Host-authoritative (ShopCounter), broadcast to every
## peer -- everyone browsing the shop together needs to see a crewmate's
## purchase land live, not just the buyer.

## Emitted locally (per-peer, not networked) when the LOCAL player enters or
## exits a ShopCounter's InteractionZone. Same shape as
## livewell_proximity_changed. Listeners: ShopDisplay UI.
signal shop_proximity_changed(shop: Node, in_range: bool)

## A purchase attempt resolved, success or not. requester_peer_id is who
## asked for it (so the UI can show a failure reason only to them --
## everyone else just needs the refresh); target_peer_id is who the
## upgrade was for (meaningless for a crew-wide item like fish_finder).
## reason is empty on success.
signal purchase_resolved(requester_peer_id: int, item_id: StringName, target_peer_id: int, success: bool, reason: StringName)
