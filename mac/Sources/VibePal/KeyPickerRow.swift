import SwiftUI
import Carbon.HIToolbox

/// 「按键」这一块:主键 chips + 修饰键开关 + 录制。做成组件嵌进控制映射的编辑器,不另开界面。
///
/// 设备把快捷键存成 `|` 分隔的十六进制键码列表(如 `FFFFFF|31`),
/// 所以多个按键是它原生就支持的形式,不用特殊处理。
/// 组合的完整样子由外面的大预览负责显示,这里只管「怎么改」。
struct KeyPickerRow: View {
    /// 设备格式的内容
    @Binding var content: String
    var onRecord: () -> Void
    var isRecording: Bool
    /// 录制时已经收了几个键,用于提示
    var recordedCount: Int = 0
    /// true = 没有辅助功能权限,系统占用的组合键(⌃+空格 等)录不到
    var degraded: Bool = false
    var onRequestPermission: () -> Void = {}

    private var decoded: (mods: Set<String>, keys: [KeyCatalog.Key]) { KeyCatalog.decodeAll(content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("按键")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0x6C6D72))
                Spacer()
                recordButton
                Button("清空") { content = "" }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: content.isEmpty ? 0xC0C1C6 : 0x6C6D72))
                    .disabled(content.isEmpty)
            }

            keyChips

            HStack(spacing: 6) {
                modToggle(DeviceShortcut.globe) { Image(systemName: "globe").font(.system(size: 13)) }
                modToggle(hex(kVK_Control)) { Text("⌃") }
                modToggle(hex(kVK_Option))  { Text("⌥") }
                modToggle(hex(kVK_Shift))   { Text("⇧") }
                modToggle(hex(kVK_Command)) { Text("⌘") }

                Rectangle().fill(Color(hex: 0xE0E0E5)).frame(width: 1, height: 20).padding(.horizontal, 3)

                Menu {
                    ForEach(KeyCatalog.groups) { g in
                        Menu(g.title) {
                            ForEach(g.keys) { k in
                                Button(k.name) { append(k) }
                            }
                        }
                    }
                } label: {
                    Label(decoded.keys.isEmpty ? "选择按键" : "添加", systemImage: "plus.circle")
                        .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()
            }

            hint
        }
    }

    // MARK: 部件

    /// 一直占一行:空着会在卡片里留个洞,录制提示进出时高度也不跳。
    private var hint: some View {
        HStack(spacing: 6) {
            if isRecording && degraded {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.system(size: 11))
                Text("缺「辅助功能」权限,⌃+空格 这类系统快捷键录不到")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("去授权", action: onRequestPermission)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x0A84FF))
            } else if isRecording {
                Text("现在按下组合键(修饰键+主键可同时按);要录多个组合就依次按,再点「结束」。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("「录制」可以直接按真实组合键,系统占用的键也能录。")
                    .font(.system(size: 11)).foregroundStyle(Color(hex: 0xA0A1A6))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 16)
    }

    private var recordButton: some View {
        Button(action: onRecord) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: isRecording ? 0xE5484D : 0x8C8D91))
                    .frame(width: 7, height: 7)
                    .opacity(isRecording ? 0.35 : 1)
                    .animation(isRecording ? .easeInOut(duration: 0.55).repeatForever() : .default,
                               value: isRecording)
                Text(isRecording ? "结束（\(recordedCount)）" : "录制")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color(hex: isRecording ? 0xE5484D : 0x2E2E33))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color(hex: isRecording ? 0xFDEDED : 0xFFFFFF), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(Color(hex: isRecording ? 0xF0BFC0 : 0xD6D6DB)))
        }
        .buttonStyle(.plain)
    }

    /// 已选的主键,点 ✕ 去掉。空的时候留一句提示,免得这行忽有忽无。
    private var keyChips: some View {
        HStack(spacing: 6) {
            if decoded.keys.isEmpty {
                Text("还没有主键 —— 点「选择按键」挑一个,或直接「录制」")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xA0A1A6))
            } else {
                ForEach(Array(decoded.keys.enumerated()), id: \.offset) { i, k in
                    HStack(spacing: 5) {
                        Text(k.name).font(.system(size: 13, weight: .medium))
                        Button { remove(at: i) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(hex: 0x0A84FF).opacity(0.55))
                    }
                    .foregroundStyle(Color(hex: 0x0A5BD0))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Color(hex: 0x0A84FF).opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 26)
    }

    private func modToggle<L: View>(_ code: String, @ViewBuilder label: () -> L) -> some View {
        let on = decoded.mods.contains(code)
        return Button { toggleMod(code) } label: {
            label()
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(on ? .white : Color(hex: 0x2E2E33))
                .frame(width: 38, height: 30)
                .background(on ? Color(hex: 0x0A84FF) : .white, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(on ? .clear : Color(hex: 0xD6D6DB)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 组装

    private func toggleMod(_ code: String) {
        var (mods, keys) = decoded
        if mods.contains(code) { mods.remove(code) } else { mods.insert(code) }
        content = compose(mods, keys)
    }

    private func append(_ k: KeyCatalog.Key) {
        let (mods, keys) = decoded
        content = compose(mods, keys + [k])
    }

    private func remove(at i: Int) {
        var (mods, keys) = decoded
        guard keys.indices.contains(i) else { return }
        keys.remove(at: i)
        content = compose(mods, keys)
    }

    /// 修饰键按固定顺序在前,主键按录入顺序在后 —— 设备就是这么存的
    private func compose(_ mods: Set<String>, _ keys: [KeyCatalog.Key]) -> String {
        var parts = [DeviceShortcut.globe, hex(kVK_Control), hex(kVK_Option), hex(kVK_Shift), hex(kVK_Command)]
            .filter { mods.contains($0) }
        parts += keys.map(\.content)
        return parts.joined(separator: "|")
    }

    private func hex(_ v: Int) -> String { String(format: "%02X", v) }
}
