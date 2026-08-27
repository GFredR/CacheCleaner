import XCTest
@testable import CacheCleaner

final class CleanHistoryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CleanHistoryStore.clear()
    }

    override func tearDown() {
        CleanHistoryStore.clear()
        super.tearDown()
    }

    private func makeEntry() -> CleanHistoryEntry {
        CleanHistoryEntry(
            source: .cacheCleaner,
            useTrash: false,
            freedBytes: 1024,
            deletedCount: 3,
            failedCount: 1,
            skippedCount: 1
        )
    }

    func testEmptyByDefault() {
        XCTAssertTrue(CleanHistoryStore.entries().isEmpty)
    }

    func testAddAndRead() {
        CleanHistoryStore.add(makeEntry())
        let list = CleanHistoryStore.entries()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.freedBytes, 1024)
        XCTAssertEqual(list.first?.deletedCount, 3)
        XCTAssertEqual(list.first?.failedCount, 1)
        XCTAssertEqual(list.first?.skippedCount, 1)
        XCTAssertEqual(list.first?.source, .cacheCleaner)
    }

    // 最新一条在前
    func testNewestFirst() {
        CleanHistoryStore.add(makeEntry())
        CleanHistoryStore.add(CleanHistoryEntry(
            source: .directoryAnalysis, useTrash: true,
            freedBytes: 2048, deletedCount: 2, failedCount: 0, skippedCount: 0
        ))
        let list = CleanHistoryStore.entries()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].source, .directoryAnalysis, "最近添加的应排在最前")
        XCTAssertEqual(list[0].freedBytes, 2048)
    }

    // 容量上限：超过 maxEntries 只保留最近 N 条
    func testCapacityCap() {
        for i in 0..<(CleanHistoryStore.maxEntries + 10) {
            CleanHistoryStore.add(CleanHistoryEntry(
                source: .cacheCleaner, useTrash: false,
                freedBytes: Int64(i), deletedCount: 1, failedCount: 0, skippedCount: 0
            ))
        }
        let list = CleanHistoryStore.entries()
        XCTAssertEqual(list.count, CleanHistoryStore.maxEntries)
        // 最新一条 freedBytes 应最大（最后插入）
        XCTAssertEqual(list.first?.freedBytes, Int64(CleanHistoryStore.maxEntries + 9))
    }

    func testClear() {
        CleanHistoryStore.add(makeEntry())
        CleanHistoryStore.clear()
        XCTAssertTrue(CleanHistoryStore.entries().isEmpty)
    }
}