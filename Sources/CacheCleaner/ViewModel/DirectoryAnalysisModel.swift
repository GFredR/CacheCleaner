import Foundation
import Combine

/// 目录分析视图模型：持有扫描结果、勾选状态与清理逻辑
/// @MainActor：所有 @Published 与状态变更收口到主线程；扫描/删除走 Task.detached 不阻塞 UI
@MainActor
final class DirectoryAnalysisModel: ObservableObject {

    @Published var rootURL: URL?
    @Published var rootName: String = ""
    @Published var files: [AnalyzedFile] = []
    /// 目录树（由 files 构建，供树形展开/折叠展示）
    @Published var tree: [DirectoryNode] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var isScanning = false
    @Published var isCleaning = false
    /// 已处理文件数（正式扫描阶段递增）
    @Published var processedCount = 0
    /// 预扫描得到的总文件数；0 表示未知（退化为 indeterminate）
    @Published var totalFiles = 0
    /// 当前正在处理的文件路径（正式扫描阶段）
    @Published var currentPath = ""
    /// 预扫描阶段进度（0..1）
    @Published var countProgress: Double = 0
    /// 当前扫描阶段（"准备中" / "扫描中"）用于 UI 文案
    @Published var scanPhase: ScanPhase = .preparing
    enum ScanPhase { case preparing, scanning }
    @Published var cleanReport: String?
    @Published var errorMessage: String?

    private var scanTask: Task<Void, Never>?
    private var scanFlag: CancellationFlag?
    private let analyzer = DirectoryAnalyzer()

    // MARK: - 统计

    /// 每个重要性等级的文件数与总大小（一次性缓存，避免每次 body 刷新 O(3n) filter）
    private(set) var levelCounts: [ImportanceLevel: Int] = [:]
    private(set) var levelSizes: [ImportanceLevel: Int64] = [:]
    /// 总大小缓存，扫描/清理后更新，避免每个 View 刷新都 O(n) reduce
    private(set) var totalSize: Int64 = 0
    /// 选中大小增量维护，避免每次渲染 O(n) 过滤求和
    private var _selectedSize: Int64 = 0

    func count(of level: ImportanceLevel) -> Int {
        levelCounts[level] ?? 0
    }

    func size(of level: ImportanceLevel) -> Int64 {
        levelSizes[level] ?? 0
    }

    /// 全列表一次性统计大小与红黄绿数量（扫描完成/清理后调用）
    private func recomputeStats() {
        var counts: [ImportanceLevel: Int] = [:]
        var sizes: [ImportanceLevel: Int64] = [:]
        var sum: Int64 = 0
        for f in files {
            counts[f.level, default: 0] += 1
            sizes[f.level, default: 0] += f.size
            sum += f.size
        }
        levelCounts = counts
        levelSizes = sizes
        totalSize = sum
    }

    var selectedSize: Int64 { _selectedSize }
    var selectedCount: Int { selectedIDs.count }

    /// 当前选中的"重要/谨慎"受保护文件（默认不勾选，删除前需二次强确认）
    var selectedProtectedFiles: [AnalyzedFile] {
        files.filter { selectedIDs.contains($0.id) && $0.level != .safeToClean }
    }

    var hasProtectedSelected: Bool {
        !selectedProtectedFiles.isEmpty
    }

    func isSelected(_ file: AnalyzedFile) -> Bool {
        selectedIDs.contains(file.id)
    }

    // MARK: - 文件夹内部选中统计（折叠时也能看出勾选了哪些；支持整目录勾选）

    /// nodeID -> 父 nodeID（文件节点 id=file.id，值为其所在文件夹 id）
    private var parentChain: [UUID: UUID] = [:]
    /// 文件夹 nodeID -> 其子树内已勾选的文件数（含重要/谨慎）
    private var selectedCountByNode: [UUID: Int] = [:]
    /// 文件夹 nodeID -> 其子树内已勾选的文件总大小
    private var selectedSizeByNode: [UUID: Int64] = [:]
    /// 文件夹 nodeID -> 其子树内文件总数（用于判断全选/部分选）
    private var totalCountByNode: [UUID: Int] = [:]
    /// 文件夹 nodeID -> 其子树内所有文件 id 集合（用于一键勾选整目录）
    private var fileIDsByFolder: [UUID: Set<UUID>] = [:]

    /// 文件夹内部已勾选的文件数（仅文件夹有意义）
    func selectedFiles(in node: DirectoryNode) -> Int {
        node.isFolder ? (selectedCountByNode[node.id] ?? 0) : 0
    }

    /// 文件夹内部文件总数（仅文件夹有意义）
    func totalFiles(in node: DirectoryNode) -> Int {
        node.isFolder ? (totalCountByNode[node.id] ?? 0) : 0
    }

