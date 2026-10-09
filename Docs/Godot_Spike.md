# Godot Spike - Results

**Dates:** 2026-09-30 to 2026-10-02 (playable app flow added 2026-10-02)
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

## What Was Built (~3,500 lines GDScript, no engine compile)

| File | Lines | Role |
|---|---|---|
| `scripts/match_sim.gd` | 384 | Authoritative rules as pure data (phases, waves, spawns, recycle queue, healer, boss minions, targeting, splash, slow, merges, win logic) |
| `scripts/net.gd` | 442 | ENet server/client autoload, RPCs, fixed-step server loop, snapshots, net stats, persistent-server reset loop |
| `scripts/online.gd` | 247 | `Online` autoload: EOS login, session search, server advertise + open/in_match state, safe exit |
| `scripts/snap_codec.gd` | 99 | Binary snapshot codec (quantised) |
| `scripts/client/arena_view.gd` | 543 | Mirrored boards, interpolation, sprites, tracers, input, bot |
| `scripts/client/hud.gd` | 114 | Match HUD + result panel (Return Home) |
| `scripts/client/app/*.gd`, `ui/ui_kit.gd` | ~1,025 | Playable app flow: splash, home (4 pages), matchmaking, summary, local profile |
| `scripts/client/dir_sprite.gd`, `sprite_sheet.gd` | 160 | Importer for the Houdini `towerclash.sprite_sheet/1` JSON + 8-direction Sprite3D |
| `scripts/client/calib_view.gd` | 91 | Sprite-vs-mesh calibration test |
| `scripts/sim_test.gd` | 66 | Offline batch sim (`--simtest`) |
| `scripts/eos_test.gd` | ~190 | EOS probe (`--eostest=server|client`) |
| `data/*.json` | - | Rules, towers, enemies, rounds (GDD values; early rounds spike-tuned) |
| `tools/*.ps1` | - | `play_local`, `run_match`, `run_eos`, `get_eosg`, `make_eos_credentials` |

Architecture follows the project rule: the server holds only data (player index, slot index,
path distance, HP). Clients spawn every visual. The server never instantiates a node per entity.

![Client 0 at 100 s](Images/Godot_Spike_Client0.png) ![Client 1 at 100 s](Images/Godot_Spike_Client1.png)

*Same moment (1x, seed 2, 100 s) on both clients. Each sees its own board at the bottom and the
opponent's board mirrored on top. Sprites are the Houdini Test_Crag sheet (8 directions, 256 px).*

---

## Playable App Flow (2026-10-02)

The client now runs the real loop instead of a test harness:
**logo splash -> title / EOS sign-in -> home -> Quick Match -> match -> result -> home with summary**,
repeating. The dedicated server persists between matches, like UE `ResetServerForNextMatch`.

![App flow](Images/Godot_Spike_App_Flow.png)

*Splash (the UE MadLee logo), home, matchmaking, match, result panel, home summary. Captured from
an EOS run with `play_local.ps1 -Shots`.*

**Client (`App`, the default when no role arg is given)**
- **Splash:** white background with the logo fade (0.6 s in / 1.4 s hold), then the "TOWER CLASH"
  title card. EOS device-ID login runs behind the title card.
- **Home:** 4 swipeable pages (Play / Deck / Profile / Settings) with a bottom tab bar.
  - Play: Quick Match, plus Ranked / Practice placeholders.
  - Deck: tower stats with sprite icons.
  - Profile: W/L/D, kills, best round, last 10 matches.
  - Settings: name, Online/Local matchmaking, local address, auto-play, reset stats.
- **Profile:** the profile is local JSON in `user://profile[_<id>].json`.
- **Matchmaking:**
  - Online mode does an EOS search for bucket `TowerClash:QuickMatch` with `BUILD=spike-1` and
    `STATE=open`, then ENet-connects to the `host_address` it finds.
  - Local mode connects to `--local=host:port`.
  - The search retries every 3 s for up to 120 s. Cancel works until the match starts.
  - A "full" server is skipped and the next host is tried.
