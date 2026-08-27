//! Bindings to Kehwin's `kwdm.dylib` — the vendor C SDK that ships inside Ulanzi Studio.
//!
//! Why: the device's vendor HID channel is encrypted, but this SDK already implements
//! the crypto, the auth handshake and the framing, and hands back plaintext JSON.
//! We load the copy installed on this machine (we never redistribute it).
use anyhow::{anyhow, Result};
use libloading::{Library, Symbol};
use std::ffi::{c_char, c_int, CStr, CString};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Mutex;

/// SDK 授权用的 App Key(取自官方 app 的 sdkInit 调用)。
pub const APP_KEY: &str = "BF1C7D81";

// macOS 会拦住对键盘类 HID 接口的打开(kIOReturnNotPermitted),
// 而厂商 SDK 正需要开这些接口才能认到设备。必须先申请「输入监视」。
#[link(name = "IOKit", kind = "framework")]
extern "C" {
    fn IOHIDRequestAccess(requestType: u32) -> bool;
    fn IOHIDCheckAccess(requestType: u32) -> u32;
}
const LISTEN_EVENT: u32 = 0; // kIOHIDRequestTypeListenEvent

/// 0 = granted, 1 = denied, 2 = unknown(还没问过)
pub fn input_monitoring_status() -> u32 { unsafe { IOHIDCheckAccess(LISTEN_EVENT) } }

/// 弹系统授权框(仅在「未问过」时会真的弹)。
pub fn request_input_monitoring() -> bool { unsafe { IOHIDRequestAccess(LISTEN_EVENT) } }

pub const DYLIB: &str = "/Applications/Ulanzi Studio.app/Contents/Frameworks/kwdm.dylib";

/// One decoded event from the device.
#[derive(Debug, Clone)]
pub enum Event {
    Connected(String),
    Disconnected(String),
    /// (device id, raw JSON-ish payload the SDK emits)
    Message(String, String),
}

static TX: Mutex<Option<Sender<Event>>> = Mutex::new(None);

fn emit(e: Event) {
    if let Ok(g) = TX.lock() {
        if let Some(tx) = g.as_ref() {
            let _ = tx.send(e);
        }
    }
}

/// Safe-ish read of a C string the SDK hands us.
unsafe fn s(p: *const c_char) -> String {
    if p.is_null() { return String::new(); }
    CStr::from_ptr(p).to_string_lossy().into_owned()
}

unsafe extern "C" fn cb_conn(id: *const c_char, _b: *const c_char) { emit(Event::Connected(s(id))); }
unsafe extern "C" fn cb_disc(id: *const c_char, _b: *const c_char) { emit(Event::Disconnected(s(id))); }
unsafe extern "C" fn cb_msg(id: *const c_char, msg: *const c_char) { emit(Event::Message(s(id), s(msg))); }

pub struct Sdk {
    lib: Library,
    pub events: Receiver<Event>,
}

impl Sdk {
    /// Load the vendor SDK and start it. Fails clearly if Ulanzi Studio isn't installed.
    pub fn load() -> Result<Self> {
        if !std::path::Path::new(DYLIB).exists() {
            return Err(anyhow!(
                "找不到 {DYLIB}\n需要先安装 Ulanzi Studio(v1 依赖它的 SDK)"
            ));
        }
        let st = input_monitoring_status();
        if st != 0 {
            eprintln!("[vibekey] 输入监视权限: {}", match st {
                1 => "已拒绝 — 需在 系统设置 › 隐私与安全性 › 输入监视 里手动勾选",
                _ => "未授权 — 正在弹出系统授权框",
            });
            request_input_monitoring();
        }
        let lib = unsafe { Library::new(DYLIB)? };
        let (tx, rx) = channel();
        *TX.lock().unwrap() = Some(tx);

        unsafe {
            let reg_c: Symbol<unsafe extern "C" fn(*const ())> =
                lib.get(b"registerDeviceConnectedCallbackListener")?;
            let reg_d: Symbol<unsafe extern "C" fn(*const ())> =
                lib.get(b"registerDeviceDisconnectedCallbackListener")?;
            let reg_m: Symbol<unsafe extern "C" fn(*const ())> =
                lib.get(b"registerDeviceMessageCallbackListener")?;
            reg_c(cb_conn as *const ());
            reg_d(cb_disc as *const ());
            reg_m(cb_msg as *const ());

            let init: Symbol<unsafe extern "C" fn(*const c_char, bool)> = lib.get(b"sdkInit")?;
            // SDK 的第一个参数是 8 位 App Key,不是名字。
            // 逆自官方 app 的 sdkInit 调用:无效 key 会让 SDK 静默不匹配任何设备。
            let key = CString::new(APP_KEY)?;
            init(key.as_ptr(), true);
        }
        Ok(Sdk { lib, events: rx })
    }

