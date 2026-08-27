import SwiftUI

@main
struct VibePalApp: App {
    @StateObject private var device = DeviceMonitor()
    @StateObject private var profiles = ProfileStore()
    @StateObject private var hotkeys = HotkeyListener()
    @StateObject private var autoSwitch = AppProfileSwitcher()

    var body: some Scene {
        Window("VibePal", id: "main") {
            ContentView()
                .environmentObject(device)
                .environmentObject(profiles)
                .environmentObject(hotkeys)
                .environmentObject(autoSwitch)
                .frame(minWidth: 940, minHeight: 560)
                .onAppear {
                    if let url = Bundle.module.url(forResource: "brand-logo", withExtension: "png") {
                        NSApplication.shared.applicationIconImage = NSImage(contentsOf: url)
                    }
                    // 两条触发源,同一套动作:
                    //   device.onControl  — 厂商 0xfffc 事件流(激活序列未通,见 PROTOCOL.md)
                    //   hotkeys.onControl — 固件哨兵键 F13–F18(今天就能用)
                    let run: (ControlID) -> Void = { control in
                        guard ShortcutRunner.hasAccessibilityPermission else {
                            ShortcutRunner.requestAccessibilityPermission()
                            return
                        }
                        let mapping = profiles.selectedProfile[control]
                        // 映射本身就是哨兵键时不能注入,否则自己触发自己
                        guard !MacroTrigger.isSentinel(mapping.content, for: control) else { return }
                        ShortcutRunner.run(mapping)
                    }
                    device.onControl = run
                    hotkeys.onControl = run
                    device.start()
                    hotkeys.start()
                    autoSwitch.start(profiles)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 700)

        MenuBarExtra {
            VStack(alignment: .leading) {
                Text(device.isConnected ? "VibePal 已连接" : "VibePal 未连接")
                Divider()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
            .padding(6)
        } label: {
            Image(systemName: device.isConnected ? "circle.fill" : "circle")
        }
    }
}
