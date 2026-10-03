class_name App
extends Node
## Client flow: Splash -> Home -> Matchmaking -> Arena -> Home (with match summary), looping.
## User args (after "--"):
##   --profile=<id>   separate user://profile_<id>.json (several clients on one machine)
##   --name=<name>    override the profile name for this run
##   --bot            auto-play: presses Quick Match itself and plays with the spike bot
##   --loops=N        quit after N matches (0 = never); for unattended runs
##   --local=host:port  skip EOS and connect straight to a server (like UE UseLocalServerConnection)
##   --online         force EOS matchmaking regardless of the profile setting
##   --app-shots=<dir>  save one screenshot per screen (splash, home pages, matchmaking, match, result)

const SEARCH_TIMEOUT_S := 120.0
const CONNECT_TIMEOUT_S := 6.0
const RETRY_S := 3.0

var profile: Profile
var bot := false

var _splash: SplashScreen
var _home: HomeScreen
var _mm: MatchmakingScreen
var _arena: ArenaView
var _fader: ColorRect
var _matches := 0
var _loops := 0
var _search_id := 0
var _net_event := ""
var _my_index := -1
var _shots_dir := ""
var _shots_taken := {}


func _ready() -> void:
	var a := Net.args
	GameData.ensure_loaded()
	profile = Profile.open(a.get("profile", ""))
	if a.has("name"):
		profile.data.name = a.name
		profile.save()
	bot = a.has("bot") or bool(profile.setting("autoplay"))
	_loops = int(a.get("loops", "0"))
	_shots_dir = str(a.get("app-shots", ""))
	if _shots_dir != "":
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	Net.joined.connect(func(i): _my_index = i; _net_event = "joined")
	Net.disconnected.connect(func(): _net_event = "disconnected")

	var fl := CanvasLayer.new()
	fl.layer = 100
	add_child(fl)
	_fader = ColorRect.new()
	_fader.color = Color(0, 0, 0, 0)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(UiKit.full_rect(_fader))

	_home = HomeScreen.new()
	_home.profile = profile
	_home.connection_note = _connection_note()
	_home.visible = false
	_home.play_pressed.connect(_play)
	add_child(_home)
	_mm = MatchmakingScreen.new()
	_mm.visible = false
	_mm.cancel_pressed.connect(_cancel)
	add_child(_mm)
	_splash = SplashScreen.new()
	add_child(_splash)
	_boot()


func _fade(to_black: bool, secs := 0.25) -> void:
	var t := create_tween()
	t.tween_property(_fader, "color:a", 1.0 if to_black else 0.0, secs)
	await t.finished


## --app-shots=<dir>: saves each named screen once (docs / visual checks).
func _shot(shot_name: String, delay := 0.0) -> void:
	if _shots_dir == "" or _shots_taken.has(shot_name):
		return
	_shots_taken[shot_name] = true
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots_dir.path_join(shot_name + ".png"))
	Net.log_line("APP shot " + shot_name)


# ---------------------------------------------------------------- connection mode

func _mode() -> String:
	if Net.args.has("local"):
		return "local"
	if Net.args.has("online"):
		return "online"
	if profile.setting("connection") == "online" and Online.has_credentials():
		return "online"
	return "local"


func _local_address() -> String:
	return str(Net.args.get("local", profile.setting("local_address")))


func _connection_note() -> String:
	if _mode() == "online":
		return "Online - EOS session search"
	var note := "Local server %s" % _local_address()
	if profile.setting("connection") == "online" and not Online.has_credentials():
		note += "  (no EOS credentials)"
	return note


# ---------------------------------------------------------------- boot / home

func _boot() -> void:
	_shot("01_splash_logo", 0.9 if not bot else 0.4)
	await _splash.run_logo(bot)
	var title_shown := Time.get_ticks_msec()
	if _mode() == "online":
		_splash.set_status("Signing in to Epic Online Services...")
		var ok: bool = await Online.login(str(profile.data.name))
		_splash.set_status("Signed in" if ok else "Sign-in failed: %s" % Online.last_error)
	else:
		_splash.set_status("Offline mode - local server")
	_shot("02_title", 0.45)
	# Keep the title card up long enough to read.
	var left := (600 if bot else 1800) - (Time.get_ticks_msec() - title_shown)
	if left > 0:
		await get_tree().create_timer(left / 1000.0).timeout
	await _fade(true)
	_splash.queue_free()
	_show_home({}, false)
	await _fade(false)
	if _shots_dir != "":
		for i in 4:
			_home.show_page(i, false)
			await _shot("%02d_home_page%d" % [3 + i, i])
		_home.show_page(0, false)


func _show_home(entry: Dictionary, with_summary: bool) -> void:
	_home.connection_note = _connection_note()
	_home.refresh()
	_home.show_page(0, false)
	_home.visible = true
	if with_summary:
		_home.show_summary(entry, 3.0 if bot else 0.0)
	if bot:
		if _loops > 0 and _matches >= _loops:
			Net.log_line("APP done: %d matches" % _matches)
			await get_tree().create_timer(1.0).timeout
			_quit()
			return
		var me := _search_id
		await get_tree().create_timer(4.5 if with_summary else 1.5).timeout
		if me == _search_id and _home.visible:
			_home.close_summary()
			_play()


