//! HID transport for the Ulanzi Vibe Key (AU05).
//! Cross-platform via the `hidapi` crate (IOKit on macOS, hidraw/win backends elsewhere).
use anyhow::{anyhow, Result};
use hidapi::{HidApi, HidDevice};

pub const VID: u16 = 0xFFF1;
pub const PID: u16 = 0x00DD;
/// Vendor-defined control interface (buttons in custom mode + LCD/LED out live here).
pub const VENDOR_PAGE: u16 = 0xFFFC;

/// (usage_page, usage, path) for every AU05 HID interface currently attached.
pub fn interfaces(api: &HidApi) -> Vec<(u16, u16, String)> {
    api.device_list()
        .filter(|d| d.vendor_id() == VID && d.product_id() == PID)
        .map(|d| (d.usage_page(), d.usage(), d.path().to_string_lossy().into_owned()))
        .collect()
}

/// Open a specific interface by HID usage page.
pub fn open_page(api: &HidApi, page: u16) -> Result<HidDevice> {
    let info = api
        .device_list()
        .find(|d| d.vendor_id() == VID && d.product_id() == PID && d.usage_page() == page)
        .ok_or_else(|| anyhow!("AU05 interface usage_page=0x{page:04x} not found (is it plugged in?)"))?;
    Ok(info.open_device(api)?)
}

/// Dump raw input reports from `page` as hex. Reversing/dev tool.
pub fn watch(api: &HidApi, page: u16) -> Result<()> {
    let dev = open_page(api, page)?;
    let mut buf = [0u8; 64];
    eprintln!("watching AU05 usage_page=0x{page:04x} — press keys (Ctrl-C to stop)");
    loop {
        let n = dev.read_timeout(&mut buf, 1000)?;
        if n > 0 {
            let hex: String = buf[..n].iter().map(|b| format!("{b:02x} ")).collect();
            println!("IN len={n:2} : {}", hex.trim_end());
        }
    }
}
