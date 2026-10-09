//! Minimal EOS SDK binding (C API, loaded at runtime with libloading): platform init, device-ID
//! Connect login (or dedicated-server mode without a user) and session search with attributes.
//!
//! Struct layouts are hand-written from the EOS SDK 1.18 headers (eos_init.h, eos_types.h,
//! eos_connect_types.h, eos_sessions_types.h). The SDK packs structs to 8 bytes, which is what
//! `repr(C)` gives on x86_64/arm64. Input structs carry the API version they were written
//! against; output structs are only read for fields every recent version has.
//! The SDK is not thread-safe: use one `Eos` from one thread only.

use libloading::Library;
use std::ffi::{c_char, c_void, CStr, CString};
use std::mem::ManuallyDrop;
use std::path::Path;
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub const SUCCESS: i32 = 0;
const INVALID_USER: i32 = 3;
const NOT_FOUND: i32 = 18;
const DUPLICATE_NOT_ALLOWED: i32 = 24;
const CT_DEVICEID_ACCESS_TOKEN: i32 = 10;
const AT_BOOLEAN: i32 = 0;
const AT_INT64: i32 = 1;
const AT_DOUBLE: i32 = 2;
const AT_STRING: i32 = 3;
const CO_EQUAL: i32 = 0;
const PF_DISABLE_OVERLAY: u64 = 0x2;
const LC_ALL_CATEGORIES: i32 = 0x7fff_ffff;
const LOG_WARNING: i32 = 300;

type Handle = *mut c_void;

#[repr(C)]
struct InitializeOptions {
    api_version: i32, // 4
    allocate: *const c_void,
    reallocate: *const c_void,
    release: *const c_void,
    product_name: *const c_char,
    product_version: *const c_char,
    reserved: *mut c_void,
    system_initialize_options: *mut c_void,
    override_thread_affinity: *mut c_void,
}

#[repr(C)]
struct ClientCredentials {
    client_id: *const c_char,
    client_secret: *const c_char,
}

#[repr(C)]
struct PlatformOptions {
    api_version: i32, // 14
    reserved: *mut c_void,
    product_id: *const c_char,
    sandbox_id: *const c_char,
    client_credentials: ClientCredentials,
    is_server: i32,
    encryption_key: *const c_char,
    override_country_code: *const c_char,
    override_locale_code: *const c_char,
    deployment_id: *const c_char,
    flags: u64,
    cache_directory: *const c_char,
    tick_budget_ms: u32,
    rtc_options: *const c_void,
    integrated_platform_options_container: *mut c_void,
    system_specific_options: *const c_void,
    task_network_timeout_seconds: *mut f64,
}

#[repr(C)]
struct CreateDeviceIdOptions {
    api_version: i32, // 1
    device_model: *const c_char,
}

#[repr(C)]
struct ConnectCredentials {
    api_version: i32, // 1
    token: *const c_char,
    kind: i32,
}

#[repr(C)]
struct UserLoginInfo {
    api_version: i32, // 2
    display_name: *const c_char,
    nsa_id_token: *const c_char,
}

#[repr(C)]
struct LoginOptions {
    api_version: i32, // 2
    credentials: *const ConnectCredentials,
    user_login_info: *const UserLoginInfo,
}

#[repr(C)]
struct CreateUserOptions {
    api_version: i32, // 1
    continuance_token: Handle,
}

/// Callback infos: all start with ResultCode, ClientData. Each callback casts the raw pointer to
/// its own exact layout (never a larger struct than the SDK passed).
#[repr(C)]
struct BasicCallbackInfo {
    result: i32,
    client_data: *mut c_void,
}

#[repr(C)]
struct CreateUserCallbackInfo {
    result: i32,
    client_data: *mut c_void,
    local_user_id: Handle,
}

#[repr(C)]
struct LoginCallbackInfo {
    result: i32,
    client_data: *mut c_void,
    local_user_id: Handle,
    continuance_token: Handle,
}