func _quit() -> void:
	Net.leave()
	Online.quit(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


# ---------------------------------------------------------------- matchmaking

func _play() -> void:
	if _mm.visible:
		return
	_search_id += 1
	var me := _search_id
	_mm.open()
	_home.visible = false
	_shot("07_matchmaking", 0.5)
	Net.log_line("APP quick match (%s)" % _mode())
	var deadline := Time.get_ticks_msec() + int(SEARCH_TIMEOUT_S * 1000)
	if _mode() == "online":
		if Online.puid == "":
			_mm.set_status("Signing in...")
			if not await Online.login(str(profile.data.name)):
				_fail(me, "Sign-in failed", Online.last_error)
				return
			if me != _search_id:
				return
		while Time.get_ticks_msec() < deadline:
			_mm.set_status("Searching for a match...", "EOS session search")
			var hosts: Array = await Online.find_open_servers()
			if me != _search_id:
				return
			for h in hosts:
				if await _try_connect(me, h):
					return
				if me != _search_id:
					return
			_mm.set_status("Searching for a match...", "No open servers yet - retrying")
			await get_tree().create_timer(RETRY_S).timeout
			if me != _search_id:
				return
	else:
		while Time.get_ticks_msec() < deadline:
			if await _try_connect(me, _local_address()):
				return
			if me != _search_id:
				return
			await get_tree().create_timer(RETRY_S).timeout
			if me != _search_id:
				return
	_fail(me, "No match found", "Is a server running? See tools/play_local.ps1.")


## Connects and waits for the welcome. On success the arena is created behind the
## matchmaking screen, which stays up until the first snapshot (both players in).
func _try_connect(me: int, addr: String) -> bool:
	var colon := addr.rfind(":")
	var host := addr if colon < 0 else addr.substr(0, colon)
	var port := Net.DEFAULT_PORT if colon < 0 else int(addr.substr(colon + 1))
	_mm.set_status("Connecting...", addr)
	_net_event = ""
	if not Net.start_client(host, port, profile.data.deck, str(profile.data.name)):
		_mm.set_status("Connecting...", "Could not open a connection to %s" % addr)
		return false
	var t := 0.0
	while _net_event == "" and t < CONNECT_TIMEOUT_S:
		await get_tree().process_frame
		t += get_process_delta_time()
		if me != _search_id:
			return false
	if _net_event != "joined":
		var why := "server is full" if Net.reject_reason == "full" else ("rejected: " + Net.reject_reason if Net.reject_reason != "" else "no answer")
		Net.log_line("APP connect %s failed (%s)" % [addr, why])
		_mm.set_status("Connecting...", "%s - %s" % [addr, why])
		Net.leave()
		return false
	_mm.set_status("Waiting for opponent...", "Connected to %s as player %d" % [addr, _my_index + 1])
	_start_arena()
	return true


func _start_arena() -> void:
	_arena = ArenaView.new()
	_arena.app_mode = true
	_arena.force_bot = bot
	_arena.match_started.connect(_on_match_started)
	_arena.finished.connect(_on_arena_finished)
	add_child(_arena)
	Net.match_info_received.connect(_on_match_info, CONNECT_ONE_SHOT)


func _on_match_info(names: Array) -> void:
	if _mm.visible and _my_index >= 0:
		_mm.set_status("Opponent found!", "vs %s" % names[1 - _my_index])


func _on_match_started() -> void:
	_mm.lock_cancel()
	_shot("08_opponent_found")
	await get_tree().create_timer(0.6).timeout
	if _mm.visible:
		_mm.fade_out()
	_shot("09_match", 6.0)


func _on_arena_finished(res: Dictionary) -> void:
	var me := _my_index
	await _shot("10_result")
	await _fade(true)
	Net.leave()
	if _arena != null:
		_arena.queue_free()
		_arena = null
	_mm.visible = false
	var entry := {}
	if not res.is_empty() and me >= 0:
		entry = profile.record(res, me)
		_matches += 1
		Net.log_line("APP match %d recorded: %s" % [_matches, entry.result])
	_search_id += 1
	_show_home(entry, true)
	await _fade(false)
	_shot("11_summary", 0.3)


func _cancel() -> void:
	_search_id += 1
	Net.leave()
	if _arena != null:
		_arena.queue_free()
		_arena = null
	if Net.match_info_received.is_connected(_on_match_info):
		Net.match_info_received.disconnect(_on_match_info)
	_mm.visible = false
	_show_home({}, false)


func _fail(me: int, title: String, detail: String) -> void:
	if me != _search_id:
		return
	Net.log_line("APP matchmaking failed: %s %s" % [title, detail])
	Net.leave()
	_mm.set_status(title, detail)
	await get_tree().create_timer(3.0).timeout
	if me == _search_id and _mm.visible:
		_cancel()
