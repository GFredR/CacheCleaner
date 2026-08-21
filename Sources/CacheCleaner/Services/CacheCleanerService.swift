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
    ///   - skipRunning: 是否跳过正在运行的 App 的缓存（**清理时刻实时查询**，而非扫描时快照）
    ///   - whitelist: 白名单路径（目录边界前缀匹配），命中则跳过
    static func clean(
        items: [CacheItem],
        toTrash: Bool,
        skipRunning: Bool,
        whitelist: Set<String>
    ) -> CleanResult {
        // 实时获取当前运行中的 bundle id（避免扫描到清理之间的时间差导致误删正在使用的 App 缓存）
        let runningNow = skipRunning ? CacheScanner.runningBundleIDs() : []
        let xcodeRunning = runningNow.contains("com.apple.dt.Xcode")

        var freed: Int64 = 0
        var failed: [String] = []
        var skipped: [String] = []

        for item in items {
            // 实时复核：此刻是否正在运行（而不是扫描时的快照）
            let running: Bool
            if item.category == .developer {
                running = xcodeRunning
            } else {
                let bid = item.url.lastPathComponent
                running = runningNow.contains(bid)
            }
            if skipRunning && running {
                skipped.append(item.url.path)
                continue
            }
            if isWhitelisted(item.url, whitelist: whitelist) {
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

    /// 白名单匹配：目录边界前缀（/Caches/WeChat 只匹配 WeChat 目录本身，不误匹配 WeChatData）
    static func isWhitelisted(_ url: URL, whitelist: Set<String>) -> Bool {
        let path = url.path
        return whitelist.contains { entry in
            path == entry || path.hasPrefix(entry + "/")
        }
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
