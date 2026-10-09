class_name ServerStatus
extends RefCounted
## Opt-in, read-only HTTP status endpoint for the dedicated server (--status-port=N), polled by
## the EOS monitor (tools/eos_monitor). Any GET returns one JSON snapshot: uptime, state, peers
## (name, address, round-trip time), counters and the most recent events.
## EOS only knows the session advertisement; connections and drops live here.
## There is no auth: keep it off the public internet (the container maps it to 127.0.0.1 only).

const MAX_EVENTS := 100
const REQUEST_TIMEOUT_MS := 1000
## Event kinds that bump a counter of the same meaning.
const COUNTED := {"connect": "connects", "disconnect": "disconnects", "drop": "drops_in_match",
	"reject": "rejected", "kick": "kicked", "match_start": "matches_started", "match_end": "matches_finished"}

var events: Array = []
var counters := {"connects": 0, "disconnects": 0, "drops_in_match": 0, "rejected": 0, "kicked": 0,
	"matches_started": 0, "matches_finished": 0, "status_requests": 0}
var started_unix := Time.get_unix_time_from_system()

var _tcp := TCPServer.new()
var _pending: Array = []   # [{peer: StreamPeerTCP, at: msec}]


func listen(port: int) -> Error:
	return _tcp.listen(port, "*")


func event(kind: String, detail := "") -> void:
	events.append({"t": snappedf(Time.get_unix_time_from_system(), 0.01), "kind": kind, "detail": detail})
	while events.size() > MAX_EVENTS:
		events.pop_front()
	if COUNTED.has(kind):
		counters[COUNTED[kind]] += 1


## Call every frame. snapshot_fn() -> Dictionary is only evaluated when a request is answered.
func poll(snapshot_fn: Callable) -> void:
	while _tcp.is_connection_available():
		_pending.append({"peer": _tcp.take_connection(), "at": Time.get_ticks_msec()})
	for p in _pending.duplicate():
		var peer: StreamPeerTCP = p.peer
		peer.poll()
		var st := peer.get_status()
		if st != StreamPeerTCP.STATUS_CONNECTED:
			_pending.erase(p)
			continue
		var waited := Time.get_ticks_msec() - int(p.at)
		if peer.get_available_bytes() == 0 and waited < REQUEST_TIMEOUT_MS:
			continue
		if peer.get_available_bytes() > 0:
			peer.get_data(peer.get_available_bytes())   # request line/headers are not needed
		counters.status_requests += 1
		var snap: Dictionary = snapshot_fn.call()
		snap["counters"] = counters
		snap["events"] = events
		snap["status_started_unix"] = started_unix
		var body := JSON.stringify(snap).to_utf8_buffer()
		var head := ("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n" +
			"Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n") % body.size()
		peer.put_data(head.to_utf8_buffer())
		peer.put_data(body)
		peer.disconnect_from_host()
		_pending.erase(p)


func stop() -> void:
	for p in _pending:
		(p.peer as StreamPeerTCP).disconnect_from_host()
	_pending.clear()
	_tcp.stop()
