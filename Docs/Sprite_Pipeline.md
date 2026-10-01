# Sprite Pipeline

Houdini (hython) generator that renders an asset into directional sprite sheets + JSON metadata.
Engine-agnostic: UE and Godot importers consume the JSON later.

## Run

```powershell
$h = "C:\Program Files\Side Effects Software\Houdini 22.0.368\bin\hython.exe"
& $h Houdini\scripts\sprite_gen.py --asset StandIn_Blocky        # full render + pack
& $h Houdini\scripts\sprite_gen.py --asset StandIn_Blocky --skip-render   # re-pack existing EXRs
& $h Houdini\scripts\sprite_gen.py --asset StandIn_Blocky --dirs S,E --anims Walk  # debug subset
& $h Houdini\scripts\sprite_gen.py --asset StandIn_Blocky --tilt 45 --anims Walk   # tilt experiment (_Tilt45 output)
& $h Houdini\scripts\sprite_gen.py --asset Calib_Box; & $h Houdini\scripts\check_calibration.py
& $h Houdini\scripts\make_test_crag_hip.py; & $h Houdini\scripts\sprite_gen.py --asset Test_Crag   # hip-source test
```

Terminal gets a 3-4 line summary; everything else (incl. husk) goes to `Houdini/logs/sprite_<Asset>.log`.
Outputs (git-ignored): `Houdini/render/<Asset>/<Asset>_Sheet.png|json`, raw EXRs in `frames/`.
The generated scene is saved to `Houdini/hip/Sprite_<Asset>.hiplc` for inspection.

## Files

| File | Role |
|---|---|
| `Houdini/config/Canonical.json` | Project constants: camera tilt, key/fill light, cm-per-pixel, directions, alpha mode, max sheet size. Conventions are written inside the file. |
| `Houdini/config/assets/<Asset>.json` | Per asset: source (procedural builder or hip + SOP path), cell size, foot pivot, animations (frames, fps, loop, parms to set). |
| `Houdini/scripts/sprite_gen.py` | Entry: build asset -> Solaris camera/lights/Karma -> render per (animation, direction) -> pack. |
| `Houdini/scripts/sprite_builders.py` | Procedural stand-ins (`blocky_standin`, `calibration_box`). |
| `Houdini/scripts/sprite_pack.py` | EXR -> straight alpha, sRGB, edge bleed, atlas packing, JSON. numpy/OIIO/PIL only. |
| `Houdini/scripts/check_calibration.py` | Projects the 100 cm calibration cube analytically and compares to the render (tolerance 1 px). |

## Asset contract

- Units cm, +Y up, feet on Y=0, pivot at the origin, facing +Z (toward camera) at yaw 0.
- Animations must be in place (no root motion); the game moves the sprite.
- Animation is driven by parms on a node (`set_parms` in the asset config) and the timeline frame
  (`frame_start` + `frames`).
- Hip sources: `"source": {"type": "hip", "hip": "<repo-relative .hiplc>", "sop": "/obj/x/OUT", "parm_node": "/obj/x"}`
  (`parm_node` optional, defaults to the SOP's parent). Verified with `Test_Crag` (see below).
- Materials: primitive `shop_materialpath` pointing at VOP materials (e.g. Principled Shader) is
  supported, including packed prims and materials inside locked HDAs. Point/detail material
  attributes are not bound (logged as a warning).
- The source hip is only read; the generator adds `__sprite_*` nodes and saves a copy as
  `Houdini/hip/Sprite_<Asset>.hiplc`.

### Test_Crag (hip-source test asset)

`Houdini/scripts/make_test_crag_hip.py` writes `Houdini/hip/Test_Crag.hiplc` from Houdini's built-in
Crag (packed pieces, textured VOP materials from an HDA, `$FF` animation), with root motion removed
and scaled to ~85 cm. Config `Test_Crag.json`: 192 px cell, 10 frames. Not game art - it only
exercises the hip path.

## How it works

- Camera: ortho, pitch `-(90 - tilt)`. Placed analytically so the world origin lands exactly on
  `pivot_px`; ortho width = `cell_w * cm_per_pixel`. Verified by `check_calibration.py` (0.4 px error).
- H22 camera LOP scales the aperture parm by 0.01 before writing USD; the generator measures the
  factor and asserts the USD value.
- Directions: 8 (decided 2026-09-30, for diagonal movement). The asset is rotated (camera and sun
  stay fixed), so lighting stays world-consistent.
  `mirror_west: true` renders only S..N and marks W-side directions `flip_x` (halves memory, but the
  mirrored sprites are lit from the wrong side - off by default).
- Materials (H22 findings): sopimport's "Create and Bind" modes do not translate SOP-level VOP
  materials, and a `materiallibrary` whose `matnet` points at another network produces nothing.
  So the generator copies each used material node into a `materiallibrary` LOP
  (`/materials/sprite/m<i>/<name>`), freezes string parms that resolved relative to the original
  location (`opdef:`/`../`, e.g. HDA-embedded textures), writes `usdmaterialpath` in the wrapper
  (sopimport binds from that attribute, not `shop_materialpath`), and imports with `bindblock`.
  It fails loudly if a material prim is missing or nothing got bound.
- Render: Karma CPU via `usdrender_rop` with `allframesatonce` (one husk per animation x direction).
  StandIn_Blocky (8 dirs x 20 frames, 128 px) = ~100 s.
- Post: un-premultiply, linear -> sRGB, 8-bit, straight alpha with full edge bleed (transparent pixels
  carry the nearest opaque color, so Masked/bilinear sampling gets no dark fringes). Warns if any
  frame touches the cell border (clipping). `content_rect` in the JSON is the union alpha bbox, useful
  for shrinking cells.
- Sheets: row = (animation, direction), column = frame; power-of-2; if the combined sheet exceeds
  `max_sheet_px` it splits into one sheet per animation.

## Lighting calibration (Karma default displayColor material)

Empirical, white-ish albedo 0.8, per unit intensity: distant key gives ~0.105 linear per unit cos,
dome gives ~0.35 on an up-facing face. Key exposure 2.5 + fill 0.8 puts a sun-facing top face at
~0.59 linear (sRGB ~201) and the camera-facing front at ~0.45. Tune in `Canonical.json`; the board's
baked lighting in-engine must be matched by eye later [Unverified against UE/Godot].

## Known limits / open items

- Camera tilt decided 2026-09-30: 40 deg (`--tilt N` still available for experiments).
- Light azimuth 135 deg is defined screen-relative here (decided). The arena isn't designed yet;
  match the level sun to it once the arena orientation exists.
- 12-frame walk x 128 px cells -> 1536 px wide, padded to 2048 (25% waste). Consider 8/16-frame
  cycles or non-pow2 sheets if the target compression allows.
- No blob shadow / ground contact rendered (engine decal per plan).
- **Cell size vs memory (open):** 8 directions per animation means per-animation sheets are
  (frames x cell) wide by 8 x cell tall. 3-anim enemy: 128 px = 1.75 MB (ASTC 4x4), 256 px = 7 MB;
  4-anim boss: 256 px = 9 MB; 512 px cells exceed the 2048 cap. Budget analysis in UE
  `Visual_Overhaul_Plan.md` (Texture Memory Budget).
- Engine importers (UE DataTable/MI, Godot SpriteFrames) not written yet.
