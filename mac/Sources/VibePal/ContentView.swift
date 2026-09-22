import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var device: DeviceMonitor
    @EnvironmentObject private var profiles: ProfileStore
    @State private var editingControl: ControlID?
    @State private var showingSettings = false
    @State private var showingDeviceInfo = false

    private let canvas = CGSize(width: 1180, height: 700)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / canvas.width, proxy.size.height / canvas.height)
            interface
                .frame(width: canvas.width, height: canvas.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: canvas.width * scale, height: canvas.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: 0xFBFBFC))
        // 换预设 = 换设备里的键位,不只是换界面上的字
        .onChange(of: profiles.selectedProfileID) { _, _ in device.apply(profiles.selectedProfile) }
        .onChange(of: device.isConnected) { _, up in if up { device.apply(profiles.selectedProfile) } }
        .sheet(item: $editingControl) { control in
            MappingEditor(
                control: control,
                mapping: profiles.selectedProfile[control],
                onSave: {
                    profiles.update(control, with: $0)
                    device.apply(profiles.selectedProfile)
                }
            )
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(profileName: profiles.selectedProfile.name) { profiles.resetSelectedProfile() }
        }
    }

    private var interface: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                header
                HStack(spacing: 0) {
                    devicePanel
                    mappingPanel
                }
            }
        }
        .overlay { controlLinks }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 机身控件 → 对应行的水平引线。行距是照着机身量出来的:
    /// 旋钮中心到第一颗按键 133pt,三颗按键之间各 95pt,所以旋钮行必须是 169pt 高。
    /// ponytail: cardTop / dialRowHeight 是跟着照片定的,换 device-source.png 要重量。
    private var controlLinks: some View {
        Canvas { ctx, _ in
            for y in Self.rowCenters {
                var path = Path()
                path.move(to: CGPoint(x: 252, y: y))
                path.addLine(to: CGPoint(x: 441, y: y))
                ctx.stroke(path, with: .color(Color(hex: 0xE2E2E7)), lineWidth: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: 249, y: y - 3, width: 6, height: 6)),
                         with: .color(Color(hex: 0xE2E2E7)))
                ctx.fill(Path(ellipseIn: CGRect(x: 438, y: y - 3, width: 6, height: 6)),
                         with: .color(Color(hex: 0xE2E2E7)))
            }
        }
        .allowsHitTesting(false)
    }

    /// header 72 + padding 54 + 标题行 35 + spacing 25
    private static let cardTop: CGFloat = 186
    private static let dialRowHeight: CGFloat = 169
    private static let rowCenters: [CGFloat] = [
        cardTop + dialRowHeight / 2,
        cardTop + dialRowHeight + 48.5,
        cardTop + dialRowHeight + 144.5,
        cardTop + dialRowHeight + 240.5
    ]

    private var header: some View {
        HStack(spacing: 19) {
            HStack(spacing: 10) {
                figmaAsset("brand-logo", ext: "png")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)
                    .accessibilityHidden(true)
                Text("VibePal")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0D0D0F))
            }

            Menu {
                ForEach(profiles.profiles) { profile in
                    Button(profile.name) { profiles.selectedProfileID = profile.id }
                }
            } label: {
                HStack(spacing: 10) {
                    figmaAsset("briefcase").frame(width: 19, height: 19)
                    Text(profiles.selectedProfile.name)
                        .font(.system(size: 19))
                        .foregroundStyle(Color(hex: 0x1F1F24))
                    Spacer()
                    figmaAsset("chevron-down").frame(width: 14, height: 14)
                }
                .padding(.horizontal, 13)
                .frame(width: 206, height: 42)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xD6D6DB)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 20)

            // 连接状态和电量都只有设备 SDK 才说得出来。没装 Ulanzi Studio 就整块不显示,
            // 而不是显示一排「未连接 / —」—— 那会让人以为是设备坏了。
            if device.sdkAvailable {
                HStack(spacing: 9) {
                    figmaAsset("connection").frame(width: 19, height: 19)
                    Text(device.isConnected ? "已连接" : "未连接").font(.system(size: 17))
                    if device.isConnected {
                        figmaAsset("online").frame(width: 9, height: 9)
                    } else {
                        Circle().fill(Color(hex: 0xC7C7CC)).frame(width: 9, height: 9)
                    }
                    Button { showingDeviceInfo.toggle() } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(Color(hex: 0x8C8D91))
                    }
                    .buttonStyle(.plain)
                    .help("设备详情")
                    .popover(isPresented: $showingDeviceInfo, arrowEdge: .bottom) {
                        deviceStatusCard.frame(width: 260).padding(16)
                    }
                }

                divider(width: 1, height: 26)

                HStack(spacing: 10) {
                    figmaAsset("battery").frame(width: 29, height: 16)
                    Text(device.batteryPercent.map { "\($0)%" } ?? "—").font(.system(size: 17))
                }
                .opacity(device.isConnected ? 1 : 0.35)

                divider(width: 1, height: 26)
            }

            Button { showingSettings = true } label: {
                figmaAsset("settings").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .foregroundStyle(Color(hex: 0x1F1F24))
        .padding(.leading, 104)
        .padding(.trailing, 26)
        .frame(width: 1180, height: 72)
        .background(Color(hex: 0xFDFDFE))
        .overlay(alignment: .bottom) { divider(height: 1) }
    }

    private var devicePanel: some View {
        ZStack(alignment: .top) {
            Color(hex: 0xFBFBFC)
            Color.clear
                .frame(width: 254, height: 628)
                .overlay(alignment: .topLeading) {
                    figmaAsset("device-source", ext: "png")
                        .resizable()
                        .frame(width: 1180, height: 840)
                        .offset(x: -83, y: -113)
                }
                .clipped()
        }
        .frame(width: 400, height: 628)
        .clipped()
        .overlay(alignment: .trailing) { divider(width: 1) }
    }

    /// 设备自报的运行状态,挂在标题栏问号里。全部来自 SDK 消息,没有一项是写死的。
    private var deviceStatusCard: some View {
        let info = device.info
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: batterySymbol(info))
                    .font(.system(size: 17))
                    .foregroundStyle(info.lowBattery ? Color(hex: 0xD0342C)
                                     : info.charging ? Color(hex: 0x17843F) : Color(hex: 0x48484A))
                Text(info.batteryText).font(.system(size: 19, weight: .semibold))
                    .monospacedDigit()
                Text(info.chargeText).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if info.lowBattery {
                    Label("电量低", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: 0xD0342C))
                }
            }

            if let b = info.battery {
                ProgressView(value: Double(b), total: 100)
                    .tint(info.lowBattery ? Color(hex: 0xD0342C) : Color(hex: 0x17843F))
            }

            Divider().padding(.vertical, 1)

            statRow("电压", info.voltageText ?? "--")
            statRow("序列号", info.serial ?? "--", mono: true)
            statRow("固件", info.firmware ?? "--")
            if let m = info.lightMode {
                statRow("指示灯", "模式 \(m)" + (info.lightBrightnessLevel.map { " · 亮度 \($0)" } ?? ""))
            }
            statRow("设备 SDK", device.sdkVersion.map { "kwdm \($0)" } ?? "未加载")
        }
        .opacity(device.isConnected ? 1 : 0.5)
    }

    private func statRow(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(v)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .foregroundStyle(.primary)
        }
    }

    private func batterySymbol(_ i: DeviceInfo) -> String {
        if i.charging { return "battery.100.bolt" }
        switch i.battery ?? 0 {
        case 0..<15: return "battery.0"
        case 15..<40: return "battery.25"
        case 40..<65: return "battery.50"
        case 65..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    private var mappingPanel: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(alignment: .firstTextBaseline) {
                Text("控制映射").font(.system(size: 29, weight: .bold))
                Spacer()
                Text("点按任意一行修改映射，保存即写入设备")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0xA0A0A8))
            }

            VStack(spacing: 0) {
                dialRow
                divider(height: 1).padding(.leading, 88)
                mappingRow(.voice)
                divider(height: 1).padding(.leading, 88)
                mappingRow(.confirm)
                divider(height: 1).padding(.leading, 88)
                mappingRow(.cancel)
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE4E4E9)))
            .shadow(color: .black.opacity(0.045), radius: 14, y: 4)
        }
        .padding(.leading, 41)
        .padding(.trailing, 46)
        .padding(.top, 54)
        .frame(width: 780, height: 628, alignment: .topLeading)
        .background(Color(hex: 0xFBFBFC))
    }

    /// The encoder is one control with three actions, so it gets three chips on one row
    /// instead of three near-identical rows the fixed-height panel has no space for.
    private var dialRow: some View {
        HStack(spacing: 16) {
            controlIcon("dial")
            Text("旋钮").font(.system(size: 21, weight: .semibold))
            Spacer(minLength: 12)
            ForEach([ControlID.dialLeft, .dialPress, .dialRight]) { control in
                DialChip(
                    label: control.title.replacingOccurrences(of: "旋钮", with: ""),
                    content: profiles.selectedProfile[control].content
                ) { editingControl = control }
            }
        }
        .padding(.horizontal, 21)
        .frame(height: Self.dialRowHeight)
    }

    private func mappingRow(_ control: ControlID) -> some View {
        let mapping = profiles.selectedProfile[control]
        return Button { editingControl = control } label: {
            HStack(spacing: 16) {
                controlIcon(control.icon)
                Text(control.title).font(.system(size: 21, weight: .semibold))
                Spacer()
                Keycaps(content: mapping.content, size: 17)
                figmaAsset("chevron-right").frame(width: 16, height: 16)
            }
            .padding(.horizontal, 21)
            .frame(height: 95)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HoverTint())
    }

}