    /// 节点勾选状态：none（未选）/ partial（部分选）/ all（全部勾选）
    func selectionState(of node: DirectoryNode) -> DirectorySelectionState {
        guard node.isFolder else {
            guard let file = node.file else { return .none }
            return selectedIDs.contains(file.id) ? .all : .none
        }
        let sel = selectedFiles(in: node)
        if sel == 0 { return .none }
        return sel >= (totalCountByNode[node.id] ?? 0) ? .all : .partial
    }

    /// 一键勾选/取消整个文件夹内的所有文件（部分选/未选 → 全选，全选 → 全不选）。
    /// 重要/谨慎会被一并勾上，点击清理时仍会走二次强确认。
    func toggleFolder(_ node: DirectoryNode) {
        guard node.isFolder,
              let ids = fileIDsByFolder[node.id],
              !ids.isEmpty else { return }
        if ids.isSubset(of: selectedIDs) {
            for f in files where ids.contains(f.id) && selectedIDs.contains(f.id) {
                selectedIDs.remove(f.id)
                _selectedSize -= f.size
            }
        } else {
            for f in files where ids.contains(f.id) && !selectedIDs.contains(f.id) {
                selectedIDs.insert(f.id)
                _selectedSize += f.size
            }
        }
        rebuildFolderMaps()
    }

    /// 沿父链 + 文件夹统计全量重建（树重建 / 勾选集整批变化后调用）
    private func rebuildFolderMaps() {
        var chain: [UUID: UUID] = [:]
        func walk(_ nodes: [DirectoryNode], parent: UUID?) {
            for n in nodes {
                if let p = parent { chain[n.id] = p }
                if let c = n.children { walk(c, parent: n.id) }
            }
        }
        walk(tree, parent: nil)
        parentChain = chain

        var selectedCounts: [UUID: Int] = [:]
        var selectedSizes: [UUID: Int64] = [:]
        var totalCounts: [UUID: Int] = [:]
        var idSets: [UUID: Set<UUID>] = [:]
        for f in files {
            var cur = f.id
            while let parent = chain[cur] {
                totalCounts[parent, default: 0] += 1
                idSets[parent, default: []].insert(f.id)
                if selectedIDs.contains(f.id) {
                    selectedCounts[parent, default: 0] += 1
                    selectedSizes[parent, default: 0] += f.size
                }
                cur = parent
            }
        }
        selectedCountByNode = selectedCounts
        selectedSizeByNode = selectedSizes
        totalCountByNode = totalCounts
        fileIDsByFolder = idSets
    }

    /// 单个文件勾选/取消时，沿父链增量更新选中统计（O(depth)，避免整目录重建）
    private func applySelectionDelta(_ file: AnalyzedFile, delta: Int) {
        let sizeDelta: Int64 = delta > 0 ? file.size : -file.size
        var cur = file.id
        while let parent = parentChain[cur] {
            selectedCountByNode[parent, default: 0] += delta
            selectedSizeByNode[parent, default: 0] += sizeDelta
            cur = parent
        }
    }

    var totalSizeString: String {
        SizeFormatter.string(from: totalSize)
    }
    var selectedSizeString: String {
        SizeFormatter.string(from: selectedSize)
    }

    // MARK: - 扫描

    /// 开始分析一个目录（拖拽或文件选择器传入）
    func analyze(_ url: URL) {
        // 清理进行中不允许切换目录（避免异步清理结果覆盖新扫描）
        guard !isCleaning else { return }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            errorMessage = "请拖入一个文件夹目录"
            return
        }

        scanTask?.cancel()
        scanFlag?.cancel()
        files = []
        tree = []
        levelCounts = [:]
        levelSizes = [:]
        totalSize = 0
        selectedIDs = []
        _selectedSize = 0
        cleanReport = nil
        errorMessage = nil

        rootURL = url
        rootName = url.lastPathComponent
        isScanning = true
        processedCount = 0
        totalFiles = 0
        countProgress = 0
        scanPhase = .preparing

        let flag = CancellationFlag()
        self.scanFlag = flag

        scanTask = Task { [weak self] in
            guard let self else { return }

            // Step 1: 快速预扫描拿总文件数（带进度回调）
            let total = await self.analyzer.countFiles(at: url,
                isCancelled: { flag.isCancelled }
            ) { processed, estimated in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.countProgress = min(Double(processed) / Double(max(estimated, 1)), 1.0)
                }
            }
            if Task.isCancelled || flag.isCancelled { return }
            await MainActor.run {
                self.totalFiles = total
                self.countProgress = 1.0
                self.scanPhase = .scanning
            }

            // Step 2: 正式扫描（读大小 + 分类），带真实进度
            let result = await self.analyzer.analyze(url: url, totalCount: total,
                isCancelled: { flag.isCancelled }
            ) { processed, total, path in
                Task { @MainActor [weak self] in
                    self?.processedCount = processed
                    self?.totalFiles = total
                    self?.currentPath = path
                }
            }

