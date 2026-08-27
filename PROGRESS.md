# Fish With Friends — Progress

This is the live status file. GDD.md is the plan; this is where things actually stand. Update it at the end of every Claude Code session — that's what lets a new session (or the planning chat) pick up in seconds instead of you re-explaining state.

Baseline below was reconstructed on 2026-08-27 from commit history and a quick read of the current files — it hasn't been kept current session-to-session yet, so treat "done" items as "looked done from the outside" and correct anything that's wrong.

Casting mechanic status was corrected on 2026-08-27 after actually reading the pipeline and running it headless — see Session Log for what was wrong and what got fixed.

## MVP Build Order status
1. [x] GodotSteam install + Steam connection — `steam_manager` autoload in place, Steam class verified. Export templates (Mac/Linux/Windows) not yet confirmed.
2. [x] GitHub setup across two machines, different OS
3. [x] Folder structure + scene tree — autoload/data/entities/scenes/systems/ui in place
4. [x] Fish data resource system — `FishData`, `CaughtFish`, `FishFactory` implemented, but no actual `.tres` species resources exist yet under `data/fish/species/` (the directory doesn't exist) — see Open Questions.
5. [x] Casting mechanic — aim/charge/release/RPC/host water-validation/lure-arc pipeline confirmed working end-to-end via `tests/cast_smoke_test.gd` (headless, no display needed). Two real bugs found and fixed along the way: `EventBus` was missing the `cast_charge_started`/`cast_charge_updated` signals `rod.gd` and `cast_meter.gd` depended on, and `CastMeter` was never instantiated into the game scene. `Rod.current_map` is now wired from `NetworkManager.get_current_map()` on equip so water validation runs for real instead of hitting its permissive no-map fallback.
6. [ ] Reel minigame + QTE — not started. `BiteEventManager` already spawns a `Fish` node and emits `bite_started` after a cast lands, but there's no reel/QTE logic consuming that signal yet.
7. [ ] Line tangling + tug of war — not started
8. [~] Shared livewell — scene + script exist but are an explicit stub (own header comment says "actual add/remove/throw-overboard logic is a future dispatch")
9. [ ] Big fish event — not started
10. [ ] Capsize minigame — not started
11. [ ] Walkable lobby — not started (main menu exists; the lobby itself doesn't)
12. [ ] Round timer + day structure — not started (`run_state.gd` autoload is still the untouched default Godot template)
13. [ ] Quota system — not started (depends on #12)

## Infrastructure in progress (not on the numbered list, but underlies it)
- Networking (`network_manager.gd`) — P2P host/client via GodotSteam, lobby create + host implemented. Substantial but not feature-complete.
- Player movement + equipment slots — RigidBody3D movement and equipment slot system in progress.
- Boat entity — just started (placeholder box geometry, capsize corner markers).
- Lake map (`scenes/maps/lake.tscn`) — was a completely empty scene (no script, no children) as of session start. Now has a placeholder Environment/lighting, a large water plane in the `water_surface` group, the boat, livewell, `BiteEventManager`, and 4 player spawn points, enough to satisfy `Map._validate_contract()` and let casting be tested for real. Still placeholder box art — real geometry is Art & Polish's per the comment in `network_manager.gd`.

## Next Up
- Reel minigame + QTE (item 6) — `BiteEventManager.fish_scene` is wired and fires `bite_started`, so the next session can start consuming that signal directly.
- Author at least one real `FishData` `.tres` resource under `data/fish/species/` so `SpawnPool`/`BiteEventManager` have something to roll — right now that directory doesn't exist and bites silently fail to spawn a fish (see Open Questions).

## Open Questions
_(design/scope questions that came up mid-build and need a call from the planning chat — log them here instead of guessing)_
- No `FishData` `.tres` resources exist anywhere yet (`data/fish/species/` isn't even created). `SpawnPool._get_pool_for_map()` can't open that directory and `push_error`s, then `BiteEventManager` just warns and spawns nothing. Casting itself isn't affected, but nothing bites. Is authoring the first species a planning-chat/content task, or should Claude Code stub in a placeholder species so the bite pipeline is testable?
- `Rod.current_map` is now set once, in `EquipmentSlot.equip_rod()`, from whatever `NetworkManager.get_current_map()` returns at that moment. For the host this is safe (map loads before players spawn), but a joining client's map-load RPC and their own player spawn/equip aren't ordered against each other, so a client could theoretically equip before their map finishes loading (current_map stays null → permissive fallback, not a crash, just unvalidated water for a frame). Not tested against a second machine this session — flagging in case it matters once real 2-machine multiplayer testing starts.

## Session Log
_(optional but useful — one line per session: date, what got done)_
- 2026-08-27 — Set up CLAUDE.md + PROGRESS.md, reconstructed this baseline from commit history, replaced GDD.md's old 5-chat hierarchy with a 2-lane (planning chat / Claude Code) workflow.
- 2026-08-27 — Verified and finished the casting mechanic end-to-end. Fixed two real bugs (EventBus missing `cast_charge_started`/`cast_charge_updated` signals; `CastMeter` never instantiated). Wired `Rod.current_map` so water validation is live. Built a placeholder Lake map (water plane, boat, livewell, spawn points, BiteEventManager) since it was a completely empty stub blocking any real test. Added `tests/cast_smoke_test.gd(.tscn)` as a headless, no-display way to drive the full cast pipeline and confirmed it works (charge → release → RPC → host water validation → lure arc → WAITING_BITE) using the GodotSteam editor console binary on this machine.
