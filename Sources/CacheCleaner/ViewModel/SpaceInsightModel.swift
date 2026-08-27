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

    enum Mode: String, CaseIterable, Identifiable {
        case largest = "最大文件"
        case duplicates = "重复文件"
        var id: String { rawValue }
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