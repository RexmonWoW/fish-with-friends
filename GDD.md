# Fish With Friends — Game Design Document

## Game Overview
Chaotic co-op fishing game, 1–4 players, solo playable, Steam only.

---

## Tech Stack
- Engine: Godot 4
- Steam: GodotSteam Standard win64-g462-s164-gs4181-editor
- Developing on: Linux and Windows
- Shipping on: Mac, Linux, Windows
- Steam App ID: 480 (testing)
- Repo: GitHub private, across two machines on different OS
- Export templates needed: Mac, Linux, Windows

---

## Art + Tone
- Art direction goal: Sea of Thieves — warm, atmospheric, painterly.
- **Nick is modeling, texturing, and painting everything himself — this is not a Code task.** Code's job stays code/systems: keep placeholder meshes/materials simple and easily swappable (standard import setup, one clear material slot per part) so real assets drop in cleanly later. Don't build stylized shaders, hand-tune lighting/atmosphere, or otherwise take a swing at the visuals unless explicitly asked.
- FPS camera
- Silly, cozy audio
- Cozy music in lobby, chaotic music on boat

---

## Core Loop
Walkable bait and tackle lobby → dock → 5 min boat round → return → sell → upgrade → repeat

- 2 rounds = 1 day
- Money quota due every 2 rounds, cumulative across days
- Forever escalating difficulty, no day cap
- Run ends when you miss quota
- On run end: lose screen shows final score, everyone disconnects, click to return to main menu

---

## Lobby
- Fully walkable bait and tackle shop
- Counter for upgrades and consumables
- Mirror for cosmetics
- Dock to ready up
- Each player's biggest fish ever caught displayed in lobby

---

## Player
- Movement: RigidBody3D — physics-based, players can bump and collide with each other
- FPS camera controls look direction independently from physics body
- Equipment slot system: whatever is equipped shows in player's hands (rod, fish, nothing)
- Rod unequipped = attaches to back visually
- Attachment points (hand, back) built into player scene from day one, meshes can be placeholder
- Full equipment visibility to other players at all times

---

## Casting
- Aim with mouse direction
- Hold click to build power meter
- Release to cast
- Power determines distance
- **Landing preview:** while charging, a marker sits on the water exactly where the bobber will land, updating live with aim and power (WEBFISHING/Fortnite style). It reads as blocked when the path is obstructed or the spot isn't water. You should never release a cast without knowing where it's going — this is the main thing that makes casting feel fair.
- **The arc hits what's in its way** — the whole flight path is checked, not just the endpoint. First thing hit wins, so a cast can't pass through the boat, a railing, or a person.
- **Dead cast:** a bobber that ends up anywhere that isn't water just lands there and lies there — nothing will ever bite it. Cancel or recast to reel it back. No penalty beyond the wasted seconds. It does not bounce; it plops where it hit (Minecraft-style).
- **Casting into a player = bonk.** Light knockback + thunk, bobber drops at their feet as a dead cast. No damage, pure comedy.
- No silent rejections — every cast visibly goes somewhere.

---

