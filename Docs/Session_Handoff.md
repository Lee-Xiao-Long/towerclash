# Session Handoff

**Created:** 2026-09-29 (carried over from a Copilot CLI session run inside the UE project repo)
**Agreed work order:** 1) Houdini sprite generator -> 2) Godot spike (done 2026-10-01, see
`Godot_Spike.md`; playable app flow added 2026-10-02) -> 3) overall doc update (UE repo doc drift below) -> back to UE / iOS device test

---

## Current State / Next Action (updated 2026-10-09, before the user went mobile on the MacBook)

### Where things are

- The Godot spike (`Godot/TowerClashSpike/`) is restyled to copy **Rush Royale** as a temporary
  baseline for tuning mechanics and feel.
  - Look: arena, cartoon units/enemies, FX, synthesised SFX, RR HUD, menus.
  - Details: `Docs/Art_Baseline.md`. Run instructions: `Docs/Godot_Spike.md` "How to Run".
- Rules: early waves eased (simtest: games ending in waves 1-2 went 47% -> 11%). In-match card
  upgrade at +25 % per level (user: keep it). Wave 4 is the next difficulty cliff; tuning methods
  come later.
- **Online works end to end over the internet** (2026-10-09):
  - Server: a Docker container on the Windows PC (`Godot/server/`, Debian 13 + Linux export
    + EOS). It advertises the public IP through an EOS session.
  - The router forwards UDP 7777 to the Windows PC.
  - Client: the macOS build, through a VPN. It found the server via EOS search and played a match.
  - Next: the user plays the remote colleague, both on Macs.
- Server cost (measured): ~1.2 % of one core and ~57 MB private per match; container ~72 MB
  with EOS on. See `Godot_Spike.md` "Server density measurement".

### Picking this up on the Mac (Claude Code session on the MacBook)

1. `git pull`. The Windows session committed everything; the user pushes from Windows.
2. `cd Godot/TowerClashSpike && ./tools/get_eosg.sh && ./tools/check.sh`.
   - The EOS addon is git-ignored and needed even offline.
   - `get_eosg.sh` and `play_local.sh` were only tested under Git Bash on Windows; this is their
     first real macOS run.
3. Run locally: `./tools/play_local.sh --local --bots 1`. `GODOT=` overrides the Godot path
   (default `/Applications/Godot.app/Contents/MacOS/Godot`).
4. Join the Windows container from the Mac:
   - by EOS: `./tools/play_local.sh --clients 1 --bots 0 --no-server`;
   - directly: add `--connect 50.47.158.60:7777`.
   - EOS mode needs `eos_credentials.local.json` copied by hand (client-only is fine). Never commit it.
5. Mac build for testers: `Godot/build/macos_client/` on the Windows PC (`TowerClashSpike.zip`
   + client-only `eos_credentials.local.json` + `README.txt`). Exporting on a Mac would need
   macOS export templates installed there.

### Open items / next actions

- **Fixed 2026-10-09, untested on a Mac:** the window was half off a MacBook screen and its
  position was not remembered.
  - `App._place_window()` now fits the 9:16 window inside the usable screen area and centres it.
  - The window rect is saved to the profile on quit and restored when it is still on a screen.
  - The macOS zip was re-exported with this fix. Check on the Mac that it opens fully on screen,
    and that after moving it and quitting (Cmd+Q / window close) it reopens in the same place.
- **In progress: EOS session monitor (Rust)**. User request: a small local app to watch EOS
  sessions (listeners), active connections and drops. Plan:
  1. **Godot server status endpoint**, not started.
     - `--status-port=N` on the server: a tiny HTTP JSON endpoint with uptime, state, peers
       (name, address, RTT), connect/disconnect/drop counters and recent events.
     - EOS knows nothing about the ENet links, so connections and drops must come from the server.
     - The container maps the status port to `127.0.0.1` only.
  2. **Rust TUI** in `tools/eos_monitor/` (cargo, ratatui), not started.
     - Loads the EOS SDK at runtime (`libloading`): `EOSSDK-Win64-Shipping.dll` or
       `libEOSSDK-Mac-Shipping.dylib` from the EOSG addon folder.
     - Searches bucket `TowerClash:QuickMatch` (all `STATE`s), reading `host_address` and
       attributes; polls each reachable server's status endpoint.
     - Logs appear/disappear/state changes, connects and drops.
     - FFI: hand-written from EOS SDK 1.18 headers. On Windows they live in the UE source tree
       (`D:\Dev\Unreal\Source5.7\Engine\Source\ThirdParty\EOSSDK\SDK\Include`), not on the Mac.
     - Structs need `#pragma pack(8)` (= `repr(C)` on x64/arm64). Check `EOS_GetVersion()` at
       runtime against the header API versions.
     - Session search needs a LocalUserId: device-ID Connect login with the client credentials,
       same as the game client.
     - Rust 1.99 (MSVC) is installed on the Windows PC (winget `Rustlang.Rustup`).
