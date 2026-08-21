import XCTest
@testable import CacheCleaner

final class DirectoryTreeBuilderTests: XCTestCase {

    func testNestedTreeAggregation() {
        let root = URL(fileURLWithPath: "/tmp/test")
        let files: [AnalyzedFile] = [
            .init(url: root.appendingPathComponent("a.txt"), relativePath: "a.txt", size: 100, level: .important),
            .init(url: root.appendingPathComponent("M/b.swift"), relativePath: "M/b.swift", size: 200, level: .important),
            .init(url: root.appendingPathComponent("M/N/c.swift"), relativePath: "M/N/c.swift", size: 300, level: .safeToClean),
            .init(url: root.appendingPathComponent("M/d.log"), relativePath: "M/d.log", size: 50, level: .safeToClean),
        ]
        let tree = DirectoryTreeBuilder.build(from: files, rootURL: root)

        XCTAssertEqual(tree.count, 2, "顶层应有 a.txt 文件 + M 文件夹")
        let m = tree.first { $0.isFolder && $0.name == "M" }
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.size, 550, "M 聚合大小 = b.swift(200) + N/c.swift(300) + d.log(50) = 550")
        XCTAssertEqual(m?.fileCount, 3, "M 子树文件数 = 3")
        let n = m?.children?.first { $0.name == "N" }
        XCTAssertEqual(n?.size, 300, "N 聚合大小 = c.swift(300)")
    }

    func testFolderSortsBeforeFile() {
        let root = URL(fileURLWithPath: "/tmp/test")
        let files: [AnalyzedFile] = [
            .init(url: root.appendingPathComponent("z.txt"), relativePath: "z.txt", size: 10, level: .cautious),
            .init(url: root.appendingPathComponent("A/x.txt"), relativePath: "A/x.txt", size: 20, level: .cautious),
        ]
        let tree = DirectoryTreeBuilder.build(from: files, rootURL: root)
        XCTAssertTrue(tree[0].isFolder, "文件夹应排在文件前")
        XCTAssertEqual(tree[0].name, "A")
        XCTAssertFalse(tree[1].isFolder)
        XCTAssertEqual(tree[1].name, "z.txt")
    }

    func testFilesSortBySizeDescending() {
        let root = URL(fileURLWithPath: "/tmp/test")
        let files: [AnalyzedFile] = [
            .init(url: root.appendingPathComponent("small.txt"), relativePath: "small.txt", size: 10, level: .cautious),
            .init(url: root.appendingPathComponent("big.txt"), relativePath: "big.txt", size: 1000, level: .cautious),
            .init(url: root.appendingPathComponent("mid.txt"), relativePath: "mid.txt", size: 100, level: .cautious),
        ]
        let tree = DirectoryTreeBuilder.build(from: files, rootURL: root)
        let sizes = tree.map(\.size)
        XCTAssertEqual(sizes, [1000, 100, 10], "同级文件按大小降序")
    }

    func testEmptyFiles() {
        let tree = DirectoryTreeBuilder.build(from: [], rootURL: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertTrue(tree.isEmpty)
    }

    func testDeepNestedNoStackOverflow() {
        // 验证递归截断（之前因未截断导致 SIGSEGV）
        let root = URL(fileURLWithPath: "/tmp/deep")
        var files: [AnalyzedFile] = []
        // 构造 100 层深嵌套
        var path = ""
        for i in 0..<100 {
            path += "d\(i)/"
        }
        path += "leaf.txt"
        files.append(.init(url: root.appendingPathComponent(path),
                            relativePath: path, size: 1, level: .safeToClean))
        let tree = DirectoryTreeBuilder.build(from: files, rootURL: root)
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree.first?.fileCount, 1)
    }
}