- **Match:** the existing arena. The result panel has Return Home. On a disconnect mid-match the
  client shows "Connection lost" and returns home.

**Server**
- Advertises one EOS session and flips its `STATE` attribute `open` <-> `in_match`.
- Rejects a third player with "full" and kicks peers that never say hello (15 s).
- After a result, it waits for both players to leave (max 20 s), then resets and re-opens the
  session.
- `--max-matches=N` makes the server shut down after N matches. It destroys the EOS session first.

**Verified (Windows, localhost, 2 bot clients, 8x sim):**
- 2-match loops pass in local mode, in EOS mode and from exported release builds.
- EOS states logged in order: `in_match, open, in_match`.
- Every process exits on its own.
- The `.pck` files contain no secrets.
- `run_match` and `run_eos` still pass.

**Not verified:**
- Touch and swipe on a real device.
- Two different EOS users: all local clients share one device ID, hence one PUID.
- Stale-session cleanup after a server crash [Unverified].

**Known simplifications:**
- No EOS `JoinSession` / `register_players`. Clients only search and then connect over ENet.
- No reconnect after a drop.
- The deck is fixed.

**Balance quirk:** some seeds end in round 1 (e.g. seed 43146252 at 8x: base HP 3-0 after ~18 s
of sim time). It reproduces in the legacy `run_match.ps1`, so it is the spike bot/rules, not the
app flow.

---

## Rush Royale Baseline Restyle (2026-10-07)

The client now copies the Rush Royale look and HUD as a temporary baseline for tuning feel.
Full notes: `Art_Baseline.md`.
- Procedural toon arena, cartoon units/enemies, FX, synthesised SFX, RR-layout HUD and menus.
  All of it is client-only; the server is still pure data.
- The opponent board is now **mirrored** across the river instead of rotated 180 deg (RR layout).
- New mechanic: in-match card upgrade (GDD 3.2.4), with card levels in snapshots.
  The +25 %/level bonus is a spike assumption.
- Draw calls are kept down by `MeshBaker`: about 1,260 before, 537 max in a 7-round match after.
- New test aids:
  - `tools/check.ps1`: parse check.
  - `run_match.ps1 -InputTest`: drag-to-merge via synthetic input.
  - `--mute`: silences bot/test clients.
  - `perf` in `CLIENT_RESULT`.

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

### Server density measurement (2026-10-09)

Release Windows server export, one match, 1x real time, two headless bot clients. No
`--codec-check` and no EOS. Machine: Ryzen 9 5950X (16C/32T), 128 GB.

| | CPU (% of one core) | Working set | Private memory |
|---|---|---|---|
| Idle, waiting for players | 0.62 % | 96 MB | 57 MB |
| During a match (123 s, 4 waves) | 1.24 % (1.53 CPU-s) | 96 MB | 57 MB |

- Most of the working set is the shared executable image. Each extra server process costs
  about the **private** figure (~57 MB).
- The pure sim is a small part of the CPU: `--simtest` puts it at ~0.3-0.5 CPU-s per full match.
  The rest is the engine loop (30 Hz frames, ENet polling) plus snapshot encoding and RPC.
- Network: ~1.3 KB/s snapshot payload per client, ~3.5 KB/s per match including headers [estimate].
- Not measured yet:
  - the Linux build in a container;
  - EOS enabled on the server (the EOS SDK adds threads and memory);
  - many processes at once (scheduler and cache effects).

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
   itself, so the probe stops the autoload's processing and just quits.
8. **EOSG autoloads are required.** `eos.gd` references `EOSGRuntime` and `HAuth`, so the plugin's
   autoload set must be registered or nothing compiles.
9. **EOS exit hang.** After a real session (login, search, ENet match), `get_tree().quit()` left
   a windowless, idle process. This happened on both client and server, in every EOS run; the
   short probe escaped it.
   - A native attach (Rider LLDB) showed the main thread in `NtWaitForSingleObject(INFINITE)`.
     The caller was in a DLL already unlinked from the module list; by size this is the EOS SDK.
   - Inferred cause: the SDK shuts down during the extension unload and waits for its own
     HTTP/websocket threads under the loader lock.
   - Fix: `Online.quit()` stops the tick, logs, then calls `OS.kill(own pid)` once our own cleanup
     (session destroy) is done.
   - Revisit with EOSG upstream before shipping. Check whether mobile OSes, which rarely "quit",
     are affected at all [Unverified].

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

