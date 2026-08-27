import XCTest
import Carbon.HIToolbox
@testable import VibePal

/// 哨兵键表编错或撞车都是**静默**失效:按键没反应,日志也不报错。
/// 所以这几条断言比看起来重要。
final class MacroTriggerTests: XCTestCase {

    /// 每个控件都得有哨兵,且互不相同 —— 撞了就分不清是哪个键按的
    func testSentinelsAreCompleteAndDistinct() {
        let codes = ControlID.allCases.map { MacroTrigger.sentinel[$0] }
        XCTAssertFalse(codes.contains(nil), "有控件没分配哨兵键")
        let unwrapped = codes.compactMap { $0 }
        XCTAssertEqual(Set(unwrapped).count, ControlID.allCases.count, "哨兵键有重复")
    }

    /// 写进固件的十六进制,必须能被注入侧原样解回来 —— 两边共用一套表示
    func testSentinelContentRoundTrips() throws {
        for control in ControlID.allCases {
            let content = MacroTrigger.content(for: control)
            let stroke = try XCTUnwrap(ShortcutRunner.stroke(from: content), "\(control.rawValue) 的哨兵解不出键码")
            XCTAssertEqual(Int(stroke.0), MacroTrigger.sentinel[control])
            XCTAssertTrue(stroke.1.isEmpty, "哨兵不该带修饰键")
        }
    }

    func testIsSentinelOnlyMatchesOwnControl() {
        XCTAssertTrue(MacroTrigger.isSentinel(MacroTrigger.content(for: .voice), for: .voice))
        XCTAssertFalse(MacroTrigger.isSentinel(MacroTrigger.content(for: .confirm), for: .voice))
    }

    /// 内置预设里如果有哪个动作正好是自己的哨兵键,按一下会自己触发自己。
    /// App 侧有 guard 拦着,但预设本身就不该这么写。
    func testBuiltInProfilesDoNotUseSentinels() {
        let sentinels = Set(ControlID.allCases.map { MacroTrigger.content(for: $0) })
        for profile in VibeProfile.builtIns {
            for control in ControlID.allCases {
                let content = profile[control].content.uppercased()
                XCTAssertFalse(sentinels.contains(content),
                               "预设「\(profile.name)」的\(control.title)用了哨兵键 \(content)")
            }
        }
    }
}

extension MacroTriggerTests {
    /// 纯按键要直发进固件 —— 关掉 VibePal 也得能用
    func testPlainKeystrokeStaysDirect() {
        let m = ControlMapping(label: "下一条", content: "7D")   // ↓
        XCTAssertFalse(MacroTrigger.needsHost(m))
    }

    /// 要切 App 或粘文本的,只能靠主机 → 写哨兵
    func testTargetAppOrTextNeedsHost() {
        XCTAssertTrue(MacroTrigger.needsHost(
            ControlMapping(label: "发送", content: "24", targetBundleID: "com.anthropic.claudefordesktop")))
        XCTAssertTrue(MacroTrigger.needsHost(
            ControlMapping(label: "插入", content: "24", textToInsert: "hello")))
    }

    /// 纯修饰键(地球键)主机注入没意义,即使带 target 也必须直发
    func testLoneModifierNeverNeedsHost() {
        let m = ControlMapping(label: "语音", content: DeviceShortcut.globe,
                               targetBundleID: "com.anthropic.claudefordesktop")
        XCTAssertFalse(MacroTrigger.needsHost(m), "纯修饰键写哨兵的话会彻底失效")
    }
}

/// 序列回放。这是「宏」和「改键」的分界:一个键要能做完一串动作。
extension MacroTriggerTests {
    /// 回归:录「⌘L 然后 Return」以前会存成 37|25|24,回放时后一个键覆盖前一个、
    /// ⌘ 还串到了 Return 上,实际只发出 ⌘Return。
    func testSequenceKeepsBothChordsAndDoesNotBleedModifiers() {
        let content = DeviceShortcut.merge("37|25", "24")
        XCTAssertEqual(content, "37|25,24")

        let strokes = ShortcutRunner.strokes(from: content)
        XCTAssertEqual(strokes.count, 2, "序列被压平了")
        XCTAssertEqual(Int(strokes[0].0), kVK_ANSI_L)
        XCTAssertTrue(strokes[0].1.contains(.maskCommand))
        XCTAssertEqual(Int(strokes[1].0), kVK_Return)
        XCTAssertFalse(strokes[1].1.contains(.maskCommand), "第一个和弦的 ⌘ 串到第二个上了")
    }

    /// 固件一个槽位只存得下一个和弦 → 序列必须由主机回放
    func testSequenceNeedsHostEvenWithoutTargetOrText() {
        XCTAssertTrue(MacroTrigger.needsHost(ControlMapping(label: "两步", content: "37|25,24")))
        XCTAssertFalse(MacroTrigger.needsHost(ControlMapping(label: "一步", content: "37|25")))
    }

    /// 单和弦仍然只发一次 —— 别把改键也变成序列
    func testSingleChordStillOneStroke() {
        XCTAssertEqual(ShortcutRunner.strokes(from: "37|33").count, 1)
        XCTAssertEqual(ShortcutRunner.strokes(from: "").count, 0)
    }

    /// 界面上序列要看得出先后
    func testDescribeShowsOrder() {
        XCTAssertEqual(DeviceShortcut.describe("37|25,24"), "⌘ + L → Return")
    }

    /// 键位选择器是单和弦编辑器,遇到序列取第一个和弦,不能被逗号噎住
    func testPickerDecodesFirstChordOnly() {
        let (mods, keys) = KeyCatalog.decodeAll("37|25,24")
        XCTAssertEqual(mods, ["37"])
        XCTAssertEqual(keys.map(\.code), [UInt16(kVK_ANSI_L)])
    }
}