private struct MappingEditor: View {
    @Environment(\.dismiss) private var dismiss
    let control: ControlID
    let onSave: (ControlMapping) -> Void
    @State private var draft: ControlMapping
    @StateObject private var recorder = KeyRecorder()
    @StateObject private var microphone = MicrophoneMonitor()
    @State private var testingMicrophone = false

    init(control: ControlID, mapping: ControlMapping, onSave: @escaping (ControlMapping) -> Void) {
        self.control = control
        self.onSave = onSave
        _draft = State(initialValue: mapping)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                preview
                card {
                    KeyPickerRow(
                        content: $draft.content,
                        onRecord: {
                            recorder.isRecording ? recorder.stop()
                                                 : recorder.start { draft.content = $0 }
                        },
                        isRecording: recorder.isRecording,
                        recordedCount: recorder.count,
                        degraded: recorder.degraded,
                        onRequestPermission: { KeyRecorder.requestAccessibility() }
                    )
                    .padding(14)
                }
                card {
                    VStack(spacing: 0) {
                        field("动作名称") {
                            TextField("给这个动作起个名字", text: $draft.label)
                        }
                        divider(height: 1)
                        field("目标应用") {
                            Picker("", selection: Binding(
                                get: { draft.targetBundleID ?? "" },
                                set: { draft.targetBundleID = $0.isEmpty ? nil : $0 }
                            )) {
                                Text("当前应用").tag("")
                                Text("Claude").tag("com.anthropic.claudefordesktop")
                                Text("Codex").tag("com.openai.codex")
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        divider(height: 1)
                        field("输入文字") {
                            TextField("按键之后自动输入,可留空", text: $draft.textToInsert)
                        }
                    }
                }
                if control == .voice {
                    card { voiceDetail.padding(14) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 20)

            footer
        }
        .frame(width: 520)
        .background(Color(hex: 0xFBFBFC))
        .onDisappear {
            recorder.stop()
            microphone.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            controlIcon(control.icon, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(control.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1F1F24))
                Text("触发时向目标 App 发这组按键")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x8C8D91))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
        .background(Color(hex: 0xFDFDFE))
        .overlay(alignment: .bottom) { divider(height: 1) }
    }

    /// 编辑器里唯一的主角:这组键最终长什么样。录制时边框亮起来。
    private var preview: some View {
        let recording = recorder.isRecording
        return VStack(spacing: 5) {
            Text(DeviceShortcut.describe(draft.content))
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(Color(hex: draft.content.isEmpty ? 0xA0A1A6 : 0x1F1F24))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(draft.content.isEmpty ? "还没有设置" : draft.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(hex: 0xA0A1A6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(hex: recording ? 0x0A84FF : 0xD6D6DB), lineWidth: recording ? 1.8 : 1))
        .animation(.easeOut(duration: 0.15), value: recording)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("测试动作") {
                if ShortcutRunner.hasAccessibilityPermission { ShortcutRunner.run(draft) }
                else { ShortcutRunner.requestAccessibilityPermission() }
            }
            .disabled(draft.content.isEmpty)
            Spacer()
            Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("保存") {
                onSave(draft)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .frame(height: 66)
        .background(Color(hex: 0xFDFDFE))
        .overlay(alignment: .top) { divider(height: 1) }
    }

    /// 白卡片 + 细边框,和主界面的控制映射列表一套皮
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xD6D6DB)))
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x6C6D72))
                .frame(width: 68, alignment: .leading)
            content()
                .font(.system(size: 14))
                .textFieldStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    /// 语音键专属:试麦克风 + 听写工具入口。语音键只发一个 fn/地球键,
    /// 真正听写归系统或输入法管 —— 这里只给入口,不检测不代装。
    private var voiceDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            WaveformView(level: testingMicrophone ? microphone.level : 0.35).frame(height: 32)

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    figmaAsset("microphone-small").frame(width: 16, height: 16)
                    Text("系统默认麦克风").font(.system(size: 14))
                    Spacer()
                    if testingMicrophone { Circle().fill(Color(hex: 0x28C840)).frame(width: 8, height: 8) }
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xD6D6DB)))

                Text(testingMicrophone ? "正在监听" : "按住测试")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 116, height: 42)
                    .background(Color(hex: 0x0A84FF), in: RoundedRectangle(cornerRadius: 8))
                    .scaleEffect(testingMicrophone ? 0.97 : 1)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !testingMicrophone else { return }
                                testingMicrophone = true
                                microphone.start()
                            }
                            .onEnded { _ in
                                testingMicrophone = false
                                microphone.stop()
                            }
                    )
            }

            HStack(spacing: 10) {
                Text("听写工具").foregroundStyle(.secondary)
                Button("系统听写") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
                .buttonStyle(.link)
                ForEach(dictationApps, id: \.name) { app in
                    Link(app.name, destination: app.url)
                }
                Text("· 都是按 fn 说话").foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.system(size: 12))

            if let error = microphone.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
            }
        }
    }

    /// 录一次真实按键,直接存成设备格式 —— 键位表在 KeyCatalog,这里不重复一份。
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var device: DeviceMonitor
    @EnvironmentObject private var hotkeys: HotkeyListener
    let profileName: String
    let reset: () -> Void
    @State private var probeReport: URL?
    /// 权限是去系统设置里改的,改完回来这个 App 不会自己知道 —— 回到前台时重读一次。
    @State private var shortcutGranted = ShortcutRunner.hasAccessibilityPermission

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("设备") {
                    if device.sdkAvailable {
                        LabeledContent("状态", value: device.status)
                        LabeledContent("电量", value: device.batteryPercent.map { "\($0)%\(device.charging ? " 充电中" : "")" } ?? "未知")
                        LabeledContent("SDK", value: device.sdkVersion.map { "kwdm \($0)" } ?? "未加载")
                    } else {
                        // 没 SDK 不是故障,是另一种正常形态 —— 说清楚少了什么,别摆一排「未知」。
                        LabeledContent("设备功能", value: "未开启")
                        Text("装上 Ulanzi Studio 可解锁电量、序列号和写固件。监听哨兵键不需要 SDK,但要先把它们写进固件 —— 没有 SDK 就得在 Ulanzi Studio 里手配一次。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("哨兵键",
                                   value: "\(hotkeys.registered.count)/\(ControlID.allCases.count) 已注册")
                    LabeledContent("当前预设", value: profileName)
                }

                Section("权限") {
                    permissionRow("快捷键", granted: shortcutGranted,
                                  hint: "没有它按键发不出去") { ShortcutRunner.requestAccessibilityPermission() }
                    if device.sdkAvailable {
                        permissionRow("输入监视", granted: device.inputMonitoringGranted,
                                      hint: "没有它 SDK 认不到设备") { DeviceMonitor.openInputMonitoringSettings() }
                    }
                }

                Section("诊断") {
                    if device.sdkAvailable {
                    LabeledContent("能力探测") {
                        HStack(spacing: 8) {
                            if let probeReport {
                                Text(probeReport.lastPathComponent)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Button(device.probing ? "探测中…" : "运行") {
                                device.runCapabilityProbe { url in
                                    probeReport = url
                                    if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                }
                            }
                            .disabled(!device.isConnected || device.probing)
                        }
                    }
                    LabeledContent("最近消息") {
                        Text(device.recentMessages.first ?? "等待设备消息…")
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    } else {
                        Text("设备诊断需要 Ulanzi Studio 提供的 SDK。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("恢复当前预设") { reset() }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460, height: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            shortcutGranted = ShortcutRunner.hasAccessibilityPermission
            device.refreshPermission()
        }
    }

    private func permissionRow(_ title: String, granted: Bool, hint: String, fix: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if granted {
                    Label("已允许", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: 0x17843F))
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(hint).foregroundStyle(.secondary)
                    Button("去开启", action: fix)
                }
            }
        }
    }
}

