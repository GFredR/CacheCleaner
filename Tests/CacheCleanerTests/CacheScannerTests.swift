import XCTest
@testable import CacheCleaner

final class CacheScannerTests: XCTestCase {

    // MARK: - isCacheInUse：运行中判定

    func testMatchesExactBundleID() {
        let running: Set<String> = ["com.google.Chrome"]
        XCTAssertTrue(CacheScanner.isCacheInUse(
            url: URL(fileURLWithPath: "/Users/x/Library/Containers/com.google.Chrome/Data/Library/Caches"),
            bundleID: "com.google.Chrome",
            runningBundleIDs: running,
            nameTokens: []
        ))
    }

    // 厂商目录（Google/Chrome）不是 bundle id，靠名称片段兜底匹配
    func testMatchesVendorDirByPathToken() {
        let tokens: Set<String> = ["google", "chrome", "com.google.chrome"]
        XCTAssertTrue(CacheScanner.isCacheInUse(
            url: URL(fileURLWithPath: "/Users/x/Library/Caches/Google/Chrome"),
            bundleID: "Google",
            runningBundleIDs: [],
            nameTokens: tokens
        ))
    }

    func testCaseInsensitivePathTokenMatch() {
        let tokens: Set<String> = ["Spotify"]
        XCTAssertTrue(CacheScanner.isCacheInUse(
            url: URL(fileURLWithPath: "/Users/x/Library/Caches/Spotify"),
            bundleID: "Spotify",
            runningBundleIDs: [],
            nameTokens: tokens
        ))
    }

    func testNotRunningWhenNoMatch() {
        let running: Set<String> = ["com.apple.Safari"]
        XCTAssertFalse(CacheScanner.isCacheInUse(
            url: URL(fileURLWithPath: "/Users/x/Library/Caches/SomeUnknownCache"),
            bundleID: "SomeUnknownCache",
            runningBundleIDs: running,
            nameTokens: ["safari"]
        ))
    }

    // 过短片段（如 "app"/"os"）不得误匹配，避免过度跳过
    func testShortTokenNotMatched() {
        let tokens: Set<String> = ["os", "app"]
        XCTAssertFalse(CacheScanner.isCacheInUse(
            url: URL(fileURLWithPath: "/Users/x/Library/Caches/com.apple.osupdate"),
            bundleID: "com.apple.osupdate",
            runningBundleIDs: [],
            nameTokens: tokens
        ))
    }

    // MARK: - CancellationFlag

    func testCancellationFlag() {
        let flag = CancellationFlag()
        XCTAssertFalse(flag.isCancelled, "初始应为未取消")
        flag.cancel()
        XCTAssertTrue(flag.isCancelled, "cancel 后应为已取消")
        flag.reset()
        XCTAssertFalse(flag.isCancelled, "reset 后应恢复")
    }
}