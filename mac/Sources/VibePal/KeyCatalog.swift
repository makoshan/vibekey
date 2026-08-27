import Foundation
import Carbon.HIToolbox

/// macOS 全部可选按键。用 Carbon 的 kVK_* 常量而不是手写十六进制,
/// 免得抄错键码 —— 设备存的就是这些虚拟键码的十六进制。
enum KeyCatalog {
    struct Key: Identifiable, Hashable {
        let name: String
        /// nil 表示地球/Fn 键 —— 它没有标准虚拟键码,设备用 FFFFFF 表示
        let code: UInt16?
        var id: String { code.map { String($0) } ?? "globe" }
        /// 写进设备的内容片段
        var content: String { code.map { String(format: "%02X", $0) } ?? DeviceShortcut.globe }
    }

    struct Group: Identifiable {
        let title: String
        let keys: [Key]
        var id: String { title }
    }

    private static func k(_ n: String, _ c: Int) -> Key { Key(name: n, code: UInt16(c)) }

    static let groups: [Group] = [
        Group(title: "常用", keys: [
            Key(name: "🌐 地球 / Fn", code: nil),
            k("Return", kVK_Return), k("Esc", kVK_Escape), k("Space", kVK_Space),
            k("Tab", kVK_Tab), k("Delete", kVK_Delete), k("前向删除", kVK_ForwardDelete),
            k("Enter（小键盘）", kVK_ANSI_KeypadEnter), k("Help", kVK_Help),
        ]),
        Group(title: "方向与翻页", keys: [
            k("↑", kVK_UpArrow), k("↓", kVK_DownArrow),
            k("←", kVK_LeftArrow), k("→", kVK_RightArrow),
            k("Home", kVK_Home), k("End", kVK_End),
            k("Page Up", kVK_PageUp), k("Page Down", kVK_PageDown),
        ]),
        Group(title: "修饰键（单独使用）", keys: [
            k("⌘ Command", kVK_Command), k("⇧ Shift", kVK_Shift),
            k("⌥ Option", kVK_Option), k("⌃ Control", kVK_Control),
            k("Caps Lock", kVK_CapsLock),
            k("右 ⌘", kVK_RightCommand), k("右 ⇧", kVK_RightShift),
            k("右 ⌥", kVK_RightOption), k("右 ⌃", kVK_RightControl),
        ]),
        Group(title: "功能键", keys: [
            k("F1", kVK_F1), k("F2", kVK_F2), k("F3", kVK_F3), k("F4", kVK_F4),
            k("F5", kVK_F5), k("F6", kVK_F6), k("F7", kVK_F7), k("F8", kVK_F8),
            k("F9", kVK_F9), k("F10", kVK_F10), k("F11", kVK_F11), k("F12", kVK_F12),
            k("F13", kVK_F13), k("F14", kVK_F14), k("F15", kVK_F15), k("F16", kVK_F16),
            k("F17", kVK_F17), k("F18", kVK_F18), k("F19", kVK_F19), k("F20", kVK_F20),
        ]),
        Group(title: "字母", keys: [
            k("A", kVK_ANSI_A), k("B", kVK_ANSI_B), k("C", kVK_ANSI_C), k("D", kVK_ANSI_D),
            k("E", kVK_ANSI_E), k("F", kVK_ANSI_F), k("G", kVK_ANSI_G), k("H", kVK_ANSI_H),
            k("I", kVK_ANSI_I), k("J", kVK_ANSI_J), k("K", kVK_ANSI_K), k("L", kVK_ANSI_L),
            k("M", kVK_ANSI_M), k("N", kVK_ANSI_N), k("O", kVK_ANSI_O), k("P", kVK_ANSI_P),
            k("Q", kVK_ANSI_Q), k("R", kVK_ANSI_R), k("S", kVK_ANSI_S), k("T", kVK_ANSI_T),
            k("U", kVK_ANSI_U), k("V", kVK_ANSI_V), k("W", kVK_ANSI_W), k("X", kVK_ANSI_X),
            k("Y", kVK_ANSI_Y), k("Z", kVK_ANSI_Z),
        ]),
        Group(title: "数字与符号", keys: [
            k("0", kVK_ANSI_0), k("1", kVK_ANSI_1), k("2", kVK_ANSI_2), k("3", kVK_ANSI_3),
            k("4", kVK_ANSI_4), k("5", kVK_ANSI_5), k("6", kVK_ANSI_6), k("7", kVK_ANSI_7),
            k("8", kVK_ANSI_8), k("9", kVK_ANSI_9),
            k("- 减号", kVK_ANSI_Minus), k("= 等号", kVK_ANSI_Equal),
            k("[ 左括号", kVK_ANSI_LeftBracket), k("] 右括号", kVK_ANSI_RightBracket),
            k("\\ 反斜杠", kVK_ANSI_Backslash), k("; 分号", kVK_ANSI_Semicolon),
            k("' 引号", kVK_ANSI_Quote), k(", 逗号", kVK_ANSI_Comma),
            k(". 句点", kVK_ANSI_Period), k("/ 斜杠", kVK_ANSI_Slash),
            k("` 反引号", kVK_ANSI_Grave),
        ]),
        Group(title: "小键盘", keys: [
            k("小键盘 0", kVK_ANSI_Keypad0), k("小键盘 1", kVK_ANSI_Keypad1),
            k("小键盘 2", kVK_ANSI_Keypad2), k("小键盘 3", kVK_ANSI_Keypad3),
            k("小键盘 4", kVK_ANSI_Keypad4), k("小键盘 5", kVK_ANSI_Keypad5),
            k("小键盘 6", kVK_ANSI_Keypad6), k("小键盘 7", kVK_ANSI_Keypad7),
            k("小键盘 8", kVK_ANSI_Keypad8), k("小键盘 9", kVK_ANSI_Keypad9),
            k("小键盘 .", kVK_ANSI_KeypadDecimal), k("小键盘 +", kVK_ANSI_KeypadPlus),
            k("小键盘 -", kVK_ANSI_KeypadMinus), k("小键盘 *", kVK_ANSI_KeypadMultiply),
            k("小键盘 /", kVK_ANSI_KeypadDivide), k("小键盘 =", kVK_ANSI_KeypadEquals),
            k("Clear", kVK_ANSI_KeypadClear),
        ]),
        Group(title: "音量", keys: [
            k("音量 +", kVK_VolumeUp), k("音量 −", kVK_VolumeDown), k("静音", kVK_Mute),
        ]),
    ]

