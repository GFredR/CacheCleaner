import Foundation
import Darwin

/// 分析出的单个文件
struct AnalyzedFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    /// 相对于根目录的路径（用于展示层级感）
    let relativePath: String
    let size: Int64
    let level: ImportanceLevel

    var sizeString: String {
        SizeFormatter.string(from: size)
    }
}

/// 目录分析器：先快预扫描数文件数 → 再正式扫描带真实进度
final class DirectoryAnalyzer {

    /// 快速预扫描：仅枚举路径，不读大小，用于进度条总量预估。
    /// 大目录通常几百毫秒完成（远快于正式扫描）。
    /// - Parameter isCancelled: 后台取消检查；detached 任务不继承父级取消，需显式传入。
    func countFiles(
        at url: URL,
        isCancelled: @escaping () -> Bool = { false },
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> Int {
        await Task.detached(priority: .userInitiated) {
            Self.countFilesSync(at: url, onProgress: onProgress, isCancelled: isCancelled)
        }.value
    }

    /// 同步枚举统计文件数
    /// onProgress: 周期性回调（processed, estimatedTotal），用于显示准备阶段进度
    private static func countFilesSync(
        at url: URL,
        onProgress: ((Int, Int) -> Void)?,
        isCancelled: @escaping () -> Bool
    ) -> Int {
        var count = 0
        var dirs = 0
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }
        // 估算顶层目录数作为进度分母（不可靠但够用）
        let totalEstimate = (try? fm.contentsOfDirectory(atPath: url.path).count) ?? 0
        var lastCb = 0
        for case let fileURL as URL in enumerator {
            if isCancelled() { break }
            let v = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if v?.isSymbolicLink == true { continue }
            if v?.isRegularFile == true { count += 1 } else { dirs += 1 }
            // 每扫 200 项回调一次（避免频繁更新 UI）
            if let cb = onProgress, (count + dirs) - lastCb >= 200 {
                lastCb = count + dirs
                cb(count + dirs, max(totalEstimate * 100, 1))  // *100：估算偏小，放大避免马上 100%
            }
        }
        onProgress?(count + dirs, count + dirs)
        return count
    }

    /// 分析指定目录
    /// - Parameters:
    ///   - url: 根目录
    ///   - totalCount: 预扫描得到的总文件数（用于显示真实百分比），0 表示未知
    ///   - onProgress: 进度回调（已处理文件数, 总文件数, 当前文件路径）
    /// - Returns: 全部文件（不含空目录）的平面列表
    func analyze(
        url: URL,
        totalCount: Int,
        isCancelled: @escaping () -> Bool = { false },
        onProgress: @escaping (Int, Int, String) -> Void
    ) async -> [AnalyzedFile] {
        // 与 countFiles 一致：枚举放后台执行。scanFiles 是全量同步枚举，
        // 若直接在当前执行体（MainActor）跑会卡死 UI；进度回调由调用方自行切主线程。
        await Task.detached(priority: .userInitiated) {
            Self.scanFiles(url: url, totalCount: totalCount, onProgress: onProgress, isCancelled: isCancelled)
        }.value
    }

    /// 同步枚举扫描（供 analyze 调用；枚举器迭代在非 async 上下文，兼容 Swift 6 严格并发）
    private static func scanFiles(
        url: URL,
        totalCount: Int,
        onProgress: @escaping (Int, Int, String) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> [AnalyzedFile] {
        let fm = FileManager.default
        var files: [AnalyzedFile] = []
        var processed = 0

        // 枚举器返回的是符号链接解析后的真实路径（如 /var → /private/var）。
        // 先把根目录统一成 realpath，relativePath 才能正确去掉前缀；否则整个绝对路径会变成目录段。
        let rootURL = url.resolvingSymlinksInPath()

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if isCancelled() { break }

            let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            // 不跟随符号链接，避免死循环与越界统计
            if values?.isSymbolicLink == true { continue }
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }

            let level = ImportanceClassifier.classify(url: fileURL)
            files.append(AnalyzedFile(
                url: fileURL,
                relativePath: relativePath(of: fileURL, from: rootURL),
                size: Int64(size),
                level: level
            ))
            processed += 1
            // 每 25 个文件回调一次（更平滑），或 totalCount 未知时也回调用于显示累计
            if processed % 25 == 0 || processed == totalCount {
                onProgress(processed, totalCount, fileURL.path)
            }
        }

        // 收尾确保最后一次回调落到 100%
        if !files.isEmpty {
            onProgress(processed, max(processed, totalCount), "")
        }

        return files
    }

    /// 计算相对路径。
    /// 枚举器可能返回符号链接已解析的真实路径（如 /var → /private/var），也可能保持原样；
    /// 因此同时尝试未解析与已解析两种形态做前缀比对，避免绝对路径被当成目录段。
    private static func relativePath(of file: URL, from root: URL) -> String {
        let rootComps = root.resolvingSymlinksInPath().pathComponents
        for path in [file.path, file.resolvingSymlinksInPath().path] {
            let comps = URL(fileURLWithPath: path).pathComponents
            guard comps.count >= rootComps.count,
                  Array(comps.prefix(rootComps.count)) == rootComps else { continue }
            return comps.suffix(comps.count - rootComps.count).joined(separator: "/")
        }
        // 前缀始终不匹配（理论上不该发生）：回退为单文件名，而非整条绝对路径，
        // 避免把 /Users/.../xxx 也切成多层目录段，渲染出假的层级树。
        return file.lastPathComponent
    }
}