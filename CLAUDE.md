# Fish With Friends — Claude Code Context

This file is auto-loaded by Claude Code at the start of every session in this repo. Read it, GDD.md, and PROGRESS.md before making changes.

## What this repo is
Fish With Friends: chaotic co-op fishing game, 1-4 players, solo playable, Steam-only. Godot 4 + GodotSteam. Full design spec is in GDD.md — treat it as the source of truth for mechanics, art direction, and scope. Don't re-derive design decisions from scratch; read GDD.md first.

## How work is split
- Design, scope, and balancing decisions happen in a separate planning chat (not here) and get written into GDD.md when decided.
- This Claude Code session is for implementation: writing GDScript, building scenes, wiring systems together, testing, committing.
- If a genuine design question comes up mid-build (not just an implementation detail you can reasonably infer from GDD.md) — don't guess and don't stall. Log it under "Open Questions" in PROGRESS.md, make the most reasonable call to keep moving, and flag it clearly to Nick so it can get resolved in the planning chat.

## Session workflow
1. Start by reading PROGRESS.md — check "Next Up" and "Open Questions" before starting work.
2. Implement in small, working increments. Prefer several small commits over one large one.
3. Before ending the session, update PROGRESS.md: check off finished items, note what's in progress, update "Next Up" for the following session, and add anything to "Open Questions" or "Session Log."

## Conventions
- GDScript style: match existing files — tabs for indentation, snake_case for members/functions, `class_name` + `extends` at the top of scripts that need it, typed variables where the codebase already does this.
- Fish content: new fish types are new `.tres` resource files under `data/fish/` — zero code changes required (per GDD.md's Fish Data section). Don't hardcode new species in scripts.
- Networking: host-authoritative for fish spawns, event triggers, livewell state, boat physics, tangle detection. Clients own their own rod locally and send cast position to host. See GDD.md's Multiplayer section before touching `autoload/network_manager.gd`.
- Architecture stubs: some scripts are intentionally placeholders (e.g. comments like "architecture stub" or "future dispatch"). Check a file's own header comment before assuming a system is fully wired up — file size and commit history are not reliable signals of completeness.
- Two dev machines, different OS (Linux + Windows) — avoid anything that hardcodes a path separator or OS-specific behavior without a guard.
- **Commit messages and PROGRESS.md Session Log entries: keep them short and human.** One or two sentences — what changed and why it mattered, in plain language. Not a paragraph, not a root-cause essay. If a bug's fix genuinely needs more explanation to be useful later, put the detail in Code Review Findings or Open Questions instead, where someone's about to make a decision and needs it — the commit log and session log are a quick scan of history, not a report.
