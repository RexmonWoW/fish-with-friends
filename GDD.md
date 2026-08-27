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
- 3D toon art style
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
*(Lake map only)*
- Boat shakes, everyone must cast at big fish within time limit
- Stardew style cursor, each player maintains their own
- All players must hold long enough together to catch
- **Fail:** capsizes, lose 2 biggest fish from livewell, triggers capsize minigame
- **Success:** big fish enters its own reserved slot, bonus money, does not take a livewell slot

---

## Capsize Minigame
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
| Players | Multiplier |
|---|---|
| 1 | 1.0x |
| 2 | 1.6x |
| 3 | 2.1x |
| 4 | 2.5x |

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
- Big fish event active
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

---

## Working Convention
Two lanes, not five chats:
- **Planning** (design, scope, balancing, decisions) — a regular chat. Decisions that change the design get written into this file.
- **Build** (implementation) — Claude Code, running in this repo. See CLAUDE.md for how a Claude Code session should operate; see PROGRESS.md for current status, next steps, and open questions.

Nothing here gates commits anymore — CLAUDE.md and PROGRESS.md are the handoff between the two lanes.
