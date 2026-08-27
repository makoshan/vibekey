import XCTest
import AppKit
import Carbon.HIToolbox
@testable import VibePal

final class KeyCaptureTests: XCTestCase {
    /// ⌃ + 空格 必须是 ⌃ + Space,不能凭空冒出地球键
    func testControlSpace() {
        let c = DeviceShortcut.encode(keyCode: UInt16(kVK_Space), modifiers: [.control])
        XCTAssertEqual(c, "3B|31")
        XCTAssertEqual(DeviceShortcut.describe(c), "⌃ + Space")
    }

    /// 方向键自带 .function 标志,不能被误判成按了地球键
    func testArrowDoesNotBecomeGlobe() {
        let c = DeviceShortcut.encode(keyCode: UInt16(kVK_UpArrow), modifiers: [.function])
        XCTAssertEqual(c, "7E")
        XCTAssertEqual(DeviceShortcut.describe(c), "↑")
    }

    /// 真按地球键才是地球键
    func testGlobeItself() {
        let c = DeviceShortcut.encode(keyCode: UInt16(kVK_Function), modifiers: [.function])
        XCTAssertEqual(c, DeviceShortcut.globe)
    }

    /// 地球键当修饰键 + 空格(设备出厂就是这个组合)
    func testGlobeAsModifier() {
        let c = DeviceShortcut.encode(keyCode: UInt16(kVK_Space), modifiers: [.function])
        XCTAssertEqual(c, "FFFFFF|31")
    }

    /// 松开修饰键不该产生录入
    func testReleasingModifierIsNotRecorded() {
        XCTAssertNil(DeviceShortcut.recordable(
            keyCode: UInt16(kVK_Control), modifiers: [], isFlagsChanged: true))
        XCTAssertEqual(DeviceShortcut.recordable(
            keyCode: UInt16(kVK_Control), modifiers: [.control], isFlagsChanged: true), "3B")
    }

    /// 连录两个键:完整和弦之间用 `,` 连成序列;修饰键中间态被后一个和弦吸收
    func testMergeTwoKeys() {
        XCTAssertEqual(DeviceShortcut.merge("24", "35"), "24,35")   // Return 然后 Esc = 两个和弦
        XCTAssertEqual(DeviceShortcut.merge("3B", "3B|31"), "3B|31")
    }

    /// 重复按同一个修饰键不该被算作录入了新键(修饰键是集合,会去重)
    func testRepeatedModifierProducesNoChange() {
        XCTAssertEqual(DeviceShortcut.merge("3B", "3B"), "3B")
    }

    /// 两个普通键要能连成序列
    func testTwoPlainKeysBecomeSequence() {
        XCTAssertEqual(DeviceShortcut.merge("00", "0B"), "00,0B")   // A 然后 B
        XCTAssertEqual(DeviceShortcut.describe("00,0B"), "A → B")
    }

    /// 修饰键 + 两个主键
    func testModifierPlusTwoKeys() {
        let step1 = DeviceShortcut.merge("3B", "3B|24")   // ⌃ 然后 ⌃+Return
        XCTAssertEqual(step1, "3B|24")
        XCTAssertEqual(DeviceShortcut.merge(step1, "35"), "3B|24,35")  // ⌃Return 然后 Esc
    }

    /// 同时按 ⌃+空格:修饰键预览 + 主键落下,最终就是一条 3B|31
    func testChordControlSpace() {
        // 按住 ⌃ 时的预览
        XCTAssertEqual(DeviceShortcut.modifiersOnly([.control]), "3B")
        // 主键落下,带着当时按住的修饰键
        let piece = DeviceShortcut.encode(keyCode: UInt16(kVK_Space), modifiers: [.control])
        XCTAssertEqual(piece, "3B|31")
        XCTAssertEqual(DeviceShortcut.describe(piece), "⌃ + Space")
    }

    /// 同时按 ⌘⇧+A
    func testChordMultiModifier() {
        let piece = DeviceShortcut.encode(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command, .shift])
        XCTAssertEqual(piece, "38|37|00")
        XCTAssertEqual(DeviceShortcut.describe(piece), "⇧ + ⌘ + A")
    }

    func testModifiersOnly() {
        XCTAssertEqual(DeviceShortcut.modifiersOnly([]), "")
        XCTAssertEqual(DeviceShortcut.modifiersOnly([.command, .option]), "3A|37")
    }

    /// 设备出厂值必须能被正确解读
    func testDecodeFactoryValues() {
        XCTAssertEqual(DeviceShortcut.describe("24"), "Return")
        XCTAssertEqual(DeviceShortcut.describe("35"), "Esc")
        XCTAssertEqual(DeviceShortcut.describe("FFFFFF|31"), "🌐 + Space")
        let (mods, keys) = KeyCatalog.decodeAll("FFFFFF|31")
        XCTAssertEqual(mods, ["FFFFFF"])
        XCTAssertEqual(keys.count, 1)
    }
}
