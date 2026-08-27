//! vibekey — third-party CLI/driver for the Ulanzi Vibe Key (AU05).
mod device;
mod sdk;
mod mapping;

use anyhow::Result;
use clap::{Parser, Subcommand};
use hidapi::HidApi;
use std::io::Read;

#[derive(Parser)]
#[command(name = "vibekey", version, about = "Third-party driver for the Ulanzi Vibe Key (AU05)")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// List attached AU05 HID interfaces
    List,
    /// Dump raw input reports (default: vendor page fffc)
    Watch {
        #[arg(long, default_value = "fffc")]
        page: String,
    },
    /// Show the state an agent event maps to
    Map { agent: String, event: String },
    /// Hook entrypoint: reads hook JSON on stdin, resolves + pushes state
    Hook { agent: String, event: String },
    /// Print the settings.json hook snippet to wire an agent to vibekey
    Hooks { agent: String },
    /// Push a state colour to the keyboard's indicator
    SetState {
        /// idle | thinking | working | error | attention | notification | sweeping | sleeping
        state: String,
        /// LED mode enum (not yet decoded — calibration knob)
        #[arg(long, default_value = "1")]
        mode: i32,
        /// animation speed (calibration knob)
        #[arg(long, default_value = "3")]
        speed: i32,
        /// brightness (calibration knob)
        #[arg(long, default_value = "100")]
        bright: i32,
        /// seconds to wait for the device to show up
        #[arg(long, default_value = "8")]
        timeout: u64,
    },
    /// Run the background daemon that owns the device (hooks talk to it over a socket)
    Serve,
    /// 直接下发 LED 效果做标定:vibekey led --mode 1 --speed 176 --bright 4 -r 0 -g 255 -b 0
    Led {
        #[arg(long, default_value = "1")] mode: i32,
        #[arg(long, default_value = "176")] speed: i32,
        #[arg(long, default_value = "4")] bright: i32,
        #[arg(short, long, default_value = "0")] r: i32,
        #[arg(short, long, default_value = "255")] g: i32,
        #[arg(short, long, default_value = "0")] b: i32,
        /// 连上后等几秒再发,以及发完保持几秒
        #[arg(long, default_value = "12")] secs: u64,
    },
    /// Drive the device through the vendor SDK (needs Ulanzi Studio installed)
    Sdk {
        /// seconds to listen for device events
        #[arg(long, default_value = "20")]
        secs: u64,
        /// after connect, try setDeviceIndicatorLightCurrentMode with this value
        #[arg(long)]
        light: Option<i32>,
        /// 也把输出写到这个文件(用 `open -a` 启动时 stdout 会丢)
        #[arg(long)]
        log: Option<String>,
    },
}

fn parse_hex_u16(s: &str) -> u16 {
    u16::from_str_radix(s.trim_start_matches("0x"), 16).unwrap_or(0)
}

fn main() -> Result<()> {
    match Cli::parse().cmd {
        Cmd::List => {
            let api = HidApi::new()?;
            let ifs = device::interfaces(&api);
            if ifs.is_empty() {
                println!("No AU05 (VID 0x{:04x} PID 0x{:04x}) found — plugged in?", device::VID, device::PID);
            }
            for (up, u, path) in ifs {
                let tag = if up == device::VENDOR_PAGE { "  <- vendor/control" } else { "" };
                println!("usage_page=0x{up:04x} usage=0x{u:02x}{tag}\n    {path}");
            }
        }
        Cmd::Watch { page } => device::watch(&HidApi::new()?, parse_hex_u16(&page))?,
        Cmd::Map { agent, event } => match mapping::map_event(&agent, &event) {
            Some(s) => println!("{}", s.as_str()),
            None => { eprintln!("(unmapped)"); std::process::exit(1); }
        },
        Cmd::Hook { agent, event } => {
            let mut _payload = String::new();
            let _ = std::io::stdin().read_to_string(&mut _payload);
            if let Some(st) = mapping::map_event(&agent, &event) {
                // Hooks block the agent, so never stall: short timeout, failure is silent.
                // ponytail: per-invocation SDK init costs seconds. If that shows up in
                // practice, move to a `vibekey serve` daemon + unix socket like the stock app does.
                // Fast path: hand the state to the daemon and get out (~1ms).
                // Hooks block the agent, so we never open the SDK from here.
                if send_to_daemon(st).is_err() {
                    eprintln!("[vibekey] {agent} {event} -> {} (daemon 未运行, 跳过)", st.as_str());
                }
            }
            println!("{{}}"); // some agents expect a JSON object on stdout
        }
        Cmd::Hooks { agent } => print_hooks(&agent),
        Cmd::Sdk { secs, light, log } => run_sdk(secs, light, log)?,
        Cmd::Led { mode, speed, bright, r, g, b, secs } => run_led(mode, speed, bright, r, g, b, secs)?,
        Cmd::Serve => run_serve()?,
        Cmd::SetState { state, mode, speed, bright, timeout } => {
            let st = mapping::State::parse(&state)
                .ok_or_else(|| anyhow::anyhow!("unknown state '{state}'"))?;
            push_state(st, mode, speed, bright, timeout)?;
        }
    }
    Ok(())
}