            await MainActor.run {
                guard !Task.isCancelled && !flag.isCancelled else { return }
                // 按重要性倒序（红在前）、同等级按大小降序
                self.files = result.sorted {
                    if $0.level.order != $1.level.order {
                        return $0.level.order > $1.level.order
                    }
                    return $0.size > $1.size
                }
                self.tree = DirectoryTreeBuilder.build(from: self.files, rootURL: url)
                self.recomputeStats()
                // 默认勾选所有可安全清理项
                let safe = self.files.filter { $0.level == .safeToClean }
                self.selectedIDs = Set(safe.map { $0.id })
                self._selectedSize = safe.reduce(0) { $0 + $1.size }
                self.rebuildFolderMaps()
                self.isScanning = false
                self.currentPath = ""
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanFlag?.cancel()
        isScanning = false
    }

    // MARK: - 选择

    func toggleSelection(_ file: AnalyzedFile) {
        if selectedIDs.contains(file.id) {
            selectedIDs.remove(file.id)
            _selectedSize -= file.size
            applySelectionDelta(file, delta: -1)
        } else {
            selectedIDs.insert(file.id)
            _selectedSize += file.size
            applySelectionDelta(file, delta: 1)
        }
    }

    /// 全选所有可清理项（仅绿；不碰受保护的红/黄文件）
    func selectAllCleanable() {
        let all = files.filter { $0.level == .safeToClean }
        selectedIDs = Set(all.map { $0.id })
        _selectedSize = all.reduce(0) { $0 + $1.size }
        rebuildFolderMaps()
    }

    // MARK: - 清理

    func cleanSelected(useTrash: Bool = false) {
        // 防重入：清理进行中再次调用直接忽略（UI 已 disabled，此处兜底编程入口）
        guard !isCleaning else { return }
        let targets = files.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        cleanReport = nil

        // 与缓存清理页共用同一套白名单保护：命中白名单的文件即使标绿也跳过
        // 预规范化（补 realpath 形态）：用户加的 /var/... 与扫描器记录的 /private/var/... 才能匹配上
        let whitelist = CacheCleanerService.normalizedWhitelist(WhitelistStore.paths())
        let candidates = targets.filter { !CacheCleanerService.isWhitelisted($0.url, whitelist: whitelist) }
        let skippedCount = targets.count - candidates.count
        // 所选文件全部命中白名单：不删除，但明确告知用户，而非静默返回
        guard !candidates.isEmpty else {
            cleanReport = "所选 \(targets.count) 个文件均命中白名单，未删除任何文件"
            return
        }

        isCleaning = true
        let skipped = skippedCount
        let rootURL = self.rootURL

        Task { [weak self] in
            guard let self else { return }
            // 后台执行删除（大量小文件删除可能耗时，不能阻塞主线程）
            let result = await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                var freed: Int64 = 0
                var failed: [String] = []
                for file in candidates {
                    do {
                        if useTrash {
                            try fm.trashItem(at: file.url, resultingItemURL: nil)
                        } else {
                            try fm.removeItem(at: file.url)
                        }
                        freed += file.size
                    } catch {
                        failed.append(file.url.path)
                    }
                }
                return (freed: freed, failed: failed)
            }.value

            await MainActor.run {
                // 只移除成功删除的；失败项保留（可能是正在使用/无权限）
                let cleanedIDs = Set(candidates.filter { !result.failed.contains($0.url.path) }.map { $0.id })
                self.files = self.files.filter { !cleanedIDs.contains($0.id) }
                self.tree = DirectoryTreeBuilder.build(from: self.files, rootURL: rootURL ?? URL(fileURLWithPath: "/"))
                self.recomputeStats()
                // 删除失败（可能被占用/无权限）的文件保留勾选，用户可直接重试而无需重新勾选
                let failedIDs = Set(candidates.filter { result.failed.contains($0.url.path) }.map { $0.id })
                self.selectedIDs = failedIDs
                self._selectedSize = self.files.filter { failedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
                self.rebuildFolderMaps()
                self.isCleaning = false

                let freedString = SizeFormatter.string(from: result.freed)
                var report = result.failed.isEmpty
                    ? "成功释放 \(freedString)"
                    : "成功释放 \(freedString)，\(result.failed.count) 个文件删除失败（可能正在使用）"
                if skipped > 0 {
                    report += "；\(skipped) 个文件命中白名单已跳过"
                }
                self.cleanReport = report

                // 写入清理历史（成功释放了才算一条）
                if result.freed > 0 {
                    CleanHistoryStore.add(CleanHistoryEntry(
                        source: .directoryAnalysis,
                        useTrash: useTrash,
                        freedBytes: result.freed,
                        deletedCount: candidates.count - result.failed.count,
                        failedCount: result.failed.count,
                        skippedCount: skipped
                    ))
                }
            }
        }
    }
}

/// 目录树节点的勾选状态：none（未选）/ partial（部分选）/ all（全部勾选）
enum DirectorySelectionState {
    case none, partial, all
}
