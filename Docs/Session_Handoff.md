# Session Handoff

**Created:** 2026-09-29 (carried over from a Copilot CLI session run inside the UE project repo)
**Agreed work order:** 1) Houdini sprite generator -> 2) Godot spike -> 3) UE doc cleanup

---

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
1. **Directional sprites missing.** RESOLVED 2026-09-30: 8 directions (diagonal movement) for moving
   units; generator renders them. Memory impact recorded in UE `Visual_Overhaul_Plan.md` budget.
   Multiplies frames and atlas memory - budget for it.
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
  asset-library plugin. Dedicated-server session maturity [Unverified]. Nakama worth a look as
  an alternative backend (auth/matchmaking/storage/leaderboards).
- Decision via **3-5 day spike** (step 2). Pass criteria:
  - Headless dedicated server + 2 clients, pure-data board, enemy path, towers, recycling
  - EOS login via EOSG (sessions if feasible)
  - iOS export running on device; note binary size
  - If EOS sessions or headless server fight back -> stay on UE with confidence.
- The Houdini sprite pipeline is engine-agnostic; proceed regardless.

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
- **Enemy/boss cell size vs memory budget (flagged in UE `Visual_Overhaul_Plan.md`).** With 8 dirs:
  enemies at 256 px ~7 MB each (total ~75 MB > 64 MB budget); at 128 px ~1.75 MB (total ~44 MB) but
  only 1.6x clarity margin. Bosses at the plan's 512 px can't fit a 2048 sheet (Walk row 4096 px).
  Options: 128/256 cells, fewer frames, bigger budget/4096 sheets. Decide after an on-device test.
- Do towers need directional frames (turrets aiming)?
- Commerce backend choice.
- Arena world orientation (determines the level sun yaw that matches the 135 deg sprite light).