# Playable flow: 1 server + windowed clients (positioned side by side). Default = 2 bots, EOS.
./tools/play_local.ps1 -Bots 1            # YOU play client 0 (left window) vs a bot
./tools/play_local.ps1 -Bots 0            # two manual clients; press Quick Match in both
./tools/play_local.ps1                    # watch two bots loop forever
./tools/play_local.ps1 -Local             # skip EOS, connect straight to 127.0.0.1:7777
./tools/play_local.ps1 -Exported          # same, using the exported builds in Godot/build/
./tools/play_local.ps1 -Stop              # close everything the last launch started
./tools/play_local.ps1 -Loops 2 -TimeScale 8 -Wait -ProfilePrefix test   # unattended check, PASS line
./tools/play_local.ps1 -Loops 1 -TimeScale 2 -Wait -Shots                 # + screenshots of client 0
# Or press Play (F5) in the Godot editor: with no args it starts the client app.
# Then run a server separately: & $godot --headless --path . -- --server --eos

./tools/check.ps1                                          # parse/import check, prints script errors only
./tools/run_match.ps1 -TimeScale 8                         # headless server + 2 bots
./tools/run_match.ps1 -TimeScale 1.5 -Visual -InputTest    # client 0 merges via synthetic mouse drags
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

### macOS / Linux (shell mirrors of the PowerShell tools)

`tools/play_local.sh`, `tools/check.sh` and `tools/get_eosg.sh` take the same options as the
`.ps1` tools, in `--kebab-case`.
- Godot binary: `$GODOT`, default `/Applications/Godot.app/Contents/MacOS/Godot` on a Mac.
- Tested on Windows under Git Bash and on macOS (MacBook Pro M4 Max, 2026-10-07): `check.sh`
  passes; `play_local.sh --local --loops 1 --wait` PASS; manual play vs a bot works.
- On a fresh checkout the first `check.sh` reports 4 errors for the project font
  (`LilitaOne-Regular.ttf` is loaded before it is imported). The second run is clean.
