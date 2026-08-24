import XCTest
@testable import CacheCleaner

/// 目录分析模型：默认勾选可清理项 + 文件夹三态勾选（折叠也能确认选中状态）
@MainActor
final class DirectoryAnalysisModelTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-model-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempRoot = dir.resolvingSymlinksInPath()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeFile(_ relative: String) throws {
        let url = tempRoot.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x0a]).write(to: url)
    }

    /// 等待分析完成（analyze 内部异步扫描）
    private func waitForScan(_ model: DirectoryAnalysisModel) async {
        let deadline = Date().addingTimeInterval(5)
        while model.isScanning && Date() < deadline {
            await Task.yield()
        }
    }

    private func node(named name: String, in nodes: [DirectoryNode]) -> DirectoryNode? {
        func walk(_ list: [DirectoryNode]) -> DirectoryNode? {
            for n in list {
                if n.name == name { return n }
                if let c = n.children, let hit = walk(c) { return hit }
            }
            return nil
        }
        return walk(nodes)
    }

    func testDefaultSelectsAllCleanableAndFolderPartial() async throws {
        try makeFile("a.tmp")
        try makeFile("sub/b.log")
        try makeFile("sub/source.swift")
        try makeFile("sub/nested/c.cache")

        let model = DirectoryAnalysisModel()
        model.analyze(tempRoot)
        await waitForScan(model)

        XCTAssertFalse(model.isScanning, "扫描应已完成")
        XCTAssertEqual(model.selectedCount, 3, "a.tmp / b.log / c.cache 三个可清理项应默认全选")

        guard let sub = node(named: "sub", in: model.tree) else {
            XCTFail("树中应存在 sub 文件夹")
            return
        }
        // sub 共 3 个文件（b.log/source.swift/c.cache），默认只勾了 2 个可清理项 → 部分选
        XCTAssertEqual(model.totalFiles(in: sub), 3)
        XCTAssertEqual(model.selectedFiles(in: sub), 2)
        XCTAssertEqual(model.selectionState(of: sub), .partial)
    }

    func testToggleSingleFileMakesFolderPartial() async throws {
        try makeFile("a.tmp")
        try makeFile("sub/b.log")
        try makeFile("sub/c.cache")

        let model = DirectoryAnalysisModel()
        model.analyze(tempRoot)
        await waitForScan(model)

        guard let sub = node(named: "sub", in: model.tree),
              let b = model.files.first(where: { $0.relativePath == "sub/b.log" }) else {
            XCTFail("应能找到 sub/b.log")
            return
        }
        XCTAssertEqual(model.selectionState(of: sub), .all, "sub 内 2 个文件均已选 → 全选态")
        model.toggleSelection(b)
        XCTAssertEqual(model.selectionState(of: sub), .partial, "取消一个 → 部分选态")
        XCTAssertEqual(model.selectedFiles(in: sub), 1)
        XCTAssertEqual(model.selectedCount, 2)
    }

    func testToggleFolderSelectsAllThenNone() async throws {
        try makeFile("a.tmp")
        try makeFile("sub/b.log")
        try makeFile("sub/c.cache")
        try makeFile("sub/source.swift")

        let model = DirectoryAnalysisModel()
        model.analyze(tempRoot)
        await waitForScan(model)

        guard let sub = node(named: "sub", in: model.tree) else {
            XCTFail("树中应存在 sub 文件夹")
            return
        }
        // 默认只勾 2 个可清理项，source.swift 未勾 → 部分选
        XCTAssertEqual(model.selectionState(of: sub), .partial)
        XCTAssertEqual(model.selectedFiles(in: sub), 2)
        XCTAssertEqual(model.selectedCount, 3)

        // 第一次点文件夹 → 全选子树所有文件（含重要 source.swift）
        model.toggleFolder(sub)
        XCTAssertEqual(model.selectionState(of: sub), .all)
        XCTAssertEqual(model.selectedFiles(in: sub), 3)
        XCTAssertEqual(model.selectedCount, 4, "根 a.tmp + sub 内 3 个")
        XCTAssertEqual(model.selectedProtectedFiles.count, 1, "重要文件被一并勾选，可探测到受保护项")

        // 再点 → 全不选
        model.toggleFolder(sub)
        XCTAssertEqual(model.selectionState(of: sub), .none)
        XCTAssertEqual(model.selectedFiles(in: sub), 0)
        XCTAssertEqual(model.selectedCount, 1, "只剩根目录 a.tmp 仍为选中")
    }

    func testProtectedFileCanBeToggledAndDetected() async throws {
        try makeFile("a.tmp")
        try makeFile("sub/source.swift")  // 重要文件，默认不勾

        let model = DirectoryAnalysisModel()
        model.analyze(tempRoot)
        await waitForScan(model)

        // 默认只勾可清理项
        XCTAssertEqual(model.selectedCount, 1)

        guard let sub = node(named: "sub", in: model.tree),
              let swiftFile = model.files.first(where: { $0.relativePath == "sub/source.swift" }) else {
            XCTFail("应找到 sub/source.swift")
            return
        }
        XCTAssertFalse(model.hasProtectedSelected)

        // 重要文件也可勾选，且会让只有这一个文件的文件夹变全选态
        model.toggleSelection(swiftFile)
        XCTAssertTrue(model.isSelected(swiftFile))
        XCTAssertEqual(model.selectedCount, 2)
        XCTAssertTrue(model.hasProtectedSelected)
        XCTAssertEqual(model.selectedProtectedFiles.count, 1)
        XCTAssertEqual(model.selectionState(of: sub), .all, "sub 唯一文件被勾选 → all")

        // 取消勾选后回到未选受保护状态
        model.toggleSelection(swiftFile)
        XCTAssertFalse(model.hasProtectedSelected)
        XCTAssertEqual(model.selectedCount, 1)
    }

    // 回归：此前 cleanSelected 只删 .safeToClean，受保护(红/黄)文件即使勾选并二次强确认也删不掉，
    // 纯选中受保护文件时还静默 return。现在受保护文件应真正可删。
    func testCleanSelectedDeletesProtectedFile() async throws {
        try makeFile("sub/source.swift")  // 重要(红)，默认不勾
        try makeFile("plain.tmp")         // 可清理(绿)，默认勾上

        let model = DirectoryAnalysisModel()
        model.analyze(tempRoot)
        await waitForScan(model)

        guard let swiftFile = model.files.first(where: { $0.relativePath == "sub/source.swift" }) else {
            XCTFail("应找到 sub/source.swift")
            return
        }
        XCTAssertFalse(model.isSelected(swiftFile), "重要文件默认不勾")

        // 只勾选受保护文件，验证纯受保护时也能删除（不能静默 return）
        model.selectedIDs = [swiftFile.id]
        model.cleanSelected(useTrash: false)
        let deadline = Date().addingTimeInterval(5)
        while model.isCleaning && Date() < deadline {
            await Task.yield()
        }

        XCTAssertFalse(model.isCleaning, "清理应完成")
        XCTAssertNil(model.files.first(where: { $0.relativePath == "sub/source.swift" }),
                     "重要文件应被真正删除")
        let url = tempRoot.appendingPathComponent("sub/source.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "磁盘上文件应已删除")
        XCTAssertNotNil(model.cleanReport, "清理应有报告，不再静默无提示")
        XCTAssertTrue((model.cleanReport ?? "").contains("成功释放"), "报告应含成功字样")
    }

    // 回归：所选文件全部命中白名单时应明确告知，而非静默返回无提示
    func testCleanAllWhitelistedShowsReport() async throws {
        try makeFile("a.tmp")
        let filePath = tempRoot.appendingPathComponent("a.tmp").path
        WhitelistStore.add(filePath)
        defer { WhitelistStore.remove(filePath) }

        let model = DirectoryAnalysisModel()
        model.analyze(tempRoot)
        await waitForScan(model)
        XCTAssertEqual(model.selectedCount, 1)

        model.cleanSelected(useTrash: false)
        let deadline = Date().addingTimeInterval(5)
        while model.isCleaning && Date() < deadline {
            await Task.yield()
        }

        // 文件未被删除，但给出了明确的白名单提示
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath), "白名单文件不应被删除")
        XCTAssertNotNil(model.cleanReport, "应有清理报告，不能静默无提示")
        XCTAssertTrue((model.cleanReport ?? "").contains("白名单"), "报告应说明命中白名单")
    }

    // 回归：删除失败（无权限等）的文件应保留勾选，方便用户直接重试
    func testCleanKeepsFailedSelectedForRetry() async throws {
        // 0o555 只读目录在 root 身份下不构成删除障碍，跳过避免误报
        try XCTSkipIf(getuid() == 0, "root 身份下只读目录仍可删除，用例不适用")
        try makeFile("sub/b.log")
        let subDir = tempRoot.appendingPathComponent("sub")
        let filePath = subDir.appendingPathComponent("b.log").path
        // 父目录只读 → removeItem 无权限失败（还原权限供 tearDown 清理）
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: subDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: subDir.path)
        }

        let model = DirectoryAnalysisModel()
        model.analyze(tempRoot)
        await waitForScan(model)
        XCTAssertEqual(model.selectedCount, 1)

        model.cleanSelected(useTrash: false)
        let deadline = Date().addingTimeInterval(5)
        while model.isCleaning && Date() < deadline {
            await Task.yield()
        }

        XCTAssertTrue(model.files.contains { $0.relativePath == "sub/b.log" }, "删除失败项应留在列表")
        XCTAssertEqual(model.selectedIDs.count, 1, "失败项应保留勾选供重试")
        XCTAssertTrue((model.cleanReport ?? "").contains("删除失败"), "报告应说明有失败项")
    }
}