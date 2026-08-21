import Foundation
import Combine

/// 目录分析视图模型：持有扫描结果、勾选状态与清理逻辑
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
        // 只有可清理项能勾选
        guard file.level == .safeToClean else { return }
        if selectedIDs.contains(file.id) {
            selectedIDs.remove(file.id)
            _selectedSize -= file.size
        } else {
            selectedIDs.insert(file.id)
            _selectedSize += file.size
        }
    }

    func selectAllCleanable() {
        let all = files.filter { $0.level == .safeToClean }
        selectedIDs = Set(all.map { $0.id })
        _selectedSize = all.reduce(0) { $0 + $1.size }
    }

    // MARK: - 清理

    func cleanSelected(useTrash: Bool = false) {
        let targets = files.filter { selectedIDs.contains($0.id) && $0.level == .safeToClean }
        guard !targets.isEmpty else { return }

        // 与缓存清理页共用同一套白名单保护：命中白名单的文件即使标绿也跳过
        let whitelisted = WhitelistStore.paths()
        let candidates = targets.filter { !CacheCleanerService.isWhitelisted($0.url, whitelist: Set(whitelisted)) }
        let skippedCount = targets.count - candidates.count
        guard !candidates.isEmpty else { return }

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
                self.selectedIDs.removeAll()
                self._selectedSize = 0
                self.isCleaning = false

                let freedString = SizeFormatter.string(from: result.freed)
                var report = result.failed.isEmpty
                    ? "成功释放 \(freedString)"
                    : "成功释放 \(freedString)，\(result.failed.count) 个文件删除失败（可能正在使用）"
                if skipped > 0 {
                    report += "；\(skipped) 个文件命中白名单已跳过"
                }
                self.cleanReport = report
            }
        }
    }
}
