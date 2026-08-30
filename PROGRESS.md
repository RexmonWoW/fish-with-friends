# Fish With Friends — Progress

Live status file. GDD.md is the plan; this is where things actually stand. Update at the end of every session. Keep every bullet here to one short line — if something needs more explanation, put the detail in Open Questions instead.

## MVP Build Order status
1. [x] GodotSteam install + Steam connection. Export templates not yet confirmed.
2. [x] GitHub setup across two machines, different OS.
3. [x] Folder structure + scene tree.
4. [x] Fish data resource system — 5 placeholder species, real weighted spawn. Needs real species content + rarity-tiered weighting.
5. [x] Casting mechanic — full aim/charge/release/validate pipeline. Confirmed on 2 machines.
6. [x] Reel minigame + QTE — full GDD mechanic, perfect-catch bonus wired.
7. [x] Line tangling + tug of war — host-authoritative, confirmed working.
8. [~] Shared livewell — hold/store(E)/grab(1-5)/toss(Q) interaction done. Still missing GDD's multi-player "negotiate when full" UX.
9. [x] Big Fish Event — triggers once per day near the end of the day's final round. Tunable numbers still placeholder (Open Questions).
10. [x] Capsize minigame — built, triggered by a failed Big Fish Event.
11. [~] Walkable lobby — bare-bones room + start trigger only. Real shop/mirror/trophy case not started.
12. [x] Round timer + day structure.
13. [x] Quota system — sells and banks the livewell at the end of every round now (not just day's end); quota pass/fail still only checked at day's end. Formula numbers still placeholder (Open Questions).

## Infrastructure in progress
- Networking (GodotSteam P2P) — **confirmed working on 2 machines**, after several spawn/registration bugs found and fixed early on (see git log if you need the detail).
- Player movement + equipment slots — working, visible to other players, rod is camera-attached.
- Boat entity — placeholder raft, no walls yet.
- Lake map — placeholder art, functional water/spawn/livewell/bite-event wiring.

## Code Review Findings
_Standing decisions worth remembering, not a changelog — see Session Log for what changed when._
- **Accepted trust trade-off**: reel outcomes and tangle-mash are client-reported with no server-side sanity check. Deliberate call for a friends-only game.
- **Accepted trust trade-off**: livewell store/toss and capsize corner-claiming don't verify proximity server-side either. Same reasoning.
- `allow_object_decoding` is enabled globally (needed for Resource RPCs). Safe under the current friends-only threat model — re-review if that ever changes (public lobbies, mods).
- GDD gap-check (2026-08-29): everything through MVP item 13 is built except full lobby content, Per-Run Shop, Boat Upgrade, Cosmetics, leaderboard, and non-Lake maps/hazards.

## Next Up
- **Needs real 2-machine re-verification**: movement brake + livewell full-sync fixes (pass 27), Big Fish Event trigger rework (pass 28), debug console + sell-every-round (pass 29-30).
- Big Fish Event / Capsize swim-pose visuals haven't been checked on 2 machines (new replication shape).
- "Line doesn't always stay connected during flight" — still open, root cause unconfirmed.
- Balance placeholder numbers: quota formula constants, Big Fish Event tunables, QTE tunables, livewell swim/look-angle tunables.
- Known accepted gaps: joining client's RunState totals lag until the next broadcast; BigFishEventManager has no disconnect handling.
- Not built yet: real lobby content, rejected-cast feedback message, real multi-player livewell "negotiate when full" UX, real fish species/art content, rarity-tiered spawn weighting.
- Future want, not scheduled: a bobber upgrade that reveals species before reeling (Per-Run Shop item).

## Pre-Release Checklist
_(things that must be removed/checked before shipping — not now, but never forget them)_
- **Remove the debug console** (`skip_round`/`skip_day`/`set_time`, added pass 29) and any other dev cheats before release.
- (Add to this list any time a cheat, debug shortcut, or test-only backdoor gets added — see CLAUDE.md convention.)

## Open Questions
_(needs a call from the planning chat)_
- **Economy model**: GDD wants personal wallets + a shared fund; implementation has one shared pot. Needs a decision before the Per-Run Shop is built.
- **"Free days" from quota banking**: confirm whether a big early haul clearing a future day's quota with zero new catches is intended.
- **Quota balancing**: formula itself resolved (2026-08-29); `BASE_QUOTA`/`1.15`/`0.4` are still placeholder numbers.
- **Big Fish Event tunables**: join radius/duration/miss-penalties still placeholder. Trigger *timing* resolved 2026-08-30 (once per day, end of final round).
- **Big Fish Event credit**: a shared catch is credited to "The Crew" rather than one participant — confirm that's right, especially once a leaderboard exists.
- **Fun idea, not scheduled**: a challenge mode combining every map's hazard at once, once all maps exist.

## Session Log
_(one line per session)_
- 2026-08-27 — Set up CLAUDE.md/PROGRESS.md and the 2-lane planning/build workflow.
- 2026-08-27 — Finished the casting mechanic end-to-end; built a placeholder Lake map to test it on.
- 2026-08-27 (2nd pass) — Fixed slow movement and a stuck-cast bug found in playtest.
- 2026-08-27 (3rd pass) — Wired catches into the livewell; core loop (cast→bite→reel→catch→livewell) complete.
- 2026-08-27 (4th pass) — Added a placeholder visual for livewell fish.
- 2026-08-27 (5th pass) — Added livewell proximity popup + throw-overboard.
- 2026-08-27 (6th pass) — Added 4 more fish species; fixed spawn weighting so variety actually shows up.
- 2026-08-27 (7th pass) — Fixed a cast-rejection bug: aiming down at the water missed the validation raycast.
- 2026-08-27 (8th pass) — Finished the reel QTE layer; added a persistent line/bobber.
- 2026-08-27 (9th pass) — Fixed accidental livewell casts and a floating bobber; bite/livewell events now broadcast to all peers.
- 2026-08-27 (10th pass) — Fixed QTE not accepting WASD and the line swinging oddly; rod is now camera-attached.
- 2026-08-27 (11th pass) — Fixed players being invisible to each other (no mesh), ahead of the first 2-machine test.
- 2026-08-27 (12th pass) — 1st 2-machine test: client couldn't play at all; fixed a spawner registration bug.
- 2026-08-28 — 2nd 2-machine test: client could move but UI stayed stuck; fixed spawn bookkeeping being host-only.
- 2026-08-28 — 3rd 2-machine test: same stuck-menu bug; replaced a flaky signal-based fix with an explicit broadcast RPC.
- 2026-08-28 — 4th 2-machine test: both screens showed the same camera; fixed by activating each local player's own camera.
- 2026-08-28 — 5th 2-machine test: **confirmed working** — first real multiplayer confirmation this project.
- 2026-08-28 (13th pass) — Added real Steam display names and a bare-bones walkable lobby (item 11).
- 2026-08-28 (planning review) — Found a HIGH regression (client cast validation) plus other findings; logged above.
- 2026-08-28 (14th pass) — Fixed the HIGH finding (removed a stale per-node map cache).
- 2026-08-28 (15th pass) — Built line tangling / tug-of-war (item 7).
- 2026-08-28 (16th pass) — Fixed four playtest bugs: bobber jitter, backwards client spawn rotation, casting in the lobby, reel/tangle UI collision.
- 2026-08-28 (17th pass) — Fixed casting at a teammate silently failing.
- 2026-08-28 (18th pass) — Built round timer, day structure, and quota system (items 12-13).
- 2026-08-29 (19th pass) — Fixed livewell progress not showing mid-round, and a cast-rejection soft-lock.
- 2026-08-29 (20th pass) — Fixed reel-finish not clearing for other peers, and a floating bobber (water collision offset).
- 2026-08-29 (21st pass) — Reworked catches to hand the fish to the player to hold and choose toss/store.
- 2026-08-29 (22nd pass) — Loosened livewell look-targeting; made the swim motion a real loop.
- 2026-08-29 (23rd pass) — 2-machine test confirmed the pass 16-22 batch; fixed tangle disconnect handling.
- 2026-08-29 (24th pass) — Built the Capsize minigame (item 10); fixed swim pose and livewell camera-lock bugs.
- 2026-08-29 (25th pass) — Added reel difficulty scaling by fish value; reworked livewell interaction to E/1-5/Q.
- 2026-08-29 (26th pass) — Implemented the adaptive quota formula; fixed livewell wiping between rounds; built the Big Fish Event (item 9).
- 2026-08-29 (27th pass) — 2-machine playtest: fixed movement sliding and a livewell cross-peer desync bug; confirmed per-round quota behavior was correct as designed.
- 2026-08-30 (28th pass) — Reworked the Big Fish Event to trigger once per day (end of final round) instead of randomly, per planning.
- 2026-08-30 (29th pass) — Added a debug console (`skip_round`/`skip_day`/`set_time`) for faster playtesting; condensed this file's history down to one line per entry.
- 2026-08-30 (30th pass) — Playtest feedback: fixed an invisible debug console (no background panel) and a Big Fish Event banner stuck on screen (hardcoded 999999s duration); reworked selling to happen at the end of every round, not just day's end, per direction.