## Bite Detection
- Fish swim visibly in the water as wandering shadows (size hints at species/rarity), all the time — not spawned by casting.
- Shadow look: Pokémon / Animal Crossing / Fishing Resort style — a flat dark silhouette blob at/under the water surface, not a 3D fish body. (Placeholder stays a simple flat dark shape Code can build; real shadow art is Nick's later.)
- Shadows belong to the fishing map — they despawn with it and never appear in the lobby or between rounds.
- Cast near one to call it: it breaks off from wandering and swims to your bobber instead of an invisible timer deciding when you get a bite.
- Casting where nothing's currently swimming isn't a dead cast — a wandering shadow that drifts into range later still gets called, just later. Aiming well gets a faster, more certain bite; aiming blind means waiting on whatever wanders by. *(Default call, not yet confirmed with Nick — flag if a hard "no shadow nearby = no bite" is preferred instead.)*
- Once a shadow is swimming for your bobber, it's yours — another player's cast can't also call it.
- Arrival at the bobber opens a short hook-set window — press to set the hook. Miss it and the fish spooks back off to wander again.
- Hook-set success drops straight into the Reel Mechanic.
- Fully synced — everyone sees the same wandering fish and the same fish converging on a bobber, not a private roll on one screen.

---

## Reel Mechanic
- Stardew Valley style minigame
- Cursor keeps fish icon inside drifting zone
- Press to go up, let go to go down
- Fish randomly runs, triggering a QTE (space or directional prompt)
- Miss QTE = zone shrinks (death spiral)
- Multiple misses = line snaps, fish gone
- Perfect catch (nail all QTEs) = bonus livewell value
- Each player gets their own cursor
- Runs client side, outcome synced to host
- The fight shows physically in the world for everyone: the real bobber reels in along the water toward the angler as progress builds, with sideways kicks on QTEs (host broadcasts positions; the private bar stays the only control).
- The bar maps to the world symmetrically: the fight starts with the bobber exactly where it landed (bar at 50%). The winning half of the bar = closing the real distance from landing spot to angler; the losing half = the fish taking line, stretching the bobber out *past* the landing spot — so an emptying bar visibly reads as the line stretching until it snaps. Max stretch distance is a tunable.
- Farther casts take longer to reel in — fill rate scales down with distance to the bobber. Numbers are placeholder, tune by feel.

---

## Line Tangling
- Lines cross = prompt appears = button mash tug of war
- Winner keeps their cast, loser loses theirs

---

## Boat
- Stationary, no driving, no anchor
- FPS camera

---

## Livewell
- Shared, 5 slots total
- Every fish including large fish takes exactly 1 slot
- No separate hanger
- When livewell is full, players must negotiate or physically intervene
- Any player can look at the livewell and see each fish's stats: species, size, value, who caught it, special attributes
- Any player can grab any fish and throw it overboard
- No confirmation prompt — thrown fish are gone immediately
- Livewell interaction is proximity-based FPS look + prompt
- Big fish event catch has its own reserved slot separate from the 5 livewell slots and does not compete with normal fish inventory

---

## Big Fish Event
*(Lake map only — Lake's signature hazard, its counterpart to Ocean's pelican, Ice Lake's cold, Swamp's mosquito, and Storm's lightning)*
- Triggers once per day, in the final stretch of the day's second (last) round — a climactic capstone to the day rather than a random mid-round surprise. Boat shakes to signal it.
- **Ready check:** players cast at the shaking spot to join in. This window has its own short time limit (placeholder ~15-20s, tune by feel). Whoever's cast in when it closes participates — doesn't require the whole lobby, so solo play is just a ready check of one. Nobody casts in = event fizzles.
- Once the ready check closes, every participating player gets an on-screen bar with their name underneath, visible to everyone (including anyone who didn't join in) — everyone starts together.
- Same feel as the Reel Mechanic: hold to rise, periodic QTE prompts.
- **A QTE miss hurts everyone**, not just whoever missed — bigger hit to the player who missed, smaller shared hit to every other active bar. It's a team moment, not just a personal one.
- **Soft max:** reaching the top of a bar isn't instant — it has to sit in a near-max band for a couple seconds to lock in as done. Falling out of that band (including from a teammate's missed QTE) cancels the lock-in countdown, not the bar's whole progress — climb back and hold again.
- **Success:** every participating player's bar locks in as done before the event's overall time limit. Big fish enters its own reserved slot, bonus money (3x value), doesn't take a normal livewell slot.
- **Fail:** time runs out with at least one bar not locked in. Capsizes, lose 2 biggest fish from livewell, triggers Capsize Minigame. Until Capsize Minigame is built, apply the fail penalty (lose 2 biggest fish) with a placeholder message instead of the full minigame — don't block this event on that one.

---

## Capsize Minigame
- Entry: players get physically tossed into the water (real physics impulse on their RigidBody, not a teleport/reposition) — funny by design. Everything downstream (swim state, corner claiming) unchanged.
- Everyone swims to a corner of the boat and interacts
- Number of corners scales with player count
  - 1 player = 1 corner
  - 2 players = 2 corners
  - 3 players = 3 corners
  - 4 players = 4 corners

---

## Multiplayer
- Steam friends only, P2P
- **Host owns:** fish spawns, event triggers, livewell state, boat physics, tangle detection
- **Clients own:** rod locally, send cast position to host
- Reel runs client side, outcome synced to host

---

## Economy
- Haul split equally into personal wallets at end of day
- Personal wallet buys per-run upgrades and consumables
- Shared boat fund (everyone chips in voluntarily) buys fish finder only
- Rod upgrades are per-run only
- Cosmetics are permanent account unlocks

---

## Per-Run Shop
| Item | Effect |
|---|---|
| Bait | Fish bite faster (personal) |
| Line strength | Miss QTE = less zone shrink |
| Reel upgrade | Bigger catch zone |
| Weighted lure | Bar moves faster |
| Mosquito spray | Immunity for one round |
| Hand warmers | Slower cold meter |
| Seagull/pelican food | Distracts bird |
| Lightning rod | Redirects lightning strikes |

---

## Boat Upgrade
- Fish finder only (shared, everyone chips in)
- Fish spawn closer to cast point, bite faster
- Stacks with personal bait for maximum efficiency

---

## Quota Scaling
Quota isn't a fixed curve independent of how you're doing — it climbs every day on its own, and climbs faster if you clear it by a lot, so one big haul doesn't buy several free days afterward.

- Day 1 quota = base quota × player-count multiplier (below).
- Every day after: `next_quota = round(previous_quota × 1.15 + surplus × 0.4)`, where `surplus` is how much your cumulative total cleared the previous quota by (0 if you just barely passed).
- Player-count multiplier is sub-linear on purpose: the livewell is shared and capped at 5 slots no matter how many people are playing, so more players mostly means filling those 5 slots with better fish faster, not more total capacity.

| Players | Multiplier |
|---|---|
| 1 | 1.0x |
| 2 | 1.6x |
| 3 | 2.1x |
| 4 | 2.5x |

Base quota and the 1.15 / 0.4 constants are starting points to playtest and tune, not final numbers — see PROGRESS.md.

---

## Fish Data
Fish are data resources with the following fields:

| Field | Type | Description |
|---|---|---|
| species | String | Fish type identifier |
| size | Float | Physical size |
| weight | Float | Weight |
| rarity | Enum | Common / Uncommon / Rare / Legendary |
| money_value | Int | Base sell value |
| location_caught | String | Map/location tag |
| caught_by | Int | Player ID |
| perfect_catch | Bool | Were all QTEs nailed? |
| special_attributes | Array | Albino, shiny, electric, etc. |
| hazard_during_catch | Bool | Caught during lightning strike, mosquito-blinded, etc. |

- Every fish takes exactly 1 livewell slot regardless of size
- New fish types added as new resource files — zero code changes required
- Steam leaderboard for biggest fish ever caught

---

## Maps
All maps are modular — fixed core, procedural surroundings.

### Lake *(Tutorial)*
- Hazard: Big Fish Event (see its own section) — once per day, end of the day's last round
- Bird: heron or duck

### Ocean
- More money per fish than lake
- Pelican steals a random livewell fish with screech warning
- Press key when close to shoo it away
- Seagull food consumable distracts birds

### Ice Lake
- Personal cold meter fills over time
- Too cold = can't cast or loses active reel
- Sprint to icehouse to warm up
- Friend can drag you to warmth
- Bird: seagull steals fish through ice hole

### Swamp
- Mosquito lands on random player
- Screen blurs, mosquito grows until slapped
- Max size = full screen blur
- Slap yourself or have a friend slap you
- Spray consumable gives immunity
- Bird: crane

### Storm
- Lightning forms with visual warning
- Put rod away or get stunned
- Stunned while reeling = cursor locks in place but fish stays on
- Lightning rod consumable redirects strikes
- No bird

---

## Cosmetics
*Permanent, achievement-locked unlocks*
- Hat
- Life jacket color
- Rod skin
- Shoes
- Face
- Skin color
- Lures on hat and life jacket (one achievement lure equipped at a time)

---

## Microtransactions
- Boat skins only
- Never pay to win

---

## Roguelite Escalation
- Longer streak = bigger, harder, rarer fish
- Each day quota increases
- Miss quota = run over, lose screen, everyone disconnects

---

## MVP Build Order
1. GodotSteam install + Steam connection + export templates
2. GitHub setup across two machines different OS
3. Folder structure + scene tree
4. Fish data resource system
5. Casting mechanic
6. Reel minigame + QTE
7. Line tangling + tug of war
8. Shared livewell
9. Big fish event
10. Capsize minigame
11. Walkable lobby
12. Round timer + day structure
13. Quota system

Live status for this list lives in PROGRESS.md, not here — this list is the plan, PROGRESS.md is the state.

---

## Deferred Until MVP Is Fun
- Upgrades and shop
- Cosmetics and achievements
- UI polish
- Maps beyond Lake
- Hazards
- Steam leaderboard
- Microtransactions
- Fun idea, not scoped: a challenge mode combining every map's hazard at once, once all maps/hazards exist

---

## Working Convention
Two lanes, not five chats:
- **Planning** (design, scope, balancing, decisions) — a regular chat. Decisions that change the design get written into this file.
- **Build** (implementation) — Claude Code, running in this repo. See CLAUDE.md for how a Claude Code session should operate; see PROGRESS.md for current status, next steps, and open questions.

Nothing here gates commits anymore — CLAUDE.md and PROGRESS.md are the handoff between the two lanes.