    static var allKeys: [Key] { groups.flatMap(\.keys) }

    /// 拆成「修饰键集合 + 主键序列」。设备的内容本来就是 | 分隔的键码列表,
    /// 所以天然支持多个主键(如 "24|35" = Return + Esc)。
    /// 只解**第一个和弦** —— 键位选择器是单和弦编辑器,多和弦序列由录制器产出。
    static func decodeAll(_ content: String) -> (mods: Set<String>, keys: [Key]) {
        var mods = Set<String>()
        var keys: [Key] = []
        let first = DeviceShortcut.chords(content).first ?? content
        let parts = first.split(separator: "|").map { String($0).uppercased() }
        for p in parts {
            if p == DeviceShortcut.globe {
                // 只有一个部件时,地球键本身就是主键;否则当修饰键
                if parts.count == 1 { keys.append(Key(name: "🌐 地球 / Fn", code: nil)) }
                else { mods.insert(p) }
                continue
            }
            guard let v = UInt16(p, radix: 16) else { continue }
            if DeviceShortcut.isModifier(v) { mods.insert(p) }
            else { keys.append(allKeys.first { $0.code == v } ?? Key(name: DeviceShortcut.name(for: v), code: v)) }
        }
        return (mods, keys)
    }

    /// 把设备里的内容拆成「修饰键集合 + 主键」,供界面回显。
    static func decode(_ content: String) -> (mods: Set<String>, key: Key?) {
        var mods = Set<String>()
        var main: Key?
        for part in content.split(separator: "|") {
            let p = String(part).uppercased()
            if p == DeviceShortcut.globe {
                // 地球键既可能是修饰键也可能是主键;有其他键时当修饰键
                if content.contains("|") { mods.insert(p) } else { main = Key(name: "🌐 地球 / Fn", code: nil) }
                continue
            }
            guard let v = UInt16(p, radix: 16) else { continue }
            if DeviceShortcut.isModifier(v) { mods.insert(p) }
            else { main = allKeys.first { $0.code == v } ?? Key(name: DeviceShortcut.name(for: v), code: v) }
        }
        return (mods, main)
    }
}
