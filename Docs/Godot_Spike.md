# Godot Spike - Results

**Dates:** 2026-09-30 to 2026-10-01
**Engine:** Godot 4.7.2-stable (official build), EOSG 2.3.1 (Epic Online Services Godot GDExtension)
**Project:** `Godot/TowerClashSpike/`
**Purpose:** Step 2 of the agreed work order. Decide whether Godot can replace UE 5.7 for TowerClash.
Pass criteria came from `Session_Handoff.md`.

---

## Verdict

| Criterion | Result |
|---|---|
| Headless dedicated server + 2 clients, pure-data board, enemy path, towers, recycling | **PASS** (localhost, Windows; also from exported release builds) |
| EOS login via EOSG | **PASS**: device-ID Connect login returns a ProductUserId |
| EOS sessions (if feasible) | **PASS**: dedicated-server platform creates an advertised session; client finds it by bucket + attribute and reads `host_address` |
| iOS export running on device, binary size | **NOT DONE**: needs a Mac (Xcode). Size estimated from templates below |
| Android export | **NOT DONE**: no JDK / Android SDK on this PC. Size estimated from templates below |

No criterion "fought back". Headless server, ENet netcode and EOS sessions all work. The one hard gate
left is **iOS on a device, including EOS on iOS**. Until that runs, the switch is not proven.

Recommendation is at the end.

---

## What Was Built (~1,970 lines GDScript, no engine compile)

| File | Lines | Role |
|---|---|---|
| `scripts/match_sim.gd` | 384 | Authoritative rules as pure data (phases, waves, spawns, recycle queue, healer, boss minions, targeting, splash, slow, merges, win logic) |
| `scripts/net.gd` | ~300 | ENet server/client autoload, RPCs, fixed-step server loop, snapshots, net stats |
| `scripts/snap_codec.gd` | 99 | Binary snapshot codec (quantised) |
| `scripts/client/arena_view.gd` | 488 | Mirrored boards, interpolation, sprites, tracers, input, bot |
| `scripts/client/dir_sprite.gd`, `sprite_sheet.gd` | 160 | Importer for the Houdini `towerclash.sprite_sheet/1` JSON + 8-direction Sprite3D |
| `scripts/client/calib_view.gd` | 91 | Sprite-vs-mesh calibration test |
| `scripts/sim_test.gd` | 66 | Offline batch sim (`--simtest`) |
| `scripts/eos_test.gd` | ~190 | EOS probe (`--eostest=server|client`) |
| `data/*.json` | - | Rules, towers, enemies, rounds (GDD values; early rounds spike-tuned) |
| `tools/*.ps1` | - | `run_match`, `run_eos`, `get_eosg`, `make_eos_credentials` |

Architecture follows the project rule: the server holds only data (player index, slot index,
path distance, HP). Clients spawn every visual. The server never instantiates a node per entity.

![Client 0 at 100 s](Images/Godot_Spike_Client0.png) ![Client 1 at 100 s](Images/Godot_Spike_Client1.png)

*Same moment (1x, seed 2, 100 s) on both clients. Each sees its own board at the bottom and the
opponent's board mirrored on top. Sprites are the Houdini Test_Crag sheet (8 directions, 256 px).*

---

## Results

### Calibration (sprite importer)
- A 1 m `Calib_Box` sprite from Houdini and a real 1 m `BoxMesh` render to identical screen bboxes:
  **0 px error**. This proves `pixel_size` = cm-per-px / 100, the foot pivot and the camera-facing
  basis at 40 deg tilt. The Houdini JSON drops straight into Godot.
- VRAM import: 2048x2048 ASTC 4x4 = 4,194,356 bytes (~1 byte/px). This confirms the budget math in
  the UE `Visual_Overhaul_Plan.md`.

### Netcode (headless server + 2 bot clients)
- Real-time run (1x, seed 2): 9 rounds, `final_round` result, 244/244 kills, both clients agree
  with the server on winner, gold and base HP. Zero engine errors or warnings.
- 10+ accelerated runs (8x) across seeds: all PASS (state agreement, no errors). Matches end in
  rounds 1-9 depending on bot luck. A round-1 loss happens when one bot's early towers miss and the
  opponent's kills recycle onto it; that is gameplay variance, not desync.
- Same harness against the **exported release builds** (`-ServerExe`/`-ClientExe`): PASS.
- Offline sim (`--simtest`, 200 matches): 101/97/2 wins/losses/draws, so no side bias. Average
  4.7 rounds. ~0.23 s CPU per full match.

