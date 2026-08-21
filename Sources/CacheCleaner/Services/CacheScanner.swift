import Foundation
import AppKit

/// 扫描过程中发现的一个候选缓存目录
struct ScanCandidate {
    let url: URL
    let category: CacheCategory
    /// 目录名即 bundle id（沙盒容器 / 大多数 App 缓存目录名），可用于反查 App 名和运行状态
    let bundleID: String?
}

/// 缓存扫描器：负责「目录发现」和「大小统计」
final class CacheScanner {

    private let fileManager = FileManager.default

    /// 发现所有候选缓存目录（用户级缓存 + 沙盒容器缓存 + Xcode DerivedData）
    func discoverCandidates() -> [ScanCandidate] {
        var candidates: [ScanCandidate] = []
        let home = fileManager.homeDirectoryForCurrentUser

        // 1. ~/Library/Caches 下的子目录
        let caches = home.appendingPathComponent("Library/Caches")
        if let entries = try? fileManager.contentsOfDirectory(
            at: caches,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries {
                guard isDirectory(entry) else { continue }
                let name = entry.lastPathComponent
                let category: CacheCategory = name.hasPrefix("com.apple.") ? .system : .application
                candidates.append(ScanCandidate(url: entry, category: category, bundleID: name))
            }
        }

        // 2. ~/Library/Containers/*/Data/Library/Caches（沙盒 App 的缓存）
        let containers = home.appendingPathComponent("Library/Containers")
        if let entries = try? fileManager.contentsOfDirectory(
            at: containers,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for container in entries where isDirectory(container) {
                let cachesDir = container.appendingPathComponent("Data/Library/Caches")
                if fileManager.fileExists(atPath: cachesDir.path) {
                    candidates.append(
                        ScanCandidate(url: cachesDir, category: .sandbox, bundleID: container.lastPathComponent)
                    )
                }
            }
        }

        // 3. Xcode DerivedData（编译缓存，通常占大头）
        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if let entries = try? fileManager.contentsOfDirectory(
            at: derived,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries where isDirectory(entry) {
                candidates.append(ScanCandidate(url: entry, category: .developer, bundleID: nil))
            }
        }

        return candidates
    }

    private func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    /// 递归统计目录总大小（不跟随符号链接，防止死循环和越界统计）
    static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        while let file = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            let values = try? file.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            if values?.isSymbolicLink == true { continue }
            if values?.isRegularFile == true, let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// 在后台线程统计目录大小
    static func directorySizeAsync(_ url: URL) async -> Int64 {
        await Task.detached(priority: .userInitiated) {
            directorySize(at: url)
        }.value
    }

    /// 当前正在运行的 App 的 bundle id 集合
    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
    }
}
