import XCTest
import Carbon.HIToolbox
@testable import VibePal

@MainActor
final class ProfileStoreTests: XCTestCase {
    // 下面两条用的是手写的 SDK 文本样例,不是真机抓包 —— 只验证解析和查表,不作为硬件证据。
    func testParsesIntFieldsFromSDKMessage() {
        let sample = "deviceBattery { battery = 32; charging = 0; voltage = 3900; }"

        XCTAssertEqual(DeviceMonitor.intField("battery", in: sample), 32)
        XCTAssertEqual(DeviceMonitor.intField("charging", in: sample), 0)
        XCTAssertNil(DeviceMonitor.intField("percent", in: sample))
    }

    func testSDKKeyIndexMapsToLogicalControl() {
        let sample = "deviceKeyEvent { index = 2; status = 1; }"
        let index = DeviceMonitor.intField("index", in: sample)

        XCTAssertEqual(index.flatMap { DeviceMonitor.keyMap[$0] }, .confirm)
    }

    func testEncoderHasThreeIndependentActions() {
        XCTAssertEqual(DeviceMonitor.keyMap[4], .dialPress)
        XCTAssertEqual(DeviceMonitor.keyMap[5], .dialLeft)
        XCTAssertEqual(DeviceMonitor.keyMap[6], .dialRight)
        // 每个内置预设都要给三个旋钮动作各配一条快捷键,不能再共用一条。
        for profile in VibeProfile.builtIns {
            let contents = [profile[.dialLeft], profile[.dialPress], profile[.dialRight]].map(\.content)
            XCTAssertEqual(Set(contents).count, 3, profile.name)
        }
    }

    func testBuiltInProfilesCoverDailyClaudeCodexAndGallery() {
        XCTAssertEqual(VibeProfile.builtIns.map(\.name), ["日常工作", "Claude", "Codex", "相册整理"])
        XCTAssertTrue(VibeProfile.builtIns.allSatisfy { $0.mappings.count == ControlID.allCases.count })
    }

    func testGalleryPresetUsesQuickLookAndFinderDelete() throws {
        let gallery = try XCTUnwrap(VibeProfile.builtIns.first { $0.name == "相册整理" })
        XCTAssertEqual(gallery[.voice].content, "31")                 // Space
        XCTAssertEqual(gallery[.cancel].content, "37|33")             // ⌘ + Delete
    }

    func testProfileEditsPersist() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "VibePalTests-\(UUID().uuidString)"))
        let store = ProfileStore(defaults: defaults)
        store.selectedProfileID = "codex"
        store.update(.confirm, with: ControlMapping(label: "运行", content: "24"))

        let restored = ProfileStore(defaults: defaults)
        XCTAssertEqual(restored.selectedProfileID, "codex")
        XCTAssertEqual(restored.selectedProfile[.confirm].label, "运行")
    }

    func testDeviceShortcutRoundTrip() {
        // 录一次 ⇧⌘G,应该编成「修饰键在前、主键在后」的设备格式
        let content = DeviceShortcut.encode(keyCode: UInt16(kVK_ANSI_G), modifiers: [.shift, .command])
        XCTAssertEqual(content, "38|37|05")
        XCTAssertEqual(DeviceShortcut.describe(content), "⇧ + ⌘ + G")

        // 地球键没有标准键码,单独按下时它自己就是主键
        XCTAssertEqual(DeviceShortcut.encode(keyCode: UInt16(kVK_Function), modifiers: [.function]), "FFFFFF")
        XCTAssertEqual(DeviceShortcut.describe("FFFFFF|31"), "🌐 + Space")
        XCTAssertEqual(DeviceShortcut.describe(""), "未设置")

        let (mods, key) = KeyCatalog.decode("38|37|05")
        XCTAssertEqual(mods, ["38", "37"])
        XCTAssertEqual(key?.code, UInt16(kVK_ANSI_G))
    }

    func testRunnerTurnsDeviceContentIntoInjectableStroke() throws {
        let (key, flags) = try XCTUnwrap(ShortcutRunner.stroke(from: "38|37|05"))
        XCTAssertEqual(key, CGKeyCode(kVK_ANSI_G))
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskShift))
        XCTAssertFalse(flags.contains(.maskControl))

        // 只绑修饰键时主机侧没得发 —— 那种绑定归设备自己
        XCTAssertNil(ShortcutRunner.stroke(from: DeviceShortcut.globe))
        XCTAssertNil(ShortcutRunner.stroke(from: ""))
    }

    func testEveryBuiltInMappingIsInjectableOrDeviceOnly() {
        for profile in VibeProfile.builtIns {
            for control in ControlID.allCases {
                let content = profile[control].content
                XCTAssertFalse(content.isEmpty, "\(profile.name)/\(control.title) 没有键位")
                // 内置预设里只有语音键允许是纯修饰键(地球键)
                if control != .voice {
                    XCTAssertNotNil(ShortcutRunner.stroke(from: content), "\(profile.name)/\(control.title)")
                }
            }
        }
    }

    /// 40 个手打的符号名,拼错一个就是探测时静默少一条。用 dlsym 直接对一遍。
    func testProbeOnlyNamesSymbolsTheSDKExports() throws {
        guard FileManager.default.fileExists(atPath: DeviceMonitor.dylib) else {
            throw XCTSkip("未安装 Ulanzi Studio,跳过 SDK 符号校验")
        }
        let handle = try XCTUnwrap(dlopen(DeviceMonitor.dylib, RTLD_NOW))
        defer { dlclose(handle) }

        let all = CapabilityProbe.plain + CapabilityProbe.indexed
        for name in all {
            XCTAssertNotNil(dlsym(handle, name), "SDK 里没有 \(name)")
        }
        XCTAssertEqual(Set(all).count, all.count, "探测清单里有重复")
    }

    func testMicrophoneLevelNormalization() {
        XCTAssertEqual(MicrophoneMonitor.normalizedLevel(decibels: -60), 0, accuracy: 0.001)
        XCTAssertEqual(MicrophoneMonitor.normalizedLevel(decibels: -30), 0.5, accuracy: 0.001)
        XCTAssertEqual(MicrophoneMonitor.normalizedLevel(decibels: 0), 1, accuracy: 0.001)
    }
}