fn print_hooks(agent: &str) {
    let Some(events) = mapping::events_for(agent) else {
        eprintln!("unknown agent: {agent}");
        return;
    };
    let exe = std::env::current_exe()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| "vibekey".into());
    let mut hooks = serde_json::Map::new();
    for ev in events {
        hooks.insert(ev.to_string(), serde_json::json!([{
            "matcher": "*",
            "hooks": [{ "type": "command", "command": format!("\"{exe}\" hook {agent} {ev}") }]
        }]));
    }
    println!("{}", serde_json::to_string_pretty(&serde_json::json!({ "hooks": hooks })).unwrap());
}


/// Load the vendor SDK, print every device event, optionally poke the indicator light.
fn run_sdk(secs: u64, light: Option<i32>, log: Option<String>) -> Result<()> {
    // 用 open -a 启动时没有终端,把 stdout/stderr 重定向到文件
    if let Some(path) = log.as_deref() {
        if let Ok(f) = std::fs::File::create(path) {
            use std::os::unix::io::AsRawFd;
            unsafe {
                libc_dup2(f.as_raw_fd(), 1);
                libc_dup2(f.as_raw_fd(), 2);
            }
            std::mem::forget(f);
        }
    }
    use std::time::{Duration, Instant};
    let sdk = sdk::Sdk::load()?;
    println!("SDK {} loaded", sdk.version());

    let deadline = Instant::now() + Duration::from_secs(secs);
    let mut dev: Option<String> = None;

    while Instant::now() < deadline {
        while let Ok(ev) = sdk.events.try_recv() {
            match ev {
                sdk::Event::Connected(id) => {
                    println!("[connected] {id}");
                    if dev.is_none() {
                        dev = Some(id.clone());
                        // ask for the basics; answers arrive as Message events
                        for f in [
                            &b"getDeviceSN"[..], b"getDeviceVersion", b"getDeviceBattery",
                            b"getDeviceBrightness", b"getDeviceSupportLedEffect", b"getDeviceLedEffect",
                            b"getDeviceName", b"getDongleSN", b"getDeviceMacAddress",
                            b"getDeviceIndicatorLightAllParams", b"getDeviceHooksMode",
                        ] {
                            let _ = sdk.ask(f, &id);
                        }
                        if let Some(v) = light {
                            match sdk.set_int(b"setDeviceIndicatorLightCurrentMode", &id, v) {
                                Ok(ok) => println!("[light] setIndicatorLightCurrentMode({v}) -> {ok}"),
                                Err(e) => println!("[light] failed: {e}"),
                            }
                        }
                    }
                }
                sdk::Event::Disconnected(id) => println!("[disconnected] {id}"),
                sdk::Event::Message(id, m) => {
                    println!("[msg] {} :: {}", &id[..id.len().min(8)], m.replace('\n', " ").trim());
                }
            }
        }
        std::thread::sleep(Duration::from_millis(120));
    }
    if dev.is_none() {
        println!("(没有检测到设备 — 接收器插好了吗?)");
    }
    Ok(())
}


/// Drive the indicator to a state's colour through the vendor SDK.
fn push_state(st: mapping::State, mode: i32, speed: i32, bright: i32, timeout: u64) -> Result<()> {
    use std::time::Duration;
    let sdk = sdk::Sdk::load()?;
    let dev = sdk
        .wait_for_device(Duration::from_secs(timeout))
        .ok_or_else(|| anyhow::anyhow!("{timeout}s 内没有检测到设备 — 接收器插好了吗?"))?;

    let (r, g, b) = st.rgb();
    let m = if st.animated() { mode } else { mode.min(1) };
    let ok = sdk.set_led(&dev, m, speed, bright, (r, g, b))?;
    eprintln!(
        "[vibekey] {} -> rgb({r},{g},{b}) mode={m} speed={speed} bright={bright} => {}",
        st.as_str(),
        if ok { "ok" } else { "rejected" }
    );
    // give the SDK a moment to flush the frame before we tear it down
    std::thread::sleep(Duration::from_millis(400));
    Ok(())
}


/// Where the daemon listens. Derived from $HOME so it is per-user on every OS
/// without dragging in libc just to call getuid().
fn socket_path() -> std::path::PathBuf {
    match std::env::var("HOME") {
        Ok(h) => std::path::PathBuf::from(h).join(".vibekey.sock"),
        Err(_) => std::env::temp_dir().join("vibekey.sock"),
    }
}

