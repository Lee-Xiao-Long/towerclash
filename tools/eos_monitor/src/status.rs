//! Polls a game server's read-only status endpoint (Godot `--status-port`): a plain HTTP GET that
//! returns one JSON document (peers, counters, recent events). std networking only.

use serde_json::Value;
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

pub fn fetch(endpoint: &str, timeout: Duration) -> Result<Value, String> {
    let addr = endpoint
        .to_socket_addrs()
        .map_err(|e| format!("resolve: {e}"))?
        .next()
        .ok_or("no address")?;
    let mut s = TcpStream::connect_timeout(&addr, timeout).map_err(|e| format!("connect: {e}"))?;
    s.set_read_timeout(Some(timeout)).ok();
    s.set_write_timeout(Some(timeout)).ok();
    s.write_all(format!("GET / HTTP/1.0\r\nHost: {endpoint}\r\n\r\n").as_bytes())
        .map_err(|e| format!("send: {e}"))?;
    let mut buf = Vec::new();
    s.read_to_end(&mut buf).map_err(|e| format!("read: {e}"))?;
    let text = String::from_utf8_lossy(&buf);
    let body = text.split_once("\r\n\r\n").map(|(_, b)| b).ok_or("no HTTP body")?;
    serde_json::from_str(body).map_err(|e| format!("json: {e}"))
}
