import Foundation
import AppKit
import Combine

/// 「空间洞察」视图模型：选目录后只读扫描最大文件 / 重复文件
@MainActor
final class SpaceInsightModel: ObservableObject {

    @Published var rootURL: URL?
    @Published var rootName: String = ""
    @Published var largestFiles: [LargeFileItem] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var isScanning = false
    @Published var mode: Mode = .largest
    @Published var scannedCount = 0
    @Published var errorMessage: String?

    // 大文件勾选删除
    @Published var selectedLargeFileIDs: Set<UUID> = []
    // 删除进行中（重入保护）
    @Published private(set) var isDeleting = false
    // 删除结果反馈
    @Published var deleteReport: DeleteReport?

    enum Mode: String, CaseIterable, Identifiable {
        case largest = "最大文件"
        case duplicates = "重复文件"
        var id: String { rawValue }
    }

    /// 一次删除操作的结果，供 UI 提示释放量 / 失败项
    struct DeleteReport {
        let freedBytes: Int64
        let trashedCount: Int
        let failedPaths: [String]
        var summary: String {
            let freed = SizeFormatter.string(from: freedBytes)
            if failedPaths.isEmpty {
                return "已删除 \(trashedCount) 个文件，释放 \(freed)"
            }
            return "已删除 \(trashedCount) 个文件，释放 \(freed)；失败 \(failedPaths.count) 个：\(failedPaths.joined(separator: "、"))"
        }
    }

    private let scanner = LargeFileScanner()
    private var scanTask: Task<Void, Never>?
    private var scanFlag: CancellationFlag?

    /// 选择目录
    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择要分析的空间"
        if panel.runModal() == .OK, let url = panel.url {
            rootURL = url
            rootName = url.lastPathComponent
            largestFiles = []
            duplicateGroups = []
            startScan()
        }
    }

    /// 用给定目录直接开始（供程序化调用/测试）
    func scan(url: URL) {
        cancelScan()
        rootURL = url
        rootName = url.lastPathComponent
        largestFiles = []
        duplicateGroups = []
        startScan()
    }

    func switchMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        mode = newMode
        // 尚未扫描过当前模式时启动；已扫过直接展示缓存的结论
        let hasData = newMode == .largest ? !largestFiles.isEmpty : !duplicateGroups.isEmpty
        if !hasData && rootURL != nil && !isScanning {
            startScan()
        }
    }

    // MARK: - 操作

    func toggleLargeFileSelection(_ id: UUID) {
        if selectedLargeFileIDs.contains(id) { selectedLargeFileIDs.remove(id) }
        else { selectedLargeFileIDs.insert(id) }
    }
    func selectAllLargest() {
        selectedLargeFileIDs = Set(largestFiles.map(\.id))
    }
    func clearLargeFileSelection() {
        selectedLargeFileIDs = []
    }

    var selectedLargeFiles: [LargeFileItem] {
        largestFiles.filter { selectedLargeFileIDs.contains($0.id) }
    }
    var selectedLargeBytes: Int64 {
        selectedLargeFiles.reduce(0) { $0 + $1.size }
    }

    /// 在 Finder 中定位（只读动作，不删不改）
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 把勾选的大文件移到废纸篓（可恢复）；成功删除的从列表移除，失败的留在列表供重试
    func trashSelectedLargeFiles() {
        let targets = selectedLargeFiles
        guard !targets.isEmpty, !isDeleting else { return }
        performTrash(files: targets) { [weak self] trashedIDs in
            guard let self else { return }
            self.largestFiles.removeAll { trashedIDs.contains($0.id) }
            self.selectedLargeFileIDs = self.selectedLargeFileIDs.intersection(Set(self.largestFiles.map(\.id)))
        }
    }

    /// 清理某重复组的多余副本——每组保留第一份，其余移入废纸篓；删除失败者留在组里
    func cleanupDuplicateGroup(_ groupID: UUID) {
        guard let group = duplicateGroups.first(where: { $0.id == groupID }),
              group.files.count >= 2, !isDeleting else { return }
        let toTrash = Array(group.files.dropFirst())
        performTrash(files: toTrash) { [weak self] trashedIDs in
            guard let self else { return }
            let leading = group.files[0]
            let remaining = group.files[1...].filter { !trashedIDs.contains($0.id) }
            let merged = DuplicateGroup(size: group.size, files: [leading] + remaining)
            if merged.files.count >= 2, let idx = self.duplicateGroups.firstIndex(where: { $0.id == groupID }) {
                self.duplicateGroups[idx] = merged
            } else {
                self.duplicateGroups.removeAll { $0.id == groupID }
            }
        }
    }

    /// 执行移到废纸篓；onComplete 在主线程回调，入参为已成功移除的 id 集合
    private func performTrash(
        files: [LargeFileItem],
        onComplete: @escaping @MainActor (_ trashedIDs: Set<UUID>) -> Void
    ) {
        isDeleting = true
        deleteReport = nil
        let urls = files.map(\.url)
        Task {
            let result = await Self.trashFiles(urls: urls)
            let trashedIDs = Set(files.filter { result.trashed.contains($0.url) }.map(\.id))
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isDeleting = false
                self.deleteReport = DeleteReport(
                    freedBytes: result.freedBytes,
                    trashedCount: result.trashed.count,
                    failedPaths: result.failedPaths
                )
                onComplete(trashedIDs)
            }
        }
    }

    /// 把一批文件移到废纸篓（后台执行）；全部走废纸篓、单条失败不中断
    private nonisolated static func trashFiles(urls: [URL]) async -> (trashed: [URL], failedPaths: [String], freedBytes: Int64) {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var trashed: [URL] = []
            var failed: [String] = []
            var freed: Int64 = 0
            for url in urls {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    freed += Int64(size)
                }
                do {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                    trashed.append(url)
                } catch {
                    failed.append(url.path)
                }
            }
            return (trashed, failed, freed)
        }.value
    }

    private func startScan() {
        guard let url = rootURL else { return }
        scanTask?.cancel()
        scanFlag?.cancel()
        let flag = CancellationFlag()
        scanFlag = flag
        scannedCount = 0
        errorMessage = nil

        scanTask = Task { [weak self] in
            guard let self else { return }
            self.isScanning = true
            switch self.mode {
            case .largest:
                let items = await self.scanner.scanLargeFiles(
                    at: url,
                    limit: 50,
                    isCancelled: { flag.isCancelled },
                    onProgress: { [weak self] processed in
                        Task { @MainActor [weak self] in
                            self?.scannedCount = processed
                        }
                    }
                )
                guard !flag.isCancelled else {
                    await MainActor.run { [weak self] in self?.isScanning = false }
                    return
                }
                await MainActor.run { [weak self] in
                    self?.largestFiles = items
                    self?.isScanning = false
                }
            case .duplicates:
                let groups = await self.scanner.scanDuplicates(
                    at: url,
                    isCancelled: { flag.isCancelled },
                    onProgress: { [weak self] processed in
                        Task { @MainActor [weak self] in
                            self?.scannedCount = processed
                        }
                    }
                )
                guard !flag.isCancelled else {
                    await MainActor.run { [weak self] in self?.isScanning = false }
                    return
                }
                await MainActor.run { [weak self] in
                    self?.duplicateGroups = groups
                    self?.isScanning = false
                }
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanFlag?.cancel()
        isScanning = false
    }
}