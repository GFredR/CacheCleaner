import XCTest
@testable import CacheCleaner

final class DirectoryAnalyzerTests: XCTestCase {

    private var tempRoot: URL!
    private let analyzer = DirectoryAnalyzer()

    override func setUp() {
        super.setUp()
        // /var 是指向 /private/var 的符号链接，需解析成真实路径，
        // 否则枚举返回 realpath 后根路径前缀不匹配，relativePath 会带出整条绝对路径。
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-analyzer-test-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
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

    // MARK: - 目录树父链接线（支撑"文件夹显示内部已勾选项"）

    func testBuilderWiresParentAndFileIDs() async throws {
        try makeFile("a.txt")
        try makeFile("M/b.log")
        try makeFile("M/N/c.swift")

        let total = await analyzer.countFiles(at: tempRoot)
        let files = await analyzer.analyze(url: tempRoot, totalCount: total) { _, _, _ in }
        let tree = DirectoryTreeBuilder.build(from: files, rootURL: tempRoot)

        // 扁平化：id -> node
        var byID: [UUID: DirectoryNode] = [:]
        var count = 0
        func walk(_ nodes: [DirectoryNode]) {
            for n in nodes {
                count += 1
                byID[n.id] = n
                if let c = n.children { walk(c) }
            }
        }
        walk(tree)
        XCTAssertEqual(count, 5, "a.txt + M + M/b.log + M/N + M/N/c.swift 共 5 个节点")

        // 每个文件节点的 id 必须复用其 file.id
        for f in files {
            guard let node = byID.values.first(where: { $0.file?.id == f.id }) else {
                XCTFail("树中应存在文件节点 \(f.relativePath)")
                continue
            }
            XCTAssertEqual(node.id, f.id, "文件节点 id 应等于 file.id，供父链统计")
        }

        // 每个非根节点的 parentID 都应指向树中某个文件夹节点
        for n in byID.values where n.parentID != nil {
            guard let parent = byID[n.parentID!] else {
                XCTFail("节点 \(n.name) 的父不存在")
                continue
            }
            XCTAssertTrue(parent.isFolder, "父节点 \(parent.name) 应为文件夹")
        }

        // 根级节点：根目录下的 a.txt 与文件夹 M，二者 parentID 均为 nil；
        // 其中仅 M 是文件夹。
        let roots = byID.values.filter { $0.parentID == nil }
        XCTAssertEqual(roots.count, 2, "根级有 a.txt 与 M 两个节点")
        let rootFolders = roots.filter { $0.isFolder }
        XCTAssertEqual(rootFolders.count, 1, "根级恰好一个文件夹")
        XCTAssertEqual(rootFolders.first?.name, "M")
    }
}
