import AppKit
import Carbon.HIToolbox

/// 宏模式的哨兵键。
///
/// 设备事件流(0xfffc 厂商口)至今没打通 —— 激活序列还差三帧,见 PROTOCOL.md。
/// 但固件本来就能存快捷键并**自己直接发给系统**,不经过任何 app。
/// 所以把每个控件在固件里写成一个几乎没人用的功能键(F13–F18)当哨兵,
/// VibePal 全局抓这几个键,就拿到了「哪个控件被按了」—— 宏键盘今天就能用。
///
/// 相比直发模式(固件里直接存目标快捷键)的好处:哨兵只是一个信号,
/// 动作可以是任意的 —— 切到目标 App、发组合键、粘一段文本,甚至以后接脚本。
enum MacroTrigger {
    /// 控件 → 哨兵键码。顺序与 `ControlID.deviceIndex` 一致,方便肉眼核对。
    /// ponytail: 固定表不做配置。F13–F18 在 macOS 上没有系统默认绑定,
    /// 真撞上了再说 —— 撞的概率比为此写一套配置界面的成本低。
    static let sentinel: [ControlID: Int] = [
        .voice: kVK_F13,
        .confirm: kVK_F14,
        .cancel: kVK_F15,
        .dialPress: kVK_F16,
        .dialLeft: kVK_F17,
        .dialRight: kVK_F18,
    ]

    /// 写进固件用的设备格式(十六进制虚拟键码)。
    static func content(for control: ControlID) -> String {
        sentinel[control].map { String(format: "%02X", $0) } ?? ""
    }

    /// 这个映射本身就是哨兵键吗?是的话不能注入,否则自己触发自己。
    static func isSentinel(_ content: String, for control: ControlID) -> Bool {
        content.uppercased() == self.content(for: control)
    }

    /// 这条映射非得 VibePal 在跑才能完成吗?
    ///
    /// 只有「切到目标 App」和「粘一段文本」必须走主机 —— 那种才写哨兵键。
    /// 纯按键继续直发进固件,关掉 VibePal 也生效,别平白加一个进程依赖。
    /// 纯修饰键(如地球键)主机注入没有意义,只能靠设备自己发,所以也算不需要主机。
    static func needsHost(_ mapping: ControlMapping) -> Bool {
        guard ShortcutRunner.stroke(from: mapping.content) != nil else { return false }
        // 固件一个槽位只存得下一个和弦,序列只能由主机回放
        if DeviceShortcut.chords(mapping.content).count > 1 { return true }
        if mapping.openURL?.isEmpty == false { return true }
        if mapping.runShortcut?.isEmpty == false { return true }
        return mapping.targetBundleID != nil || !mapping.textToInsert.isEmpty
    }
}

private let vibeHotkeySignature: OSType = 0x56424B59  // 'VBKY'

/// Carbon 的回调是 C 函数指针,捕获不了上下文,所以走单例。
private func vibeHotkeyHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hk = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hk
    )
    guard err == noErr, hk.signature == vibeHotkeySignature else { return noErr }
    let index = Int(hk.id)
    Task { @MainActor in HotkeyListener.shared?.fire(index) }
    return noErr
}

/// 全局监听哨兵键。
///
/// 用 Carbon `RegisterEventHotKey` 而不是 CGEventTap/NSEvent 全局监听:
/// 前者**不需要辅助功能权限**,而且会把按键吞掉,不会漏给前台 App
/// (漏过去的话 F13 会被某些 App 当成自己的快捷键)。
@MainActor
final class HotkeyListener: ObservableObject {
    static private(set) var shared: HotkeyListener?

    /// 哨兵键被按下时回调。
    var onControl: ((ControlID) -> Void)?

    /// 已成功注册的控件 —— 没注册上的说明键被别人占了。
    @Published private(set) var registered: Set<ControlID> = []

    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    /// id → 控件。id 用数组下标,因为 EventHotKeyID.id 只能是数字。
    private var byID: [Int: ControlID] = [:]

    func start() {
        guard handler == nil else { return }
        Self.shared = self

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), vibeHotkeyHandler, 1, &spec, nil, &handler)

        for (i, control) in ControlID.allCases.enumerated() {
            guard let code = MacroTrigger.sentinel[control] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: vibeHotkeySignature, id: UInt32(i))
            let status = RegisterEventHotKey(
                UInt32(code), 0, id, GetEventDispatcherTarget(), 0, &ref
            )
            if status == noErr, ref != nil {
                refs.append(ref)
                byID[i] = control
                registered.insert(control)
            } else {
                vlog("RegisterEventHotKey(\(control.rawValue), vk=0x\(String(code, radix: 16))) 失败 status=\(status)")
            }
        }
        vlog("HotkeyListener 注册 \(registered.count)/\(ControlID.allCases.count) 个哨兵键")
    }

    func stop() {
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        byID.removeAll()
        registered.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        if Self.shared === self { Self.shared = nil }
    }

    fileprivate func fire(_ index: Int) {
        guard let control = byID[index] else { return }
        onControl?(control)
    }

    deinit { }
}