private struct WaveformView: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<56, id: \.self) { index in
                    let pattern = Double((index * 17) % 11) / 10
                    Capsule()
                        .fill(Color(hex: 0x0A84FF))
                        .frame(width: 2, height: max(2, proxy.size.height * (0.08 + pattern * max(level, 0.18))))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.08), value: level)
        }
    }
}

/// 装哪个都行,共同点是默认拿 fn 唤起 —— 正好是语音键默认发出去的键。
private let dictationApps: [(name: String, url: URL)] = [
    ("Typeless", URL(string: "https://www.typeless.com/downloads")!),
    ("豆包输入法", URL(string: "https://shurufa.doubao.com/pc")!),
    ("微信输入法", URL(string: "https://z.weixin.qq.com")!)
]

/// "⌘ + L → Return" 这类描述拆成一颗颗键帽。数据仍是 describe 的输出,不另建一套解析。
private struct Keycaps: View {
    let content: String
    var size: CGFloat = 15

    var body: some View {
        let text = DeviceShortcut.describe(content)
        if text == "未设置" {
            Text(text).font(.system(size: size)).foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 5) {
                ForEach(Array(text.components(separatedBy: " → ").enumerated()), id: \.offset) { ci, chord in
                    if ci > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: size - 5))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(chord.components(separatedBy: " + ").enumerated()), id: \.offset) { _, key in
                        Text(key)
                            .font(.system(size: size, weight: .medium))
                            .foregroundStyle(Color(hex: 0x3A3A40))
                            .frame(minWidth: size + 9)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(Color(hex: 0xF6F6F8), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xDDDDE3)))
                    }
                }
            }
        }
    }
}

/// 行的 hover 底色。每个实例自带状态,挂上去就行。
private struct HoverTint: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .background(on ? Color(hex: 0xF6F7FA) : .clear)
            .onHover { on = $0 }
    }
}

private struct DialChip: View {
    let label: String
    let content: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x8C8D91))
                Keycaps(content: content, size: 15)
            }
            .frame(width: 108, height: 116)
            .background(hovered ? Color(hex: 0xFAFBFF) : .white,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(hovered ? Color(hex: 0xAFC7F8) : Color(hex: 0xE2E2E7)))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private func controlIcon(_ name: String, size: CGFloat = 51) -> some View {
    ZStack {
        Circle()
            .fill(.white)
            .overlay(Circle().stroke(Color(hex: 0xC9C9D1), lineWidth: 1.2))
        figmaAsset(name).frame(width: size * 0.55, height: size * 0.55)
    }
    .frame(width: size, height: size)
}

private func figmaAsset(_ name: String, ext: String = "svg") -> Image {
    Image(nsImage: NSImage(contentsOf: Bundle.module.url(forResource: name, withExtension: ext)!)!)
}

private func divider(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
    Rectangle().fill(Color(hex: 0xE0E0E5)).frame(width: width, height: height)
}