/// Hook fast path: one line to the daemon, then exit.
fn send_to_daemon(st: mapping::State) -> Result<()> {
    use std::io::Write;
    use std::os::unix::net::UnixStream;
    let mut s = UnixStream::connect(socket_path())?;
    s.set_write_timeout(Some(std::time::Duration::from_millis(200)))?;
    writeln!(s, "state {}", st.as_str())?;
    Ok(())
}

/// 客户端发来的一行命令。先 parse 成值再执行,好让解析本身可测。
#[derive(Debug, PartialEq)]
enum DaemonCmd {
    State(mapping::State),
    /// 六个原始参数:mode speed bright r g b
    Led([i32; 6]),
    /// `bool f(const char *deviceId)` 形式的查询
    Ask(String),
    /// `bool f(const char *deviceId, int)` 形式的查询/设置
    AskInt(String, i32),
    /// 把快捷键写进设备固件的第 index 个按键
    Button(i32, String),
}

fn parse_daemon_cmd(line: &str) -> Option<DaemonCmd> {
    let mut it = line.split_whitespace();
    match it.next()? {
        "state" => mapping::State::parse(it.next()?).map(DaemonCmd::State),
        // 参数不齐就整条丢掉 —— 补默认值等于往设备上乱写。
        "led" => <[i32; 6]>::try_from(it.filter_map(|v| v.parse().ok()).collect::<Vec<i32>>())
            .ok()
            .map(DaemonCmd::Led),
        "ask" => Some(DaemonCmd::Ask(it.next()?.to_string())),
        "ask-i" => Some(DaemonCmd::AskInt(it.next()?.to_string(), it.next()?.parse().ok()?)),
        "button" => Some(DaemonCmd::Button(it.next()?.parse().ok()?, it.next()?.to_string())),
        _ => None,
    }
}

fn run_daemon_cmd(sdk: &sdk::Sdk, dev: &str, cmd: DaemonCmd) -> Result<bool> {
    match cmd {
        DaemonCmd::State(st) => {
            let (r, g, b) = st.rgb();
            sdk.set_led(dev, if st.animated() { 2 } else { 1 }, 3, 100, (r, g, b))
        }
        DaemonCmd::Led(p) => sdk.set_led_effect(dev, p),
        DaemonCmd::Ask(f) => sdk.ask(f.as_bytes(), dev),
        DaemonCmd::AskInt(f, v) => sdk.set_int(f.as_bytes(), dev, v),
        DaemonCmd::Button(i, c) => sdk.set_button_shortcut(dev, i, &c),
    }
}

/// 写一行给某个订阅者。写不进去就说明对面没了,调用方据此把它摘掉。
fn line_to(s: &std::os::unix::net::UnixStream, line: &str) -> bool {
    use std::io::Write;
    let mut w = s;
    writeln!(w, "{line}").is_ok()
}