### Bandwidth (10 Hz snapshots, 30 Hz server tick)

| | Average | Max |
|---|---|---|
| Binary codec snapshot | 135-170 B | 425 B |
| Naive `var_to_bytes` Dictionary (for comparison) | 1,100-1,600 B | 3,444 B (> MTU) |

- Payload is ~1.4-1.7 KB/s per client. ENet/UDP/IP headers add about 0.4 KB/s [estimate]. That
  puts a 4-minute match at ~0.5 MB per client.
- The codec round-trips cleanly: 0 failures across every `--codec-check` sample.
- Snapshots are `unreliable_ordered`. A dropped snapshot only loses cosmetic shot/kill events; the
  match result goes over a reliable RPC.

### Server cost (exported Windows dedicated server, 1x, full match)
- Working set **~91 MB** (engine + loaded EOS DLL; EOS not initialised in match mode).
- CPU **3.2 % of one core** after capping `Engine.max_fps` to the tick rate. Before the cap the
  headless idle loop spun at 17.9 %. That figure still includes diagnostic work every snapshot
  (naive-size measurement, codec checks).
- So memory, not CPU, bounds one process per match. Because the sim is a plain `MatchSim` object,
  several matches per process is a cheap later option.

### EOS (EOSG 2.3.1)
- Install: `tools/get_eosg.ps1` (git-ignored addon; Windows + Linux binaries installed).
  Credentials: `tools/make_eos_credentials.ps1` reads the UE `Config/*.ini` and writes the
  git-ignored `eos_credentials.local.json`.
- Server (`--eostest=server`): `is_server`, DedicatedServer client credentials, no local user.
  Creates a session in bucket `TowerClashSpike:Global` with a nonce attribute and `host_address`.
  `update_session` takes ~0.6-0.9 s.
- Client (`--eostest=client`): device-ID create + Connect login (~0.6-0.8 s). It then searches by
  bucket + nonce, finds the session and reads `host_address = 127.0.0.1:7777`.
- Also passes from the exported release builds, with credentials placed next to the executable.
  A scan confirmed that neither secret is inside any `.pck`.
- Not tested: session join / `register_players`, Epic Account login, P2P/NAT relay, EOS on
  Android/iOS, anti-cheat.

### Export sizes (release templates, x86_64 unless noted)

| Build | Engine binary | .pck | EOS libs | Total on disk |
|---|---|---|---|---|
| Windows client | 104.2 MB exe | 8.3 MB | 20.5 MB (SDK 18.6 + eosg 1.1 + xaudio 0.8) | 133 MB |
| Windows dedicated server | 104.2 MB exe | 0.23 MB (visuals stripped) | 20.5 MB | 125 MB |
| Linux dedicated server | 70.1 MB | 0.23 MB | 28.5 MB (SDK 25.4 + eosg 3.0) | 99 MB |

Mobile, measured from the 4.7.2 templates (no export was possible):
- Android arm64 engine: `libgodot_android.so` 67.8 MB raw / **22.9 MB compressed in APK**.
  EOSG adds `libeosg` arm64 1.8 MB plus the EOS SDK `.aar` (18.4 MB, all ABIs; arm64 share
  [Unverified]).
- iOS arm64: EOSSDK.framework 11.2 MB, libeosg 1.0 MB. Engine size after App Store thinning is
  [Unverified]; it needs a Mac export.
- Estimated Android arm64 download: ~23 MB engine + ~8 MB content + EOS ~6-10 MB, so **~40 MB**
  [estimate]. A custom template with unused modules disabled would cut the engine part further
  [Unverified].
- The 8.3 MB client pck is almost entirely the two 2048x2048 test sheets (4 MB each, VRAM
  compressed). Content will dominate size, not the engine.

---

## Bugs Found and Fixed (lessons for either engine)

1. **Dictionary-in-Array removal.** `Array.has/erase` compare Dictionaries by value, so killed
   enemies were not removed reliably. Fixed by removing by id.
2. **Tower cooldown drift.** Cooldown reset to `1/rate` lost the overshoot; now `cd += 1/rate`.
3. **"Unable to send packet on channel 0, max channels: 0".** Caused by SceneMultiplayer
   `server_relay` (on by default) notifying peers that dropped in the same frame. Fixed by setting
   `server_relay = false` (clients only talk to the authority) and sending only to connected peers.
4. **Snapshots over MTU.** Naive Variant snapshots hit 1.4-3.4 KB. The binary codec brought them to
   ~150 B.
