//! TowerClash EOS monitor: a terminal dashboard of EOS sessions ("listeners") and game server
//! status (connections, round-trip times, connects/drops). Dev tool; see tools/eos_monitor/README.md.
//!
//! Threads: the EOS worker owns the SDK (not thread-safe) and searches the bucket on a timer; the
//! status worker polls the game servers' `--status-port` JSON endpoints; the main thread diffs
//! both into an event log and draws the UI (ratatui). `--once` prints a text report instead.

mod eos;
mod status;

use chrono::{DateTime, Local};
use ratatui::crossterm::event::{self, Event, KeyCode, KeyEventKind};
use ratatui::layout::{Constraint, Layout};
use ratatui::style::{Color, Modifier, Style, Stylize};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Cell, List, ListItem, Paragraph, Row, Table};
use serde_json::Value;
use std::collections::{BTreeMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const HELP: &str = "eos_monitor - watch TowerClash EOS sessions and game server status

USAGE: eos_monitor [options]
  --creds PATH         eos_credentials.local.json (default: found upward from cwd/exe)
  --sdk PATH           EOS SDK library (default: the EOSG addon's DLL/dylib/so)
  --mode client|server client = device-ID login (client creds), server = dedicated-server creds
                       (default: client if client_id exists)
  --bucket NAME        session bucket (default TowerClash:QuickMatch)
  --build ID|any       only sessions with BUILD=ID (default any)
  --interval SECS      EOS search interval (default 5)
  --status HOST:PORT   poll a game server status endpoint (repeatable; default 127.0.0.1:7780)
  --status-port N      also poll <session host>:N for every session found (default 7780, 0 = off)
  --once               search once, print a report, exit (no UI)
  --snapshot SECS      run SECS seconds, then print one rendered UI frame as text and exit
Keys: q quit, r search now, c clear log";

struct Config {
    creds: PathBuf,
    sdk: PathBuf,
    server_mode: bool,
    bucket: String,
    build: Option<String>,
    interval: Duration,
    status: Vec<String>,
    status_port: u16,
    once: bool,
    snapshot: Option<u64>,
}

fn find_upwards(rel: &str) -> Option<PathBuf> {
    let mut starts = vec![std::env::current_dir().ok()?];
    if let Ok(exe) = std::env::current_exe() {
        if let Some(d) = exe.parent() {
            starts.push(d.to_path_buf());
        }
    }
    for start in starts {
        let mut dir: Option<&Path> = Some(start.as_path());
        while let Some(d) = dir {
            let p = d.join(rel);
            if p.exists() {
                return Some(p);
            }
            dir = d.parent();
        }
    }
    None
}

fn default_sdk() -> Option<PathBuf> {
    let base = "Godot/TowerClashSpike/addons/epic-online-services-godot/bin";
    let rel = if cfg!(windows) {
        format!("{base}/windows/EOSSDK-Win64-Shipping.dll")
    } else if cfg!(target_os = "macos") {
        format!("{base}/macos/libeosg.macos.template_release.framework/libEOSSDK-Mac-Shipping.dylib")
    } else {
        format!("{base}/linux/libEOSSDK-Linux-Shipping.so")
    };
    find_upwards(&rel)
}

fn parse_args() -> Result<(Config, Value), String> {
    let mut args = std::env::args().skip(1);
    let (mut creds, mut sdk, mut mode, mut build) = (None, None, None, None);
    let mut bucket = "TowerClash:QuickMatch".to_string();
    let mut interval = 5u64;
    let mut status: Vec<String> = Vec::new();
    let mut status_port = 7780u16;
    let mut once = false;
    let mut snapshot = None;
    while let Some(a) = args.next() {
        let mut val = |name: &str| args.next().ok_or(format!("{name} needs a value"));
        match a.as_str() {
            "--creds" => creds = Some(PathBuf::from(val("--creds")?)),
            "--sdk" => sdk = Some(PathBuf::from(val("--sdk")?)),
            "--mode" => mode = Some(val("--mode")?),
            "--bucket" => bucket = val("--bucket")?,
            "--build" => build = Some(val("--build")?),
            "--interval" => interval = val("--interval")?.parse().map_err(|_| "bad --interval")?,
            "--status" => status.push(val("--status")?),
            "--status-port" => status_port = val("--status-port")?.parse().map_err(|_| "bad --status-port")?,
            "--once" => once = true,
            "--snapshot" => snapshot = Some(val("--snapshot")?.parse().map_err(|_| "bad --snapshot")?),
            "-h" | "--help" => return Err(HELP.to_string()),
            other => return Err(format!("unknown option {other}\n\n{HELP}")),
        }
    }
    let creds = creds
        .or_else(|| find_upwards("eos_credentials.local.json"))
        .or_else(|| find_upwards("Godot/TowerClashSpike/eos_credentials.local.json"))
        .ok_or("no eos_credentials.local.json found (use --creds)")?;
    let sdk = sdk.or_else(default_sdk).ok_or("EOS SDK library not found (run get_eosg, or use --sdk)")?;
    let json: Value = serde_json::from_str(&std::fs::read_to_string(&creds).map_err(|e| format!("{}: {e}", creds.display()))?)
        .map_err(|e| format!("{}: {e}", creds.display()))?;
    let has_client = json.get("client_id").is_some();
    let server_mode = match mode.as_deref() {
        Some("server") => true,
        Some("client") => false,
        Some(m) => return Err(format!("--mode {m}: use client or server")),
        None => !has_client,
    };
    if status.is_empty() {
        status.push("127.0.0.1:7780".into());
    }
    let build = build.filter(|b| b != "any");
    Ok((Config { creds, sdk, server_mode, bucket, build, interval: Duration::from_secs(interval.max(1)), status, status_port, once, snapshot }, json))
}

fn credentials(json: &Value, server_mode: bool) -> Result<eos::Credentials, String> {
    let get = |k: &str| json.get(k).and_then(Value::as_str).map(str::to_string).ok_or(format!("credentials file has no {k}"));
    let (id, secret) = if server_mode { ("server_client_id", "server_client_secret") } else { ("client_id", "client_secret") };
    Ok(eos::Credentials {
        product_id: get("product_id")?,
        sandbox_id: get("sandbox_id")?,
        deployment_id: get("deployment_id")?,
        client_id: get(id)?,
        client_secret: get(secret)?,
    })
}

// ---------------------------------------------------------------- workers

enum Msg {
    EosReady { version: String, user: String, server_mode: bool },
    EosError(String),
    Sessions(Vec<eos::Session>),
    SdkLog(String),
    Status(String, Result<Value, String>),
}

fn filters(cfg: &Config) -> Vec<(String, String)> {
    cfg.build.iter().map(|b| ("BUILD".to_string(), b.clone())).collect()
}

fn eos_worker(cfg: Arc<Config>, creds: eos::Credentials, tx: Sender<Msg>, refresh: Receiver<()>) {
    let client = loop {
        match eos::Eos::start(&cfg.sdk, &creds, cfg.server_mode) {
            Ok(e) => break e,
            Err(e) => {
                let _ = tx.send(Msg::EosError(e));
                std::thread::sleep(Duration::from_secs(15));
            }
        }
    };
    let _ = tx.send(Msg::EosReady { version: client.version.clone(), user: client.user_id.clone(), server_mode: client.server_mode });
    loop {
        match client.search(&cfg.bucket, &filters(&cfg), 50) {
            Ok(list) => {
                if tx.send(Msg::Sessions(list)).is_err() {
                    return;
                }
            }
            Err(e) => {
                let _ = tx.send(Msg::EosError(e));
            }
        }
        for line in eos::drain_sdk_log() {
            let _ = tx.send(Msg::SdkLog(line));
        }
        let until = Instant::now() + cfg.interval;
        while Instant::now() < until {
            client.tick();
            if refresh.try_recv().is_ok() {
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }
}

fn status_worker(endpoints: Arc<Mutex<Vec<String>>>, tx: Sender<Msg>) {
    loop {
        let list = endpoints.lock().map(|v| v.clone()).unwrap_or_default();
        for ep in list {
            let r = status::fetch(&ep, Duration::from_millis(800));
            if tx.send(Msg::Status(ep, r)).is_err() {
                return;
            }
        }
        std::thread::sleep(Duration::from_secs(2));
    }
}

// ---------------------------------------------------------------- model

#[derive(Clone, Copy, PartialEq)]
enum Tone {
    Good,
    Warn,
    Bad,
    Info,
    Plain,
}

struct SessionRow {
    session: eos::Session,
    first_seen: DateTime<Local>,
}

#[derive(Default)]
struct StatusRow {
    last: Option<Value>,
    error: Option<String>,
    last_ok: Option<DateTime<Local>>,
    last_event_t: f64,
}

struct App {
    cfg: Arc<Config>,
    eos_line: String,
    eos_error: Option<String>,
    last_search: Option<(DateTime<Local>, usize)>,
    sessions: BTreeMap<String, SessionRow>,
    status: BTreeMap<String, StatusRow>,
    endpoints: Arc<Mutex<Vec<String>>>,
    log: VecDeque<(DateTime<Local>, String, Tone)>,
}

fn host_of(addr: &str) -> &str {
    addr.rsplit_once(':').map(|(h, _)| h).unwrap_or(addr)
}

fn unix_to_local(t: f64) -> DateTime<Local> {
    DateTime::from_timestamp(t.trunc() as i64, (t.fract() * 1e9) as u32).map(|d| d.with_timezone(&Local)).unwrap_or_else(Local::now)
}

fn tone_for(kind: &str) -> Tone {
    match kind {
        "drop" | "kick" | "reject" => Tone::Bad,
        "disconnect" => Tone::Warn,
        "connect" | "join" | "match_start" => Tone::Good,
        "eos_state" | "reset" | "server_start" | "match_end" => Tone::Info,
        _ => Tone::Plain,
    }
}

impl App {
    fn new(cfg: Arc<Config>, endpoints: Arc<Mutex<Vec<String>>>) -> App {
        let mode = if cfg.server_mode { "server" } else { "client" };
        App {
            eos_line: format!("starting EOS ({mode} mode)..."),
            cfg,
            eos_error: None,
            last_search: None,
            sessions: BTreeMap::new(),
            status: BTreeMap::new(),
            endpoints,
            log: VecDeque::new(),
        }
    }

    /// Inserts in time order: server events carry their own timestamps, which can be older than
    /// local events already logged.
    fn push(&mut self, at: DateTime<Local>, text: String, tone: Tone) {
        let idx = self.log.iter().rposition(|(t, _, _)| *t <= at).map(|i| i + 1).unwrap_or(0);
        self.log.insert(idx, (at, text, tone));
        while self.log.len() > 500 {
            self.log.pop_front();
        }
    }

    fn handle(&mut self, msg: Msg) {
        let now = Local::now();
        match msg {
            Msg::EosReady { version, user, server_mode } => {
                let who = if server_mode { "dedicated-server credentials, no user".to_string() } else { format!("user {}", short(&user, 12)) };
                self.eos_line = format!("EOS SDK {version} | {who}");
                self.eos_error = None;
                self.push(now, format!("EOS ready: SDK {version}"), Tone::Info);
            }
            Msg::EosError(e) => {
                if self.eos_error.as_deref() != Some(&e) {
                    self.push(now, format!("EOS error: {e}"), Tone::Bad);
                }
                self.eos_error = Some(e);
            }
            Msg::SdkLog(line) => self.push(now, format!("sdk: {line}"), Tone::Warn),
            Msg::Sessions(list) => self.on_sessions(list, now),
            Msg::Status(ep, r) => self.on_status(ep, r, now),
        }
    }

    fn on_sessions(&mut self, list: Vec<eos::Session>, now: DateTime<Local>) {
        self.eos_error = None;
        self.last_search = Some((now, list.len()));
        let mut seen = BTreeMap::new();
        for s in list {
            match self.sessions.get(&s.id) {
                None => {
                    let msg = format!("listener up {} ({} {})", s.host_address, s.attr("STATE"), s.attr("BUILD"));
                    self.push(now, msg, Tone::Good);
                }
                Some(old) if old.session.attr("STATE") != s.attr("STATE") => {
                    let msg = format!("{} STATE {} -> {}", s.host_address, old.session.attr("STATE"), s.attr("STATE"));
                    self.push(now, msg, Tone::Info);
                }
                _ => {}
            }
            let first = self.sessions.get(&s.id).map(|r| r.first_seen).unwrap_or(now);
            seen.insert(s.id.clone(), SessionRow { session: s, first_seen: first });
        }
        let mut gone = Vec::new();
        for (id, old) in &self.sessions {
            if !seen.contains_key(id) {
                gone.push(format!("listener gone {} ({})", old.session.host_address, short(id, 10)));
            }
        }
        for msg in gone {
            self.push(now, msg, Tone::Warn);
        }
        self.sessions = seen;
        // Poll the status endpoint next to every advertised host (plus the explicit ones).
        let mut eps = self.cfg.status.clone();
        if self.cfg.status_port != 0 {
            for r in self.sessions.values() {
                let h = host_of(&r.session.host_address);
                if !h.is_empty() {
                    let ep = format!("{h}:{}", self.cfg.status_port);
                    if !eps.contains(&ep) {
                        eps.push(ep);
                    }
                }
            }
        }
        if let Ok(mut v) = self.endpoints.lock() {
            *v = eps;
        }
    }

    fn on_status(&mut self, ep: String, r: Result<Value, String>, now: DateTime<Local>) {
        let mut new_events: Vec<(DateTime<Local>, String, Tone)> = Vec::new();
        let row = self.status.entry(ep.clone()).or_default();
        match r {
            Ok(v) => {
                let addrs = server_addrs(&v);
                if row.error.is_some() || row.last_ok.is_none() {
                    new_events.push((now, format!("[{ep}] status reachable"), Tone::Info));
                }
                if let Some(evs) = v.get("events").and_then(Value::as_array) {
                    for e in evs {
                        let t = e.get("t").and_then(Value::as_f64).unwrap_or(0.0);
                        if t > row.last_event_t {
                            let kind = e.get("kind").and_then(Value::as_str).unwrap_or("?");
                            let mut detail = e.get("detail").and_then(Value::as_str).unwrap_or("").to_string();
                            if let Some((head, addr)) = detail.rsplit_once(" from ") {
                                detail = format!("{head} from {}", tag_address(addr, &addrs));
                            }
                            new_events.push((unix_to_local(t), format!("[{ep}] {kind}: {detail}"), tone_for(kind)));
                            row.last_event_t = t;
                        }
                    }
                }
                row.last = Some(v);
                row.error = None;
                row.last_ok = Some(now);
            }
            Err(e) => {
                if row.error.is_none() && row.last_ok.is_some() {
                    new_events.push((now, format!("[{ep}] status unreachable: {e}"), Tone::Bad));
                }
                row.error = Some(e);
            }
        }
        for (at, text, tone) in new_events {
            self.push(at, text, tone);
        }
    }
}

/// True when `ip` looks like the gateway of a NAT in front of the server, e.g. Docker Desktop,
/// which relays published ports so every client appears as the bridge gateway (x.y.0.1).
/// Uses the server's own addresses when reported, else Docker's default 172.17-31.x.1 range.
fn is_nat_gateway(ip: &str, server_addrs: &[String]) -> bool {
    let o: Vec<u8> = ip.split('.').filter_map(|p| p.parse().ok()).collect();
    if o.len() != 4 || o[3] != 1 {
        return false;
    }
    let same_net = server_addrs.iter().any(|a| {
        let s: Vec<u8> = a.split('.').filter_map(|p| p.parse().ok()).collect();
        s.len() == 4 && s[0] == o[0] && s[1] == o[1] && a != ip
    });
    same_net || (o[0] == 172 && (17..=31).contains(&o[1]))
}

fn server_addrs(v: &Value) -> Vec<String> {
    v["local_addresses"].as_array().into_iter().flatten().filter_map(|a| a.as_str().map(str::to_string)).collect()
}

/// "ip:port" -> "ip:port (Docker NAT)" when the ip is a NAT gateway.
fn tag_address(addr: &str, server_addrs: &[String]) -> String {
    match addr.rsplit_once(':') {
        Some((ip, _)) if is_nat_gateway(ip, server_addrs) => format!("{addr} (Docker NAT, real IP hidden)"),
        _ => addr.to_string(),
    }
}

fn short(s: &str, n: usize) -> String {
    if s.chars().count() <= n {
        s.to_string()
    } else {
        format!("{}..", s.chars().take(n).collect::<String>())
    }
}

fn ago(t: DateTime<Local>) -> String {
    let s = (Local::now() - t).num_seconds().max(0);
    if s < 60 {
        format!("{s}s")
    } else if s < 3600 {
        format!("{}m{:02}s", s / 60, s % 60)
    } else {
        format!("{}h{:02}m", s / 3600, (s / 60) % 60)
    }
}

fn color(t: Tone) -> Color {
    match t {
        Tone::Good => Color::Green,
        Tone::Warn => Color::Yellow,
        Tone::Bad => Color::Red,
        Tone::Info => Color::Cyan,
        Tone::Plain => Color::Gray,
    }
}

// ---------------------------------------------------------------- UI

fn draw(f: &mut ratatui::Frame, app: &App) {
    let [head, sess, servers, peers, log, foot] = Layout::vertical([
        Constraint::Length(3),
        Constraint::Length((app.sessions.len() as u16).clamp(1, 8) + 3),
        Constraint::Length((app.status.len() as u16).clamp(1, 6) + 3),
        Constraint::Length(8),
        Constraint::Min(5),
        Constraint::Length(1),
    ])
    .areas(f.area());

    let search = match (&app.eos_error, app.last_search) {
        (Some(e), _) => Span::styled(format!("error: {}", short(e, 80)), Style::new().fg(Color::Red)),
        (None, Some((t, n))) => Span::raw(format!("last search {} ago, {n} found", ago(t))),
        (None, None) => Span::raw("searching..."),
    };
    let header = Paragraph::new(vec![
        Line::from(vec![Span::styled(app.eos_line.clone(), Style::new().fg(Color::Cyan)), Span::raw("  |  "), search]),
        Line::from(format!(
            "bucket {}  build {}  every {}s  status port {}",
            app.cfg.bucket,
            app.cfg.build.as_deref().unwrap_or("any"),
            app.cfg.interval.as_secs(),
            app.cfg.status_port
        ))
        .fg(Color::DarkGray),
    ])
    .block(Block::bordered().title(" TowerClash EOS monitor "));
    f.render_widget(header, head);

    let bold = Style::new().add_modifier(Modifier::BOLD);
    let rows: Vec<Row> = app
        .sessions
        .values()
        .map(|r| {
            let s = &r.session;
            let state = s.attr("STATE").to_string();
            let st = match state.as_str() {
                "open" => Style::new().fg(Color::Green),
                "in_match" => Style::new().fg(Color::Yellow),
                _ => Style::new(),
            };
            Row::new(Vec::<Cell>::from([
                Span::raw(s.host_address.clone()).into(),
                Span::styled(state, st).into(),
                s.attr("BUILD").to_string().into(),
                format!("{}/{}", s.max_slots.saturating_sub(s.open_slots), s.max_slots).into(),
                ago(r.first_seen).into(),
                short(&s.id, 14).into(),
            ]))
        })
        .collect();
    let t = Table::new(rows, [Constraint::Length(22), Constraint::Length(10), Constraint::Length(10), Constraint::Length(8), Constraint::Length(9), Constraint::Min(10)])
        .header(Row::new(vec!["Host", "STATE", "BUILD", "Filled", "Seen for", "Session"]).style(bold))
        .block(Block::bordered().title(" Listeners (EOS sessions) "));
    f.render_widget(t, sess);

    let rows: Vec<Row> = app
        .status
        .iter()
        .map(|(ep, r)| match (&r.last, &r.error) {
            (Some(v), None) => {
                let c = &v["counters"];
                let m = &v["match"];
                let match_s = if m.is_object() {
                    let phase = match m["phase"].as_str().unwrap_or("") {
                        "wave" => "",
                        "intermission" => " break",
                        p => p,
                    };
                    format!("wave {}/{}{phase}  hp {}-{}", m["round"], m["rounds"], m["base_hp"][0], m["base_hp"][1])
                } else {
                    "-".into()
                };
                Row::new(vec![
                    ep.clone(),
                    v["state"].as_str().unwrap_or("?").to_string(),
                    match_s,
                    v["peers"].as_array().map(|a| a.len()).unwrap_or(0).to_string(),
                    format!("{}/{}/{}/{}", c["connects"], c["drops_in_match"], c["rejected"], c["kicked"]),
                    v["matches_played"].to_string(),
                    format!("{}s", v["uptime_s"]),
                ])
            }
            (_, err) => Row::new(vec![ep.clone(), "unreachable".into(), short(err.as_deref().unwrap_or(""), 40), String::new(), String::new(), String::new(), String::new()])
                .style(Style::new().fg(Color::DarkGray)),
        })
        .collect();
    let t = Table::new(rows, [Constraint::Length(22), Constraint::Length(11), Constraint::Length(24), Constraint::Length(6), Constraint::Length(19), Constraint::Length(8), Constraint::Min(8)])
        .header(Row::new(vec!["Status endpoint", "State", "Match", "Peers", "Conn/Drop/Rej/Kick", "Matches", "Uptime"]).style(bold))
        .block(Block::bordered().title(" Game servers (status endpoints) "));
    f.render_widget(t, servers);

    let mut rows: Vec<Row> = Vec::new();
    for (ep, r) in &app.status {
        let Some(v) = &r.last else { continue };
        if r.error.is_some() {
            continue;
        }
        let now = v["now_unix"].as_f64().unwrap_or(0.0);
        let addrs = server_addrs(v);
        for p in v["peers"].as_array().into_iter().flatten() {
            let rtt = p["rtt_ms"].as_i64().unwrap_or(-1);
            let rtt_style = Style::new().fg(if rtt > 150 { Color::Red } else if rtt > 80 { Color::Yellow } else { Color::Green });
            let since = (now - p["connected_unix"].as_f64().unwrap_or(now)).max(0.0) as i64;
            rows.push(Row::new(Vec::<Cell>::from([
                Span::raw(ep.clone()).into(),
                Span::raw(match p["player"].as_i64() { Some(i) if i >= 0 => format!("P{}", i + 1), _ => "-".into() }).into(),
                Span::raw(p["name"].as_str().unwrap_or("").to_string()).into(),
                Span::raw(tag_address(p["address"].as_str().unwrap_or(""), &addrs)).into(),
                Span::styled(format!("{rtt} ms"), rtt_style).into(),
                Span::raw(format!("{:.1}%", p["packet_loss"].as_f64().unwrap_or(0.0) * 100.0)).into(),
                Span::raw(format!("{}m{:02}s", since / 60, since % 60)).into(),
            ])));
        }
    }
    let t = Table::new(rows, [Constraint::Length(22), Constraint::Length(4), Constraint::Length(16), Constraint::Length(44), Constraint::Length(8), Constraint::Length(7), Constraint::Min(8)])
        .header(Row::new(vec!["Server", "Seat", "Name", "Address", "RTT", "Loss", "Connected"]).style(bold))
        .block(Block::bordered().title(" Connections "));
    f.render_widget(t, peers);

    let height = log.height.saturating_sub(2) as usize;
    let items: Vec<ListItem> = app
        .log
        .iter()
        .rev()
        .take(height)
        .map(|(t, text, tone)| {
            ListItem::new(Line::from(vec![
                Span::styled(t.format("%H:%M:%S ").to_string(), Style::new().fg(Color::DarkGray)),
                Span::styled(text.clone(), Style::new().fg(color(*tone))),
            ]))
        })
        .collect();
    f.render_widget(List::new(items).block(Block::bordered().title(" Events (newest first) ")), log);
    f.render_widget(Paragraph::new(" q quit   r search now   c clear log").fg(Color::DarkGray), foot);
}

// ---------------------------------------------------------------- main

/// Ends the process without running DLL/dylib unload handlers. A normal exit (ExitProcess on
/// Windows) unloads the EOS SDK, which then waits forever on its own worker threads under the
/// loader lock - the same hang the Godot client works around with OS.kill (Godot_Spike.md, bug 9).
fn hard_exit(code: i32) -> ! {
    use std::io::Write;
    let _ = std::io::stdout().flush();
    let _ = std::io::stderr().flush();
    #[cfg(windows)]
    unsafe {
        extern "system" {
            fn GetCurrentProcess() -> *mut std::ffi::c_void;
            fn TerminateProcess(process: *mut std::ffi::c_void, exit_code: u32) -> i32;
        }
        TerminateProcess(GetCurrentProcess(), code as u32);
    }
    #[cfg(unix)]
    unsafe {
        extern "C" {
            fn _exit(code: i32) -> !;
        }
        _exit(code);
    }
    #[allow(unreachable_code)]
    std::process::exit(code)
}

fn run_once(cfg: &Config, creds: &eos::Credentials) -> i32 {
    println!("sdk: {}\ncreds: {}", cfg.sdk.display(), cfg.creds.display());
    let client = match eos::Eos::start(&cfg.sdk, creds, cfg.server_mode) {
        Ok(c) => c,
        Err(e) => {
            println!("EOS ERROR {e}");
            return 2;
        }
    };
    println!("EOS SDK {} mode={} user={}", client.version, if cfg.server_mode { "server" } else { "client" }, client.user_id);
    let mut code = 0;
    let mut eps = cfg.status.clone();
    match client.search(&cfg.bucket, &filters(cfg), 50) {
        Ok(list) => {
            println!("SESSIONS {} in bucket {}", list.len(), cfg.bucket);
            for s in &list {
                println!("  {}  STATE={} BUILD={} filled {}/{} id={}", s.host_address, s.attr("STATE"), s.attr("BUILD"),
                    s.max_slots.saturating_sub(s.open_slots), s.max_slots, s.id);
                if cfg.status_port != 0 {
                    let ep = format!("{}:{}", host_of(&s.host_address), cfg.status_port);
                    if !eps.contains(&ep) {
                        eps.push(ep);
                    }
                }
            }
        }
        Err(e) => {
            println!("SEARCH ERROR {e}");
            code = 1;
        }
    }
    for ep in eps {
        match status::fetch(&ep, Duration::from_millis(800)) {
            Ok(v) => println!("STATUS {ep}: state={} peers={} matches={} counters={}", v["state"], v["peers"].as_array().map(|a| a.len()).unwrap_or(0), v["matches_played"], v["counters"]),
            Err(e) => println!("STATUS {ep}: unreachable ({e})"),
        }
    }
    for l in eos::drain_sdk_log() {
        println!("sdk: {l}");
    }
    code
}

fn main() {
    let (cfg, json) = match parse_args() {
        Ok(x) => x,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };
    let creds = match credentials(&json, cfg.server_mode) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };
    if cfg.once {
        hard_exit(run_once(&cfg, &creds));
    }
    let cfg = Arc::new(cfg);
    let (tx, rx) = mpsc::channel::<Msg>();
    let (refresh_tx, refresh_rx) = mpsc::channel::<()>();
    let endpoints = Arc::new(Mutex::new(cfg.status.clone()));
    {
        let (cfg, tx) = (cfg.clone(), tx.clone());
        std::thread::spawn(move || eos_worker(cfg, creds, tx, refresh_rx));
    }
    {
        let (eps, tx) = (endpoints.clone(), tx.clone());
        std::thread::spawn(move || status_worker(eps, tx));
    }
    let snapshot = cfg.snapshot;
    let mut app = App::new(cfg, endpoints);
    if let Some(secs) = snapshot {
        // Headless check / bug reports: render one frame into an in-memory buffer and print it.
        let until = Instant::now() + Duration::from_secs(secs);
        while Instant::now() < until {
            while let Ok(m) = rx.try_recv() {
                app.handle(m);
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        let mut t = ratatui::Terminal::new(ratatui::backend::TestBackend::new(150, 46)).expect("test backend");
        let _ = t.draw(|f| draw(f, &app));
        let buf = t.backend().buffer();
        for y in 0..buf.area.height {
            let line: String = (0..buf.area.width).map(|x| buf[(x, y)].symbol()).collect();
            println!("{}", line.trim_end());
        }
        hard_exit(0);
    }
    let mut terminal = ratatui::init();
    loop {
        while let Ok(m) = rx.try_recv() {
            app.handle(m);
        }
        if terminal.draw(|f| draw(f, &app)).is_err() {
            break;
        }
        if event::poll(Duration::from_millis(250)).unwrap_or(false) {
            if let Ok(Event::Key(k)) = event::read() {
                if k.kind == KeyEventKind::Press {
                    match k.code {
                        KeyCode::Char('q') | KeyCode::Esc => break,
                        KeyCode::Char('r') => {
                            let _ = refresh_tx.send(());
                        }
                        KeyCode::Char('c') => app.log.clear(),
                        _ => {}
                    }
                }
            }
        }
    }
    ratatui::restore();
    hard_exit(0);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nat_gateway_detection() {
        let server = vec!["172.19.0.2".to_string(), "127.0.0.1".to_string()];
        assert!(is_nat_gateway("172.19.0.1", &server));
        assert!(!is_nat_gateway("172.19.0.5", &server));
        assert!(!is_nat_gateway("50.47.158.60", &server));
        assert!(!is_nat_gateway("192.168.0.1", &[]));
        assert!(is_nat_gateway("172.20.0.1", &[]));
        assert!(is_nat_gateway("10.42.0.1", &["10.42.0.7".to_string()]));
        assert_eq!(tag_address("50.47.158.60:7777", &server), "50.47.158.60:7777");
        assert!(tag_address("172.19.0.1:5000", &server).contains("Docker NAT"));
    }
}
