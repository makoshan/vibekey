import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum ShortcutRunner {
    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func run(_ mapping: ControlMapping) {
        if let bundleID = mapping.targetBundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { send(mapping) }
            }
        } else {
            send(mapping)
        }
    }

    /// 整段内容 → 按先后顺序要注入的一串组合键。
    static func strokes(from content: String) -> [(CGKeyCode, CGEventFlags)] {
        DeviceShortcut.chords(content).compactMap(stroke(from:))
    }

    /// **第一个和弦** → 可注入的键码 + 修饰键。
    /// 只绑了修饰键(比如纯地球键)时返回 nil:主机侧发一个孤立的修饰键没有意义,
    /// 那种绑定要靠设备自己发。
    static func stroke(from content: String) -> (CGKeyCode, CGEventFlags)? {
        let content = DeviceShortcut.chords(content).first ?? content
        var flags: CGEventFlags = []
        var key: CGKeyCode?
        for part in content.split(separator: "|") {
            let p = String(part).uppercased()
            if p == DeviceShortcut.globe { flags.insert(.maskSecondaryFn); continue }
            guard let v = UInt16(p, radix: 16) else { continue }
            switch Int(v) {
            case kVK_Command, kVK_RightCommand: flags.insert(.maskCommand)
            case kVK_Shift, kVK_RightShift: flags.insert(.maskShift)
            case kVK_Option, kVK_RightOption: flags.insert(.maskAlternate)
            case kVK_Control, kVK_RightControl: flags.insert(.maskControl)
            default: key = CGKeyCode(v)
            }
        }
        return key.map { ($0, flags) }
    }

    /// 和弦之间的间隔。连着发目标 App 会漏掉 —— 它得有时间处理上一个组合。
    /// ponytail: 固定 30ms,真机上发现某些 App 跟不上再调,不做成配置项。
    private static let chordGapMicroseconds: UInt32 = 30_000

    /// 注入是串行且要 sleep 的,不能占着主线程。
    private static let queue = DispatchQueue(label: "dev.mako.vibepal.macro")

    private static func send(_ mapping: ControlMapping) {
        let chords = strokes(from: mapping.content)
        let text = mapping.textToInsert

        // 剪贴板在主线程上先写好,再去后台发按键
        if !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        queue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            for (i, chord) in chords.enumerated() {
                if i > 0 { usleep(chordGapMicroseconds) }
                tap(source, chord.0, chord.1)
            }
            if !text.isEmpty {
                if !chords.isEmpty { usleep(chordGapMicroseconds) }
                tap(source, CGKeyCode(kVK_ANSI_V), .maskCommand)
            }
            openURL(mapping.openURL)
            runShortcut(mapping.runShortcut)
        }
    }

    /// 打开 URL。`shortcuts://`、`alfred://runtrigger/...`、`raycast://` 都走这里 ——
    /// macOS 的自动化工具各自注册了 scheme,一个字段就够,不用一家一个集成。
    private static func openURL(_ raw: String?) {
        guard let raw, !raw.isEmpty, let url = URL(string: raw) else { return }
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
    }

    /// 运行一条 macOS 快捷指令。`shortcuts run` 是同步的,所以留在后台队列上跑。
    private static func runShortcut(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        do { try p.run() } catch { NSLog("VibePal: 运行快捷指令「\(name)」失败 \(error)") }
    }

    /// 本机可用的快捷指令名 —— 界面上给用户挑,免得手打错名字(错了是静默失败)。
    static func availableShortcuts() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["list"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private static func tap(_ source: CGEventSource?, _ key: CGKeyCode, _ flags: CGEventFlags) {
        for isDown in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }
}
