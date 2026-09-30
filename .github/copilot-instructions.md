# TowerClash Art & Engine-Spike Workspace - Agent Guide

This repo (`D:\Dev\GameDev\MadLeeStudios\TowerClash\`) holds engine-agnostic art tooling (Houdini)
and the Godot evaluation spike for TowerClash. The shipping UE 5.7 project lives separately at
`D:\Dev\Unreal\Source5.7\Games\TowerClash\` (source-engine game folder; MLS plugin and
Documentation are separate repos cloned inside it).

**Start every session by reading `Docs/Session_Handoff.md`.**

## Rules
- Prefix shell commands with `rtk` where supported (`rtk git ...`). `rtk ls` does not work on Windows; use glob/Get-ChildItem.
- Automation of Houdini/UE/Godot: send verbose output to `*/logs/*.log`, print only a short summary to the terminal.
- No BOM marks in any file. Docs use Pascal_Casing names (e.g. `Sprite_Pipeline.md`).
- Do not create summary docs before testing. Do not guess - say "I don't know" or mark [Unverified].
- Give honest, critical feedback; correctness and maintainability over quick hacks.
- Server is pure data (PlayerIndex, SlotIndex, occupied-slot sets); clients spawn cosmetics. Keep this in any engine.

## Tools
- Houdini 22.0.368 **Indie** (`.hiplc`). hython (not on PATH):
  `& "C:\Program Files\Side Effects Software\Houdini 22.0.368\bin\hython.exe"`
- Git LFS is enabled (see `.gitattributes`) for hip/hda/images/models.
- Other DCC: Affinity suite (UI, card art, paint-overs), old Substance Painter/Designer.

## Layout
```
Houdini/hip       scenes          Houdini/scripts  hython generators
Houdini/hda       digital assets  Houdini/config   canonical constants (JSON)
Houdini/render    output (ignored) Houdini/logs    logs (ignored)
Godot/            engine spike     Docs/            handoff + pipeline docs
refs/             user reference material (existing hip, images, models)
```
