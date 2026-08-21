import Foundation

/// 分析出的单个文件
struct AnalyzedFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    /// 相对于根目录的路径（用于展示层级感）
    let relativePath: String
    let size: Int64
    let level: ImportanceLevel

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// 目录分析器：先快预扫描数文件数 → 再正式扫描带真实进度
final class DirectoryAnalyzer {

    /// 快速预扫描：仅枚举路径，不读大小，用于进度条总量预估。
    /// 大目录通常几百毫秒完成（远快于正式扫描）。
    func countFiles(at url: URL) async -> Int {
        await Task.detached(priority: .userInitiated) {
            Self.countFilesSync(at: url)
        }.value
    }

    /// 同步枚举统计文件数（枚举迭代在非并发闭包上下文，兼容 Swift 6 严格并发）
    private static func countFilesSync(at url: URL) -> Int {
        var count = 0
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            let v = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if v?.isSymbolicLink == true { continue }
            if v?.isRegularFile == true { count += 1 }
        }
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
        onProgress: @escaping (Int, Int, String) -> Void
    ) async -> [AnalyzedFile] {
        // 枚举在同步私有函数中执行（避免 Swift 6 async 上下文的 makeIterator 限制）
        scanFiles(url: url, totalCount: totalCount, onProgress: onProgress)
    }

    /// 同步枚举扫描（供 analyze 调用；枚举器迭代在非 async 上下文，兼容 Swift 6 严格并发）
    private func scanFiles(
        url: URL,
        totalCount: Int,
        onProgress: @escaping (Int, Int, String) -> Void
    ) -> [AnalyzedFile] {
        let fm = FileManager.default
        var files: [AnalyzedFile] = []
        var processed = 0

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }

            let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            // 不跟随符号链接，避免死循环与越界统计
            if values?.isSymbolicLink == true { continue }
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }

            let level = ImportanceClassifier.classify(url: fileURL)
            files.append(AnalyzedFile(
                url: fileURL,
                relativePath: relativePath(of: fileURL, from: url),
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

    /// 计算相对路径
    private func relativePath(of file: URL, from root: URL) -> String {
        let filePath = file.path
        let rootPath = root.path
        guard filePath.hasPrefix(rootPath) else { return filePath }
        let rel = String(filePath.dropFirst(rootPath.count))
        return rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
    }
}