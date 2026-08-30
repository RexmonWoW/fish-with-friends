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
- **Visuals are Nick's own work — modeling, texturing, painting, shaders, lighting/atmosphere.** See GDD.md's Art + Tone section. Don't build or improve any of that unless explicitly asked, even in service of another task — keep placeholder meshes/materials simple and swappable and move on.
- **Any dev cheat, debug shortcut, or test-only backdoor (e.g. the debug console) must be added to PROGRESS.md's Pre-Release Checklist the same session it's added.** Easy to forget one exists by the time release is near — the checklist is the only thing that catches it.
- **Keep PROGRESS.md and commit messages short — this is a hard rule, not a suggestion.** Nick reads these and does not want to read paragraphs. Every Session Log entry is **ONE line**, full stop — if it doesn't fit on one line, cut detail until it does, don't wrap to a second sentence. Every other PROGRESS.md bullet (MVP list, Next Up, Open Questions, Code Review Findings) is 1-2 short sentences max, same bar. Commit messages: a one-line summary; a body only if genuinely needed, and even then 2-3 short lines, not a report. If a bug's fix needs real explanation to be useful later, that detail goes in Open Questions (a live decision someone needs) — never used as an excuse to let a Session Log line grow. When in doubt, cut it shorter than feels natural.
