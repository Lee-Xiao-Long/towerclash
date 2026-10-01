class_name EosTest
extends Node
## EOS feasibility probe via EOSG (no editor plugin, only the EOSGRuntime autoload that ticks EOS).
##   --eostest=server [--nonce=X] [--hold=45]   dedicated-server platform, creates an advertised session
##   --eostest=client [--nonce=X]               device-ID Connect login, then searches for that session
## Credentials come from res://eos_credentials.local.json (git-ignored, tools/make_eos_credentials.ps1).
## Prints one "EOS_RESULT {json}" line.

const CREDS_PATH := "res://eos_credentials.local.json"
const BUCKET := "TowerClashSpike:Global"
const SESSION_NAME := "TCSpike"
const TIMEOUT_S := 90.0

var _out := {"ok": false, "steps": []}
var _t0 := 0
var _done := false


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	get_tree().create_timer(TIMEOUT_S).timeout.connect(func():
		_step("timeout", false, "")
		_finish())
	IEOS.logging_interface_callback.connect(func(m: Dictionary):
		if int(m.get("level", 0)) <= EOS.Logging.LogLevel.Warning:
			print("[EOS %s] %s" % [m.get("category", ""), m.get("message", "")]))
	_run()


func _step(name: String, ok: bool, detail: Variant) -> void:
	_out.steps.append({"step": name, "ok": ok, "detail": detail, "ms": Time.get_ticks_msec() - _t0})
	print("EOS_STEP %s ok=%s %s" % [name, ok, str(detail)])


func _finish() -> void:
	if _done:
		return
	_done = true
	print("EOS_RESULT " + JSON.stringify(_out))
	# EOSG releases the platform and shuts the SDK down itself when the extension unloads;
	# doing it here as well crashes at exit. Stop ticking and quit.
	EOSGRuntime.set_process(false)
	get_tree().quit(0 if _out.ok else 1)


func _run() -> void:
	var mode: String = Net.args.get("eostest", "client")
	var nonce: String = Net.args.get("nonce", "spike")
	_out.mode = mode
	# Exports exclude *.local.json, so a shipped build reads credentials placed next to the executable.
	var creds := CREDS_PATH
	if not FileAccess.file_exists(creds):
		creds = OS.get_executable_path().get_base_dir().path_join(CREDS_PATH.get_file())
	if not FileAccess.file_exists(creds):
		_step("credentials", false, "missing " + CREDS_PATH)
		return _finish()
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(creds))
	var is_server := mode == "server"

	var init := EOS.Platform.InitializeOptions.new()
	init.product_name = "TowerClashSpike"
	init.product_version = "0.1"
	var r: EOS.Result = EOS.Platform.PlatformInterface.initialize(init)
	_step("initialize", EOS.is_success(r) or r == EOS.Result.AlreadyConfigured, EOS.result_str(r))
	EOS.Logging.set_log_level(EOS.Logging.LogCategory.AllCategories, EOS.Logging.LogLevel.Warning)

	var co := EOS.Platform.CreateOptions.new()
	co.product_id = c.product_id
	co.sandbox_id = c.sandbox_id
	co.deployment_id = c.deployment_id
	co.client_id = c.server_client_id if is_server else c.client_id
	co.client_secret = c.server_client_secret if is_server else c.client_secret
	co.encryption_key = c.encryption_key
	co.is_server = is_server
	co.flags = EOS.Platform.PlatformFlags.DisableOverlay
	var created: bool = EOS.Platform.PlatformInterface.create(co)
	_step("create_platform", created, "server" if is_server else "client")
	if not created:
		return _finish()

	if is_server:
		await _server(nonce)
	else:
		await _client(nonce)
	_finish()


