import AppKit

/// 按前台 App 自动切预设。
///
/// 预设本来就是 per-app 的 ——「Claude」「Codex」「相册整理」—— 却要手动切,等于白设。
/// duckyPad 为这一个功能单开了一个仓库(`duckyPad-profile-autoswitcher`),
/// RMT 有 `WindowHotkeyManager`;两家都单独做,说明是刚需。
///
/// 规则模型抄 duckyPad:**自上而下匹配,首个命中即停**。
/// 但规则不另做一套配置 —— 预设里的控件指向哪个 App,它就是那个 App 的预设,直接推导。
/// 少一份要维护、要跟预设保持同步的数据。
@MainActor
final class AppProfileSwitcher: ObservableObject {
    /// 关掉就完全不介入,用户的手动选择说了算。
    @Published var enabled: Bool = true {
        didSet { if !enabled { restoreFallback() } }
    }
    /// 当前是被哪条规则切过来的,界面上可以显示。nil = 没有规则命中。
    @Published private(set) var activeBundleID: String?

    private weak var store: ProfileStore?
    private var observer: NSObjectProtocol?
    /// 第一次自动切之前用户选的预设。规则不再命中时回到这里,免得把人晾在别的预设上。
    private var fallback: String?

    /// 这个预设是给哪个 App 用的?取控件里出现最多的那个 targetBundleID。
    /// 没有任何控件指定 App 的预设(如「日常工作」)不参与自动切换。
    static func appBundleID(of profile: VibeProfile) -> String? {
        let ids = profile.mappings.values.compactMap(\.targetBundleID).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return nil }
        return Dictionary(grouping: ids, by: { $0 })
            .max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }?.key
    }

    /// bundleID → 预设 id,按预设顺序排列(先定义的优先)。
    static func rules(for profiles: [VibeProfile]) -> [(bundleID: String, profileID: String)] {
        profiles.compactMap { p in appBundleID(of: p).map { (bundleID: $0, profileID: p.id) } }
    }

    /// `initialFrontmost` 默认取真实前台 App —— 启动时先对一次,别等到下次切换。
    /// 参数化出来是为了可测:否则 start() 一调就去读真实环境,测试结果随当时开着什么 App 变。
    func start(_ store: ProfileStore,
               initialFrontmost: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
        guard observer == nil else { return }
        self.store = store
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.frontmostChanged(to: id) }
        }
        frontmostChanged(to: initialFrontmost)
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    func frontmostChanged(to bundleID: String?) {
        guard enabled, let store else { return }
        // VibePal 自己在前台时不切 —— 否则一点自己的窗口预设就跳走,没法编辑
        if bundleID == Bundle.main.bundleIdentifier { return }

        guard let bundleID,
              let hit = Self.rules(for: store.profiles).first(where: { $0.bundleID == bundleID })
        else {
            restoreFallback()
            return
        }
        if fallback == nil { fallback = store.selectedProfileID }
        activeBundleID = bundleID
        select(hit.profileID)
    }

    private func restoreFallback() {
        activeBundleID = nil
        guard let f = fallback else { return }
        fallback = nil
        select(f)
    }

    /// 值没变就不写 —— selectedProfileID 的 didSet 会落盘,还会触发固件下发。
    private func select(_ id: String) {
        guard let store, store.selectedProfileID != id else { return }
        store.selectedProfileID = id
    }

    deinit { }
}