    pub fn version(&self) -> String {
        unsafe {
            self.lib
                .get::<unsafe extern "C" fn() -> *const c_char>(b"sdkVersion")
                .map(|f| s(f()))
                .unwrap_or_default()
        }
    }

    pub fn connected_count(&self) -> i32 {
        unsafe {
            self.lib
                .get::<unsafe extern "C" fn() -> c_int>(b"getConnectedDeviceCount")
                .map(|f| f())
                .unwrap_or(0)
        }
    }

    /// Call a `bool f(const char *deviceId)` SDK getter. Results arrive as Events.
    pub fn ask(&self, func: &[u8], dev: &str) -> Result<bool> {
        let id = CString::new(dev)?;
        unsafe {
            let f: Symbol<unsafe extern "C" fn(*const c_char) -> bool> = self.lib.get(func)?;
            Ok(f(id.as_ptr()))
        }
    }

    /// Call a `bool f(const char *deviceId, int)` SDK setter.
    pub fn set_int(&self, func: &[u8], dev: &str, v: i32) -> Result<bool> {
        let id = CString::new(dev)?;
        unsafe {
            let f: Symbol<unsafe extern "C" fn(*const c_char, c_int) -> bool> = self.lib.get(func)?;
            Ok(f(id.as_ptr(), v))
        }
    }

    /// Block until the SDK reports a connected device, or time out.
    pub fn wait_for_device(&self, timeout: std::time::Duration) -> Option<String> {
        let deadline = std::time::Instant::now() + timeout;
        while std::time::Instant::now() < deadline {
            if let Ok(Event::Connected(id)) = self.events.recv_timeout(std::time::Duration::from_millis(200)) {
                return Some(id);
            }
        }
        None
    }

    /// `setDeviceLedEffect(dev, mode, speed, bright, red, green, blue)`.
    /// Field meanings come from the SDK's own callback selector
    /// `onMessageDeviceLedEffect:mode:speed:bright:red:green:blue:`.
    pub fn set_led(&self, dev: &str, mode: i32, speed: i32, bright: i32, rgb: (i32, i32, i32)) -> Result<bool> {
        self.set_led_effect(dev, [mode, speed, bright, rgb.0, rgb.1, rgb.2])
    }

    /// `setDeviceButtonShortcutFunction(dev, index, content)` — 把快捷键写进设备固件,
    /// 这样按键在客户端没跑的时候也生效。content 是十六进制 macOS 虚拟键码,
    /// 多个键用 `|` 分隔(如 `FFFFFF|31`)。
    pub fn set_button_shortcut(&self, dev: &str, index: i32, content: &str) -> Result<bool> {
        let id = CString::new(dev)?;
        let mut buf = CString::new(content)?.into_bytes_with_nul();
        unsafe {
            let f: Symbol<unsafe extern "C" fn(*const c_char, c_int, *mut c_char) -> bool> =
                self.lib.get(b"setDeviceButtonShortcutFunction")?;
            Ok(f(id.as_ptr(), index, buf.as_mut_ptr() as *mut c_char))
        }
    }

    /// `setDeviceLedEffect(dev, a, b, c, d, e, f)` — raw six-int form.
    pub fn set_led_effect(&self, dev: &str, p: [i32; 6]) -> Result<bool> {
        let id = CString::new(dev)?;
        unsafe {
            let f: Symbol<
                unsafe extern "C" fn(*const c_char, c_int, c_int, c_int, c_int, c_int, c_int) -> bool,
            > = self.lib.get(b"setDeviceLedEffect")?;
            Ok(f(id.as_ptr(), p[0], p[1], p[2], p[3], p[4], p[5]))
        }
    }
}

impl Drop for Sdk {
    fn drop(&mut self) {
        unsafe {
            if let Ok(f) = self.lib.get::<unsafe extern "C" fn()>(b"sdkQuit") {
                f();
            }
        }
        *TX.lock().unwrap() = None;
    }
}
