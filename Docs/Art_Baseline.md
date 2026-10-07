# Art Baseline - Rush Royale Copy (Godot spike)

**Started:** 2026-10-07
**Status:** temporary baseline. The look copies Rush Royale (RR) so mechanics, HUD and
"feel" (sound, shake, impact) can be tuned first. TowerClash's own art direction and gameplay
twist come later and will replace this.
**Project:** `Godot/TowerClashSpike/`. References: `refs/images/` (RR phone screenshots).

---

## What the Reference Does (analysis of refs/images)

| Area | Rush Royale | Implemented here |
|---|---|---|
| Board | 5x3 light-green checker grid, diamond studs at the joints, light stone frame with corner posts, coloured gate mid-wall (blue mine, red opponent) | Same, procedural (`ArenaArt`) |
| Path | Wide sand lane on three sides; purple swirl portal bottom-left, stone castle bottom-right | Same; the lane follows `BoardLayout` |
| Two boards | Opponent board is **mirrored** across a river (portal also on the left), not rotated | Mirrored (was rotated 180 deg in the spike) |
| Middle band | River with a rubber duck, hearts per side, wave and timer | River shader, duck, hearts, wave/timer pill |
| Units | Round coloured pad per unit, cartoon character, merge rank marks | Pad + ring + chibi figure + gold rank pips |
| Enemies | Small cartoon monsters, **HP numbers** (no bars) next to them | Round critters with eyes, HP numbers |
| Bottom HUD | Mana count, big yellow summon button with cost, 5 deck cards with L.x and upgrade cost, avatar | Same (`Hud`) |
| Top HUD | Opponent deck row with L.x, opponent avatar + name plate | Same |
| Menus | Deep blue patterned background, chunky buttons with a darker bottom lip, white text with dark outline, yellow primary, wooden panels, bottom tab bar with raised Battle | Same (`UiKit`, `HomeScreen`) |
| Result | Ribbon banner (VICTORY), wooden player panels, blue Continue | Ribbon + wood card (`ResultCard`) |
| Font | Chunky rounded display face | Lilita One (OFL, Google Fonts) as the theme font |

Palette tokens live in `UiKit` (UI) and `ArenaArt` (world). All colours are placeholders.

---

## Implementation (client only; the server is unchanged pure data)

| File | Role |
|---|---|
| `scripts/client/art/toon.gd` | Cached toon materials (banded diffuse, rim on characters only), inverted-hull outlines, primitive mesh helpers, font |
| `scripts/client/art/arena_art.gd` | Arena, environment, light, river, portals, castles, scenery; `board_world()` mirroring |
| `scripts/client/art/figures.gd` | Unit and enemy placeholders from the `look` blocks in `data/towers.json` / `data/enemies.json` |
| `scripts/client/art/mesh_baker.gd` | Merges primitives into vertex-coloured meshes, cached per type as PackedScenes |
| `scripts/client/art/fx.gd` | Projectiles per `look.shot`, sparks, puffs, rings, recycle orb, camera shake |
| `scripts/client/art/figure_icons.gd` | Card/portrait textures rendered from the same 3D figures (offscreen SubViewport) |
| `scripts/client/sfx.gd` | Autoload `Sfx`: placeholder sounds synthesised at startup; silent when headless or `--mute` |
| `scripts/client/hud.gd` | RR-layout match HUD, banners, toasts, result |
| `scripts/client/ui/*.gd` | `UiKit` style kit, `Glyph` vector icons, `Avatar`, `ResultCard` |
| `scripts/client/app/*.gd` | Splash, home (5 tabs), matchmaking, summary in the same style |
| `assets/shaders/*.gdshader` | River water, portal swirl |
| `assets/fonts/` | Lilita One + OFL licence |

**Feel / feedback list** (what to tune when testing on a device):
- Summon: the unit pops in (elastic scale), a ring and a summon sound.
- Merge: drag lifts the unit, which follows the finger; valid targets (same type and rank) pulse.
  The result pops with a puff and a chime.
