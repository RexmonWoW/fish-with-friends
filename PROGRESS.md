# Fish With Friends — Progress

Live status file. GDD.md is the plan; this is where things actually stand. Update at the end of every session. Keep every bullet here to one short line — if something needs more explanation, put the detail in Open Questions instead.

## MVP Build Order status
1. [x] GodotSteam install + Steam connection. Export templates not yet confirmed.
2. [x] GitHub setup across two machines, different OS.
3. [x] Folder structure + scene tree.
4. [x] Fish data resource system — 5 placeholder species, real weighted spawn. Needs real species content + rarity-tiered weighting.
5. [x] Casting mechanic — full aim/charge/release/validate pipeline. Confirmed on 2 machines.
6. [x] Reel minigame + QTE — full GDD mechanic, perfect-catch bonus wired. Real bobber now visibly reels in/out with the private progress bar, synced to every nearby peer (not pixel-exact by design). Reel Mechanic itself (the Stardew bar) still on hold pending planning.
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
- **Run restart teardown (2026-08-30)** verified solo (fail → menu → restart, twice in a row) — still needs a real 2-machine check that a client disconnecting/rejoining a fresh host session behaves the same way.
- **Casting rework, step 1 of 3 (2026-09-01)**: landing preview built and headless-tested (parity-checked against the real cast). Steps 2-3 (arc first-hit collision, dead-cast-lies-there, bonk) wait on Nick trying step 1 and confirming whether yaw+power aiming feels fine with the preview visible, or needs pitch to matter too.
- **2-machine test fixup batch (2026-09-01)**: hook-set, corner-claim, tangle-mash, and Big Fish Event holding/QTE reporting were all silently broken for non-host clients (same is_server()-gated add_to_group bug in 4 different managers) — needs a real 2-machine confirmation, headless tests can't exercise a genuine second peer.
- **Before the shop gets built**: minigame tunables (bite timing, zone shrink, bar speed, etc.) currently live as hardcoded `const`s across BiteEventManager/ReelMinigame/VisualFishSpawner. Upgrades need something to actually modify, so these need to become per-player modifiable stats before Per-Run Shop items can hook into them. Not now, just don't lose it.
- **2-machine test in progress (passes 31-34) — movement CONFIRMED working.** Everything else still needs re-verification after four full rounds of real bugs surfacing as soon as things became testable, most recently: capsize left players unable to move at all (a velocity-clobbering ordering bug in Player's swim branch), line tangling's collision radius was 10x too tight to ever realistically trigger. Treat nothing here as done until a clean pass with no new reports.
- **Bite Detection was reworked into a standing ambient population (2026-08-30)** — shadows now wander continuously and get called by a nearby cast instead of spawning per-cast; a miss sends one back to wandering instead of despawning it. New networked shape, still not tested on 2 machines — headless-tested solo only so far.
- **Reel Mechanic: first piece back after the reset (2026-08-30)** — the real bobber/line now reels in/out with progress and tugs during a QTE, synced to every peer (new `ReelFightManager` + QTE kick). The bobber is now its own independent node (new `Bobber`, never parented to Rod/Player, same pattern as Fish/VisualFish) after a camera-swing bug traced back to exactly that parenting. The Stardew bar itself is still the old unchanged version — everything else about the reel/Big Fish rework stays on hold pending planning. Not yet tested on 2 machines.
- **Balance note (2026-08-30)**: Big Fish Event still feels too easy even with the QTE label now visible. Hold off retuning again until it's been tested with the label fix in place first.
- **Design ask, not built yet**: make the Big Fish Event feel more like a real (easier) mini reel — right now it's just hold-and-wait with an occasional QTE. Needs a planning/design pass before building.
- **Explicitly deferred by request**: livewell fish should actually swim around, spawn, and despawn (currently static placement per slot) — do after the current bug list is clean.
- Capsize's placeholder swim pose/bob animation removed by request (2026-08-30) — real swim animation is Art & Polish's for later.
- "Line doesn't always stay connected during flight" — still open, root cause unconfirmed.
- Balance placeholder numbers: quota formula constants, Big Fish Event tunables, QTE tunables, livewell swim/look-angle tunables, ambient shadow population (count/spread/swim speed/call-radius growth rate/**max call radius**), capsize toss impulse strength/settle time, reel fill-rate distance falloff, reel bar's max stretch distance.
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
- **Quota balancing**: formula itself resolved (2026-08-29); `BASE_QUOTA`/`1.35`/`0.5` (retuned 2026-09-01, was 1.15/0.4 — too flat in playtest) are still placeholder numbers.
- **Quota now gets paid out of the pot at day end (2026-09-01), not cumulative-forever**: "take away quota money at the end of the day" was a terse ask with real design weight, so flagging the exact call made rather than guessing silently — a passed day now sets `total_money_earned` to just the surplus (this day's earnings minus what it owed), so next day starts from the profit, not the whole run's history. A failed day is unaffected (run just ends). Confirm this is the intended shape before the Per-Run Shop gets built on top of it — ties into the Economy model question above.
- **Big Fish Event tunables**: join radius/duration/miss-penalties still placeholder; climb speed/QTE cadence retuned 2026-08-30 (was solvable by pure hold, no real challenge), still needs real playtesting to dial in further. Trigger *timing* resolved 2026-08-30 (once per day, end of final round).
- **Big Fish Event credit**: a shared catch is credited to "The Crew" rather than one participant — confirm that's right, especially once a leaderboard exists.
- **Fun idea, not scheduled**: a challenge mode combining every map's hazard at once, once all maps exist.
- **Blind-cast bite pacing (GDD flagged this one itself)**: implemented as a soft default — a cast with nothing nearby isn't dead, the shadow-search radius grows the longer it waits (a few seconds worst case today). GDD explicitly flagged this as a default call, not confirmed — say the word if a hard "no shadow nearby = no bite" is preferred, or if the wait should feel longer/more suspenseful than today's few-second tuning.
- **Capsize toss doesn't actually rotate the player** — real launch impulse (arc, real gravity), but no body-tumbling animation. Rotating the physics body directly would spin the local player's own camera with it (the camera rig is a direct child, and "a shove to the body never affects camera direction" is a stated architecture rule) — skipped rather than risk that. If real tumbling is wanted, it'd need a decoupled visual effect instead of rotating the RigidBody itself.

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
- 2026-08-30 (31st pass, 2-machine test in progress) — Movement confirmed working. Found and fixed real bugs as things became visible for the first time: Big Fish Event could trigger during the round-1-to-lobby transition (round_number/timer race before the scene actually clears), no world marker ever existed at the disturbance spot, capsized players were stuck on the boat deck instead of in the water (no toss, plus the Hull's own collision blocked them), and set_time didn't sync the displayed round timer. Also retuned the Big Fish Event's climb/QTE pacing (was winnable by pure hold, no real challenge) and added a simple boat-tilt visual on capsize.
- 2026-08-30 (32nd pass, 2-machine test continued) — 7 more real bugs fixed (off-screen capsize text, re-broken client timer, stuck-mid-cast on capsize, big fish spawning under the boat, its blank QTE prompt, round-end selling skipping the reserved slot and held fish); added cast-cancel and a one-step livewell swap.
- 2026-08-30 (33rd pass) — Cast-cancel wasn't discoverable (no hint) and capsize's water toss only tried one direction (could strand a player above water) -- both fixed. Added a collective progress bar + countdown to the Big Fish Event, by request.
- 2026-08-30 (34th pass) — Root-caused "capsize -- can't move" for real: Player's swim branch reset linear_velocity.y AFTER applying the movement impulse, silently discarding it every frame via a read-modify-write. Fixed the ordering, plus gave water a low-friction material and a toss clearance margin (real contributing factors, not the main cause). Fixed line tangling's collision radius (0.05 -- absurdly tight) and a timing race it exposed. Removed the placeholder swim pose animation by request.
- 2026-08-30 — Reset repo to fdd3b46 — reel/big fish rework after that point missed the mark, rebuilding from here. Prior HEAD kept at branch `pre-reset-backup` for reference.
- 2026-08-30 — Cherry-picked Bite Detection and bobber drift back onto main from `pre-reset-backup` — both tested clean and weren't part of what went wrong with the reel rework.
- 2026-08-30 (planning update) — Reworked Bite Detection into a standing ambient shadow population (new `ShadowWander` helper, rewritten `VisualFishSpawner`) instead of spawn-per-cast; a nearby cast calls one in, a miss releases it back to wandering, only a catch despawns one for good, and a growing search radius keeps a blind cast from ever being dead.
- 2026-08-30 — Shadow size now scales off the fish's actual size stat (rolled per-shadow, same call a real catch uses) instead of money value.
- 2026-08-30 — Added back the real bobber reeling in/out with reel progress, synced to every nearby peer (new, simpler `ReelFightManager`) -- first scoped piece of the reel rework, rest stays on hold for planning.
- 2026-08-30 — Playtest feedback on the new bobber: fixed a landing pop (drift wasn't eased in), fixed it visibly following the rod when just looking around while reeling (closes toward the angler's own position now, not the camera-attached rod tip), and added the GDD sideways "tug" during a QTE.
- 2026-08-30 (planning update) — Confirmed root cause of the camera-swing bug (bobber parented under the camera-attached Rod, fighting the parent transform every frame). Made the bobber a fully independent scene-root node (new `Bobber`, same pattern Fish/VisualFish already use) instead of patching the symptom -- Rod/LureAnimator now just tracks a reference to it for the line. Also fixed the landing-pop drift bug at its actual root: drift magnitude now ramps in from zero over ~1.5s of time-since-landing instead of easing toward an already-nonzero sample.
- 2026-08-30 (review pass) — Fixed a bobber leak (nothing freed it on disconnect/scene-change; now cleaned up in `_exit_tree()` and parented under the map) and a stale reel-fight position (never cleared when the broadcast stopped including a peer). Found along the way: capsizing mid-REELING orphaned the Fish/fight server-side forever -- `force_cancel_cast()` only ever checked WAITING_BITE.
- 2026-08-30 (planning update) — Fixed ambient shadows surviving into the lobby between rounds (parented under the map now, like the bobber fix); swapped the shadow's placeholder mesh from an upright capsule to a flat dark oval blob sitting just under the water surface; capsize toss is now a real physics launch (impulse + real gravity for ~1.3s before swim mode engages) instead of a teleport, with the old validated-water-point logic kept as a safety net; `ReelFightManager` broadcasts throttled to ~12Hz and sends one final broadcast when the last fight ends so a lingering bobber's stale-position guard actually fires.
- 2026-08-30 (playtest fixes) — Capsize toss actually carries now: normal movement/braking was killing the impulse before swim mode engaged, and the hull could block the launch outright -- both fixed (a ballistic-phase flag skips movement/braking/jump, and boat collision is masked for the same window). Corner claiming fixed to measure XZ distance with a separate vertical tolerance instead of full 3D -- the tilting boat put the raised side's corners out of reach. Reel bobber no longer yanks halfway in the instant a fight starts (display progress remapped so the fight's actual starting value maps to the landing spot); losing progress now drags it back past the anchor instead of clamping. Cast distance now scales the fill rate (farther = slower to reel in).
- 2026-08-30 (correction) — Reel bar's world mapping corrected to what Nick actually meant: symmetric around the 50% start, winning half closes real distance to the angler, losing half stretches the bobber out past the landing spot by a fixed tunable distance (not another full cast-length).
- 2026-08-30 (bug fix) — Fixed run restart duplicating the world: `disconnect_from_lobby()` only cleared the multiplayer peer and the `spawned_players` dict, never the actual World/Player nodes, so a second "start a new game" in the same session left the old run's map and player sitting there (`_load_map` only ever adds, never replaces). Built one explicit teardown that frees World and Players and resets RunState/scene-tracking on return-to-menu; new-game code no longer has to defensively re-clear anything. Verified with a new solo test that fails the quota, returns to menu, and restarts twice in a row.
- 2026-08-31 — Parked cast collision/bounce physics — wasn't working out in playtest. Reset `main` to before it (was cleanly at the tip); kept on branch `cast-bounce-experiment`. Planning is writing a simpler spec (landing preview + first-hit + dead-cast-lies-there, no bounce physics) before casting gets rebuilt.
- 2026-09-01 — Casting rework step 1: live landing preview while charging, sharing the exact aim math with the real cast (new `Rod._compute_aim_point`, called by both) so it can never disagree with where a cast actually lands; shows blocked/red when the spot isn't water. Purely client-side, no networking.
- 2026-09-01 (2-machine fixes) — Fixed hook-set/corner-claim/tangle-mash/Big-Fish-holding all silently dropping for non-host clients (`add_to_group` gated behind `is_server()` in 4 managers, same pass-37 bug shape); left+right click both now cancel/reel back a waiting cast (left still sets the hook during an open window); rounds now force-cancel every rod's cast on end; shadow call radius capped so a blind wait can't eventually reach the whole lake.
- 2026-09-01 — Added a placeholder crosshair; quota now pays out of the pot at day end (only the surplus carries forward) instead of accumulating forever -- flagged in Open Questions, real design call worth confirming.
