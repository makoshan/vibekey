import AppKit
import Carbon.HIToolbox

/// 设备里快捷键的存储格式。两级分隔符:
///   `|` 分隔**和弦内部**的键(同时按下),`,` 分隔**先后按下的和弦**。
/// 逆自设备自报的配置,例如:
///   "24"          = Return
///   "35"          = Esc
///   "FFFFFF|31"   = 地球键 + Space(同时)
///   "FFFFFF"      = 地球键(Fn)
///   "37|25,24"    = ⌘L,然后 Return(两个和弦)
///
/// 固件只存得下一个和弦,所以多和弦的内容写不进设备 —— 那种会改写成哨兵键
/// 由 VibePal 回放,见 `MacroTrigger.needsHost`。
enum DeviceShortcut {
    /// 地球/Fn 键没有标准虚拟键码,设备用全 F 表示。
    static let globe = "FFFFFF"

    /// 把一次真实按键(含修饰键)编码成设备格式。
    /// macOS 会在这些键上**自动**置 .function 标志(不代表用户按了地球键)。
    /// 不排除的话,录一个 ↑ 会变成「🌐 + ↑」。
    private static let impliesFunctionFlag: Set<Int> = [
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        kVK_ForwardDelete, kVK_Help,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// 把一次真实按键(含修饰键)编码成设备格式。没有任何内容时返回空串。
    static func encode(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        // 地球键:要么按的就是它本身,要么它被当修饰键按住。
        // 但方向键/F 键这类会自带 .function,必须排除,否则凭空多出一个 🌐。
        let isGlobeItself = Int(keyCode) == kVK_Function
        let globeHeld = modifiers.contains(.function) && !impliesFunctionFlag.contains(Int(keyCode))
        if isGlobeItself || globeHeld { parts.append(globe) }

        if modifiers.contains(.control)  { parts.append(hexOf(kVK_Control)) }
        if modifiers.contains(.option)   { parts.append(hexOf(kVK_Option)) }
        if modifiers.contains(.shift)    { parts.append(hexOf(kVK_Shift)) }
        if modifiers.contains(.command)  { parts.append(hexOf(kVK_Command)) }
        // 单独按修饰键时不再重复追加
        if !isModifier(keyCode) { parts.append(hex(keyCode)) }

        return parts.joined(separator: "|")   // 空就是空,不再兜底成地球键
    }

    /// 只把修饰键编码出来(录制时做实时预览用)。
    static func modifiersOnly(_ modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.function) { parts.append(globe) }
        if modifiers.contains(.control)  { parts.append(hexOf(kVK_Control)) }
        if modifiers.contains(.option)   { parts.append(hexOf(kVK_Option)) }
        if modifiers.contains(.shift)    { parts.append(hexOf(kVK_Shift)) }
        if modifiers.contains(.command)  { parts.append(hexOf(kVK_Command)) }
        return parts.joined(separator: "|")
    }

