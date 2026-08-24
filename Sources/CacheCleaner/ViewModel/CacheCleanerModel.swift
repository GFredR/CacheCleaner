import Foundation
import Combine

/// 主视图模型：持有扫描/选中/清理状态
/// @MainActor：所有 @Published 与状态变更都收口到主线程；重 IO 走 Task.detached 不触碰可达状态
@MainActor
final class CacheCleanerModel: ObservableObject {

    // MARK: - 发布状态

    @Published var items: [CacheItem] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var scanProgress: Double = 0
    @Published var currentPath: String = ""
    @Published var permissionState: PermissionState = .unknown
    @Published var cleanReport: CleanReport?

    // MARK: - 设置（UserDefaults 持久化）

    @Published var skipRunningApps: Bool {
        didSet { UserDefaults.standard.set(skipRunningApps, forKey: "skipRunningApps") }
    }
    @Published var useTrash: Bool {
        didSet { UserDefaults.standard.set(useTrash, forKey: "useTrash") }
    }
    /// 系统缓存（com.apple.*）清理时强制移入废纸篓，防止不可恢复误删
    @Published var forceTrashForSystem: Bool {
        didSet { UserDefaults.standard.set(forceTrashForSystem, forKey: "forceTrashForSystem") }
    }

    enum PermissionState {
        case unknown, granted, denied
    }

    struct CleanReport {
        let freedString: String
        let failedCount: Int
        let skippedCount: Int
        var details: String {
            var text = "成功释放 \(freedString)"
            if failedCount > 0 {
                text += "，\(failedCount) 项清理失败（可能正在使用）"
            }
            if skippedCount > 0 {
                text += "，\(skippedCount) 项已跳过（运行中或白名单）"
            }
            return text
        }
    }

    // MARK: - 私有

    private let scanner = CacheScanner()
    private var scanTask: Task<Void, Never>?
    private var scanFlag: CancellationFlag?

    // MARK: - 统计

    /// 已缓存的总大小，扫描完成后更新，避免每个 View 刷新都做一次 O(n) reduce
    private(set) var totalSize: Int64 = 0
    /// 选中大小增量维护，避免每次渲染都 O(n) 过滤求和
    private var _selectedSize: Int64 = 0

    var selectedSize: Int64 { _selectedSize }
    var selectedCount: Int { selectedIDs.count }

    /// 选中项中属于系统缓存（com.apple.*）的数量——清理时会强制进废纸篓
    var selectedSystemCount: Int {
        items.filter { selectedIDs.contains($0.id) && $0.category == .system }.count
    }

    var totalSizeString: String {
        SizeFormatter.string(from: totalSize)
    }
    var selectedSizeString: String {
        SizeFormatter.string(from: selectedSize)
    }
    /// 选中项中「将被跳过」的数量（运行中或白名单，且 skipRunningApps 开启时）
    var selectedSkippedCount: Int {
        guard skipRunningApps else { return 0 }
        return items.filter { selectedIDs.contains($0.id) && ($0.isRunning || $0.isWhitelisted) }.count
    }

    // MARK: - 权限

    init() {
        skipRunningApps = UserDefaults.standard.object(forKey: "skipRunningApps") as? Bool ?? true
        useTrash = UserDefaults.standard.object(forKey: "useTrash") as? Bool ?? false
        forceTrashForSystem = UserDefaults.standard.object(forKey: "forceTrashForSystem") as? Bool ?? true
    }

    @Published var isCheckingPermission = false

    func checkPermission() {
        // 已在检查中则忽略重复点击，避免 ViewBridge sheet 重入崩溃
        guard !isCheckingPermission else { return }
        isCheckingPermission = true
        Task { [weak self] in
            // 后台枚举磁盘目录，避免主线程 IO 卡死
            let granted = await Task.detached(priority: .userInitiated) {
                PermissionService.hasFullDiskAccess()
            }.value
            let state: PermissionState = granted ? .granted : .denied
            await MainActor.run { [weak self] in
                self?.permissionState = state
                self?.isCheckingPermission = false
            }
        }
    }

    // MARK: - 扫描

    func startScan() {
        scanTask?.cancel()
        scanFlag?.cancel()
        selectedIDs.removeAll()
        _selectedSize = 0
        cleanReport = nil

        let whitelist = self.whitelist
        let running = CacheScanner.runningBundleIDs()
        let nameTokens = CacheScanner.runningAppNameTokens()
        let xcodeRunning = running.contains("com.apple.dt.Xcode")
        let flag = CancellationFlag()
        self.scanFlag = flag

        scanTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isScanning = true
                self.scanProgress = 0
                self.currentPath = ""
                self.items = []
            }