#[repr(C)]
struct CreateSessionSearchOptions {
    api_version: i32, // 1
    max_search_results: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
union AttrValue {
    as_i64: i64,
    as_f64: f64,
    as_bool: i32,
    as_utf8: *const c_char,
}

#[repr(C)]
struct AttributeData {
    api_version: i32, // 1
    key: *const c_char,
    value: AttrValue,
    value_type: i32,
}

#[repr(C)]
struct SetParameterOptions {
    api_version: i32, // 1
    parameter: *const AttributeData,
    comparison_op: i32,
}

#[repr(C)]
struct FindOptions {
    api_version: i32, // 2
    local_user_id: Handle,
}

#[repr(C)]
struct ApiVersionOnly {
    api_version: i32,
}

#[repr(C)]
struct CopyByIndexOptions {
    api_version: i32, // 1
    index: u32,
}

#[repr(C)]
struct SessionDetailsSettings {
    api_version: i32,
    bucket_id: *const c_char,
    num_public_connections: u32,
    allow_join_in_progress: i32,
    permission_level: i32,
}

#[repr(C)]
struct SessionDetailsInfo {
    api_version: i32,
    session_id: *const c_char,
    host_address: *const c_char,
    num_open_public_connections: u32,
    settings: *const SessionDetailsSettings,
}

#[repr(C)]
struct SessionDetailsAttribute {
    api_version: i32,
    data: *const AttributeData,
    advertisement_type: i32,
}

#[repr(C)]
struct LogMessage {
    category: *const c_char,
    message: *const c_char,
    level: i32,
}

type OnCallback = unsafe extern "C" fn(*const c_void);
type OnLog = unsafe extern "C" fn(*const LogMessage);

/// Raw function pointers resolved from the SDK library.
struct Api {
    get_version: unsafe extern "C" fn() -> *const c_char,
    result_to_string: unsafe extern "C" fn(i32) -> *const c_char,
    initialize: unsafe extern "C" fn(*const InitializeOptions) -> i32,
    logging_set_callback: unsafe extern "C" fn(OnLog) -> i32,
    logging_set_log_level: unsafe extern "C" fn(i32, i32) -> i32,
    platform_create: unsafe extern "C" fn(*const PlatformOptions) -> Handle,
    platform_tick: unsafe extern "C" fn(Handle),
    get_connect: unsafe extern "C" fn(Handle) -> Handle,
    get_sessions: unsafe extern "C" fn(Handle) -> Handle,
    puid_to_string: unsafe extern "C" fn(Handle, *mut c_char, *mut i32) -> i32,
    connect_create_device_id: unsafe extern "C" fn(Handle, *const CreateDeviceIdOptions, *mut c_void, OnCallback),
    connect_login: unsafe extern "C" fn(Handle, *const LoginOptions, *mut c_void, OnCallback),
    connect_create_user: unsafe extern "C" fn(Handle, *const CreateUserOptions, *mut c_void, OnCallback),
    sessions_create_search: unsafe extern "C" fn(Handle, *const CreateSessionSearchOptions, *mut Handle) -> i32,
    search_set_parameter: unsafe extern "C" fn(Handle, *const SetParameterOptions) -> i32,
    search_find: unsafe extern "C" fn(Handle, *const FindOptions, *mut c_void, OnCallback),
    search_result_count: unsafe extern "C" fn(Handle, *const ApiVersionOnly) -> u32,
    search_copy_result: unsafe extern "C" fn(Handle, *const CopyByIndexOptions, *mut Handle) -> i32,
    search_release: unsafe extern "C" fn(Handle),
    details_copy_info: unsafe extern "C" fn(Handle, *const ApiVersionOnly, *mut *mut SessionDetailsInfo) -> i32,
    details_attr_count: unsafe extern "C" fn(Handle, *const ApiVersionOnly) -> u32,
    details_copy_attr: unsafe extern "C" fn(Handle, *const CopyByIndexOptions, *mut *mut SessionDetailsAttribute) -> i32,
    details_release: unsafe extern "C" fn(Handle),
    details_info_release: unsafe extern "C" fn(*mut SessionDetailsInfo),
    details_attr_release: unsafe extern "C" fn(*mut SessionDetailsAttribute),
}

macro_rules! sym {
    ($lib:expr, $name:literal) => {
        *$lib
            .get(concat!($name, "\0").as_bytes())
            .map_err(|e| format!("missing symbol {}: {e}", $name))?
    };
}

impl Api {
    unsafe fn load(lib: &Library) -> Result<Api, String> {
        Ok(Api {
            get_version: sym!(lib, "EOS_GetVersion"),
            result_to_string: sym!(lib, "EOS_EResult_ToString"),
            initialize: sym!(lib, "EOS_Initialize"),
            logging_set_callback: sym!(lib, "EOS_Logging_SetCallback"),
            logging_set_log_level: sym!(lib, "EOS_Logging_SetLogLevel"),
            platform_create: sym!(lib, "EOS_Platform_Create"),
            platform_tick: sym!(lib, "EOS_Platform_Tick"),
            get_connect: sym!(lib, "EOS_Platform_GetConnectInterface"),
            get_sessions: sym!(lib, "EOS_Platform_GetSessionsInterface"),
            puid_to_string: sym!(lib, "EOS_ProductUserId_ToString"),
            connect_create_device_id: sym!(lib, "EOS_Connect_CreateDeviceId"),
            connect_login: sym!(lib, "EOS_Connect_Login"),
            connect_create_user: sym!(lib, "EOS_Connect_CreateUser"),
            sessions_create_search: sym!(lib, "EOS_Sessions_CreateSessionSearch"),
            search_set_parameter: sym!(lib, "EOS_SessionSearch_SetParameter"),
            search_find: sym!(lib, "EOS_SessionSearch_Find"),
            search_result_count: sym!(lib, "EOS_SessionSearch_GetSearchResultCount"),
            search_copy_result: sym!(lib, "EOS_SessionSearch_CopySearchResultByIndex"),
            search_release: sym!(lib, "EOS_SessionSearch_Release"),
            details_copy_info: sym!(lib, "EOS_SessionDetails_CopyInfo"),
            details_attr_count: sym!(lib, "EOS_SessionDetails_GetSessionAttributeCount"),
            details_copy_attr: sym!(lib, "EOS_SessionDetails_CopySessionAttributeByIndex"),
            details_release: sym!(lib, "EOS_SessionDetails_Release"),
            details_info_release: sym!(lib, "EOS_SessionDetails_Info_Release"),
            details_attr_release: sym!(lib, "EOS_SessionDetails_Attribute_Release"),
        })
    }
}

/// SDK warnings/errors captured by the log callback, drained by the caller.
static SDK_LOG: Mutex<Vec<String>> = Mutex::new(Vec::new());

unsafe extern "C" fn on_log(msg: *const LogMessage) {
    if msg.is_null() {
        return;
    }
    let m = &*msg;
    let line = format!("{}: {}", cstr(m.category), cstr(m.message));
    if let Ok(mut v) = SDK_LOG.lock() {
        if v.len() < 200 {
            v.push(line);
        }
    }
}

pub fn drain_sdk_log() -> Vec<String> {
    SDK_LOG.lock().map(|mut v| std::mem::take(&mut *v)).unwrap_or_default()
}

/// Completion slot shared with an async SDK call through ClientData.
#[derive(Default)]
struct Slot {
    done: bool,
    result: i32,
    user: usize,
    continuance: usize,
}

unsafe extern "C" fn on_complete(data: *const c_void) {
    let info = &*(data as *const BasicCallbackInfo);
    let slot = &mut *(info.client_data as *mut Slot);
    slot.result = info.result;
    slot.done = true;
}

unsafe extern "C" fn on_login(data: *const c_void) {
    let info = &*(data as *const LoginCallbackInfo);
    let slot = &mut *(info.client_data as *mut Slot);
    slot.result = info.result;
    slot.user = info.local_user_id as usize;
    slot.continuance = info.continuance_token as usize;
    slot.done = true;
}

unsafe extern "C" fn on_create_user(data: *const c_void) {
    let info = &*(data as *const CreateUserCallbackInfo);
    let slot = &mut *(info.client_data as *mut Slot);
    slot.result = info.result;
    slot.user = info.local_user_id as usize;
    slot.done = true;
}

unsafe fn cstr(p: *const c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        CStr::from_ptr(p).to_string_lossy().into_owned()
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Session {
    pub id: String,
    pub host_address: String,
    pub bucket: String,
    pub open_slots: u32,
    pub max_slots: u32,
    /// Advertised attributes, e.g. BUILD, STATE (values stringified).
    pub attributes: Vec<(String, String)>,
}

impl Session {
    pub fn attr(&self, key: &str) -> &str {
        self.attributes
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(key))
            .map(|(_, v)| v.as_str())
            .unwrap_or("")
    }
}

pub struct Credentials {
    pub product_id: String,
    pub sandbox_id: String,
    pub deployment_id: String,
    pub client_id: String,
    pub client_secret: String,
}

pub struct Eos {
    api: Api,
    /// Never unloaded: unloading the EOS SDK (FreeLibrary/dlclose) blocks forever on its own
    /// worker threads. The process ends with hard_exit (main.rs) instead.
    _lib: ManuallyDrop<Library>,
    platform: Handle,
    user: Handle,
    pub version: String,
    pub user_id: String,
    pub server_mode: bool,
    _keep: Vec<CString>,
}

impl Eos {
    /// Loads the SDK library and creates a platform. server_mode = dedicated-server credentials
    /// and no local user; otherwise a device-ID Connect login with client credentials.
    pub fn start(sdk_path: &Path, creds: &Credentials, server_mode: bool) -> Result<Eos, String> {
        unsafe {
            let lib = Library::new(sdk_path).map_err(|e| format!("cannot load {}: {e}", sdk_path.display()))?;
            let api = Api::load(&lib)?;
            let version = cstr((api.get_version)());
            let mut keep: Vec<CString> = Vec::new();
            let mut c = |s: &str| -> *const c_char {
                let cs = CString::new(s).unwrap_or_default();
                let p = cs.as_ptr();
                keep.push(cs);
                p
            };
            let init = InitializeOptions {
                api_version: 4,
                allocate: std::ptr::null(),
                reallocate: std::ptr::null(),
                release: std::ptr::null(),
                product_name: c("TowerClash EOS Monitor"),
                product_version: c(env!("CARGO_PKG_VERSION")),
                reserved: std::ptr::null_mut(),
                system_initialize_options: std::ptr::null_mut(),
                override_thread_affinity: std::ptr::null_mut(),
            };
            let r = (api.initialize)(&init);
            if r != SUCCESS {
                return Err(format!("EOS_Initialize: {} (SDK {version})", cstr((api.result_to_string)(r))));
            }
            (api.logging_set_callback)(on_log);
            (api.logging_set_log_level)(LC_ALL_CATEGORIES, LOG_WARNING);
            let cache = std::env::temp_dir().join("towerclash_eos_monitor");
            let _ = std::fs::create_dir_all(&cache);
            let opts = PlatformOptions {
                api_version: 14,
                reserved: std::ptr::null_mut(),
                product_id: c(&creds.product_id),
                sandbox_id: c(&creds.sandbox_id),
                client_credentials: ClientCredentials { client_id: c(&creds.client_id), client_secret: c(&creds.client_secret) },
                is_server: if server_mode { 1 } else { 0 },
                encryption_key: std::ptr::null(),
                override_country_code: std::ptr::null(),
                override_locale_code: std::ptr::null(),
                deployment_id: c(&creds.deployment_id),
                flags: PF_DISABLE_OVERLAY,
                cache_directory: c(&cache.to_string_lossy()),
                tick_budget_ms: 0,
                rtc_options: std::ptr::null(),
                integrated_platform_options_container: std::ptr::null_mut(),
                system_specific_options: std::ptr::null(),
                task_network_timeout_seconds: std::ptr::null_mut(),
            };
            let platform = (api.platform_create)(&opts);
            if platform.is_null() {
                let log = drain_sdk_log().join(" | ");
                return Err(format!("EOS_Platform_Create failed (SDK {version}; header API 1.18). {log}"));
            }
            let mut eos = Eos { api, _lib: ManuallyDrop::new(lib), platform, user: std::ptr::null_mut(), version, user_id: String::new(), server_mode, _keep: keep };
            if !server_mode {
                eos.login()?;
            }
            Ok(eos)
        }
    }