- Shots: a projectile per tower style (arrow, bolt, dart, arcing bomb, ice shard). The tower
  recoils with a squash.
- Hits and kills:
  - Hit: the enemy flashes white and squashes.
  - Kill: a puff and a pop sound.
  - Recycled kill: a purple orb arcs over the river into the opponent's portal, which pulses.
- Base hit: the castle shakes, plus a red puff, camera shake, a red screen flash, a heart pop and a boom.
- Waves: a "Wave N" ribbon and a horn. A boss wave gets a red "BOSS WAVE" ribbon and a rumble.
  The boss enters with a big pop, a ring and a shake.
- UI: every button squashes and clicks; mana pops when it rises; card upgrades pop with a chime.
  Failures show a toast ("Not enough mana!") and shake the summon button.

## Mechanics Added for the HUD

- **In-match card upgrade** (GDD 3.2.4 "tower type upgrade: 100/200/400"): tap a deck card to
  raise that unit type's level for all its towers.
  - Code: `MatchSim.request_upgrade`, `Net.request_upgrade`.
  - Card levels travel in snapshots (codec: one u8 per deck slot); decks travel in `match_info`.
  - **Spike assumption:** +25 % damage per level (`rules.card_upgrade_damage_bonus`). The GDD
    gives only the costs.
- Bots (client bot and `--simtest`) upgrade occasionally. Simtest with 100 matches:
  51/48/1 wins/losses/draws, so there is no side bias.

## Differences From RR That Stay (GDD decisions, not copied)

- Killed enemies are recycled to the opponent (GDD core twist). RR has no recycling.
- Merge ranks max 3 (`rules.max_tower_level`). RR goes to 7.
- Camera tilt is 40 deg (Canonical.json). RR looks almost top-down. This is why figures face the
  camera and only lean toward targets.
- "Gold" in data/server = the mana shown in the HUD (icon only, no word, so there is no rename yet).

## Performance (Windows, RTX 3090, 540x960 window, bot match)

| | Before baking | After `MeshBaker` |
|---|---|---|
| Max draw calls (whole match) | ~1,260 (2-round match) | 537 (7-round match), ~330 early |

- This is still high for low-end mobile. The next step, if needed, is MultiMesh per enemy
  type or fewer outline passes. Measure on a device first.
- `CLIENT_RESULT` logs `perf` (max draw calls, objects, fps) for every test match.

## Swapping in Real Art Later

- Units and enemies: replace the `look` blocks (or `Figures.tower/creature`) with Houdini
  sprite sheets (`DirSprite`, already supported) or glTF models. The view only needs `root`,
  `body` and `pips`.
- The arena is self-contained in `ArenaArt.build()`. A baked Houdini glTF board can replace it
  as long as `board_world()` stays the mapping.
- UI: `UiKit` constants and `Glyph` drawings are the only style sources. Swap to a Theme
  resource and textures when real UI art exists.
- Sounds: `Sfx` keys (`click`, `summon`, `merge`, `shot_<kind>`, `hit`, `kill`, `coin`,
  `base_hit`, `horn`, `boss`, `fail`, `victory`, `defeat`, `upgrade`) can load real audio files
  instead of synthesising.

## Known Gaps

- No real-device touch test yet. Drag-to-merge is verified through the real input path with
  synthetic mouse events: `run_match.ps1 -Visual -InputTest` (2026-10-07: 14 drags, 14
  server merges, 0 failures). Touch relies on Godot's default touch-to-mouse emulation [Unverified on device].
- Bot matches often end in wave 1-2 (recycle snowball with 3 hearts). This is a rules/balance
  issue, already noted in `Godot_Spike.md` "Balance quirk", not a visual one.
- Arena progression on home (1 arena per 5 wins) and Shop/Co-Op are placeholders.