            let candidates = self.scanner.discoverCandidates()
            let sorted = candidates.sorted {
                $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            let total = sorted.count
            var done = 0
            var results: [CacheItem] = []
            var sum: Int64 = 0
            let chunkSize = 8

            for start in stride(from: 0, to: sorted.count, by: chunkSize) {
                if flag.isCancelled { break }
                let end = min(start + chunkSize, sorted.count)
                let slice = Array(sorted[start..<end])

                // 并行统计一个批次的大小；后台任务通过显式标志提前中断
                let sizes = await withTaskGroup(of: (Int, Int64).self) { group in
                    for (i, cand) in slice.enumerated() {
                        group.addTask {
                            let size = await CacheScanner.directorySizeAsync(cand.url) {
                                flag.isCancelled
                            }
                            return (i, size)
                        }
                    }
                    var dict: [Int: Int64] = [:]
                    for await (i, size) in group { dict[i] = size }
                    return dict
                }

                for (i, cand) in slice.enumerated() {
                    if flag.isCancelled { break }
                    let size = sizes[i] ?? 0
                    if size <= 0 { continue } // 空缓存不展示

                    let isRunning: Bool = cand.category == .developer
                        ? xcodeRunning
                        : CacheScanner.isCacheInUse(
                            url: cand.url,
                            bundleID: cand.bundleID,
                            runningBundleIDs: running,
                            nameTokens: nameTokens
                        )

                    sum += size
                    results.append(CacheItem(
                        url: cand.url,
                        name: Self.displayName(for: cand),
                        category: cand.category,
                        bundleID: cand.bundleID,
                        size: size,
                        isRunning: isRunning,
                        isWhitelisted: CacheCleanerService.isWhitelisted(cand.url, whitelist: whitelist)
                    ))
                }

                done += slice.count
                let progress = Double(done) / Double(max(total, 1))
                let lastPath = slice.last?.url.path ?? ""
                await MainActor.run {
                    self.scanProgress = progress
                    self.currentPath = lastPath
                }
            }

            let final = results.sorted { $0.size > $1.size }
            let totalBytes = sum
            await MainActor.run {
                self.items = final
                self.totalSize = totalBytes
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

    func toggleSelection(_ item: CacheItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
            _selectedSize -= item.size
        } else {
            selectedIDs.insert(item.id)
            _selectedSize += item.size
        }
    }

    /// 一键勾选所有「安全」项：非运行中、非白名单
    func selectAllSafe() {
        let safe = items.filter { !$0.isRunning && !$0.isWhitelisted }
        selectedIDs = Set(safe.map { $0.id })
        _selectedSize = safe.reduce(0) { $0 + $1.size }
    }

    /// 全选所有项（含运行中、白名单）—— 用户主动承担风险
    func selectAll() {
        selectedIDs = Set(items.map { $0.id })
        _selectedSize = items.reduce(0) { $0 + $1.size }
    }

    func clearSelection() {
        selectedIDs.removeAll()
        _selectedSize = 0
    }

    // MARK: - 清理

    func cleanSelected() {
        let toClean = items.filter { selectedIDs.contains($0.id) }
        guard !toClean.isEmpty else { return }

        isCleaning = true
        let useTrash = self.useTrash
        let skipRunning = self.skipRunningApps
        let whitelist = self.whitelist
        let forceTrash = self.forceTrashForSystem
        let flag = CancellationFlag()

        Task { [weak self] in
            guard let self else { return }
            // 后台执行（directorySize + 删除可能耗时很久，不能阻塞主线程）
            let result = await Task.detached(priority: .userInitiated) {
                CacheCleanerService.clean(
                    items: toClean,
                    toTrash: useTrash,
                    skipRunning: skipRunning,
                    whitelist: whitelist,
                    forceTrashForSystem: forceTrash,
                    isCancelled: { flag.isCancelled }
                )
            }.value

            await MainActor.run {
                // 移除「确实清理过」的项（完整或部分成功）；彻底失败的保留在列表（可能有正在使用的文件）
                let failedSet = Set(result.failedPaths)
                let doneIDs = Set(toClean.filter { !failedSet.contains($0.url.path) }.map { $0.id })
                self.items = self.items.filter { !doneIDs.contains($0.id) }
                self.totalSize = self.items.reduce(0) { $0 + $1.size }
                self.selectedIDs.removeAll()
                self._selectedSize = 0
                self.isCleaning = false

                let freed = SizeFormatter.string(from: result.freedBytes)
                self.cleanReport = CleanReport(
                    freedString: freed,
                    failedCount: result.totalFailed,
                    skippedCount: result.skippedPaths.count
                )
            }
        }
    }

    // MARK: - 白名单

    var whitelist: Set<String> {
        Set(WhitelistStore.paths())
    }

    func whitelistPaths() -> [String] {
        WhitelistStore.paths()
    }

    func addWhitelist(_ path: String) {
        WhitelistStore.add(path)
    }

    func removeWhitelist(_ path: String) {
        WhitelistStore.remove(path)
    }

    // MARK: - 辅助

    private static func displayName(for candidate: ScanCandidate) -> String {
        if let bundleID = candidate.bundleID,
           let name = AppNameMapper.displayName(forBundleID: bundleID) {
            return name
        }
        return candidate.url.lastPathComponent
    }
}
