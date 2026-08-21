import XCTest
@testable import CacheCleaner

final class CacheCleanerServiceTests: XCTestCase {

    private let wl: Set<String> = ["/Users/x/Library/Caches/WeChat"]

    // MARK: - clean：真实删除流程

    private func makeCacheDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-clean-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fakeItem(url: URL) -> CacheItem {
        CacheItem(url: url, name: "test", category: .application, bundleID: "com.test.app", size: 0)
    }

    func testCleanDeletesContentsKeepsDir() throws {
        let dir = makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0, count: 100).write(to: dir.appendingPathComponent("a.bin"))
        try Data(repeating: 0, count: 200).write(to: dir.appendingPathComponent("b.bin"))

        let result = CacheCleanerService.clean(
            items: [fakeItem(url: dir)],
            toTrash: false,
            skipRunning: false,
            whitelist: [],
            forceTrashForSystem: false,
            isCancelled: { false }
        )

        XCTAssertEqual(result.failedPaths, [])
        XCTAssertEqual(result.skippedPaths, [])
        XCTAssertEqual(result.freedBytes, 300, "应释放 300 字节")
        // 内容已删，但目录本身保留（App 可重建）
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 0)
    }

    func testCleanSkipsWhitelistedPath() throws {
        let dir = makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0, count: 50).write(to: dir.appendingPathComponent("c.bin"))

        let result = CacheCleanerService.clean(
            items: [fakeItem(url: dir)],
            toTrash: false,
            skipRunning: false,
            whitelist: [dir.path],
            forceTrashForSystem: false,
            isCancelled: { false }
        )

        XCTAssertEqual(result.skippedPaths, [dir.path], "命中白名单应被跳过")
        XCTAssertEqual(result.freedBytes, 0)
        // 内容必须原样保留
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("c.bin").path))
    }

    func testCleanReportsNonexistentAsFailed() {
        let missing = URL(fileURLWithPath: "/tmp/cc-does-not-exist-\(UUID().uuidString)")
        let result = CacheCleanerService.clean(
            items: [fakeItem(url: missing)],
            toTrash: false,
            skipRunning: false,
            whitelist: [],
            forceTrashForSystem: false,
            isCancelled: { false }
        )
        XCTAssertEqual(result.failedPaths, [missing.path], "不存在的目录应计入失败")
    }

    // MARK: - 白名单目录边界匹配

    func testWhitelistMatchesExactPath() {
        XCTAssertTrue(CacheCleanerService.isWhitelisted(
            URL(fileURLWithPath: "/Users/x/Library/Caches/WeChat"),
            whitelist: wl
        ))
    }

    func testWhitelistMatchesSubPath() {
        XCTAssertTrue(CacheCleanerService.isWhitelisted(
            URL(fileURLWithPath: "/Users/x/Library/Caches/WeChat/ab/c"),
            whitelist: wl
        ))
    }

    // 关键修复点：前缀误匹配
    func testWhitelistDoesNotMatchPrefixCollision() {
        XCTAssertFalse(CacheCleanerService.isWhitelisted(
            URL(fileURLWithPath: "/Users/x/Library/Caches/WeChatData"),
            whitelist: wl
        ))
        XCTAssertFalse(CacheCleanerService.isWhitelisted(
            URL(fileURLWithPath: "/Users/x/Library/Caches/WeChatHelper"),
            whitelist: wl
        ))
    }

    func testWhitelistDoesNotMatchUnrelated() {
        XCTAssertFalse(CacheCleanerService.isWhitelisted(
            URL(fileURLWithPath: "/Users/x/Library/Caches/OtherApp"),
            whitelist: wl
        ))
    }

    // MARK: - 空白名单

    func testEmptyWhitelistNeverMatches() {
        let url = URL(fileURLWithPath: "/Users/x/Library/Caches/Anything")
        XCTAssertFalse(CacheCleanerService.isWhitelisted(url, whitelist: []))
    }

    // MARK: - 多条白名单

    func testMultipleWhitelistEntries() {
        let multi: Set<String> = [
            "/Users/x/Library/Caches/WeChat",
            "/Users/x/Library/Developer/Xcode/DerivedData/ProjectA"
        ]
        XCTAssertTrue(CacheCleanerService.isWhitelisted(
            URL(fileURLWithPath: "/Users/x/Library/Developer/Xcode/DerivedData/ProjectA/foo.o"),
            whitelist: multi
        ))
        XCTAssertFalse(CacheCleanerService.isWhitelisted(
            URL(fileURLWithPath: "/Users/x/Library/Developer/Xcode/DerivedData/ProjectB/foo.o"),
            whitelist: multi
        ))
    }
}
