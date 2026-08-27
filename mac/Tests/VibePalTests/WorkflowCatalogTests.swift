import XCTest
@testable import VibePal

final class WorkflowCatalogTests: XCTestCase {

    /// agent 相关的快捷指令要排在前面 —— VibePal 的场景就是 agent 陪跑
    func testAgentShortcutsRankFirst() {
        let r = WorkflowCatalog.fromInstalledShortcuts(["设定低电量模式", "Ask ChatGPT", "乘车", "ask-agent-v1"])
        XCTAssertEqual(Array(r.prefix(2)).map(\.title).sorted(), ["Ask ChatGPT", "ask-agent-v1"])
    }

    func testAgentDetectionCoversChineseAndEnglish() {
        XCTAssertTrue(WorkflowCatalog.isAgentish("询问 ChatGPT"))
        XCTAssertTrue(WorkflowCatalog.isAgentish("总结这段"))
        XCTAssertTrue(WorkflowCatalog.isAgentish("ask-agent-v1"))
        XCTAssertFalse(WorkflowCatalog.isAgentish("设定低电量模式"))
    }

    /// 推荐出来的每一条都必须是能直接绑上去的 —— 不能列一堆点了没反应的
    func testEveryRecipeIsBindable() {
        let all = WorkflowCatalog.recipes(installedShortcuts: ["Ask ChatGPT"], appExists: { _ in true })
        XCTAssertFalse(all.isEmpty)
        for r in all {
            let m = r.mapping
            let hasAction = !m.content.isEmpty
                || m.openURL?.isEmpty == false
                || m.runShortcut?.isEmpty == false
                || !m.textToInsert.isEmpty
            XCTAssertTrue(hasAction, "配方「\(r.title)」没有任何动作")
        }
    }

    /// 快捷指令类配方必须走 runShortcut,而且要因此判定为「需要主机」
    func testShortcutRecipeRoutesThroughHost() {
        let r = try! XCTUnwrap(WorkflowCatalog.fromInstalledShortcuts(["Ask ChatGPT"]).first)
        XCTAssertEqual(r.mapping.runShortcut, "Ask ChatGPT")
        XCTAssertTrue(MacroTrigger.needsHost(r.mapping), "快捷指令固件跑不了,必须写哨兵键")
    }

    /// 没装的第三方要标出来,不能假装能用
    func testUninstalledThirdPartyIsMarkedUnavailable() {
        let none = WorkflowCatalog.thirdParty { _ in false }
        XCTAssertFalse(none.isEmpty)
        for r in none {
            XCTAssertFalse(r.available)
            XCTAssertNotNil(r.howToGet, "「\(r.title)」不可用却没说怎么装")
        }
        let all = WorkflowCatalog.thirdParty { _ in true }
        XCTAssertTrue(all.allSatisfy(\.available))
    }

    /// 系统配方在任何 macOS 上都该可用,不依赖装了什么
    func testSystemRecipesAlwaysAvailable() {
        XCTAssertTrue(WorkflowCatalog.systemRecipes().allSatisfy(\.available))
    }

    func testRecipeIDsAreUnique() {
        let ids = WorkflowCatalog.recipes(installedShortcuts: ["A", "B"], appExists: { _ in true }).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

extension WorkflowCatalogTests {
    /// 回归:只有 URL / 快捷指令、没有按键的映射也必须拿到哨兵键。
    /// 早先 needsHost 第一行的 guard 会因为 content 为空直接返回 false,
    /// 于是这种映射永远写不进哨兵,按下去毫无反应。
    func testActionWithoutKeystrokeStillGetsSentinel() {
        XCTAssertTrue(MacroTrigger.needsHost(
            ControlMapping(label: "跑流程", content: "", runShortcut: "Ask ChatGPT")))
        XCTAssertTrue(MacroTrigger.needsHost(
            ControlMapping(label: "开面板", content: "", openURL: "shortcuts://gallery")))
        XCTAssertTrue(MacroTrigger.needsHost(
            ControlMapping(label: "插文本", content: "", textToInsert: "hi")))
    }

    /// 但纯修饰键仍然必须直发 —— 这条不能被上面的修改带坏
    func testLoneModifierStillStaysDirect() {
        XCTAssertFalse(MacroTrigger.needsHost(
            ControlMapping(label: "语音", content: DeviceShortcut.globe,
                           targetBundleID: "com.anthropic.claudefordesktop")))
    }
}
