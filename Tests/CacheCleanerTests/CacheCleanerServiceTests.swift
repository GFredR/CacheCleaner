import XCTest
@testable import CacheCleaner

final class CacheCleanerServiceTests: XCTestCase {

    private let wl: Set<String> = ["/Users/x/Library/Caches/WeChat"]

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
