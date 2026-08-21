import Foundation
import Combine

/// 主视图模型：持有扫描/选中/清理状态
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

    private static let whitelistKey = "whitelist"

    // MARK: - 统计

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 {
        items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
    var selectedCount: Int { selectedIDs.count }

    var totalSizeString: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    var selectedSizeString: String {
        ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)
    }

    // MARK: - 权限

    init() {
        skipRunningApps = UserDefaults.standard.object(forKey: "skipRunningApps") as? Bool ?? true
        useTrash = UserDefaults.standard.object(forKey: "useTrash") as? Bool ?? false
    }

    func checkPermission() {
        permissionState = PermissionService.hasFullDiskAccess() ? .granted : .denied
    }

    // MARK: - 扫描

    func startScan() {
        scanTask?.cancel()
        selectedIDs.removeAll()
        cleanReport = nil

        let whitelist = self.whitelist
        let running = CacheScanner.runningBundleIDs()
        let xcodeRunning = running.contains("com.apple.dt.Xcode")

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
            let chunkSize = 8

            for start in stride(from: 0, to: sorted.count, by: chunkSize) {
                if Task.isCancelled { break }
                let end = min(start + chunkSize, sorted.count)
                let slice = Array(sorted[start..<end])

                // 并行统计一个批次的大小
                let sizes = await withTaskGroup(of: (Int, Int64).self) { group in
                    for (i, cand) in slice.enumerated() {
                        group.addTask {
                            let size = await CacheScanner.directorySizeAsync(cand.url)
                            return (i, size)
                        }
                    }
                    var dict: [Int: Int64] = [:]
                    for await (i, size) in group { dict[i] = size }
                    return dict
                }

                for (i, cand) in slice.enumerated() {
                    if Task.isCancelled { break }
                    let size = sizes[i] ?? 0
                    if size <= 0 { continue } // 空缓存不展示

                    let isRunning: Bool = cand.category == .developer
                        ? xcodeRunning
                        : running.contains(cand.bundleID ?? cand.url.lastPathComponent)

                    results.append(CacheItem(
                        url: cand.url,
                        name: Self.displayName(for: cand),
                        category: cand.category,
                        size: size,
                        isRunning: isRunning,
                        isWhitelisted: whitelist.contains(where: { cand.url.path.hasPrefix($0) })
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
            await MainActor.run {
                self.items = final
                self.isScanning = false
                self.currentPath = ""
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    // MARK: - 选择

    func toggleSelection(_ item: CacheItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    /// 一键勾选所有「安全」项：非运行中、非白名单
    func selectAllSafe() {
        selectedIDs = Set(
            items.filter { !$0.isRunning && !$0.isWhitelisted }.map { $0.id }
        )
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    // MARK: - 清理

    func cleanSelected() {
        let toClean = items.filter { selectedIDs.contains($0.id) }
        guard !toClean.isEmpty else { return }

        isCleaning = true
        let result = CacheCleanerService.clean(
            items: toClean,
            toTrash: useTrash,
            skipRunning: skipRunningApps,
            whitelist: whitelist
        )

        // 已清理的项从列表移除
        let cleanedIDs = Set(toClean.map { $0.id })
        items = items.filter { !cleanedIDs.contains($0.id) }
        selectedIDs.removeAll()
        isCleaning = false

        let freed = ByteCountFormatter.string(fromByteCount: result.freedBytes, countStyle: .file)
        cleanReport = CleanReport(
            freedString: freed,
            failedCount: result.failedPaths.count,
            skippedCount: result.skippedPaths.count
        )
    }

    // MARK: - 白名单

    var whitelist: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.whitelistKey) ?? [])
    }

    func whitelistPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.whitelistKey) ?? []
    }

    func addWhitelist(_ path: String) {
        var list = whitelistPaths()
        guard !list.contains(path) else { return }
        list.append(path)
        UserDefaults.standard.set(list, forKey: Self.whitelistKey)
    }

    func removeWhitelist(_ path: String) {
        var list = whitelistPaths()
        list.removeAll { $0 == path }
        UserDefaults.standard.set(list, forKey: Self.whitelistKey)
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
