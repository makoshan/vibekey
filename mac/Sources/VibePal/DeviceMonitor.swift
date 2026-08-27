import AppKit

/// 诊断日志。app 由 `open` 启动时 stdout 会丢,NSLog 也未必落到 log show,所以直接写文件。
let vibePalLogPath = "/tmp/vibepal_debug.log"
func vlog(_ msg: String) {
    let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(msg)\n"
    if let d = line.data(using: .utf8) {
        if let h = FileHandle(forWritingAtPath: vibePalLogPath) {
            h.seekToEndOfFile(); h.write(d); h.closeFile()
        } else {
            FileManager.default.createFile(atPath: vibePalLogPath, contents: d)
        }
    }
}
import Foundation
import IOKit
import IOKit.hid

/// 设备连接的唯一真相来源。
///
/// 内核是 Kehwin 的 `kwdm.dylib`(随 Ulanzi Studio 安装),它已经实现了厂商通道的
/// 加密、鉴权握手与分帧,回调给出明文。我们只加载本机已装的那一份,绝不分发它。
///
/// 注意:SDK 需要独占设备,所以这里**不再**自己打开 HID 接口——之前那样做会把 SDK 挡在外面。
/// 设备自报的运行状态。字段名与 SDK 回调选择器一一对应:
/// onMessageDeviceBattery:battery:voltage:charging:chargeFull:lowbat:powerOff:
struct DeviceInfo: Equatable {
    var battery: Int?          // 百分比
    var voltageMV: Int?        // 毫伏
    var charging = false
    var chargeFull = false
    var lowBattery = false
    var powerOff = false
    var serial: String?
    var firmware: String?
    var brightness: Int?
    var lightMode: Int?
    var lightBrightnessLevel: Int?

    /// 4063 -> "4.06 V"
    var voltageText: String? {
        voltageMV.map { String(format: "%.2f V", Double($0) / 1000) }
    }
    var batteryText: String { battery.map { "\($0)%" } ?? "--" }
    var chargeText: String {
        if chargeFull { return "已充满" }
        if charging { return "充电中" }
        return "使用电池"
    }
}

final class DeviceMonitor: ObservableObject {
    static weak var shared: DeviceMonitor?

    /// SDK 授权用的 App Key,逆自官方 app 的 sdkInit 调用。传错会静默匹配不到任何设备。
    private static let appKey = "BF1C7D81"
    static let dylib = "/Applications/Ulanzi Studio.app/Contents/Frameworks/kwdm.dylib"

    /// 装了 Ulanzi Studio 才有设备 SDK。没有就是纯哨兵键模式 —— 界面把设备那部分整块藏掉。
    @Published private(set) var sdkAvailable = false
    @Published var isConnected = false
    @Published var deviceID: String?
    @Published var sdkVersion: String?
    @Published var info = DeviceInfo()
    /// 兼容旧界面用法
    var batteryPercent: Int? { info.battery }
    var charging: Bool { info.charging }
    /// 最近若干条设备消息,调试面板用
    @Published var recentMessages: [String] = []
    @Published var lastKeyEvent: String?
    /// 设备固件里当前每个按键的快捷键(index -> 十六进制内容)
    @Published var deviceShortcuts: [Int: String] = [:]
    @Published var status: String = "启动中"

    /// 输入监视权限:SDK 要打开键盘类 HID 接口才能认到设备,没这个权限它会静默失败。
    @Published var inputMonitoringGranted = false

    private var handle: UnsafeMutableRawPointer?

    /// 实体控件被按下时回调(由 App 接到 ShortcutRunner)。
    var onControl: ((ControlID) -> Void)?
    /// 能力探测:见 CapabilityProbe.swift
    @Published var probing = false
    var probeLog: [String] = []
    var probeStart: Date?

    /// 尚未认识的按键编号 —— 真机标定时看这个。
    @Published var unknownKeyIndices: Set<Int> = []

    // MARK: 权限

