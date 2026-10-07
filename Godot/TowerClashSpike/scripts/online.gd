extends Node
## Autoload "Online". Thin EOS (EOSG) wrapper used by the playable flow:
##   client: platform init -> device-ID Connect login -> session search for an open server
##   server: platform init (DedicatedServer creds) -> advertise one session, flip its STATE
##           attribute open/in_match between matches.
## Nothing here is required for the direct-connect test paths; it is only used on demand.
## The step order mirrors scripts/eos_test.gd, which is the regression probe for it.

signal status(text: String)

const CREDS_FILE := "eos_credentials.local.json"
const BUCKET := "TowerClash:QuickMatch"
const SESSION_NAME := "TowerClashMatch"
## Clients only match servers that advertise the same build id (protocol compatibility).
const BUILD_ID := "spike-1"
const STATE_OPEN := "open"
const STATE_IN_MATCH := "in_match"

var platform_ready := false
var is_server := false
var puid := ""
var last_error := ""

var _session_live := false
var _state_target := ""
var _state_applied := ""
var _state_worker := false


func credentials_path() -> String:
	var p := "res://" + CREDS_FILE
	if FileAccess.file_exists(p):
		return p
	# Exports exclude *.local.json, so a built game reads the file placed next to the executable.
	return OS.get_executable_path().get_base_dir().path_join(CREDS_FILE)


func has_credentials() -> bool:
	return FileAccess.file_exists(credentials_path())


func _fail(msg: String) -> bool:
	last_error = msg
	Net.log_line("EOS ERROR " + msg)
	return false


## Synchronous. Safe to call more than once.
func init_platform(as_server: bool) -> bool:
	if platform_ready:
		return true
	if not has_credentials():
		return _fail("no credentials (%s)" % CREDS_FILE)
	var c = JSON.parse_string(FileAccess.get_file_as_string(credentials_path()))
	if typeof(c) != TYPE_DICTIONARY:
		return _fail("bad credentials file")
	var key_id := "server_client_id" if as_server else "client_id"
	var key_secret := "server_client_secret" if as_server else "client_secret"
	if not c.has(key_id) or not c.has(key_secret):
		return _fail("credentials file has no %s" % key_id)
	var init := EOS.Platform.InitializeOptions.new()
	init.product_name = "TowerClashSpike"
	init.product_version = "0.2"
	var r: EOS.Result = EOS.Platform.PlatformInterface.initialize(init)
	if not (EOS.is_success(r) or r == EOS.Result.AlreadyConfigured):
		return _fail("initialize " + EOS.result_str(r))
	EOS.Logging.set_log_level(EOS.Logging.LogCategory.AllCategories, EOS.Logging.LogLevel.Warning)
	var co := EOS.Platform.CreateOptions.new()
	co.product_id = c.product_id
	co.sandbox_id = c.sandbox_id
	co.deployment_id = c.deployment_id
	co.client_id = c[key_id]
	co.client_secret = c[key_secret]
	co.encryption_key = c.encryption_key
	co.is_server = as_server
	co.flags = EOS.Platform.PlatformFlags.DisableOverlay
	if not EOS.Platform.PlatformInterface.create(co):
		return _fail("create_platform")
	platform_ready = true
	is_server = as_server
	Net.log_line("EOS platform ready (%s)" % ("server" if as_server else "client"))
	return true


# ---------------------------------------------------------------- client

