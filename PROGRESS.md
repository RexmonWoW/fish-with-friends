# Fish With Friends — Progress

This is the live status file. GDD.md is the plan; this is where things actually stand. Update it at the end of every Claude Code session — that's what lets a new session (or the planning chat) pick up in seconds instead of you re-explaining state.

Baseline below was reconstructed on 2026-08-27 from commit history and a quick read of the current files — it hasn't been kept current session-to-session yet, so treat "done" items as "looked done from the outside" and correct anything that's wrong.

Casting mechanic status was corrected on 2026-08-27 after actually reading the pipeline and running it headless — see Session Log for what was wrong and what got fixed.

## MVP Build Order status
1. [x] GodotSteam install + Steam connection — `steam_manager` autoload in place, Steam class verified. Export templates (Mac/Linux/Windows) not yet confirmed.
2. [x] GitHub setup across two machines, different OS
3. [x] Folder structure + scene tree — autoload/data/entities/scenes/systems/ui in place
4. [x] Fish data resource system — `FishData`, `CaughtFish`, `FishFactory` implemented. One placeholder species (`data/fish/species/sunfish.tres`) now exists so the pipeline has something to roll; still needs real species content from planning/content.
5. [x] Casting mechanic — aim/charge/release/RPC/host water-validation/lure-arc pipeline confirmed working end-to-end via `tests/cast_smoke_test.gd` (headless, no display needed). Two real bugs found and fixed along the way: `EventBus` was missing the `cast_charge_started`/`cast_charge_updated` signals `rod.gd` and `cast_meter.gd` depended on, and `CastMeter` was never instantiated into the game scene. `Rod.current_map` is now wired from `NetworkManager.get_current_map()` on equip so water validation runs for real instead of hitting its permissive no-map fallback.
6. [~] Reel minigame + QTE — first slice in place (`ui/reel_minigame.gd`): hold-to-rise catch zone vs. a drifting fish icon, fill/drain meter, resolves back to `Rod.state = IDLE` either way. Fixes the "cast once then stuck forever" bug (`Rod.state` had no path back from `WAITING_BITE` to `IDLE`). Still missing: QTE prompts, zone-shrink-on-miss death spiral, line snapping, perfect-catch bonus — see Open Questions for the multiplayer gap.
7. [ ] Line tangling + tug of war — not started
8. [~] Shared livewell — data layer now real: `add_fish()`/`remove_fish()`/`is_full()` on `Livewell`, and a successful catch actually lands in a slot (`BiteEventManager` builds a `CaughtFish` via `FishFactory` and calls `add_fish`). Still missing: negotiation/throw-overboard interaction, per-slot visual fish display, "any player can look at the livewell and see stats" UI.
9. [ ] Big fish event — not started
10. [ ] Capsize minigame — not started
11. [ ] Walkable lobby — not started (main menu exists; the lobby itself doesn't)
12. [ ] Round timer + day structure — not started (`run_state.gd` autoload is still the untouched default Godot template)
13. [ ] Quota system — not started (depends on #12)

## Infrastructure in progress (not on the numbered list, but underlies it)
- Networking (`network_manager.gd`) — P2P host/client via GodotSteam, lobby create + host implemented. Substantial but not feature-complete.
- Player movement + equipment slots — RigidBody3D movement and equipment slot system in progress. Movement was near-frozen (plateaued ~0.2 m/s against a 5.0 m/s cap) because default RigidBody3D/StaticBody3D friction against the boat hull was eating almost all applied force — fixed with a low-friction `PhysicsMaterial` on both, plus retuned `move_force`/`linear_damp`. Verified with `tests/movement_smoke_test.gd`.
- Boat entity — just started. Currently a flat raft (hull only, no walls) per direction — the walls were also causing a hard full-stop on collision at speed.
- Lake map (`scenes/maps/lake.tscn`) — was a completely empty scene (no script, no children) as of session start. Now has a placeholder Environment/lighting, a large water plane in the `water_surface` group, the boat, livewell, `BiteEventManager`, and 4 player spawn points, enough to satisfy `Map._validate_contract()` and let casting be tested for real. Still placeholder box art — real geometry is Art & Polish's per the comment in `network_manager.gd`.

## Next Up
- Livewell interaction: throw-overboard and the "negotiate when full" UI (currently a full livewell just silently discards the catch with a warning). Look-at-livewell-to-see-stats display also doesn't exist yet.
- Reel minigame QTE layer — GDD calls for the fish randomly running and triggering a space/directional prompt, missed QTE shrinking the catch zone (death spiral), and multiple misses snapping the line. None of that exists yet; current `ReelMinigame` is just the drift-and-fill core.
- Perfect catch bonus (nail all QTEs → bonus livewell value) — depends on the QTE layer existing first.
- Fix `bite_started` only firing on the host (see Open Questions) before any real 2-machine multiplayer testing of casting/reeling.
- Line tangling + tug of war (item 7) — not started.
- Real fish species content from planning/content — only `sunfish` (placeholder) exists.
- Real player display names for `CaughtFish.caught_by_player_name` — currently a `"Player <id>"` placeholder; needs Steam persona name lookup.

## Open Questions
_(design/scope questions that came up mid-build and need a call from the planning chat — log them here instead of guessing)_
- **Multiplayer gap, not yet fixed**: `BiteEventManager._ready()` only connects `EventBus.cast_landed` `if multiplayer.is_server()`, and `EventBus.bite_started`/`reel_finished` are local `.emit()` calls, not RPCs — they only ever fire on whichever machine is host. In solo/host testing this is invisible (the host peer IS the local player), but a real second-machine client would cast, the host would resolve the bite server-side, and the client would never see `bite_started` fire, so their `ReelMinigame` would never appear. Needs an RPC broadcast (same pattern as `Rod._cast_landed`) before this is genuinely multiplayer-testable. Flagging rather than fixing since it's a networking-architecture call, not an implementation detail.
- `Rod.current_map` is set once, in `EquipmentSlot.equip_rod()`, from whatever `NetworkManager.get_current_map()` returns at that moment. For the host this is safe (map loads before players spawn), but a joining client's map-load RPC and their own player spawn/equip aren't ordered against each other, so a client could theoretically equip before their map finishes loading (current_map stays null → permissive fallback, not a crash, just unvalidated water for a frame). Same "not tested against a second machine" caveat as above.

## Session Log
_(optional but useful — one line per session: date, what got done)_
- 2026-08-27 — Set up CLAUDE.md + PROGRESS.md, reconstructed this baseline from commit history, replaced GDD.md's old 5-chat hierarchy with a 2-lane (planning chat / Claude Code) workflow.
- 2026-08-27 — Verified and finished the casting mechanic end-to-end. Fixed two real bugs (EventBus missing `cast_charge_started`/`cast_charge_updated` signals; `CastMeter` never instantiated). Wired `Rod.current_map` so water validation is live. Built a placeholder Lake map (water plane, boat, livewell, spawn points, BiteEventManager) since it was a completely empty stub blocking any real test. Added `tests/cast_smoke_test.gd(.tscn)` as a headless, no-display way to drive the full cast pipeline and confirmed it works (charge → release → RPC → host water validation → lure arc → WAITING_BITE) using the GodotSteam editor console binary on this machine.
- 2026-08-27 (same day, second pass) — Playtest feedback: movement was "very very slow" and casting only worked once then went dead. Fixed both. Movement: default RigidBody3D/StaticBody3D friction against the boat hull was eating almost all applied force (measured plateau ~0.2 m/s via `tests/movement_smoke_test.gd`); added low-friction PhysicsMaterial + retuned `move_force`/`linear_damp`, now reaches the 5.0 m/s cap in <0.5s. Boat simplified to a raft (walls removed) per direction. Stuck cast: `Rod.state` had no path from `WAITING_BITE` back to `IDLE`, so every cast after the first silently no-op'd — root-caused and fixed by building a first-slice reel minigame (`ui/reel_minigame.gd`) that resolves the state back to `IDLE`. Along the way fixed a pre-existing bug where spawned `Fish` nodes got `global_position` set before `add_child`, silently failing (fish always spawned at the origin). Added a placeholder `sunfish` species so the bite pipeline had something to roll. Verified with `tests/reel_smoke_test.gd`.
- 2026-08-27 (same day, third pass) — Wired a successful catch into the livewell: `Livewell.add_fish()`/`remove_fish()`/`is_full()` plus `BiteEventManager` building a real `CaughtFish` via the already-implemented `FishFactory` on catch. Closes the full core loop (cast → bite → reel → catch → livewell) end to end for the first time. `tests/reel_smoke_test.gd` now also checks the livewell slot fills with the right species/size/value.
