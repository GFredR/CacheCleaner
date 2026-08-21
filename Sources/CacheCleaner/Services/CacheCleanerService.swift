import Foundation

/// 清理结果报告
struct CleanResult {
    let freedBytes: Int64
    let failedPaths: [String]
    let skippedPaths: [String]
}

/// 清理服务：删除缓存目录内容（保留目录本身，App 运行时可正常重建）
enum CacheCleanerService {

    /// 执行清理
    /// - Parameters:
    ///   - items: 用户勾选的缓存项
    ///   - toTrash: true 时移入废纸篓（可恢复、较慢）；false 直接删除
    ///   - skipRunning: 是否跳过正在运行的 App 的缓存
    ///   - whitelist: 白名单路径（前缀匹配），命中则跳过
    static func clean(
        items: [CacheItem],
        toTrash: Bool,
        skipRunning: Bool,
        whitelist: Set<String>
    ) -> CleanResult {
        var freed: Int64 = 0
        var failed: [String] = []
        var skipped: [String] = []

        for item in items {
            if skipRunning && item.isRunning {
                skipped.append(item.url.path)
                continue
            }
            if whitelist.contains(where: { item.url.path.hasPrefix($0) }) {
                skipped.append(item.url.path)
                continue
            }

            let before = CacheScanner.directorySize(at: item.url)
            if removeContents(of: item.url, toTrash: toTrash) {
                freed += before
            } else {
                failed.append(item.url.path)
            }
        }

        return CleanResult(freedBytes: freed, failedPaths: failed, skippedPaths: skipped)
    }

    /// 删除目录内的所有内容（保留目录本身）
    private static func removeContents(of dir: URL, toTrash: Bool) -> Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return false
        }

        var allSucceeded = true
        for item in contents {
            do {
                if toTrash {
                    try fm.trashItem(at: item, resultingItemURL: nil)
                } else {
                    try fm.removeItem(at: item)
                }
            } catch {
                allSucceeded = false
            }
        }
        return allSucceeded
    }
}
