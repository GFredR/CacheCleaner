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
    /// 清理进度：已完成项数 / 总项数 / 当前正在处理的项名（驱动进度条与文案）
    @Published var cleanDone = 0
    @Published var cleanTotal = 0
    @Published var cleanCurrentName = ""
    var cleanProgress: Double { Double(cleanDone) / Double(max(cleanTotal, 1)) }
    /// 清理取消：点一次后置位，等后台任务返回（按钮转为「停止中…」防重复点击）
    @Published var isCancellingClean = false
    @Published var scanProgress: Double = 0
    @Published var currentPath: String = ""
    @Published var permissionState: PermissionState = .unknown
    @Published var cleanReport: CleanReport?

    // MARK: - 废纸篓

    @Published var trashSize: Int64 = 0
    @Published var isEmptingTrash = false
    var trashSizeString: String { SizeFormatter.string(from: trashSize) }

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
        /// 失败原因汇总（如「权限不足 2 · 文件被占用 1」），无失败明细时为 nil
        let failureSummary: String?
        /// 非缓存清理场景（如清空废纸篓）的自定义文案，设置后 details 直接返回它
        let customDetails: String?
        /// 有失败/跳过项且已保留勾选时，报告弹窗可一键重试
        var canRetry: Bool { customDetails == nil && (failedCount > 0 || skippedCount > 0) }

        init(
            freedString: String,
            failedCount: Int,
            skippedCount: Int,
            failureSummary: String? = nil,
            customDetails: String? = nil
        ) {
            self.freedString = freedString
            self.failedCount = failedCount
            self.skippedCount = skippedCount
            self.failureSummary = failureSummary
            self.customDetails = customDetails
        }

        var details: String {
            if let customDetails { return customDetails }
            var text = "成功释放 \(freedString)"
            if failedCount > 0 {
                text += "，\(failedCount) 项清理失败"
                if let failureSummary {
                    text += "（\(failureSummary)）"
                }
            }
            if skippedCount > 0 {
                text += "，\(skippedCount) 项已跳过（运行中或白名单）"
            }
            if canRetry {
                text += "。未完成项已保留勾选，可重试"
            }
            return text
        }
    }

    // MARK: - 按应用聚合

    /// 缓存清理页展示维度：按目录（原列表）/ 按应用（同一应用缓存归并成一组）
    enum CacheDisplayMode: String, CaseIterable, Identifiable {
        case directory = "按目录"
        case app = "按应用"
        var id: String { rawValue }
    }

    @Published var displayMode: CacheDisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: "cacheDisplayMode") }
    }

    /// 一个应用分组：同一 bundle id（或同名目录）的缓存项归并以直观展示"这个 App 占了多少"
    struct AppGroup: Identifiable {
        let id: String
        let name: String
        let systemImage: String
        var items: [CacheItem]
        var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
        var sizeString: String { SizeFormatter.string(from: totalSize) }
    }

    enum CacheSelectionState { case none, partial, all }

    /// 把 items 按应用归并成组，组按总大小降序
    var appGroups: [AppGroup] {
        var map: [String: AppGroup] = [:]
        for item in items {
            let key = item.bundleID ?? item.name
            var group = map[key] ?? AppGroup(
                id: key,
                name: item.name,
                systemImage: item.category.systemImage,
                items: []
            )
            group.items.append(item)
            map[key] = group
        }
        return map.values.sorted { $0.totalSize > $1.totalSize }
    }

    func selectionState(_ group: AppGroup) -> CacheSelectionState {
        let sel = group.items.filter { selectedIDs.contains($0.id) }.count
        if sel == 0 { return .none }
        if sel == group.items.count { return .all }
        return .partial
    }

    /// 整组勾选/取消
    func toggleGroup(_ group: AppGroup) {
        let allSelected = group.items.allSatisfy { selectedIDs.contains($0.id) }
        if allSelected {
            for item in group.items {
                selectedIDs.remove(item.id)
                _selectedSize -= item.size
            }
        } else {
            for item in group.items {
                selectedIDs.insert(item.id)
                _selectedSize += item.size
            }
        }
    }

    // MARK: - 私有

    private let scanner = CacheScanner()
    private var scanTask: Task<Void, Never>?
    private var scanFlag: CancellationFlag?
    private var cleanFlag: CancellationFlag?

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
        displayMode = .directory
        if let raw = UserDefaults.standard.string(forKey: "cacheDisplayMode"),
           let mode = CacheDisplayMode(rawValue: raw) {
            displayMode = mode
        }
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
        // 防重入：清理进行中再次调用直接忽略（UI 已 disabled，此处兜底编程入口）
        guard !isCleaning else { return }
        let toClean = items.filter { selectedIDs.contains($0.id) }
        guard !toClean.isEmpty else { return }

        isCleaning = true
        isCancellingClean = false
        cleanDone = 0
        cleanTotal = toClean.count
        cleanCurrentName = ""
        let useTrash = self.useTrash
        let skipRunning = self.skipRunningApps
        let whitelist = self.whitelist
        let forceTrash = self.forceTrashForSystem
        let flag = CancellationFlag()
        self.cleanFlag = flag

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
                ) { done, total, name in
                    // 回调在后台线程，进度 UI 更新切回主线程
                    Task { @MainActor in
                        self.cleanDone = done
                        self.cleanTotal = total
                        self.cleanCurrentName = name
                    }
                }
            }.value

            await MainActor.run {
                // 移除「确实清理过」的项（完整或部分成功）；彻底失败的保留在列表（可能有正在使用的文件）
                let failedSet = Set(result.failedPaths)
                let doneIDs = Set(toClean.filter { !failedSet.contains($0.url.path) }.map { $0.id })
                self.items = self.items.filter { !doneIDs.contains($0.id) }
                self.totalSize = self.items.reduce(0) { $0 + $1.size }
                // 失败/跳过的项保留勾选：用户可直接点「清理所选」重试，无需重新勾选
                self._selectedSize = self.items.filter { self.selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
                self.cleanDone = self.cleanTotal
                self.isCleaning = false
                self.isCancellingClean = false
                self.cleanFlag = nil

                let freed = SizeFormatter.string(from: result.freedBytes)
                self.cleanReport = CleanReport(
                    freedString: freed,
                    failedCount: result.totalFailed,
                    skippedCount: result.skippedPaths.count,
                    failureSummary: result.failureSummary
                )
                // 写入清理历史（成功释放了才算一条，纯粹跳过/全白名单不记）
                if result.freedBytes > 0 {
                    CleanHistoryStore.add(CleanHistoryEntry(
                        source: .cacheCleaner,
                        useTrash: useTrash,
                        freedBytes: result.freedBytes,
                        deletedCount: toClean.count - result.totalFailed - result.skippedPaths.count,
                        failedCount: result.totalFailed,
                        skippedCount: result.skippedPaths.count
                    ))
                }
                // 废纸篓模式下清理会改变废纸篓占用，顺手刷新
                if useTrash { self.refreshTrashSize() }
            }
        }
    }

    /// 取消进行中的清理：置位标志即可，后台任务在下一个检查点退出并按已完成部分汇报
    func cancelClean() {
        guard isCleaning, !isCancellingClean else { return }
        isCancellingClean = true
        cleanFlag?.cancel()
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

    /// 右键加入白名单并立即刷新列表标记（白名单徽标即时出现，无需重新扫描）
    func addWhitelistAndRefresh(_ path: String) {
        WhitelistStore.add(path)
        refreshWhitelistFlags()
    }

    func removeWhitelistAndRefresh(_ path: String) {
        WhitelistStore.remove(path)
        refreshWhitelistFlags()
    }

    private func refreshWhitelistFlags() {
        let wl = whitelist
        for i in items.indices {
            let hit = CacheCleanerService.isWhitelisted(items[i].url, whitelist: wl)
            if items[i].isWhitelisted != hit {
                items[i].isWhitelisted = hit
            }
        }
    }

    func removeWhitelist(_ path: String) {
        WhitelistStore.remove(path)
    }

    // MARK: - 废纸篓

    private var isRefreshingTrash = false

    /// 后台统计废纸篓占用（可能上万文件，绝不能在主线程算）
    func refreshTrashSize() {
        guard !isRefreshingTrash, !isEmptingTrash else { return }
        isRefreshingTrash = true
        Task { [weak self] in
            let size = await Task.detached(priority: .utility) {
                CacheCleanerService.trashSize()
            }.value
            await MainActor.run { [weak self] in
                self?.trashSize = size
                self?.isRefreshingTrash = false
            }
        }
    }

    /// 清空废纸篓（确认对话框后调用），结果并入清理历史
    func emptyTrash() {
        guard !isEmptingTrash, !isCleaning else { return }
        isEmptingTrash = true

        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                CacheCleanerService.emptyTrash(isCancelled: { false })
            }.value

            await MainActor.run {
                self.isEmptingTrash = false
                self.refreshTrashSize()
                if result.freed > 0 {
                    CleanHistoryStore.add(CleanHistoryEntry(
                        source: .trash,
                        useTrash: false,
                        freedBytes: result.freed,
                        deletedCount: 0,
                        failedCount: result.failedCount,
                        skippedCount: 0
                    ))
                }
                var details: String
                if result.freed > 0 {
                    details = "已清空废纸篓，释放 \(SizeFormatter.string(from: result.freed))"
                    if result.failedCount > 0 {
                        details += "，\(result.failedCount) 个文件未能删除（可能已锁定或无权限）"
                    }
                } else if result.failedCount > 0 {
                    details = "废纸篓未能清空：\(result.failedCount) 个文件删除失败（可能已锁定或无权限）"
                } else {
                    details = "废纸篓已是空的"
                }
                self.cleanReport = CleanReport(
                    freedString: SizeFormatter.string(from: result.freed),
                    failedCount: 0,
                    skippedCount: 0,
                    customDetails: details
                )
            }
        }
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
