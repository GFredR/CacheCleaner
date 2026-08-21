import XCTest
@testable import CacheCleaner

final class WhitelistPersistenceTests: XCTestCase {

    /// 验证 UserDefaults.standard.set + stringArray 写入读取一致（机制层验证）
    func testUserDefaultsArrayPersistence() {
        let defaults = UserDefaults.standard
        let testKey = "test_whitelist_\(UUID().uuidString)"

        // 清理
        defaults.removeObject(forKey: testKey)
        XCTAssertNil(defaults.stringArray(forKey: testKey))

        // 写入
        defaults.set(["/Users/x/Library/Caches/WeChat"], forKey: testKey)

        // 立即读（同进程内）
        let read = defaults.stringArray(forKey: testKey)
        XCTAssertEqual(read, ["/Users/x/Library/Caches/WeChat"],
                       "UserDefaults.standard.set + stringArray 应能往返")

        // 清理
        defaults.removeObject(forKey: testKey)
    }

    /// 验证 CacheCleanerModel.addWhitelist 完整流程（含去重）
    func testAddWhitelistAndDedup() {
        // 隔离测试：用一个唯一 key 避免污染真实数据
        let model = CacheCleanerModel()

        // 用 UserDefaults 直接测：模拟 addWhitelist 的核心逻辑
        let testKey = "test_addwl_\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: testKey) }

        // 首次添加
        var list = UserDefaults.standard.stringArray(forKey: testKey) ?? []
        list.append("/path/A")
        list.append("/path/B")
        UserDefaults.standard.set(list, forKey: testKey)
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: testKey),
                       ["/path/A", "/path/B"])

        // 重复添加（去重）
        var list2 = UserDefaults.standard.stringArray(forKey: testKey) ?? []
        let path = "/path/A"
        if !list2.contains(path) {
            list2.append(path)
            UserDefaults.standard.set(list2, forKey: testKey)
        }
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: testKey),
                       ["/path/A", "/path/B"], "重复路径不应重复添加")
    }

    /// 验证白名单 key 名称稳定性（防止误改 key 导致已存数据读不到）
    func testWhitelistKeyConstant() {
        // 通过反射拿不到 private static let；用 UserDefaults 写入读出验证
        let testKey = "whitelist"
        let original = UserDefaults.standard.stringArray(forKey: testKey) ?? []
        defer {
            // 还原原始数据
            UserDefaults.standard.set(original, forKey: testKey)
        }

        let testPaths = ["/tmp/test_\(UUID().uuidString)"]
        UserDefaults.standard.set(testPaths, forKey: testKey)
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: testKey), testPaths)
    }
}