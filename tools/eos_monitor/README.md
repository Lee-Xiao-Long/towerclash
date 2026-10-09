# eos_monitor

A small Rust terminal dashboard for TowerClash online testing. It shows:
- **Listeners:** the EOS sessions in the `TowerClash:QuickMatch` bucket, with host address,
  `STATE` (open / in_match), `BUILD` and how long each has been seen.
- **Game servers:** each dedicated server's status endpoint: state, wave and hearts, peer
  count, connects/drops/rejects/kicks, matches played and uptime.
- **Connections:** every connected peer, with seat, name, address, round-trip time, packet loss
  and time connected.
- **Events:** listeners appearing and disappearing, `STATE` flips, and the servers' own events
  (connect, join, match start/end, disconnect, **drop**, reject, kick, reset), in time order.

EOS only knows the session advertisement. Connections and drops come from the game server's
`--status-port` endpoint (`Godot/TowerClashSpike/scripts/server_status.gd`).

## Build

Needs Rust (`rustup`, stable). On Windows the MSVC toolchain needs Visual Studio's C++ build tools.

```bash
cd tools/eos_monitor
cargo build --release          # -> target/release/eos_monitor(.exe)
```

## Run

```bash
target/release/eos_monitor                     # dashboard; q quit, r search now, c clear log
target/release/eos_monitor --once              # one search + status poll, text report
target/release/eos_monitor --snapshot 20       # run 20 s, print one rendered frame as text
target/release/eos_monitor --help
```

Defaults are found by walking up from the current directory and from the executable:
- **Credentials:** `Godot/TowerClashSpike/eos_credentials.local.json`, or one in the current
  directory.
  - Client credentials mean **client mode**: device-ID login, the same as the game.
  - With only server credentials it uses **server mode**: no user. `--mode` overrides.
- **EOS SDK:** the EOSG addon's library, so run `get_eosg` first. `--sdk` overrides.
  - Windows: `.../bin/windows/EOSSDK-Win64-Shipping.dll`
  - macOS: `.../bin/macos/libeosg.macos.template_release.framework/libEOSSDK-Mac-Shipping.dylib`
  - Linux: `.../bin/linux/libEOSSDK-Linux-Shipping.so`
- **Status endpoints:**
  - always `127.0.0.1:7780`, the container's mapping;
  - plus `<session host>:7780` for every session found (`--status-port 0` turns this off);
  - plus any `--status HOST:PORT`.

The status endpoint has no authentication. The container publishes it on `127.0.0.1` only, so
connections and drops are visible on the machine that runs the server. From elsewhere you see the
EOS listeners only, unless you tunnel the port.

## Implementation notes

- `src/eos.rs` holds hand-written FFI for the EOS C SDK: platform, Connect device-ID login and
  session search.
  - Layouts come from the EOS SDK 1.18 headers (in the UE source tree:
    `Engine/Source/ThirdParty/EOSSDK/SDK/Include`).
  - Verified against the EOSG-bundled SDK 1.19.1 on Windows.
  - The SDK is loaded at runtime with `libloading`, so no link step or import library is needed.
- **The SDK is never unloaded and the process ends with `TerminateProcess` / `_exit`.**
  Unloading the EOS SDK (FreeLibrary / normal process exit) blocks forever on its worker threads.
  This is the same hang the Godot client avoids with `OS.kill` (`Docs/Godot_Spike.md`, bug 9).
- The EOS SDK is not thread-safe, so one worker thread owns it. Status polling has its own thread;
  the UI runs on the main thread (ratatui).

## Status

- Windows: built and tested 2026-10-09 against the live container session (client and server
  mode) and a local server with a status endpoint, including a real drop.
- macOS: not built or run yet [Unverified]. It should build unchanged with `cargo build --release`.