- **Cleanup after testing:**
  - Remove the router UDP 7777 forward; the dev server has no authentication.
  - Stop the container: `docker compose down` in `Godot/server`. It auto-restarts until then.
- Still open from before:
  - Doc step 3: UE repo doc drift (list below). Also record that the Godot spike mirrors the
    opponent board instead of rotating it.
  - The iOS export/device test, which gates the engine decision (`Godot_Spike.md` "Recommendation").
  - Later idea: Rust for hot paths. The measurements say the game sim is a small slice of server
    CPU; see the density notes.

### Earlier state (2026-10-03, kept for context)

- Steps 1 and 2 are done: the Houdini sprite generator, and the Godot spike with its playable flow.
- The engine decision is pending the iOS device test.
- Agreed next step: step 3, the UE doc update
  (`D:\Dev\Unreal\Source5.7\Games\TowerClash\Documentation\GAME_PROJECTS\TowerClash\`).
- **Agent tooling:** the session moved from GitHub Copilot CLI to Claude Code on 2026-10-03.
  The agent guide is shared: `.github/copilot-instructions.md`, imported by `CLAUDE.md`.

## Project Context (short)

- TowerClash: competitive 1v1 mobile tower defense (iOS first, then Android; PC/web later).
  3-5 min matches, one-tap random tower placement, enemies killed once are recycled to the
  opponent, boss rounds, base HP win condition. Full design: UE repo
  `Documentation/GAME_PROJECTS/TowerClash/GDD.md`.
- Shipping project: UE 5.7 source build, `D:\Dev\Unreal\Source5.7\Games\TowerClash\`.
  MVP ~98%: match loop, EOS session lifecycle (Redpoint EOS), return-home, DataTable rounds,
  bosses, targeting modes all working in PIE. ~7k lines game C++ + ~10k lines MLS plugin
  (`Plugins/MadLeeMultiplayerPlugins/MadLeeMultiplayerCore`, reusable across games).
- Architecture: server tracks pure data only; clients spawn cosmetic actors. Mirrored view:
  each client sees own board at bottom, opponent's flipped on top.
- Visual target: 2.5D. Unlit pre-rendered sprites (from Houdini) on a lit, statically-baked
  3D board. Ortho camera, 40 deg tilt (decided 2026-09-30). Spec: UE repo `Visual_Overhaul_Plan.md` and
  `Houdini_Quickstart.md`.
- Backends: EOS is staying. Commerce backend (LootLocker etc.) undecided.

## Canonical Constants (source of truth: `Houdini/config/Canonical.json`)

| Constant | Value |
|---|---|
| Projection | Orthographic |
| Camera tilt | 40 deg from vertical (decided 2026-09-30, was 15) |
| Key/sun light | azimuth 135 deg (from screen lower-right), elevation 45 deg, slightly warm. Arena orientation not designed yet; match the level sun to this screen-space direction later |
| Sprite output | PNG, sRGB, transparent bg, power-of-2 |
| Units | 1 unit = 1 cm; tower slot ~100-150 cm; board 5x3 slots per player |

## Findings From Analysis (act on these)

Sprite/visual plan issues:
1. **Directional sprites missing.** RESOLVED 2026-09-30: 8 directions for towers, enemies and
   bosses; generator renders them. Memory impact recorded in UE `Visual_Overhaul_Plan.md` budget.
2. **Premultiplied alpha + Masked blend conflict.** Masked ignores partial alpha, so
   premultiplied edges go dark. For Masked: straight alpha + color dilation/edge bleed.
3. **No pixel-density or pivot standard.** Every sprite needs a fixed world-cm-per-pixel
   and a foot pivot written to metadata, else sizes/grounding drift.
4. **15 deg tilt is near top-down.** RESOLVED 2026-09-30: tilt set to 40 deg after comparison
   renders (15/30/45); UE spec docs updated to match.
5. UE code gives each sprite actor its own MID and ticks `CurrentFrame`. OK for now; later
   use Custom Primitive Data + material time offset to batch and drop ticks.
6. Recommendation: bake environment in Houdini and export (glTF/FBX) rather than live
   in-engine HDAs - keeps the pipeline engine-agnostic until the engine decision.

UE doc drift (for step 3, doc cleanup - UE repo `Documentation/GAME_PROJECTS/TowerClash/`):
- Visual overhaul marked PLANNED, but `TowerClashSpriteAnimator`, `TowerClashViewportManager`,
  `TowerClashArenaVolume`, `EnemyVisualData` exist; Lumen already disabled in DefaultEngine.ini.
- Sprite rotation: docs `FRotator(-75,0,0)` vs code `FRotator(0,90,15)`.
- `EOS_Session_Lifecycle.md` says 5s cleanup timer; code/other docs say 0.5s.
- `Mirrored_View_Architecture.md` is empty (2 bytes) but linked from README.
- BOMs present in `README.md`, `EOS_Session_Lifecycle.md`, `MVP_Completion_Plan.md` (violates no-BOM rule).
- GDD says UE 5.6; GDD min iOS 12 vs `Config/IOS/IOSEngine.ini` `IOS_13` vs UE 5.7 minimum iOS 15 (per Epic docs).
- `.uproject` `TargetPlatforms` lacks IOS/Android. GDD 500 MB / 2 GB RAM targets are tight for UE.

## Engine Assessment (Godot vs UE) - summary

- Godot fits this game's profile (unlit 2.5D, mobile-first, tiny binaries, web export,
  text scenes the agent can edit directly, no engine compile). UE's strengths (Lumen,
  Nanite) are all disabled here.
- UE keeps: mature replication/dedicated server, Redpoint EOS (UE-only), existing MLS plugin
  and hard-won EOS lifecycle.
- Godot EOS options: community EOSG (github.com/3ddelano/epic-online-services-godot), "Godot EOS"
  asset-library plugin. EOSG dedicated-server sessions verified in the spike (2026-10-01). Nakama worth a look as
  an alternative backend (auth/matchmaking/storage/leaderboards).
- Decision via **3-5 day spike** (step 2). Pass criteria:
  - Headless dedicated server + 2 clients, pure-data board, enemy path, towers, recycling
  - EOS login via EOSG (sessions if feasible)
  - iOS export running on device; note binary size
  - If EOS sessions or headless server fight back -> stay on UE with confidence.
- The Houdini sprite pipeline is engine-agnostic; proceed regardless.

## Step 2 Status (2026-10-01) - Godot spike done (Windows-testable criteria PASS)

Full results: `Docs/Godot_Spike.md`. Project: `Godot/TowerClashSpike/`.
- PASS: headless authoritative server + 2 bot clients over ENet, pure-data sim, path, towers,
  merges, recycling, mirrored boards. Real-time full match with client/server state agreement;
  also passes from exported release builds.
- PASS: EOS via EOSG 2.3.1. Device-ID Connect login, dedicated-server session advertised and
  found by client search (`host_address` read back).
- Numbers: snapshots ~150 B (binary codec) at 10 Hz, ~2 KB/s per client including headers
  [estimate]. Server ~91 MB RAM, ~3 % of a core. Linux server export 99 MB incl. EOS. Houdini
  sprite JSON imports with 0 px calibration error.
- NOT DONE: iOS export (needs Mac), Android export (no JDK/SDK here). Estimated Android arm64
  download ~40 MB [estimate].
- Recommendation: Godot is viable, but do not switch until iOS export + EOS login runs on an
  iPhone (EOSG is a single-maintainer plugin). Then Android, then a real-network test.
- Security: the UE repo commits the EOS client and DedicatedServer secrets in `Config/*.ini`.
  Consider rotating them and moving them out of version control.

## Step 2b Status (2026-10-02) - Godot spike playable app flow

The spike now simulates the real product loop. Details: `Godot_Spike.md` "Playable App Flow".
- Client flow: MadLee logo splash -> title + EOS sign-in -> home (Play/Deck/Profile/Settings,
  swipe + tabs) -> Quick Match (EOS search, open servers only) -> match -> result -> home with
  summary.
- Persistent dedicated server: it resets between matches and flips the EOS session
  `STATE` open/in_match.
- Launcher: `Godot/TowerClashSpike/tools/play_local.ps1`.
  - `-Bots 1` puts you against a bot; `-Local` skips EOS; `-Exported` uses the release builds;
    `-Stop` closes everything.
  - `-Loops N -Wait` runs an unattended check that prints a PASS line.
- Verified: local mode, EOS mode and exported builds (2-match bot loops); `run_match` and
  `run_eos` still pass.
- Found and fixed: the process hung at exit after real EOS use (EOS SDK shutdown during
  extension unload). The workaround is a hard exit after cleanup; it is a revisit item for
  EOSG upstream.
- Next on the spike, short of iOS:
  - Android export on a device (install JDK 17 + Android SDK) with touch/swipe UX.
  - Linux server on a VPS (`--public-address`) for a real-network test.
  - Two distinct EOS users: Epic Account or per-device IDs.
  - Deck editing.
  - Real art in the arena.

## Step 1 Status (2026-09-29) - generator working end-to-end

Done and verified - details in `Docs/Sprite_Pipeline.md`:
- `sprite_gen.py` + `Canonical.json` + per-asset configs. StandIn_Blocky: 8 dirs x (Idle 8 + Walk 12)
  at 128 px, 0.75 cm/px -> 2048x2048 sheet + JSON in ~100 s.
- Camera/pivot math verified with `Calib_Box` + `check_calibration.py` (0.4 px error).
- Straight alpha + full edge bleed (resolves finding #2), fixed cm-per-pixel + foot pivot in JSON
  (finding #3), 8 directions via asset yaw with optional west mirroring (finding #1).
- Tilt decided: 40 deg (user chose 30-45; 40 picked as best character read vs board depth).
  Re-rendered StandIn_Blocky (no border clipping, content rows 15-118 of 128) and Calib_Box
  (0.33 px error, PASS) at 40 deg.
- Light: 135 deg / 45 deg kept; arena not designed yet, so engine sun mapping is deferred.
- Hip source path verified (2026-09-30) with `Test_Crag` (built-in Crag: packed prims, textured VOP
  materials inside an HDA): 8 dirs x 10 frames at 192 px in ~137 s. Needed fixes for material
  binding and HDA texture paths (details in `Sprite_Pipeline.md`); generated nodes now `__sprite_*`.
- Plan after step 1: finish sprite gen -> Godot spike -> overall doc update -> back to UE
  (sprite plane rotation `FRotator(-50,0,0)` vs code `FRotator(0,90,15)` checked then).
- Policy: older spec docs (UE repo Documentation) are updated as decisions are made.
  Done for tilt/light in `Houdini_Quickstart.md`, `Visual_Overhaul_Plan.md`, `CURRENT_STATUS.md`.
  Sprite plane rotation in docs is now `FRotator(-50,0,0)`; code still uses `FRotator(0,90,15)`
  [Unverified which is right for UE's Plane mesh - check in-engine].

Next for step 1:
- First real game asset through the pipeline (needs art: a character hip following the asset
  contract - in-place animation, cm units, facing +Z, feet at origin).
- Optional: engine importer for the JSON once the engine is chosen.

## Step 1 Plan - Houdini Sprite Generator (original)

Goal: hython-driven, data-driven generator that renders an asset to directional sprite atlases.
- `Houdini/config/Canonical.json` - camera tilt, light az/el/color, cm-per-pixel, directions.
- `Houdini/scripts/` - hython entry script: load hip/HDA -> set canonical ortho cam + key light
  -> per direction x per animation render frames (Karma) -> Copernicus/COP atlas pack with
  edge bleed -> write `<Asset>_Sheet.png` + `<Asset>_Sheet.json` (grid, anim ranges per
  direction, pivot, cm-per-pixel). Logs to `Houdini/logs/`.
- Start with a procedural blocky stand-in character so the loop runs end-to-end without art.
- Existing user scene: `refs/Houdini/TowerClash.hiplc` (not yet inspected).
- Engine importers (UE DataTable/MI or Godot resources) consume the JSON later.

## Open Questions
- **Engine decision (Godot vs UE):** pending the iOS device test from `Godot_Spike.md` (user's MacBook).
- **Cell size + budget DECIDED 2026-09-30:** 256 px for towers, enemies, bosses (enemy/boss judged
  on MacBook Retina clarity test); texture budget raised 64 -> ~160 MB (~153 MB all content,
  <= ~145 MB per match); load per match (deck towers only). Still to do: confirm on a low-end
  device (iPhone SE 3 / 2 GB Android). Clarity page rebuild: render `Test_Crag --cell 128|256|512
  --dirs S,SE,E` (+ `--max-sheet 8192 --skip-render` for 256/512), then `python Houdini/scripts/make_clarity_test.py`.
- Commerce backend choice.
- Arena world orientation (determines the level sun yaw that matches the 135 deg sprite light).
