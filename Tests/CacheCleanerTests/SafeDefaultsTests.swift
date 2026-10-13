import XCTest
@testable import CacheCleaner

/// 安全默认值的回归测试。
///
/// 背景：v1.1 及更早，「移入废纸篓」的默认值是 `false` —— 也就是**首次使用默认直接删除、
/// 不可恢复**，只靠二次确认弹窗挡着。而同一个init 里的另外两个保护开关
/// （跳过运行中 App、系统缓存强制进废纸篓）默认值都是 `true`，
/// 唯独最需要保护的那一档是关的。
///
/// 这三条断言防止它被改回去。它们测的是**真实的 `CacheCleanerModel.init()`**，
/// 不是在测试里用 UserDefaults 重演一遍逻辑（那样只能证明测试自己没写错）。
@MainActor
final class SafeDefaultsTests: XCTestCase {

    /// 在一个干净的 UserDefaults 上构造 model，并在结束后还原现场
    private func withClearedDefaults<T>(_ keys: [String], _ body: () -> T) -> T {
        let defaults = UserDefaults.standard
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.removeObject(forKey: key) }
        return body()
    }

    /// 没手动设过 ⇒ 必须默认移入废纸篓。false 会让首次使用变成不可恢复的删除。
    func testUseTrashDefaultsToTrueWhenNeverConfigured() {
        withClearedDefaults(["useTrash"]) {
            let model = CacheCleanerModel()
            XCTAssertTrue(model.useTrash,
                          "「移入废纸篓」必须默认开启：默认关闭等于首次使用就可能永久删除用户文件")
        }
    }

    /// 用户手动关过 ⇒ 保持关闭。改默认值不该覆盖用户明确表达过的偏好（不做强推）。
    func testUseTrashKeepsExplicitUserChoice() {
        let defaults = UserDefaults.standard
        let key = "useTrash"
        let saved = defaults.object(forKey: key)
        defer {
            if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        defaults.set(false, forKey: key)
        let model = CacheCleanerModel()
        XCTAssertFalse(model.useTrash,
                       "用户手动关过就该保持关闭 —— 默认值只兜底未配置的情形，不覆盖既有选择")

        defaults.set(true, forKey: key)
        XCTAssertTrue(CacheCleanerModel().useTrash,
                      "用户手动开过就该保持开启")
    }

    /// 三个保护开关的默认值必须全部为 true。
    /// 这条不变量就是当初漏掉 useTrash 的那个缺口 —— 一旦三个里再有一个是 false 就会报红。
    func testAllProtectionSwitchesDefaultToSafe() {
        withClearedDefaults(["skipRunningApps", "useTrash", "forceTrashForSystem"]) {
            let model = CacheCleanerModel()
            XCTAssertTrue(model.skipRunningApps, "跳过运行中 App 应默认开启")
            XCTAssertTrue(model.useTrash, "移入废纸篓应默认开启")
            XCTAssertTrue(model.forceTrashForSystem, "系统缓存强制进废纸篓应默认开启")
        }
    }
}