    fn result_str(&self, r: i32) -> String {
        unsafe { cstr((self.api.result_to_string)(r)) }
    }

    /// Ticks the platform until the slot completes or the timeout passes.
    fn wait(&self, slot: &Slot, what: &str, timeout: Duration) -> Result<(), String> {
        let start = Instant::now();
        while !unsafe { std::ptr::read_volatile(&slot.done) } {
            unsafe { (self.api.platform_tick)(self.platform) };
            if start.elapsed() > timeout {
                return Err(format!("{what}: timed out after {}s", timeout.as_secs()));
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        Ok(())
    }

    fn login(&mut self) -> Result<(), String> {
        unsafe {
            let connect = (self.api.get_connect)(self.platform);
            let model = CString::new(format!("eos_monitor {}", std::env::consts::OS)).unwrap();
            let mut slot = Box::new(Slot::default());
            let dopt = CreateDeviceIdOptions { api_version: 1, device_model: model.as_ptr() };
            (self.api.connect_create_device_id)(connect, &dopt, &mut *slot as *mut Slot as *mut c_void, on_complete);
            self.wait(&slot, "create device id", Duration::from_secs(20))?;
            if slot.result != SUCCESS && slot.result != DUPLICATE_NOT_ALLOWED {
                return Err(format!("create device id: {}", self.result_str(slot.result)));
            }
            let name = CString::new("EOS Monitor").unwrap();
            let creds = ConnectCredentials { api_version: 1, token: std::ptr::null(), kind: CT_DEVICEID_ACCESS_TOKEN };
            let info = UserLoginInfo { api_version: 2, display_name: name.as_ptr(), nsa_id_token: std::ptr::null() };
            let lopt = LoginOptions { api_version: 2, credentials: &creds, user_login_info: &info };
            let mut slot = Box::new(Slot::default());
            (self.api.connect_login)(connect, &lopt, &mut *slot as *mut Slot as *mut c_void, on_login);
            self.wait(&slot, "connect login", Duration::from_secs(20))?;
            if slot.result == INVALID_USER && slot.continuance != 0 {
                let copt = CreateUserOptions { api_version: 1, continuance_token: slot.continuance as Handle };
                let mut cslot = Box::new(Slot::default());
                (self.api.connect_create_user)(connect, &copt, &mut *cslot as *mut Slot as *mut c_void, on_create_user);
                self.wait(&cslot, "create user", Duration::from_secs(20))?;
                if cslot.result != SUCCESS {
                    return Err(format!("create user: {}", self.result_str(cslot.result)));
                }
                slot.user = cslot.user;
            } else if slot.result != SUCCESS {
                return Err(format!("connect login: {}", self.result_str(slot.result)));
            }
            self.user = slot.user as Handle;
            let mut buf = [0 as c_char; 64];
            let mut len = buf.len() as i32;
            if (self.api.puid_to_string)(self.user, buf.as_mut_ptr(), &mut len) == SUCCESS {
                self.user_id = cstr(buf.as_ptr());
            }
            Ok(())
        }
    }

    /// One search of a bucket (plus optional exact-match string attributes). NotFound = empty.
    pub fn search(&self, bucket: &str, filters: &[(String, String)], max: u32) -> Result<Vec<Session>, String> {
        unsafe {
            let sessions = (self.api.get_sessions)(self.platform);
            let mut search: Handle = std::ptr::null_mut();
            let r = (self.api.sessions_create_search)(sessions, &CreateSessionSearchOptions { api_version: 1, max_search_results: max }, &mut search);
            if r != SUCCESS {
                return Err(format!("create session search: {}", self.result_str(r)));
            }
            let result = self.run_search(search, bucket, filters);
            (self.api.search_release)(search);
            result
        }
    }

    unsafe fn run_search(&self, search: Handle, bucket: &str, filters: &[(String, String)]) -> Result<Vec<Session>, String> {
        let mut params = vec![("bucket".to_string(), bucket.to_string())];
        params.extend_from_slice(filters);
        for (k, v) in &params {
            let key = CString::new(k.as_str()).unwrap();
            let val = CString::new(v.as_str()).unwrap();
            let data = AttributeData { api_version: 1, key: key.as_ptr(), value: AttrValue { as_utf8: val.as_ptr() }, value_type: AT_STRING };
            let r = (self.api.search_set_parameter)(search, &SetParameterOptions { api_version: 1, parameter: &data, comparison_op: CO_EQUAL });
            if r != SUCCESS {
                return Err(format!("search parameter {k}: {}", self.result_str(r)));
            }
        }
        let mut slot = Box::new(Slot::default());
        (self.api.search_find)(search, &FindOptions { api_version: 2, local_user_id: self.user }, &mut *slot as *mut Slot as *mut c_void, on_complete);
        self.wait(&slot, "session search", Duration::from_secs(20))?;
        if slot.result == NOT_FOUND {
            return Ok(Vec::new());
        }
        if slot.result != SUCCESS {
            return Err(format!("session search: {}", self.result_str(slot.result)));
        }
        let count = (self.api.search_result_count)(search, &ApiVersionOnly { api_version: 1 });
        let mut out = Vec::new();
        for i in 0..count {
            let mut details: Handle = std::ptr::null_mut();
            if (self.api.search_copy_result)(search, &CopyByIndexOptions { api_version: 1, index: i }, &mut details) != SUCCESS {
                continue;
            }
            out.push(self.read_details(details));
            (self.api.details_release)(details);
        }
        Ok(out)
    }

    unsafe fn read_details(&self, details: Handle) -> Session {
        let mut s = Session { id: String::new(), host_address: String::new(), bucket: String::new(), open_slots: 0, max_slots: 0, attributes: Vec::new() };
        let mut info: *mut SessionDetailsInfo = std::ptr::null_mut();
        if (self.api.details_copy_info)(details, &ApiVersionOnly { api_version: 1 }, &mut info) == SUCCESS && !info.is_null() {
            let i = &*info;
            s.id = cstr(i.session_id);
            s.host_address = cstr(i.host_address);
            s.open_slots = i.num_open_public_connections;
            if !i.settings.is_null() {
                s.bucket = cstr((*i.settings).bucket_id);
                s.max_slots = (*i.settings).num_public_connections;
            }
            (self.api.details_info_release)(info);
        }
        let n = (self.api.details_attr_count)(details, &ApiVersionOnly { api_version: 1 });
        for a in 0..n {
            let mut attr: *mut SessionDetailsAttribute = std::ptr::null_mut();
            if (self.api.details_copy_attr)(details, &CopyByIndexOptions { api_version: 1, index: a }, &mut attr) != SUCCESS || attr.is_null() {
                continue;
            }
            if !(*attr).data.is_null() {
                let d = &*(*attr).data;
                let value = match d.value_type {
                    AT_BOOLEAN => (d.value.as_bool != 0).to_string(),
                    AT_INT64 => d.value.as_i64.to_string(),
                    AT_DOUBLE => d.value.as_f64.to_string(),
                    AT_STRING => cstr(d.value.as_utf8),
                    _ => "?".into(),
                };
                s.attributes.push((cstr(d.key), value));
            }
            (self.api.details_attr_release)(attr);
        }
        s
    }

    /// Services the SDK (auth refresh, network). Call regularly between searches.
    /// There is deliberately no shutdown: see `hard_exit` in main.rs.
    pub fn tick(&self) {
        unsafe { (self.api.platform_tick)(self.platform) };
    }
}
