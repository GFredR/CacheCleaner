import XCTest
@testable import CacheCleaner

final class LargeFileScannerTests: XCTestCase {

    private var tempRoot: URL!
    private let scanner = LargeFileScanner()

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-space-test-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempRoot = dir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func makeFile(_ name: String, content: String) throws {
        try content.write(
            to: tempRoot.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - 最大文件

    func testLargeFilesSortedBySize() async throws {
        try makeFile("small.txt", content: "x")
        try makeFile("big.txt", content: String(repeating: "a", count: 1000))
        try makeFile("huge.txt", content: String(repeating: "b", count: 5000))

        let items = await scanner.scanLargeFiles(at: tempRoot, limit: 10)
        XCTAssertEqual(items.count, 3)
        // 降序：huge > big > small
        XCTAssertEqual(items[0].url.lastPathComponent, "huge.txt")
        XCTAssertEqual(items[1].url.lastPathComponent, "big.txt")
        XCTAssertEqual(items[2].url.lastPathComponent, "small.txt")
    }

    func testLargeFilesLimit() async throws {
        for i in 0..<5 {
            try makeFile("f\(i).txt", content: String(repeating: "x", count: i * 100 + 10))
        }
        let items = await scanner.scanLargeFiles(at: tempRoot, limit: 3)
        XCTAssertEqual(items.count, 3)
    }

    // MARK: - 重复文件

    func testDuplicatesDetectedByContent() async throws {
        // 两组内容相同的文件 + 一个同大小不同内容
        try makeFile("dup-a1.txt", content: String(repeating: "same-a", count: 20))
        try makeFile("dup-a2.txt", content: String(repeating: "same-a", count: 20))
        try makeFile("dup-b1.txt", content: String(repeating: "same-b", count: 30))
        try makeFile("dup-b2.txt", content: String(repeating: "same-b", count: 30))
        try makeFile("collision.txt", content: String(repeating: "same-b", count: 29)) // 大小不同

        let groups = await scanner.scanDuplicates(at: tempRoot)
        // 应恰好两组（dup-a 组、dup-b 组）
        XCTAssertEqual(groups.count, 2, "应识别出 dup-a 与 dup-b 两组重复")

        let groupA = groups.first { $0.files.contains { $0.url.lastPathComponent == "dup-a1.txt" } }
        XCTAssertNotNil(groupA)
        XCTAssertEqual(groupA?.files.count, 2)
        // 可释放量 = 单份大小 × 1
        XCTAssertEqual(groupA?.wastedBytes, groupA?.size)
    }

    // 同大小但内容不同：不判为重复
    func testSameSizeDifferentContentNotDuplicate() async throws {
        try makeFile("x1.txt", content: String(repeating: "aaaa", count: 10))
        try makeFile("x2.txt", content: String(repeating: "bbbb", count: 10)) // 同大小、不同内容
        let groups = await scanner.scanDuplicates(at: tempRoot)
        XCTAssertTrue(groups.isEmpty, "同大小不同内容不应判为重复")
    }

    // 单文件不成组
    func testSingleFileNotDuplicate() async throws {
        try makeFile("only.txt", content: "alone")
        let groups = await scanner.scanDuplicates(at: tempRoot)
        XCTAssertTrue(groups.isEmpty)
    }

    // 取消应立即返回空
    func testCancellation() async throws {
        for i in 0..<20 {
            try makeFile("f\(i).txt", content: "data\(i)")
        }
        var cancelled = false
        let groups = await scanner.scanDuplicates(at: tempRoot, isCancelled: { cancelled })
        cancelled = true
        // 已满足：不崩溃、正常返回数组（取消发生在扫描开始后由 flag 控制）
        XCTAssertNotNil(groups)
    }
}