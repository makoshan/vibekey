import AppKit
import SwiftUI
import ApplicationServices

/// 按键录制器。
///
/// 语义:**一次「同时按下」= 一个组合**。按住修饰键时只做实时预览,
/// 按下主键那一刻才确认成一条。想录多个组合就依次按,它们会串起来。
///
/// 为什么用 CGEventTap 而不是 NSEvent 本地监听:
/// 像 ⌃+空格(切换输入法)、⌘+空格(Spotlight)这类**系统级快捷键**,
/// 会在送达 app 之前被系统吃掉,本地监听只能收到修饰键、收不到主键。
/// CGEventTap 以 headInsert 插在会话最前端,能先于系统热键拿到事件。
/// 代价是需要「辅助功能」权限;没授权时退回本地监听(录不了系统组合)。
///
/// 状态放在 class 里而不是 View 的 @State:事件回调是长生命周期的,
/// 而 View 是值类型会被反复重建,放 @State 会出现多个监听器各持一份状态副本。
@MainActor
final class KeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var count = 0
    /// 没有辅助功能权限时为 true —— 系统占用的组合键录不了
    @Published private(set) var degraded = false

    private var apply: ((String) -> Void)?
    private var committed = ""
    private var heldMods = ""

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackMonitor: Any?

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// 弹系统授权框(带「打开系统设置」按钮)。比让用户自己去翻设置靠谱得多。
    /// 已授权时不会弹,所以可以放心多调。
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func start(_ apply: @escaping (String) -> Void) {
        stop()
        self.apply = apply
        committed = ""
        heldMods = ""
        count = 0
        isRecording = true
        apply("")

        // 权限可能在 app 运行期间被授予,所以每次录制都重新判定,不缓存
        if !Self.hasAccessibility { Self.requestAccessibility() }

        if Self.hasAccessibility, startTap() {
            degraded = false
            vlog("REC 使用 CGEventTap(可截获系统快捷键)")
        } else {
            degraded = true
            startFallback()
            vlog("REC 退回本地监听(缺辅助功能权限,系统快捷键录不到)")
        }
    }

    // MARK: CGEventTap(能截住系统快捷键)

    private func startTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,      // 插在最前面,先于系统热键
            options: .defaultTap,            // defaultTap 才能吞掉事件
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, ctx in
                guard let ctx else { return Unmanaged.passUnretained(event) }
                let recorder = Unmanaged<KeyRecorder>.fromOpaque(ctx).takeUnretainedValue()
                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                DispatchQueue.main.async {
                    recorder.handle(keyCode: code, modifiers: flags, isFlagsChanged: type == .flagsChanged)
                }
                return nil   // 吞掉,连系统热键也不放行
            },
            userInfo: me
        ) else { return false }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: 退化路径(没有辅助功能权限)

    private func startFallback() {
        fallbackMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
            guard let self, self.isRecording else { return ev }
            self.handle(keyCode: ev.keyCode, modifiers: ev.modifierFlags,
                        isFlagsChanged: ev.type == .flagsChanged)
            return nil
        }
    }

    // MARK: 共用处理

    private func handle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isFlagsChanged: Bool) {
        guard isRecording else { return }
        vlog("REC \(isFlagsChanged ? "flags" : "key") code=0x\(String(keyCode, radix: 16)) mods=\(modifiers.rawValue) committed=\(committed) held=\(heldMods)")

        if isFlagsChanged {
            heldMods = DeviceShortcut.modifiersOnly(modifiers)
            apply?(preview)
            return
        }
        let piece = DeviceShortcut.encode(keyCode: keyCode, modifiers: modifiers)
        guard !piece.isEmpty else { return }
        committed = committed.isEmpty ? piece : DeviceShortcut.merge(committed, piece)
        heldMods = ""
        count += 1
        apply?(committed)
    }

    private var preview: String {
        if heldMods.isEmpty { return committed }
        return committed.isEmpty ? heldMods : committed + "|" + heldMods
    }

    func stop() {
        if isRecording, committed.isEmpty, !heldMods.isEmpty {
            committed = heldMods
            count = 1
            apply?(committed)
        }
        teardown()
        isRecording = false
        heldMods = ""
        apply = nil
    }

    private func teardown() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        runLoopSource = nil
        if let m = fallbackMonitor { NSEvent.removeMonitor(m) }
        fallbackMonitor = nil
    }

    deinit {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let m = fallbackMonitor { NSEvent.removeMonitor(m) }
    }
}