## Device-ID Connect login. Returns true when a Product User ID is available.
## Note: every process on one OS account shares the device ID, so two local clients log in as
## the same EOS user. Fine for search-only matchmaking; real accounts come later.
## --devauth=host:port --devcred=<name> logs in through the EOS SDK DevAuthTool instead (Epic
## account per credential name, like UE's DevAuthTool flow), so local clients get distinct users.
func login(display_name: String) -> bool:
	if puid != "":
		return true
	if not platform_ready and not init_platform(false):
		return false
	status.emit("Signing in...")
	if Net.args.has("devauth"):
		return await _login_devauth(str(Net.args.devauth), str(Net.args.get("devcred", "")))
	var dopt := EOS.Connect.CreateDeviceIdOptions.new()
	dopt.device_model = "%s %s" % [OS.get_name(), OS.get_model_name()]
	EOS.Connect.ConnectInterface.create_device_id(dopt)
	var dr = await IEOS.connect_interface_create_device_id_callback
	if not (EOS.is_success(dr) or int(dr.result_code) == EOS.Result.DuplicateNotAllowed):
		return _fail("create_device_id " + EOS.result_str(dr))
	var lo := EOS.Connect.LoginOptions.new()
	lo.credentials = EOS.Connect.Credentials.new()
	lo.credentials.type = EOS.ExternalCredentialType.DeviceidAccessToken
	lo.credentials.token = null
	lo.user_login_info = EOS.Connect.UserLoginInfo.new()
	lo.user_login_info.display_name = display_name
	EOS.Connect.ConnectInterface.login(lo)
	var lr: Dictionary = await IEOS.connect_interface_login_callback
	var id: String = lr.get("local_user_id", "")
	if int(lr.result_code) == EOS.Result.InvalidUser:
		var cu := EOS.Connect.CreateUserOptions.new()
		cu.continuance_token = lr.continuance_token
		EOS.Connect.ConnectInterface.create_user(cu)
		var cr: Dictionary = await IEOS.connect_interface_create_user_callback
		if not EOS.is_success(cr):
			return _fail("create_user " + EOS.result_str(cr))
		id = cr.get("local_user_id", "")
	elif not EOS.is_success(lr):
		return _fail("connect_login " + EOS.result_str(lr))
	if id == "":
		return _fail("no product user id")
	puid = id
	Net.log_line("EOS signed in (puid %s...)" % puid.substr(0, 8))
	return true


## Auth (Developer credential via DevAuthTool) -> Connect with the Epic ID token, done by EOSG's
## HAuth helper. Needs Epic Account Services enabled for the product in the Dev Portal.
func _login_devauth(host: String, cred: String) -> bool:
	if cred == "":
		return _fail("--devauth needs --devcred=<credential name from DevAuthTool>")
	var ok: bool = await HAuth.login_devtool_async(host, cred)
	if not ok or HAuth.product_user_id == "":
		return _fail("devauth login failed (is DevAuthTool running on %s with credential '%s'?)" % [host, cred])
	puid = HAuth.product_user_id
	Net.log_line("EOS signed in via DevAuthTool '%s' (puid %s...)" % [cred, puid.substr(0, 8)])
	return true


## One search pass. Returns open servers' host addresses ("ip:port"), shuffled.
func find_open_servers() -> Array:
	if puid == "":
		_fail("not signed in")
		return []
	var so := EOS.Sessions.CreateSessionSearchOptions.new()
	so.max_search_results = 10
	var sr: Dictionary = EOS.Sessions.SessionsInterface.create_session_search(so)
	if not EOS.is_success(sr):
		_fail("create_session_search " + EOS.result_str(sr))
		return []
	var search: EOSGSessionSearch = sr.session_search
	search.set_parameter("bucket", BUCKET, EOS.ComparisonOp.Equal)
	search.set_parameter("BUILD", BUILD_ID, EOS.ComparisonOp.Equal)
	search.set_parameter("STATE", STATE_OPEN, EOS.ComparisonOp.Equal)
	search.find(puid)
	var fr: Dictionary = await IEOS.session_search_find_callback
	if not EOS.is_success(fr) and int(fr.result_code) != EOS.Result.NotFound:
		_fail("session_search " + EOS.result_str(fr))
		return []
	var out: Array = []
	for i in search.get_search_result_count():
		var cp: Dictionary = search.copy_search_result_by_index(i)
		if not EOS.is_success(cp):
			continue
		var info: Dictionary = cp.session_details.copy_info()
		var host := str(info.get("info", {}).get("host_address", ""))
		if host != "" and not out.has(host):
			out.append(host)
	out.shuffle()
	return out


