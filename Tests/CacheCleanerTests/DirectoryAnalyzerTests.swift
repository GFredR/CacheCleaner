import XCTest
@testable import CacheCleaner

final class DirectoryAnalyzerTests: XCTestCase {

    private var tempRoot: URL!
    private let analyzer = DirectoryAnalyzer()

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cc-analyzer-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempRoot = dir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private func makeFile(_ relative: String, content: String = "x") throws {
        let url = tempRoot.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - countFiles / analyze 一致性

    func testCountAndAnalyzeConsistency() async throws {
        try makeFile("a.txt", content: "hello")
        try makeFile("M/b.log", content: "world")
        try makeFile("M/N/c.swift", content: "let x = 1")

        let total = await analyzer.countFiles(at: tempRoot)
        let files = await analyzer.analyze(url: tempRoot, totalCount: total) { _, _, _ in }

        XCTAssertEqual(total, 3)
        XCTAssertEqual(files.count, 3, "预扫描数应与正式扫描结果一致")
    }

    // MARK: - 空目录

    func testEmptyDirectory() async {
        let total = await analyzer.countFiles(at: tempRoot)
        let files = await analyzer.analyze(url: tempRoot, totalCount: total) { _, _, _ in }
        XCTAssertEqual(total, 0)
        XCTAssertTrue(files.isEmpty)
    }

    // MARK: - 符号链接不跟随（实测验证的安全特性）

    func testSymlinkNotFollowed() async throws {
        try makeFile("real.txt", content: "content")
        // 创建指向自身的符号链接（循环引用）
        try FileManager.default.createSymbolicLink(
            at: tempRoot.appendingPathComponent("loop_link"),
            withDestinationURL: tempRoot
        )
        let total = await analyzer.countFiles(at: tempRoot)
        // 应只统计 1 个真文件，不计符号链接，不无限循环
        XCTAssertEqual(total, 1, "符号链接不应被计入，且不应死循环")
        let files = await analyzer.analyze(url: tempRoot, totalCount: total) { _, _, _ in }
        XCTAssertEqual(files.count, 1)
    }

    // MARK: - 进度回调

    func testProgressCallbackFires() async throws {
        // 构造 50 个文件（每 25 个回调一次，至少触发 2 次）
        for i in 0..<50 {
            try makeFile("file-\(i).tmp")
        }
        var calls = 0
        let total = await analyzer.countFiles(at: tempRoot)
        _ = await analyzer.analyze(url: tempRoot, totalCount: total) { _, _, _ in
            calls += 1
        }
        XCTAssertGreaterThan(calls, 0, "50 个文件应触发进度回调")
    }
}