    /// 键码对应的修饰键标志,用来判断 flagsChanged 是「按下」还是「松开」。
    static func flag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand: return .command
        case kVK_Shift, kVK_RightShift:     return .shift
        case kVK_Option, kVK_RightOption:   return .option
        case kVK_Control, kVK_RightControl: return .control
        case kVK_Function:                  return .function
        case kVK_CapsLock:                  return .capsLock
        default: return nil
        }
    }

    /// 录制时该不该记这个事件。flagsChanged 既有按下也有松开,只认按下 ——
    /// 否则松开 ⌃ 会被当成一次新录入。
    static func recordable(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isFlagsChanged: Bool) -> String? {
        if isFlagsChanged {
            guard let f = flag(for: keyCode), modifiers.contains(f) else { return nil }
        }
        let s = encode(keyCode: keyCode, modifiers: modifiers)
        return s.isEmpty ? nil : s
    }

    /// 反向:把设备里的内容翻译成人能读的样子,用于界面显示。
    static func describe(_ content: String) -> String {
        if content.isEmpty { return "未设置" }
        let list = chords(content)
        if list.count > 1 { return list.map(describeChord).joined(separator: " → ") }
        return describeChord(content)
    }

    /// 单个和弦的人类可读形式。
    private static func describeChord(_ content: String) -> String {
        content.split(separator: "|").map { part -> String in
            if part.uppercased() == globe { return "🌐" }
            guard let v = UInt16(part, radix: 16) else { return String(part) }
            return name(for: v)
        }.joined(separator: " + ")
    }

    /// 接上一个和弦。
    ///
    /// 两种情况要分开:
    /// - `a` 只是「修饰键按住了」的中间态,`b` 是真正落下的完整和弦 → **吸收**,
    ///   仍是一个和弦(录 ⌃+空格 不该变成「⌃ 然后 ⌃+空格」)。
    /// - `a` 已经是完整和弦 → `b` 是**下一个**和弦,用 `,` 接上。
    ///
    /// 早先那版无论哪种都把修饰键取并集再压平,于是「⌘L 然后 Return」
    /// 存成 `37|25|24`,回放时后一个键覆盖前一个、⌘ 还串了过去,实际只发出 ⌘Return。
    static func merge(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        if isModifiersOnly(a), partsSet(a).isSubset(of: partsSet(b)) { return b }
        return a + "," + b
    }

    private static func partsSet(_ chord: String) -> Set<String> {
        Set(chord.split(separator: "|").map { String($0).uppercased() })
    }

    /// 这个和弦里全是修饰键(含地球键)、没有主键吗?
    private static func isModifiersOnly(_ chord: String) -> Bool {
        let parts = chord.split(separator: "|").map { String($0).uppercased() }
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { p in
            p == globe || UInt16(p, radix: 16).map(isModifier) == true
        }
    }

    /// 拆成一个个和弦。空串返回空数组。
    static func chords(_ content: String) -> [String] {
        content.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    static func hexOf(_ v: Int) -> String { String(format: "%02X", v) }

    static func isModifier(_ k: UInt16) -> Bool {
        [kVK_Command, kVK_Shift, kVK_Option, kVK_Control,
         kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl,
         kVK_Function, kVK_CapsLock].contains(Int(k))
    }

    private static func hex(_ v: UInt16) -> String { String(format: "%02X", v) }

    static func name(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_Space: return "Space"
        case kVK_Delete: return "Delete"
        case kVK_Tab: return "Tab"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_Command: return "⌘"
        case kVK_Shift: return "⇧"
        case kVK_Option: return "⌥"
        case kVK_Control: return "⌃"
        case kVK_Function: return "🌐"
        default:
            // 用当前键盘布局把键码翻译成字符
            if let s = charFor(keyCode) { return s.uppercased() }
            return String(format: "0x%02X", keyCode)
        }
    }

    private static func charFor(_ keyCode: UInt16) -> String? {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// 装了哪些输入法 —— 用来给语音键推荐合适的快捷键。
enum InputMethodScan {
    struct Suggestion: Identifiable {
        let id = UUID()
        let name: String
        let content: String
        let why: String
    }

    /// 用户**已启用**的输入源(不是全部已安装的 —— 那会返回几百个系统布局)。
    static func installedInputSources() -> [String] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.compactMap { src in
            guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
        }
    }

    /// 语音输入的候选方案,按「装了什么」排序。
    static func voiceSuggestions() -> [Suggestion] {
        let ids = installedInputSources().map { $0.lowercased() }
        var out: [Suggestion] = []
        if ids.contains(where: { $0.contains("tencent") || $0.contains("wetype") }) {
            out.append(.init(name: "腾讯输入法 · 语音", content: DeviceShortcut.globe,
                             why: "检测到腾讯输入法,它的语音输入默认绑在地球键"))
        }
        if ids.contains(where: { $0.contains("sogou") }) {
            out.append(.init(name: "搜狗输入法 · 语音", content: DeviceShortcut.globe,
                             why: "检测到搜狗输入法,语音输入默认走地球键"))
        }
        if ids.contains(where: { $0.contains("baidu") }) {
            out.append(.init(name: "百度输入法 · 语音", content: DeviceShortcut.globe,
                             why: "检测到百度输入法,语音输入默认走地球键"))
        }
        out.append(.init(name: "系统听写", content: DeviceShortcut.globe,
                         why: "macOS 听写默认是连按两次地球键/Fn"))
        return out
    }
}