# ---------------------------------------------------------------- server

## Creates the advertised session (first call) and marks it open.
func server_advertise(host_address: String) -> bool:
	if not platform_ready and not init_platform(true):
		return false
	if not _session_live:
		var o := EOS.Sessions.CreateSessionModificationOptions.new()
		o.session_name = SESSION_NAME
		o.bucket_id = BUCKET
		o.max_players = 2
		o.local_user_id = ""  # dedicated server: no local user
		var ret: Dictionary = EOS.Sessions.SessionsInterface.create_session_modification(o)
		if not EOS.is_success(ret):
			return _fail("create_session_modification " + EOS.result_str(ret))
		var mod: EOSGSessionModification = ret.session_modification
		mod.set_host_address(host_address)
		mod.set_permission_level(EOS.Sessions.OnlineSessionPermissionLevel.PublicAdvertised)
		mod.set_join_in_progress_allowed(false)
		mod.add_attribute("BUILD", BUILD_ID, EOS.Sessions.SessionAttributeAdvertisementType.Advertise)
		mod.add_attribute("STATE", STATE_OPEN, EOS.Sessions.SessionAttributeAdvertisementType.Advertise)
		if not await _update(mod):
			return false
		_session_live = true
		_state_applied = STATE_OPEN
		Net.log_line("EOS session advertised at %s" % host_address)
	server_set_state(STATE_OPEN)
	return true


## Fire-and-forget. Updates are serialised so concurrent awaits cannot cross callbacks.
func server_set_state(state: String) -> void:
	_state_target = state
	if _state_worker or not _session_live:
		return
	_state_worker = true
	while _state_applied != _state_target:
		var want := _state_target
		var uo := EOS.Sessions.UpdateSessionModificationOptions.new()
		uo.session_name = SESSION_NAME
		var ret: Dictionary = EOS.Sessions.SessionsInterface.update_session_modification(uo)
		if not EOS.is_success(ret):
			_fail("update_session_modification " + EOS.result_str(ret))
			break
		var mod: EOSGSessionModification = ret.session_modification
		mod.add_attribute("STATE", want, EOS.Sessions.SessionAttributeAdvertisementType.Advertise)
		if not await _update(mod):
			break
		_state_applied = want
		Net.log_line("EOS session state -> %s" % want)
	_state_worker = false


func _update(mod: EOSGSessionModification) -> bool:
	var uo := EOS.Sessions.UpdateSessionOptions.new()
	uo.session_modification = mod
	EOS.Sessions.SessionsInterface.update_session(uo)
	var ur: Dictionary = await IEOS.sessions_interface_update_session_callback
	if not EOS.is_success(ur):
		return _fail("update_session " + EOS.result_str(ur))
	return true


func server_destroy() -> void:
	if not _session_live:
		return
	var d := EOS.Sessions.DestroySessionOptions.new()
	d.session_name = SESSION_NAME
	EOS.Sessions.SessionsInterface.destroy_session(d)
	var dr: Dictionary = await IEOS.sessions_interface_destroy_session_callback
	_session_live = false
	Net.log_line("EOS session destroyed (%s)" % EOS.result_str(dr))


## Ends the process. Call instead of get_tree().quit() anywhere EOS may have been initialised.
## A normal quit with EOS up can hang forever: EOSG shuts the SDK down while Godot unloads the
## extension, and the SDK then waits (INFINITE) on its own worker threads under the loader lock -
## observed as an idle, windowless process stuck in NtWaitForSingleObject inside the EOS SDK dll.
## Releasing the platform by hand instead crashes at exit (see Docs/Godot_Spike.md), so once our
## own cleanup (session destroy, logs) is done we terminate the process outright.
func quit(code := 0) -> void:
	if not platform_ready:
		get_tree().quit(code)
		return
	EOSGRuntime.set_process(false)
	Net.log_line("exit (EOS up: terminating process, code %d)" % code)
	OS.kill(OS.get_process_id())
