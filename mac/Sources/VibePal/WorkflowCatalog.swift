import Foundation

/// macOS workflow 推荐库。
///
/// 为什么不内置一份第三方 workflow 清单:Apple 快捷指令的分享靠 iCloud 链接
/// (RoutineHub / 各种 gallery),链接会失效、内容会变,GitHub 上也没有权威集合 ——
/// 有真实 GitHub 生态的是 Alfred(`zenorocha/alfred-workflows` 12k★)和 Raycast,
/// 但那是两个要另外装的 App。硬编码一份清单等于给自己找维护负担,而且多半在推荐
/// 用户机器上根本没有的东西。
///
/// 所以反过来做:**扫本机实际有什么**,加上几条不依赖任何第三方的系统配方。
/// 推荐出来的每一条都是当场能绑、能用的。
enum WorkflowCatalog {

    /// 一条可以直接绑到控件上的配方。
    struct Recipe: Identifiable, Equatable {
        let id: String
        /// 界面上的名字
        let title: String
        /// 为什么值得占一个键 / 怎么用
        let detail: String
        /// 选中后写进控件的映射
        let mapping: ControlMapping
        /// 本机现在就能用吗。false 的仍然列出来,但要标明缺什么。
        let available: Bool
        /// 不可用时怎么补齐
        let howToGet: String?
    }

    /// 名字里带这些词的快捷指令优先推荐 —— VibePal 的场景是 agent 陪跑,
    /// 这类 workflow 绑到实体键上收益最大。
    private static let agentKeywords = [
        "claude", "codex", "chatgpt", "gpt", "agent", "ai", "llm",
        "翻译", "总结", "润色", "提问", "询问", "问",
    ]

    /// 全部推荐,已排好序:本机已有的在前,要装的在后。
    ///
    /// 依赖用参数注入,测试时不必真去读这台机器。
    static func recipes(
        installedShortcuts: [String]? = nil,
        appExists: (String) -> Bool = { FileManager.default.fileExists(atPath: "/Applications/\($0).app") }
    ) -> [Recipe] {
        let shortcuts = installedShortcuts ?? ShortcutRunner.availableShortcuts()
        return fromInstalledShortcuts(shortcuts) + systemRecipes() + thirdParty(appExists)
    }

    // MARK: 本机已装的快捷指令 —— 最实在的示例库

    static func fromInstalledShortcuts(_ names: [String]) -> [Recipe] {
        let ranked = names.sorted { a, b in
            let (sa, sb) = (isAgentish(a), isAgentish(b))
            return sa == sb ? a.localizedCaseInsensitiveCompare(b) == .orderedAscending : sa
        }
        return ranked.map { name in
            Recipe(
                id: "shortcut:\(name)",
                title: name,
                detail: isAgentish(name)
                    ? "本机已有的快捷指令,看名字是 agent 相关 —— 绑到实体键上按一下就跑"
                    : "本机已有的快捷指令",
                mapping: ControlMapping(label: name, content: "", runShortcut: name),
                available: true,
                howToGet: nil
            )
        }
    }

    static func isAgentish(_ name: String) -> Bool {
        let n = name.lowercased()
        return agentKeywords.contains { n.contains($0) }
    }

    // MARK: 系统配方 —— 不依赖任何第三方,macOS 自带

    static func systemRecipes() -> [Recipe] {
        [
            Recipe(
                id: "system:create-shortcut",
                title: "新建一条快捷指令",
                detail: "打开快捷指令编辑器。想让这个键做点系统里没有的事,从这里开始编 —— "
                      + "快捷指令自带「运行 Shell 脚本」「运行 AppleScript」,不用 VibePal 自己实现。",
                mapping: ControlMapping(label: "新建快捷指令", content: "",
                                        openURL: "shortcuts://create-shortcut"),
                available: true, howToGet: nil
            ),
            Recipe(
                id: "system:gallery",
                title: "浏览快捷指令图库",
                detail: "Apple 官方图库,按场景找现成的,导入后就能在上面这一栏里选到。",
                mapping: ControlMapping(label: "快捷指令图库", content: "",
                                        openURL: "shortcuts://gallery"),
                available: true, howToGet: nil
            ),
        ]
    }

    // MARK: 第三方 —— 装了才推荐,不给没装的人打广告

    static func thirdParty(_ appExists: (String) -> Bool) -> [Recipe] {
        var out: [Recipe] = []
        let hasRaycast = appExists("Raycast")
        out.append(Recipe(
            id: "raycast:ai",
            title: "Raycast · AI 对话",
            detail: "Raycast 的深链可以直接唤起某个扩展。装了之后 `raycast://` 开头的地址"
                  + "都能填进「打开 URL」。",
            mapping: ControlMapping(label: "Raycast AI", content: "",
                                    openURL: "raycast://extensions/raycast/raycast-ai/ai-chat"),
            available: hasRaycast,
            howToGet: hasRaycast ? nil : "未安装 Raycast(raycast.com)"
        ))

        let hasAlfred = appExists("Alfred 5") || appExists("Alfred 4") || appExists("Alfred")
        out.append(Recipe(
            id: "alfred:trigger",
            title: "Alfred · 触发某个 workflow",
            detail: "Alfred 的 workflow 可以挂「外部触发器」,地址形如 "
                  + "alfred://runtrigger/<workflow>/<trigger>/?argument=xxx。"
                  + "生态在 GitHub 上很大(zenorocha/alfred-workflows 12k★)。",
            mapping: ControlMapping(label: "Alfred workflow", content: "",
                                    openURL: "alfred://runtrigger/workflow/trigger/"),
            available: hasAlfred,
            howToGet: hasAlfred ? "把地址里的 workflow/trigger 换成你自己的" : "未安装 Alfred(alfredapp.com)"
        ))
        return out
    }
}
