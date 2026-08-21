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
    /// - Parameter isCancelled: 周期性取消检查（true 时提前停止）。后台 detached 任务不继承父级取消，
    ///   必须显式传入标志才能让用户在扫描/清理时真正中断。
    static func directorySize(at url: URL, isCancelled: () -> Bool = { false }) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        while let file = enumerator.nextObject() as? URL {
            if isCancelled() { break }
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

    /// 在后台线程统计目录大小（支持通过 isCancelled 中断）
    static func directorySizeAsync(_ url: URL, isCancelled: @escaping () -> Bool = { false }) async -> Int64 {
        await Task.detached(priority: .userInitiated) {
            directorySize(at: url, isCancelled: isCancelled)
        }.value
    }

    /// 当前正在运行的 App 的 bundle id 集合
    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
    }

    /// 正在运行 App 的「名称片段」（localizedName / 可执行名 分词小写）。
    /// 很多缓存目录名并不是 bundle id（如 `~/Library/Caches/Google/Chrome`），
    /// 单靠 bundle id 会漏判从而误删正在运行 App 的缓存。这套片段可兜底模糊匹配。
    static func runningAppNameTokens() -> Set<String> {
        var tokens = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            let names = [app.localizedName, app.executableURL?.lastPathComponent]
            for name in names.compactMap({ $0 }) {
                let parts = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                for part in parts where part.count >= 3 {
                    tokens.insert(String(part))
                }
            }
            if let bid = app.bundleIdentifier?.lowercased() { tokens.insert(bid) }
        }
        return tokens
    }

    /// 判断一个缓存目录是否正被某个运行中的 App 使用。
    /// - 优先：缓存目录名/bundleID 直接命中运行中 bundle id（准确）
    /// - 兜底：路径任一目录片段命中运行 App 的名称片段（覆盖 Google/Chrome 这类厂商目录）
    /// 判定偏保守——宁可跳过不删，也不误删正在使用的缓存。
    static func isCacheInUse(
        url: URL,
        bundleID: String?,
        runningBundleIDs: Set<String>,
        nameTokens: Set<String>
    ) -> Bool {
        if let bid = bundleID, runningBundleIDs.contains(bid) { return true }
        if runningBundleIDs.contains(url.lastPathComponent) { return true }

        let path = url.path.lowercased()
        for token in nameTokens where token.count >= 3 {
            let low = token.lowercased()
            if path == "/" + low
                || path.hasPrefix("/" + low + "/")
                || path.contains("/" + low + "/")
                || path.hasSuffix("/" + low) {
                return true
            }
        }
        return false
    }
}