/// Daemon: owns the SDK + device.
///
/// 厂商 SDK 要独占设备,所以整台机器上只有这个进程可以加载它。hook 往里推状态,
/// Mac app 作为订阅者收设备事件、发 LED 和按键配置 —— 谁都不用自己 dlopen。
fn run_serve() -> Result<()> {
    use std::io::{BufRead, BufReader};
    use std::os::unix::net::{UnixListener, UnixStream};
    use std::sync::mpsc::channel;
    use std::time::Duration;

    let path = socket_path();
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path)?;
    eprintln!("[vibekey] daemon listening on {}", path.display());

    let sdk = sdk::Sdk::load()?;
    let version = sdk.version();
    eprintln!("[vibekey] SDK {version} loaded, waiting for device...");

    // accept 和每个客户端的读都在自己的线程里:阻塞读没有半行状态机要维护。
    // SDK 调用全部回到主循环这一根线程上,和之前一样。
    let (new_tx, new_rx) = channel::<UnixStream>();
    let (cmd_tx, cmd_rx) = channel::<String>();
    std::thread::spawn(move || {
        for s in listener.incoming().flatten() {
            if new_tx.send(s).is_err() {
                break;
            }
        }
    });

    let mut subs: Vec<UnixStream> = Vec::new();
    let mut dev: Option<String> = None;

    loop {
        // 1. 新客户端:先补一遍当前状态,免得晚来的一片空白
        while let Ok(stream) = new_rx.try_recv() {
            let Ok(reader) = stream.try_clone() else { continue };
            let _ = line_to(&stream, &format!("sdk {version}"));
            if let Some(id) = dev.as_deref() {
                let _ = line_to(&stream, &format!("connected {id}"));
            }
            subs.push(stream);

            let tx = cmd_tx.clone();
            std::thread::spawn(move || {
                for line in BufReader::new(reader).lines().flatten() {
                    if tx.send(line).is_err() {
                        break;
                    }
                }
            });
        }

        // 2. 设备事件:原样转发,客户端自己挑 deviceKeyEvent / deviceBattery。
        //    标定期间还没认识的消息也照样能看到。
        while let Ok(ev) = sdk.events.try_recv() {
            let line = match ev {
                sdk::Event::Connected(id) => {
                    eprintln!("[vibekey] device connected: {id}");
                    dev = Some(id.clone());
                    format!("connected {id}")
                }
                sdk::Event::Disconnected(id) => {
                    eprintln!("[vibekey] device gone: {id}");
                    if dev.as_deref() == Some(id.as_str()) {
                        dev = None;
                    }
                    format!("disconnected {id}")
                }
                sdk::Event::Message(_, m) => {
                    let m = m.replace('\n', " ");
                    let m = m.trim();
                    if m.is_empty() {
                        continue;
                    }
                    eprintln!("[vibekey] msg: {m}");
                    format!("msg {m}")
                }
            };
            subs.retain(|s| line_to(s, &line));
        }

        // 3. 客户端命令
        while let Ok(line) = cmd_rx.try_recv() {
            let line = line.trim();
            let Some(cmd) = parse_daemon_cmd(line) else {
                if !line.is_empty() {
                    eprintln!("[vibekey] 看不懂的命令: {line}");
                }
                continue;
            };
            let Some(d) = dev.as_deref() else {
                eprintln!("[vibekey] 丢弃「{line}」(设备不在线)");
                continue;
            };
            match run_daemon_cmd(&sdk, d, cmd) {
                Ok(ok) => eprintln!("[vibekey] {line} -> {}", if ok { "ok" } else { "rejected" }),
                Err(e) => eprintln!("[vibekey] {line} -> error {e}"),
            }
        }

        std::thread::sleep(Duration::from_millis(40));
    }
}

extern "C" {
    #[link_name = "dup2"]
    fn libc_dup2(src: i32, dst: i32) -> i32;
}


/// 连上设备后下发一次 LED 效果,用于标定六个参数的含义。
fn run_led(mode: i32, speed: i32, bright: i32, r: i32, g: i32, b: i32, secs: u64) -> Result<()> {
    use std::time::{Duration, Instant};
    let sdk = sdk::Sdk::load()?;
    println!("SDK {} loaded — 等设备…", sdk.version());
    let deadline = Instant::now() + Duration::from_secs(secs);
    let mut dev: Option<String> = None;
    let mut sent = false;
    while Instant::now() < deadline {
        while let Ok(ev) = sdk.events.try_recv() {
            match ev {
                sdk::Event::Connected(id) => { println!("[connected] {id}"); dev = Some(id); }
                sdk::Event::Message(_, m) => {
                    let one = m.replace('\n', " ");
                    if one.contains("LedEffect") || one.contains("Battery") {
                        println!("[msg] {}", one.trim());
                    }
                }
                sdk::Event::Disconnected(_) => {}
            }
        }
        if !sent {
            if let Some(d) = dev.clone() {
                std::thread::sleep(Duration::from_millis(600));
                let ok = sdk.set_led_effect(&d, [mode, speed, bright, r, g, b])?;
                println!("setDeviceLedEffect(mode={mode} speed={speed} bright={bright} rgb={r},{g},{b}) -> {ok}");
                let _ = sdk.ask(b"getDeviceLedEffect", &d);
                sent = true;
            }
        }
        std::thread::sleep(Duration::from_millis(120));
    }
    if dev.is_none() { println!("(没连上设备)"); }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_daemon_commands() {
        assert_eq!(
            parse_daemon_cmd("state working"),
            Some(DaemonCmd::State(mapping::State::Working))
        );
        assert_eq!(
            parse_daemon_cmd("led 1 176 4 0 255 0"),
            Some(DaemonCmd::Led([1, 176, 4, 0, 255, 0]))
        );
        assert_eq!(
            parse_daemon_cmd("button 6 FFFFFF|31"),
            Some(DaemonCmd::Button(6, "FFFFFF|31".into()))
        );
        assert_eq!(
            parse_daemon_cmd("ask-i getDeviceButtonFunc 3"),
            Some(DaemonCmd::AskInt("getDeviceButtonFunc".into(), 3))
        );

        // 参数不齐 / 认不出来的一律不下发
        assert_eq!(parse_daemon_cmd("led 1 2 3"), None);
        assert_eq!(parse_daemon_cmd("led 1 2 3 4 5 6 7"), None);
        assert_eq!(parse_daemon_cmd("state nope"), None);
        assert_eq!(parse_daemon_cmd("button six 24"), None);
        assert_eq!(parse_daemon_cmd(""), None);
    }
}
