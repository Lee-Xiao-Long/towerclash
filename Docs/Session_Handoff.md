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
  3D board. Ortho camera, 15 deg tilt. Spec: UE repo `Visual_Overhaul_Plan.md` and
  `Houdini_Quickstart.md`.
- Backends: EOS is staying. Commerce backend (LootLocker etc.) undecided.

## Canonical Constants (from Houdini_Quickstart.md)

| Constant | Value |
|---|---|
| Projection | Orthographic |
| Camera tilt | 15 deg from vertical (UNDER REVIEW - see findings #4) |
| Key/sun light | azimuth 135 deg, elevation 45 deg, slightly warm |
| Sprite output | PNG, sRGB, transparent bg, power-of-2 |
| Units | 1 unit = 1 cm; tower slot ~100-150 cm; board 5x3 slots per player |

## Findings From Analysis (act on these)

Sprite/visual plan issues:
1. **Directional sprites missing.** Plan renders one south-facing view, but enemies walk
   winding splines on two mirrored boards. Need >= 4 directions (8 preferred; mirror L/R).
   Multiplies frames and atlas memory - budget for it.
2. **Premultiplied alpha + Masked blend conflict.** Masked ignores partial alpha, so
   premultiplied edges go dark. For Masked: straight alpha + color dilation/edge bleed.
3. **No pixel-density or pivot standard.** Every sprite needs a fixed world-cm-per-pixel
   and a foot pivot written to metadata, else sizes/grounding drift.
4. **15 deg tilt is near top-down.** Kingdom Rush style 3/4 is ~30-45 deg. Upright
   character planes at 15 deg may read as standing cards. Decide during the quickstart lap.
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

## Step 1 Plan - Houdini Sprite Generator

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
- Final camera tilt (15 vs ~30-45 deg).
- Direction count (4 vs 8).
- Commerce backend choice.