    static func inputMonitoringStatus() -> IOHIDAccessType { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) }
    @discardableResult
    static func requestInputMonitoring() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 生命周期

    func start() {
        Self.shared = self

        // SDK 是可选的。没装 Ulanzi Studio 就整块跳过:哨兵键那条路不经过这里,照常工作。
        // 权限也一起跳过 —— 「输入监视」只有 SDK 认设备才要,没 SDK 还弹框是白打扰用户。
        guard FileManager.default.fileExists(atPath: Self.dylib) else {
            status = "未装 Ulanzi Studio —— 设备功能关闭,哨兵键仍然工作"
            return
        }

        refreshPermission()
        if !inputMonitoringGranted {
            // 只有「从未问过」时系统才会弹框;被拒过就得手动去设置里开。
            Self.requestInputMonitoring()
            refreshPermission()
        }

        guard let h = dlopen(Self.dylib, RTLD_NOW) else {
            status = "SDK 加载失败: \(String(cString: dlerror()))"
            return
        }
        handle = h
        sdkAvailable = true

        if let vsym = dlsym(h, "sdkVersion") {
            let f = unsafeBitCast(vsym, to: (@convention(c) () -> UnsafePointer<CChar>?).self)
            if let p = f() { sdkVersion = String(cString: p) }
        }
        for (name, cb) in [("registerDeviceConnectedCallbackListener", unsafeBitCast(kwConnected, to: UnsafeRawPointer.self)),
                           ("registerDeviceDisconnectedCallbackListener", unsafeBitCast(kwDisconnected, to: UnsafeRawPointer.self)),
                           ("registerDeviceMessageCallbackListener", unsafeBitCast(kwMessage, to: UnsafeRawPointer.self))] {
            if let sym = dlsym(h, name) {
                let f = unsafeBitCast(sym, to: (@convention(c) (UnsafeRawPointer?) -> Void).self)
                f(cb)
            }
        }
        if let sym = dlsym(h, "sdkInit") {
            let f = unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>?, Bool) -> Void).self)
            Self.appKey.withCString { f($0, true) }
        }
        status = inputMonitoringGranted ? "SDK \(sdkVersion ?? "?") 就绪,等待设备…"
                                        : "缺少「输入监视」权限,设备无法识别"
    }

    func refreshPermission() {
        inputMonitoringGranted = (Self.inputMonitoringStatus() == kIOHIDAccessTypeGranted)
    }

    // MARK: SDK 调用

    @discardableResult
    func call(_ name: String, _ dev: String) -> Bool {
        guard let h = handle, let sym = dlsym(h, name) else { return false }
        let f = unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>?) -> Bool).self)
        return dev.withCString { f($0) }
    }

    @discardableResult
    func setLedEffect(mode: Int32, speed: Int32, bright: Int32, r: Int32, g: Int32, b: Int32) -> Bool {
        guard let h = handle, let dev = deviceID, let sym = dlsym(h, "setDeviceLedEffect") else { return false }
        let f = unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>?, Int32, Int32, Int32, Int32, Int32, Int32) -> Bool).self)
        return dev.withCString { f($0, mode, speed, bright, r, g, b) }
    }

    /// 标定用:连上后依次发几种颜色,把每次调用的返回值写进日志。
    /// 设备当前值是 mode=1 speed=176 bright=4,先沿用,只改 RGB。
    /// 把按键相关的配置全问一遍 —— 设备会自己报出支持哪些键、每个键当前干什么。
    private func probeButtons() {
        guard let dev = deviceID else { return }
        call("getDeviceSupportButtonFunc", dev)
        call("getDeviceAIButtonFunc", dev)
        call("getDeviceHooksMode", dev)
        for i in 0..<8 {
            _ = askIndexed("getDeviceButtonFunc", dev, Int32(i))
            _ = askIndexed("getDeviceButtonShortcutFunction", dev, Int32(i))
        }
    }

    /// 调用 `bool f(const char*, int)` 形式的查询。
    /// 把快捷键写进设备固件。content 是十六进制 macOS 虚拟键码,
    /// 多个键用 | 分隔(如 "FFFFFF|31" = 修饰键+Space)。
    @discardableResult
    func setButtonShortcut(_ dev: String, index: Int32, content: String) -> Bool {
        guard let h = handle, let sym = dlsym(h, "setDeviceButtonShortcutFunction") else { return false }
        let f = unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<CChar>?) -> Bool).self)
        var buf = Array(content.utf8CString)
        let ok = dev.withCString { d in buf.withUnsafeMutableBufferPointer { f(d, index, $0.baseAddress) } }
        vlog("setDeviceButtonShortcutFunction(idx=\(index), \"\(content)\") -> \(ok)")
        return ok
    }

    /// 把一整套预设写进固件。写完之后关掉 VibePal 也生效,换台电脑也带着。
    /// 返回真正写成功的条数 —— 设备离线或某个键被拒绝时不会假装成功。
    ///
    /// **只写变化的槽位**。前台 App 自动切预设会频繁调进来,每次全量下发 6 条
    /// HID 写就是写入风暴;而且多数预设之间只有一两个槽位不同。
    @discardableResult
    func apply(_ profile: VibeProfile) -> Int {
        guard let dev = deviceID else { return 0 }
        var written = 0
        for control in ControlID.allCases {
            let mapping = profile[control]
            // 需要主机参与的(切 App / 粘文本)写哨兵键,由 VibePal 接管;
            // 纯按键仍然直发,这样关掉 VibePal 也照样能用。
            let content = MacroTrigger.needsHost(mapping)
                ? MacroTrigger.content(for: control)
                : mapping.content
            guard !content.isEmpty else { continue }
            guard deviceShortcuts[Int(control.deviceIndex)] != content else { continue }
            if setButtonShortcut(dev, index: control.deviceIndex, content: content) {
                deviceShortcuts[Int(control.deviceIndex)] = content
                written += 1
            }
        }
        vlog("apply(\(profile.name)) -> 写了 \(written) 个槽位(其余未变)")
        return written
    }


    @discardableResult
    func askIndexed(_ name: String, _ dev: String, _ i: Int32) -> Bool {
        guard let h = handle, let sym = dlsym(h, name) else { return false }
        let f = unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>?, Int32) -> Bool).self)
        return dev.withCString { f($0, i) }
    }

    /// 能力自检:逐个试 SDK 的写入类接口,把返回值和回读结果写进 /tmp/vibepal_debug.log。
    /// 改动的项目会在最后还原,不留痕。
    func runSelfTest() {
        guard let dev = deviceID else { return }
        vlog("========== 自检开始 ==========")

        // 1. 写入通路:拿没用的 index 7 试,不动用户的配置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let ok = self.setButtonShortcut(dev, index: 7, content: "7A")   // F1
            vlog("[1] 按键写入 index7=F1 -> \(ok)")
            self.askIndexed("getDeviceButtonShortcutFunction", dev, 7)
            // 双主键:设备的内容本来就是 | 分隔的列表,验证它是否原样保存
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let ok2 = self.setButtonShortcut(dev, index: 7, content: "24|35")  // Return + Esc
                vlog("[1b] 双键写入 index7=24|35 -> \(ok2)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.askIndexed("getDeviceButtonShortcutFunction", dev, 7)
                }
            }
        }
        // 2. 马达:能被手感知,是最可靠的物理反馈
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let a = self.setInt("setDeviceMotorStrength", dev, 3)
            vlog("[2] setDeviceMotorStrength(3) -> \(a)")
            self.call("getDeviceMotorStrength", dev)
            let b = self.setInt2("setDeviceMotorVibrationParams", dev, 3, 200)
            vlog("[2] setDeviceMotorVibrationParams(3,200) -> \(b)")
        }
        // 3. 亮度
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            let ok = self.setInt("setDeviceBrightness", dev, 3)
            vlog("[3] setDeviceBrightness(3) -> \(ok)")
            self.call("getDeviceBrightness", dev)
        }
        // 4. 指示灯:逐个模式,每个停 2 秒便于肉眼观察
        for (i, m) in [1, 2, 3].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.5 + Double(i) * 2.0) {
                let ok = self.setInt("setDeviceIndicatorLightCurrentMode", dev, Int32(m))
                vlog("[4] 指示灯模式 \(m) -> \(ok)")
                self.call("getDeviceIndicatorLightAllParams", dev)
            }
        }
        // 5. 还原:index 7 清空、指示灯回 0、亮度回原值
        DispatchQueue.main.asyncAfter(deadline: .now() + 13.0) {
            _ = self.setButtonShortcut(dev, index: 7, content: "")
            _ = self.setInt("setDeviceIndicatorLightCurrentMode", dev, 0)
            if let b = self.info.brightness { _ = self.setInt("setDeviceBrightness", dev, Int32(b)) }
            vlog("[5] 已还原")
            vlog("========== 自检结束 ==========")
        }
    }

    /// `bool f(const char*, int, int)`
    @discardableResult
    func setInt2(_ name: String, _ dev: String, _ a: Int32, _ b: Int32) -> Bool {
        guard let h = handle, let sym = dlsym(h, name) else { return false }
        let f = unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>?, Int32, Int32) -> Bool).self)
        return dev.withCString { f($0, a, b) }
    }

    private func runLedCalibration() {
        guard let dev = deviceID else { return }
        probeButtons()
        // deviceHooksMode 读回来是 0(关)。这多半就是「AI 状态灯」模式的总开关,
        // 也可能是按键改走上报通道的前提 —— 打开后复查。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, let d = self.deviceID else { return }
            let ok = self.setInt("setDeviceHooksMode", d, 1)
            vlog("setDeviceHooksMode(1) -> \(ok)"); self.recentMessages.insert("→ setDeviceHooksMode(1) = \(ok)", at: 0)
            self.call("getDeviceHooksMode", d)
            // 干净的写入验证:等探测风暴过去,再写 index 6,再单独读回
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                vlog("--- 开始写入验证 ---")
                _ = self.setButtonShortcut(d, index: 6, content: "24")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    vlog("--- 回读 index 6 ---")
                    self.askIndexed("getDeviceButtonShortcutFunction", d, 6)
                }
            }
        }
        // deviceSupportLedEffect 回的是 status=0,所以这台大概率没有 RGB 灯,
        // 而是「指示灯」那一套 API。先把当前参数读回来,再逐个模式试。
        call("getDeviceIndicatorLightAllParams", dev)
    }

    @discardableResult
    func setInt(_ name: String, _ dev: String, _ v: Int32) -> Bool {
        guard let h = handle, let sym = dlsym(h, name) else { return false }
        let f = unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>?, Int32) -> Bool).self)
        return dev.withCString { f($0, v) }
    }

    // MARK: 回调入口

    fileprivate func handleConnected(_ id: String) {
        vlog("CONNECTED \(id)")
        vlog("输入源: \(InputMethodScan.installedInputSources().joined(separator: ", "))")
        for sug in InputMethodScan.voiceSuggestions() { vlog("建议 \(sug.name) -> \(sug.content)  (\(sug.why))") }
        logWorkflowRecipes()
        isConnected = true
        deviceID = id
        status = "已连接"
        for f in ["getDeviceSN", "getDeviceVersion", "getDeviceBattery",
                  "getDeviceBrightness", "getDeviceSupportLedEffect", "getDeviceLedEffect"] {
            call(f, id)
        }
        probeButtons()
        // 自检会改设备设置,不该每次启动都跑;需要时用环境变量触发
        if ProcessInfo.processInfo.environment["VIBEPAL_SELFTEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.runSelfTest() }
        }
    }

    /// 把本机可用的 workflow 配方记一笔 —— 和上面的输入法建议同一个用途:
    /// 界面还没接上时,先让人知道这台机器上有什么能绑。
    private func logWorkflowRecipes() {
        let recipes = WorkflowCatalog.recipes()
        let usable = recipes.filter(\.available)
        vlog("workflow 配方 \(usable.count) 条可用 / 共 \(recipes.count) 条")
        for r in usable.prefix(8) {
            let what = r.mapping.runShortcut.map { "快捷指令「\($0)」" }
                ?? r.mapping.openURL.map { "打开 \($0)" } ?? "?"
            vlog("  · \(r.title) -> \(what)")
        }
        for r in recipes where !r.available {
            vlog("  ✗ \(r.title) —— \(r.howToGet ?? "不可用")")
        }
    }

    fileprivate func handleDisconnected(_ id: String) {
        if id == deviceID || deviceID == nil {
            isConnected = false
            deviceID = nil
            info = DeviceInfo()
            status = "设备已断开"
        }
    }

    fileprivate func handleMessage(_ id: String, _ body: String) {
        let one = body.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        vlog("MSG \(one)")
        recentMessages.insert(one, at: 0)
        if recentMessages.count > 40 { recentMessages.removeLast() }
        if probing, let t = probeStart {
            probeLog.append(String(format: "  [%6.2fs] %@", Date().timeIntervalSince(t), one))
        }

        if one.contains("deviceButtonShortcutFunction"),
           let idx = Self.intField("index", in: one) ?? Self.jsonInt("index", in: one) {
            deviceShortcuts[idx] = Self.jsonString("content", in: one) ?? ""
        }
        if one.contains("deviceKeyEvent") {
            lastKeyEvent = one
            handleKeyEvent(one)
        }
        // battery = NN;  —— SDK 用 plist 风格输出
        parseInfo(one)
    }

    /// SDK 按键编号 → 逻辑控件。真机标定后再确认;未知编号会记进 unknownKeyIndices。
    /// SDK 上报的 index -> 控件。0-based,真机抓包验证(不是猜):
    ///   func 111→index 0(语音)、112→1(✓)、113→2(✕)、110→3(旋钮按下)、
    ///   114→4(旋钮左转)、115→5(旋钮右转)。
    /// 注意 AU05 被打了 isSwitchKeyIndex=1 补丁,SDK 的 index 取自帧 byte[4]。
    static let keyMap: [Int: ControlID] = [
        0: .voice,      // 麦克风键
        1: .confirm,    // ✓
        2: .cancel,     // ✕
        3: .dialPress,  // 旋钮按下
        4: .dialLeft,   // 旋钮左转
        5: .dialRight,  // 旋钮右转
    ]

    private func handleKeyEvent(_ text: String) {
        // SDK 两种输出风格都要认
        func field(_ k: String) -> Int? { Self.intField(k, in: text) ?? Self.jsonInt(k, in: text) }
        guard let idx = field("index") else { return }
        // status: 0 抬起 / 1 按下。只在按下触发,避免一次按键跑两遍。
        // 注意旋钮转动(func 114/115)只发 status=1、无抬起 —— 正好每次转动触发一次。
        let status = field("status") ?? 1
        guard status == 1 else { return }
        lastKeyEvent = "index=\(idx) \(Self.keyMap[idx].map { $0.title } ?? "未知")"
        if let ctrl = Self.keyMap[idx] {
            onControl?(ctrl)
        } else {
            unknownKeyIndices.insert(idx)
        }
    }

    /// 把设备消息里认识的字段收进 info。SDK 有 plist 与 JSON 两种输出风格,都要认。
    private func parseInfo(_ t: String) {
        func num(_ k: String) -> Int? { Self.intField(k, in: t) ?? Self.jsonInt(k, in: t) }
        func str(_ k: String) -> String? { Self.jsonString(k, in: t) ?? Self.plistString(k, in: t) }
        func flag(_ k: String) -> Bool? { num(k).map { $0 != 0 } }

        if t.contains("deviceBattery") {
            info.battery = num("battery") ?? info.battery
            info.voltageMV = num("voltage") ?? info.voltageMV
            info.charging = flag("charging") ?? info.charging
            info.chargeFull = flag("chargeFull") ?? info.chargeFull
            info.lowBattery = flag("lowbat") ?? info.lowBattery
            info.powerOff = flag("powerOff") ?? info.powerOff
        }
        if t.contains("deviceSN") { info.serial = str("code") ?? info.serial }
        if t.contains("deviceVersion") {
            // 固件用 customCode 编码,如 410000 -> 4.1.0
            if let c = num("customCode") {
                let s = String(c)
                info.firmware = s.count >= 6
                    ? "\(Int(s.prefix(1)) ?? 0).\(Int(s.dropFirst().prefix(2)) ?? 0).\(Int(s.dropFirst(3).prefix(2)) ?? 0)"
                    : s
            }
            info.firmware = str("version") ?? info.firmware
        }
        if t.contains("deviceBrightness") { info.brightness = num("value") ?? info.brightness }
        if t.contains("deviceIndicatorLightAllParams") {
            info.lightMode = num("currentMode") ?? info.lightMode
            info.lightBrightnessLevel = num("allOnModeBrightnessLevel") ?? info.lightBrightnessLevel
        }
    }

    /// plist 风格的 `key = value;`(值不带引号)
    static func plistString(_ key: String, in text: String) -> String? {
        guard let r = text.range(of: "\(key) = ") else { return nil }
        let tail = text[r.upperBound...]
        guard let end = tail.firstIndex(of: ";") else { return nil }
        return tail[..<end].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }

    /// SDK 在不同路径上会输出 plist 风格或 JSON 风格,两种都要能解析。
    static func jsonInt(_ key: String, in text: String) -> Int? {
        guard let r = text.range(of: "\"\(key)\" : ") else { return nil }
        return Int(text[r.upperBound...].prefix { $0.isNumber })
    }
    static func jsonString(_ key: String, in text: String) -> String? {
        guard let r = text.range(of: "\"\(key)\" : \"") else { return nil }
        let tail = text[r.upperBound...]
        guard let end = tail.firstIndex(of: "\"") else { return nil }
        return String(tail[..<end])
    }

    /// 从 SDK 的 `key = value;` 文本里取一个整数字段。
    static func intField(_ key: String, in text: String) -> Int? {
        guard let r = text.range(of: "\(key) = ") else { return nil }
        let tail = text[r.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Int(digits)
    }
}

// C 回调必须是无捕获的顶层函数
private let kwConnected: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void = { id, _ in
    let s = id.map { String(cString: $0) } ?? ""
    DispatchQueue.main.async { DeviceMonitor.shared?.handleConnected(s) }
}
private let kwDisconnected: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void = { id, _ in
    let s = id.map { String(cString: $0) } ?? ""
    DispatchQueue.main.async { DeviceMonitor.shared?.handleDisconnected(s) }
}
private let kwMessage: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void = { id, msg in
    let i = id.map { String(cString: $0) } ?? ""
    let m = msg.map { String(cString: $0) } ?? ""
    DispatchQueue.main.async { DeviceMonitor.shared?.handleMessage(i, m) }
}