5. **`Engine.time_scale` changes outcomes.** It scales the physics delta (bigger steps), not the step
   count. Accelerated tests now run N fixed 1/30 s substeps per tick.
6. **Headless server spins a core.** No vsync when headless. Fixed by setting `Engine.max_fps` to the
   tick rate, scaled by timescale for accelerated tests so bot input latency is unchanged.
7. **EOSG shutdown segfault.** The `EOSGRuntime` autoload ticks the SDK each frame, and calling
   `PlatformInterface.release()/shutdown()` manually crashes at exit. EOSG releases on unload
   itself, so the fix is to stop the autoload's processing and just quit.
8. **EOSG autoloads are required.** `eos.gd` references `EOSGRuntime` and `HAuth`, so the plugin's
   autoload set must be registered or nothing compiles.

## Spike Assumptions (not design decisions)
- Hitscan shots; tower abilities not implemented.
- Final round waits until every enemy resolves (120 s cap). Recycled enemies spawn 1 s apart,
  during waves only.
- Base HP 3 (GDD). Early-round HP and spawn counts were lowered for the spike only
  (Scout 30, Soldier 60; R1 4+3, R2 6+4).
- Bots place a tower whenever affordable. They merge at 12+ towers or with a 15 % chance.
- All tests ran on localhost. Latency, jitter and packet loss on real networks are untested.

---

## Recommendation

**Godot is technically viable for TowerClash.** Everything testable on Windows passed: the
server/client model, the pure-data sim, EOS sessions, the Houdini sprite pipeline and dedicated
server export. It took about one working day of agent time, with no engine builds. The
iteration-speed and size advantages are real:
- text scenes and scripts the agent edits directly;
- ~0.2 s offline full-match sims;
- a server pck of 0.23 MB;
- an estimated ~40 MB Android download.

Do **not** switch on this evidence alone. Remaining gates, in order:
1. **iOS export on the MacBook.** Export the client, run on an iPhone, and log in to EOS via EOSG
   on device. If EOSG iOS fails, that is the "fights back" case.
2. **Android export** (install JDK 17 + Android SDK) with an EOS login on device.
3. **Real-network test.** Linux server on a VPS, two phones on cellular, measure RTT/jitter and
   check the 0.12 s interpolation delay.

Risks to weigh against UE's ~98 % MVP:
- **EOSG is a single-maintainer community plugin.** UE's Redpoint is commercial. EOSG 2.3.1 is
  recent and works, but the bus factor is 1.
- **Port cost.** The UE game C++ (~7k lines) and the MLS plugin (~10k lines) would be replaced.
  Much of that is engine glue and EOS lifecycle work this spike already reproduces in ~2k lines,
  but UI, abilities, return-home flow and commerce are not ported [estimate].
- Neither engine hosts servers. EOS sessions are discovery only, so hosting (VPS, Edgegap,
  Hathora, etc.) is needed with either engine.

**Security note:** the UE repo commits the EOS client secret *and* the DedicatedServer client secret
in `Config/DefaultEngine.ini` / `DedicatedServerEngine.ini`. The server secret must never ship
in a client build. Consider rotating both in the Epic Dev Portal and moving them out of
version control.

---

## How to Run

```powershell
$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
cd Godot/TowerClashSpike
./tools/get_eosg.ps1                     # once per checkout (add -Platform linux for Linux server export)
./tools/make_eos_credentials.ps1         # once; writes git-ignored eos_credentials.local.json
& $godot --headless --path . --import    # after adding addons or class_name scripts

./tools/run_match.ps1 -TimeScale 8                         # headless server + 2 bots
./tools/run_match.ps1 -TimeScale 1 -Visual -Shots "15,100" # windowed clients + screenshots
./tools/run_eos.ps1 -HoldSec 15                            # EOS server session + client search
& $godot --headless --path . -- --simtest --matches=200    # offline balance batch

# Exports (templates: Godot 4.7.2 export templates installed for windows + linux)
& $godot --headless --path . --export-release "Windows Client"
& $godot --headless --path . --export-release "Windows Server"
& $godot --headless --path . --export-release "Linux Server"
./tools/run_match.ps1 -TimeScale 8 -ServerExe ../build/windows_server/TowerClashSpikeServer.exe -ClientExe ../build/windows_client/TowerClashSpike.exe
```

Logs go to `Godot/logs/<run>_<stamp>/` and exports to `Godot/build/`; both are git-ignored.
Exports exclude `*.local.json`. An exported build reads `eos_credentials.local.json` from next to
its executable.
