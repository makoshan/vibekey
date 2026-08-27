import Foundation
import Carbon.HIToolbox

enum ControlID: String, CaseIterable, Codable, Identifiable {
    case dialLeft, dialPress, dialRight, voice, confirm, cancel
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dialLeft: "旋钮左转"
        case .dialPress: "旋钮按下"
        case .dialRight: "旋钮右转"
        case .voice: "语音键"
        case .confirm: "确认键"
        case .cancel: "取消键"
        }
    }

    /// 列表和编辑器共用的图标资源名
    var icon: String {
        switch self {
        case .dialLeft, .dialPress, .dialRight: "dial"
        case .voice: "microphone"
        case .confirm: "confirm"
        case .cancel: "cancel"
        }
    }

    /// 固件里的按键编号,`setDeviceButtonShortcutFunction` 用的就是它。
    /// ponytail: 0–5 是按上报顺序推的,真机逐个写入回读确认后再定这张表。
    var deviceIndex: Int32 {
        switch self {
        case .voice: 0
        case .confirm: 1
        case .cancel: 2
        case .dialPress: 3
        case .dialLeft: 4
        case .dialRight: 5
        }
    }
}

/// 组一个设备格式的快捷键。用 Carbon 常量而不是手写十六进制,免得抄错键码。
private func vk(_ code: Int, _ mods: Int...) -> String {
    (mods + [code]).map { String(format: "%02X", $0) }.joined(separator: "|")
}

struct ControlMapping: Codable, Equatable {
    var label: String
    /// 设备格式的快捷键。`|` 分隔和弦内部的键,`,` 分隔先后按下的和弦。
    /// 主机注入和写进固件用的是同一份 —— 两套表示迟早会对不上。
    var content: String
    var targetBundleID: String? = nil
    var textToInsert: String = ""
    /// 打开一个 URL。一个字段同时覆盖 http(s)、`shortcuts://`、`alfred://runtrigger/...`、
    /// `raycast://` —— macOS 上的自动化工具都注册了自己的 scheme,不用一家写一个集成。
    var openURL: String? = nil
    /// 运行一条 macOS 快捷指令(按名字)。走 `/usr/bin/shortcuts run`。
    /// 接上快捷指令就等于接上了它的整个动作库,不用自研脚本语言。
    var runShortcut: String? = nil
}

// 新增字段一律用 Optional:合成的 Codable 对 Optional 走 decodeIfPresent,
// 老配置缺这些 key 也能解出来。用非 Optional 的话解码会抛,而 ProfileStore
// 解码失败时会静默回落到内置预设 —— 等于把用户配置悄悄清空。

struct VibeProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var mappings: [ControlID: ControlMapping]

    subscript(control: ControlID) -> ControlMapping {
        mappings[control]!
    }

    static let builtIns: [VibeProfile] = [
        profile("daily", "日常工作", voice: "语音输入", voiceKey: DeviceShortcut.globe),
        profile("claude", "Claude", target: "com.anthropic.claudefordesktop", voice: "聚焦输入", voiceKey: vk(kVK_ANSI_L, kVK_Command), confirm: "发送", cancel: "停止"),
        profile("codex", "Codex", target: "com.openai.codex", voice: "聚焦输入", voiceKey: vk(kVK_ANSI_L, kVK_Command), confirm: "发送", cancel: "停止"),
        VibeProfile(id: "gallery", name: "相册整理", mappings: [
            .dialLeft: ControlMapping(label: "上一张", content: vk(kVK_LeftArrow)),
            .dialPress: ControlMapping(label: "旋转", content: vk(kVK_ANSI_R, kVK_Command)),
            .dialRight: ControlMapping(label: "下一张", content: vk(kVK_RightArrow)),
            .voice: ControlMapping(label: "快速预览", content: vk(kVK_Space)),
            .confirm: ControlMapping(label: "打开", content: vk(kVK_Return)),
            .cancel: ControlMapping(label: "移到废纸篓", content: vk(kVK_Delete, kVK_Command))
        ])
    ]

    private static func profile(
        _ id: String,
        _ name: String,
        target: String? = nil,
        voice: String,
        voiceKey: String,
        confirm: String = "确认",
        cancel: String = "取消"
    ) -> VibeProfile {
        VibeProfile(id: id, name: name, mappings: [
            .dialLeft: ControlMapping(label: "上一条", content: vk(kVK_UpArrow), targetBundleID: target),
            .dialPress: ControlMapping(label: "命令菜单", content: vk(kVK_ANSI_Slash), targetBundleID: target),
            .dialRight: ControlMapping(label: "下一条", content: vk(kVK_DownArrow), targetBundleID: target),
            .voice: ControlMapping(label: voice, content: voiceKey, targetBundleID: target),
            .confirm: ControlMapping(label: confirm, content: vk(kVK_Return), targetBundleID: target),
            .cancel: ControlMapping(label: cancel, content: vk(kVK_Escape), targetBundleID: target)
        ])
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [VibeProfile]
    @Published var selectedProfileID: String { didSet { save() } }

    private let defaults: UserDefaults
    private let profilesKey = "profiles.v1"
    private let selectionKey = "selectedProfile.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedProfiles = defaults.data(forKey: profilesKey)
            .flatMap { try? JSONDecoder().decode([VibeProfile].self, from: $0) }
            ?? VibeProfile.builtIns
        profiles = loadedProfiles
        selectedProfileID = defaults.string(forKey: selectionKey) ?? loadedProfiles[0].id
    }

    var selectedProfile: VibeProfile {
        profiles.first { $0.id == selectedProfileID } ?? profiles[0]
    }

    func update(_ control: ControlID, with mapping: ControlMapping) {
        guard let index = profiles.firstIndex(where: { $0.id == selectedProfile.id }) else { return }
        profiles[index].mappings[control] = mapping
        save()
    }

    func resetSelectedProfile() {
        guard let source = VibeProfile.builtIns.first(where: { $0.id == selectedProfile.id }),
              let index = profiles.firstIndex(where: { $0.id == selectedProfile.id }) else { return }
        profiles[index] = source
        save()
    }

    private func save() {
        defaults.set(selectedProfileID, forKey: selectionKey)
        defaults.set(try? JSONEncoder().encode(profiles), forKey: profilesKey)
    }
}