func _server(nonce: String) -> void:
	var o := EOS.Sessions.CreateSessionModificationOptions.new()
	o.session_name = SESSION_NAME
	o.bucket_id = BUCKET
	o.max_players = 2
	o.local_user_id = ""  # dedicated server: no local user
	var ret: Dictionary = EOS.Sessions.SessionsInterface.create_session_modification(o)
	_step("create_session_modification", EOS.is_success(ret), EOS.result_str(ret))
	if not EOS.is_success(ret):
		return
	var mod: EOSGSessionModification = ret.session_modification
	mod.set_host_address("127.0.0.1:7777")
	mod.set_permission_level(EOS.Sessions.OnlineSessionPermissionLevel.PublicAdvertised)
	mod.set_join_in_progress_allowed(false)
	mod.add_attribute("SPIKE", nonce, EOS.Sessions.SessionAttributeAdvertisementType.Advertise)
	var uo := EOS.Sessions.UpdateSessionOptions.new()
	uo.session_modification = mod
	EOS.Sessions.SessionsInterface.update_session(uo)
	var ur: Dictionary = await IEOS.sessions_interface_update_session_callback
	_step("update_session", EOS.is_success(ur), {"result": EOS.result_str(ur), "session_id": ur.get("session_id", "")})
	if not EOS.is_success(ur):
		return
	_out.session_id = ur.get("session_id", "")
	var hold := float(Net.args.get("hold", "45"))
	print("EOS_SESSION_READY %s" % _out.session_id)
	await get_tree().create_timer(hold).timeout
	var d := EOS.Sessions.DestroySessionOptions.new()
	d.session_name = SESSION_NAME
	EOS.Sessions.SessionsInterface.destroy_session(d)
	var dr: Dictionary = await IEOS.sessions_interface_destroy_session_callback
	_step("destroy_session", EOS.is_success(dr), EOS.result_str(dr))
	_out.ok = EOS.is_success(dr)


func _client(nonce: String) -> void:
	var dopt := EOS.Connect.CreateDeviceIdOptions.new()
	dopt.device_model = "%s %s" % [OS.get_name(), OS.get_model_name()]
	EOS.Connect.ConnectInterface.create_device_id(dopt)
	var dr = await IEOS.connect_interface_create_device_id_callback
	var dev_ok: bool = EOS.is_success(dr) or int(dr.result_code) == EOS.Result.DuplicateNotAllowed
	_step("create_device_id", dev_ok, EOS.result_str(dr))
	if not dev_ok:
		return

	var lo := EOS.Connect.LoginOptions.new()
	lo.credentials = EOS.Connect.Credentials.new()
	lo.credentials.type = EOS.ExternalCredentialType.DeviceidAccessToken
	lo.credentials.token = null
	lo.user_login_info = EOS.Connect.UserLoginInfo.new()
	lo.user_login_info.display_name = "SpikeBot"
	EOS.Connect.ConnectInterface.login(lo)
	var lr: Dictionary = await IEOS.connect_interface_login_callback
	var puid: String = lr.get("local_user_id", "")
	if int(lr.result_code) == EOS.Result.InvalidUser:
		_step("connect_login", true, "InvalidUser -> create_user")
		var cu := EOS.Connect.CreateUserOptions.new()
		cu.continuance_token = lr.continuance_token
		EOS.Connect.ConnectInterface.create_user(cu)
		var cr: Dictionary = await IEOS.connect_interface_create_user_callback
		_step("create_user", EOS.is_success(cr), EOS.result_str(cr))
		if not EOS.is_success(cr):
			return
		puid = cr.get("local_user_id", "")
	else:
		_step("connect_login", EOS.is_success(lr), EOS.result_str(lr))
		if not EOS.is_success(lr):
			return
	# Product User IDs are opaque but not secret; log only a prefix anyway.
	_out.puid_prefix = puid.substr(0, 8)
	_step("product_user_id", puid != "", _out.puid_prefix + "...")
	if puid == "":
		return

	var so := EOS.Sessions.CreateSessionSearchOptions.new()
	so.max_search_results = 10
	var sr: Dictionary = EOS.Sessions.SessionsInterface.create_session_search(so)
	if not EOS.is_success(sr):
		_step("create_session_search", false, EOS.result_str(sr))
		return
	var search: EOSGSessionSearch = sr.session_search
	search.set_parameter("bucket", BUCKET, EOS.ComparisonOp.Equal)
	search.set_parameter("SPIKE", nonce, EOS.ComparisonOp.Equal)
	var found := 0
	var host := ""
	for attempt in 6:
		search.find(puid)
		var fr: Dictionary = await IEOS.session_search_find_callback
		if not EOS.is_success(fr) and int(fr.result_code) != EOS.Result.NotFound:
			_step("session_search", false, EOS.result_str(fr))
			return
		found = search.get_search_result_count()
		if found > 0:
			var cp: Dictionary = search.copy_search_result_by_index(0)
			if EOS.is_success(cp):
				var info: Dictionary = cp.session_details.copy_info()
				host = str(info.get("info", {}).get("host_address", ""))
			break
		await get_tree().create_timer(3.0).timeout
	_step("session_search", found > 0, {"found": found, "host_address": host})
	_out.ok = found > 0
