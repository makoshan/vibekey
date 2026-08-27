import XCTest
@testable import VibePal

@MainActor
final class AppProfileSwitcherTests: XCTestCase {

    private func makeStore() throws -> ProfileStore {
        let d = try XCTUnwrap(UserDefaults(suiteName: "VibePalTests-\(UUID().uuidString)"))
        return ProfileStore(defaults: d)
    }

    /// 规则从预设自身推导:控件指向哪个 App,它就是那个 App 的预设
    func testDerivesAppFromProfile() {
        let byID = Dictionary(uniqueKeysWithValues: VibeProfile.builtIns.map { ($0.id, $0) })
        XCTAssertEqual(AppProfileSwitcher.appBundleID(of: byID["claude"]!), "com.anthropic.claudefordesktop")
        XCTAssertEqual(AppProfileSwitcher.appBundleID(of: byID["codex"]!), "com.openai.codex")
        XCTAssertNil(AppProfileSwitcher.appBundleID(of: byID["daily"]!), "没指定 App 的预设不该参与自动切换")
        XCTAssertNil(AppProfileSwitcher.appBundleID(of: byID["gallery"]!))
    }

    func testRulesOnlyCoverAppProfiles() {
        let rules = AppProfileSwitcher.rules(for: VibeProfile.builtIns)
        XCTAssertEqual(rules.map(\.profileID), ["claude", "codex"])
    }

    /// 切到 Claude → 用 Claude 预设;切到没规则的 App → 回到原来那个,别把人晾着
    func testSwitchesOnMatchAndRestoresOnMiss() throws {
        let store = try makeStore()
        store.selectedProfileID = "gallery"
        let sw = AppProfileSwitcher()
        sw.start(store)

        sw.frontmostChanged(to: "com.anthropic.claudefordesktop")
        XCTAssertEqual(store.selectedProfileID, "claude")
        XCTAssertEqual(sw.activeBundleID, "com.anthropic.claudefordesktop")

        sw.frontmostChanged(to: "com.apple.finder")
        XCTAssertEqual(store.selectedProfileID, "gallery", "没规则命中就该回到用户原来选的")
        XCTAssertNil(sw.activeBundleID)
        sw.stop()
    }

    /// VibePal 自己在前台时不能切 —— 否则一点自己的窗口预设就跳走,没法编辑
    func testOwnAppDoesNotTriggerSwitch() throws {
        let store = try makeStore()
        store.selectedProfileID = "claude"
        let sw = AppProfileSwitcher()
        sw.start(store)
        sw.frontmostChanged(to: Bundle.main.bundleIdentifier)
        XCTAssertEqual(store.selectedProfileID, "claude")
        sw.stop()
    }

    /// 关掉开关要退回用户的选择,不留在自动切过去的预设上
    func testDisablingRestores() throws {
        let store = try makeStore()
        store.selectedProfileID = "daily"
        let sw = AppProfileSwitcher()
        sw.start(store)
        sw.frontmostChanged(to: "com.openai.codex")
        XCTAssertEqual(store.selectedProfileID, "codex")
        sw.enabled = false
        XCTAssertEqual(store.selectedProfileID, "daily")
        sw.stop()
    }
}

/// 新动作:URL 与 macOS 快捷指令
final class WorkflowActionTests: XCTestCase {

    /// 这两种动作固件都做不了,必须写哨兵让 VibePal 接管
    func testURLAndShortcutNeedHost() {
        XCTAssertTrue(MacroTrigger.needsHost(
            ControlMapping(label: "开面板", content: "24", openURL: "raycast://confetti")))
        XCTAssertTrue(MacroTrigger.needsHost(
            ControlMapping(label: "跑流程", content: "24", runShortcut: "Ask ChatGPT")))
        XCTAssertFalse(MacroTrigger.needsHost(ControlMapping(label: "回车", content: "24")))
    }

    /// 老配置里没有这两个 key,必须还能解出来。
    /// 解码一抛异常 ProfileStore 就静默回落到内置预设 —— 等于把用户配置清空。
    func testOldConfigWithoutNewFieldsStillDecodes() throws {
        let json = #"{"label":"发送","content":"24","textToInsert":""}"#
        let m = try JSONDecoder().decode(ControlMapping.self, from: Data(json.utf8))
        XCTAssertEqual(m.content, "24")
        XCTAssertNil(m.openURL)
        XCTAssertNil(m.runShortcut)
    }
}
