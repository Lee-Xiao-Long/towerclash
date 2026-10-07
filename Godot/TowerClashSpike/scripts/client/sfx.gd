extends Node
## Autoload "Sfx". Placeholder sound effects synthesised at startup (no audio assets yet):
## clicks, summon, merge, per-tower shots, hits, kills, coins, base hit, wave horn, stingers.
## Sfx.play(name) is throttled per sound so rapid towers do not stack into noise.
## Headless processes (dedicated server, bot test clients) build nothing and play nothing.

const RATE := 22050
const VOICES := 14

var enabled := true
var volume_db := -6.0
var _streams: Dictionary = {}
var _last: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()

# name: min seconds between plays
const THROTTLE := {
	"shot_arrow": 0.05, "shot_bolt": 0.05, "shot_dart": 0.07, "shot_bomb": 0.06, "shot_ice": 0.06,
	"hit": 0.045, "kill": 0.04, "coin": 0.06, "step": 0.1,
}


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		enabled = false
		return
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build()


func play(sound: String, pitch_jitter := 0.06, gain_db := 0.0) -> void:
	if not enabled or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sound, -10.0)) < float(THROTTLE.get(sound, 0.0)):
		return
	_last[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = volume_db + gain_db
	p.play()


# ---------------------------------------------------------------- synthesis

func _build() -> void:
	_streams.click = _wav(_tone(0.045, 1400, 900, "sine", 0.002, 0.04, 0.5))
	_streams.summon = _wav(_mix([_tone(0.16, 320, 980, "square", 0.005, 0.15, 0.22), _tone(0.2, 1600, 2400, "sine", 0.06, 0.14, 0.18)]))
	_streams.merge = _wav(_seq([[0.0, _tone(0.12, 784, 784, "sine", 0.004, 0.11, 0.4)], [0.07, _tone(0.12, 988, 988, "sine", 0.004, 0.11, 0.4)], [0.14, _tone(0.3, 1319, 1319, "sine", 0.004, 0.28, 0.45)]]))
	_streams.shot_arrow = _wav(_mix([_noise(0.06, 0.001, 0.05, 0.25, 0.35), _tone(0.05, 900, 500, "sine", 0.001, 0.05, 0.2)]))
	_streams.shot_bolt = _wav(_tone(0.14, 1800, 300, "saw", 0.002, 0.13, 0.22))
	_streams.shot_dart = _wav(_tone(0.035, 2200, 1500, "square", 0.001, 0.03, 0.12))
	_streams.shot_bomb = _wav(_mix([_tone(0.16, 180, 60, "sine", 0.002, 0.15, 0.6), _noise(0.08, 0.001, 0.07, 0.6, 0.25)]))
	_streams.shot_ice = _wav(_mix([_tone(0.16, 2600, 2400, "sine", 0.002, 0.15, 0.2), _tone(0.16, 3300, 3100, "sine", 0.01, 0.15, 0.12)]))
	_streams.hit = _wav(_noise(0.03, 0.001, 0.028, 0.5, 0.22))
	_streams.kill = _wav(_mix([_tone(0.1, 700, 160, "sine", 0.001, 0.09, 0.5), _noise(0.07, 0.001, 0.06, 0.4, 0.2)]))
	_streams.coin = _wav(_seq([[0.0, _tone(0.06, 988, 988, "square", 0.001, 0.05, 0.12)], [0.05, _tone(0.12, 1319, 1319, "square", 0.001, 0.11, 0.12)]]))
	_streams.base_hit = _wav(_mix([_tone(0.45, 110, 45, "sine", 0.002, 0.43, 0.8), _noise(0.25, 0.001, 0.24, 0.7, 0.35)]))
	_streams.horn = _wav(_mix([_tone(0.6, 220, 220, "saw", 0.04, 0.3, 0.16), _tone(0.6, 330, 330, "saw", 0.04, 0.3, 0.12), _tone(0.6, 440, 440, "sine", 0.04, 0.3, 0.12)]))
	_streams.boss = _wav(_seq([[0.0, _tone(0.35, 110, 104, "saw", 0.01, 0.3, 0.3)], [0.3, _tone(0.6, 98, 92, "saw", 0.01, 0.55, 0.3)]]))
	_streams.fail = _wav(_seq([[0.0, _tone(0.09, 330, 300, "square", 0.002, 0.08, 0.15)], [0.09, _tone(0.14, 247, 220, "square", 0.002, 0.13, 0.15)]]))
	_streams.victory = _wav(_seq([[0.0, _tone(0.14, 523, 523, "square", 0.004, 0.12, 0.16)], [0.13, _tone(0.14, 659, 659, "square", 0.004, 0.12, 0.16)],
			[0.26, _tone(0.14, 784, 784, "square", 0.004, 0.12, 0.16)], [0.39, _tone(0.6, 1047, 1047, "square", 0.004, 0.55, 0.18)]]))
	_streams.defeat = _wav(_seq([[0.0, _tone(0.22, 392, 392, "saw", 0.004, 0.2, 0.15)], [0.22, _tone(0.22, 349, 349, "saw", 0.004, 0.2, 0.15)],
			[0.44, _tone(0.7, 262, 247, "saw", 0.004, 0.65, 0.16)]]))
	_streams.upgrade = _wav(_seq([[0.0, _tone(0.1, 523, 1046, "sine", 0.003, 0.09, 0.35)], [0.08, _tone(0.25, 1046, 1568, "sine", 0.003, 0.22, 0.35)]]))
	_streams.whoosh = _wav(_noise(0.35, 0.12, 0.2, 0.15, 0.2))
	_streams.portal = _wav(_tone(0.3, 200, 420, "sine", 0.05, 0.25, 0.18))


## Mono float samples. shape: sine | square | saw. Linear pitch sweep, attack/decay envelope.
func _tone(secs: float, f0: float, f1: float, shape: String, attack: float, decay: float, amp: float) -> PackedFloat32Array:
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / secs)
		ph += f / RATE
		var x := 0.0
		match shape:
			"square":
				x = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
			"saw":
				x = fmod(ph, 1.0) * 2.0 - 1.0
			_:
				x = sin(ph * TAU)
		out[i] = x * amp * _env(t, secs, attack, decay)
	return out


## Filtered noise burst; smooth (0..1) is a one-pole low-pass amount (higher = darker).
func _noise(secs: float, attack: float, decay: float, smooth: float, amp: float) -> PackedFloat32Array:
	var n := int(secs * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y = lerpf(_rng.randf_range(-1.0, 1.0), y, smooth)
		out[i] = y * amp * _env(t, secs, attack, decay) * (1.0 + smooth)
	return out


func _env(t: float, secs: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / maxf(attack, 1e-4)
	var d := (t - attack) / maxf(decay, 1e-4)
	return maxf(0.0, 1.0 - d) * maxf(0.0, 1.0 - d) if t < secs else 0.0


func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	return out


## [[start_s, samples], ...]
func _seq(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, int(p[0] * RATE) + p[1].size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		var o := int(p[0] * RATE)
		for i in p[1].size():
			out[o + i] += p[1][i]
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