- Retina: Godot sizes the window in physical pixels, so 540x960 showed at half size on a 2x
  screen. `main.gd` `_fit_hidpi_window()` scales the window by the screen scale on desktop,
  capped to the usable height (1.88x on a 14" MBP, rendering at 1014x1802). Mobile and
  Windows (scale 1.0) are unaffected.
- Mac perf (Metal, Forward Mobile, 120 Hz ProMotion): ~119 fps vsync-locked at 1014x1802,
  315-824 max draw calls per client in a 4x-speed bot match.

```bash
export GODOT=/Applications/Godot.app/Contents/MacOS/Godot   # if Godot 4.7.2 lives elsewhere
cd Godot/TowerClashSpike
./tools/get_eosg.sh          # once per checkout: EOSG addon (macos binaries; clears quarantine)
./tools/check.sh             # import + parse check
./tools/play_local.sh --local --bots 1    # server + you vs a bot
./tools/play_local.sh --local --bots 0    # two manual clients
./tools/play_local.sh --stop
```

- The EOS addon is needed even in local mode: the autoloads reference it.
- `eos_credentials.local.json` is git-ignored. Copy it to the Mac by hand (USB/AirDrop) if you
  want EOS mode there. Never commit it.

### Cross-machine play (LAN): Windows + Mac clients against one server

Host the server on one machine and tell it which address to advertise.
- With EOS, clients find it through session search. Without EOS, they connect straight to it.
- Each machine has its own device ID, so a Windows client and a Mac client are already
  distinct EOS users. DevAuthTool is only needed for several users on one machine.

```powershell
# Windows host (this PC's LAN IP, e.g. 192.168.0.16). Allow inbound UDP 7777 once (elevated):
#   New-NetFirewallRule -DisplayName "TowerClash dev server" -Direction Inbound -Protocol UDP -LocalPort 7777 -Action Allow -Profile Private
./tools/play_local.ps1 -ServerOnly -PublicAddress 192.168.0.16             # EOS-advertised server
./tools/play_local.ps1 -Clients 1 -Bots 0 -NoServer                         # a client here, via EOS search
```
```bash
# Mac client
./tools/play_local.sh --clients 1 --bots 0 --no-server                      # via EOS search
./tools/play_local.sh --clients 1 --bots 0 --no-server --connect 192.168.0.16:7777   # or direct
```

- Each role has its own tracking file, so client launches do not stop a `-ServerOnly` server
  on the same machine. `-Stop` / `--stop` closes all of them.

### Dedicated server in a container (Docker, Linux build)

`Godot/server/`: `Dockerfile`, `entrypoint.sh`, `compose.yaml`, `build_image.ps1`, `.env.example`.
- The image (`towerclash-server:dev`, ~256 MB) is Debian 13 slim plus the "Linux Server" export
  and the EOS libraries.
- EOSG's `libeosg` needs **glibc >= 2.38**, so Debian 12 does not work.
- EOS credentials are not in the image. `build_image.ps1` writes a **server-only**
  `eos_server_credentials.local.json` (no client secret), which compose mounts read-only.
- The server advertises `PUBLIC_ADDRESS:PORT` in the EOS session. The host port must equal `PORT`.

```powershell
cd Godot/server
./build_image.ps1                 # export Linux server + docker build (+ server creds)
copy .env.example .env            # set PUBLIC_ADDRESS (git-ignored)
docker compose up -d ; docker compose logs -f ; docker compose down
```

- Verified 2026-10-09: two Windows clients found the container through EOS session search
  (`play_local.ps1 -NoServer`) and played a full match. The session went `in_match` -> `open`
  and the server reset.
- Container usage: ~72 MB, ~2 % of a core with EOS on, Docker Desktop on Windows.
- `run/flush_stdout_on_print=true` (project.godot) makes `docker compose logs` show lines live.

### Remote test over the internet (router port forward)

1. Router: forward **UDP 7777** to this PC (192.168.0.16). Windows firewall rule
   "TowerClash dev server" (UDP 7777, Private) already exists.
2. `Godot/server/.env`: `PUBLIC_ADDRESS=<public IP>`, then `docker compose up -d`.
3. macOS clients: the "macOS Client" export preset produces a universal zip, ad-hoc signed
   (no notarization), in `build/macos_client/`.
   - Export templates: `macos.zip` taken from the official 4.7.2 `.tpz`.
   - EOSG binaries: `tools/get_eosg.ps1 -Platform macos`.
   - Ship the zip with a **client-only** `eos_credentials.local.json` placed next to the
     `.app`, plus the README.
   - Testers clear the quarantine once with `xattr -dr com.apple.quarantine TowerClashSpike.app`.
4. Close the port forward after testing: the dev server has no authentication.

Client credential lookup order:
- next to the executable;
- on macOS, next to the `.app` (files added inside a signed bundle break its signature);
- `user://`.

### Several EOS users on one machine (DevAuthTool, like UE)

The EOS SDK's DevAuthTool works the same way as with UE:
- Run it from the EOS SDK `Tools` folder (Windows and macOS builds ship with the SDK) and give it a port.
- Log in one Epic account per credential name.

Clients then use `--devauth=localhost:<port> --devcred=<name>` (launchers: `-DevAuth` /
`--devauth`, credential names `<prefix><i>`, default `Player0`, `Player1`, ...). The client then:
- logs in through EOS Auth (Developer credential) and EOS Connect via EOSG's `HAuth`;
- gets a distinct Product User ID per account.

Needs Epic Account Services enabled for the product in the Dev Portal. Implemented 2026-10-07,
not yet run [Unverified].
Exports exclude `*.local.json`. An exported build reads `eos_credentials.local.json` from next to
its executable.
