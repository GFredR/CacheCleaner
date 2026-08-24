import Foundation

/// 清理结果报告
struct CleanResult {
    let freedBytes: Int64
    /// 完全没能删（一个条目都没删掉），保留在列表中等待用户回退（用户可重试）
    let failedPaths: [String]
    /// 只删了一部分（其余条目可能被占用/无权限），内容已基本清空，从列表移除
    let partialPaths: [String]
    let skippedPaths: [String]

    var totalFailed: Int { failedPaths.count + partialPaths.count }
}

/// 清理服务：删除缓存目录内容（保留目录本身，App 运行时可正常重建）
enum CacheCleanerService {

    /// 执行清理
    /// - Parameters:
    ///   - items: 用户勾选的缓存项
    ///   - toTrash: true 时移入废纸篓（可恢复、较慢）；false 直接删除
    ///   - skipRunning: 是否跳过正在运行的 App 的缓存（**清理时刻实时查询**，而非扫描时快照）
    ///   - whitelist: 白名单路径（目录边界前缀匹配），命中则跳过
    ///   - forceTrashForSystem: 系统缓存（com.apple.*）是否强制移入废纸篓作为保护，防止不可恢复误删
    ///   - isCancelled: 后台取消检查，true 时提前终止未开始的处理
    static func clean(
        items: [CacheItem],
        toTrash: Bool,
        skipRunning: Bool,
        whitelist: Set<String>,
        forceTrashForSystem: Bool,
        isCancelled: @escaping () -> Bool
    ) -> CleanResult {
        // 实时获取当前运行中的 app（避免扫描到清理之间的时间差导致误删正在使用的 App 缓存）
        let runningNow = skipRunning ? CacheScanner.runningBundleIDs() : []
        let nameTokens = skipRunning ? CacheScanner.runningAppNameTokens() : []

        var freed: Int64 = 0
        var failed: [String] = []
        var partial: [String] = []
        var skipped: [String] = []

        for item in items {
            if isCancelled() { break }

            // 实时复核：此刻是否正在运行（而不是扫描时的快照）
            let inUse = CacheScanner.isCacheInUse(
                url: item.url,
                bundleID: item.bundleID,
                runningBundleIDs: runningNow,
                nameTokens: nameTokens
            )
            if skipRunning && inUse {
                skipped.append(item.url.path)
                continue
            }
            if isWhitelisted(item.url, whitelist: whitelist) {
                skipped.append(item.url.path)
                continue
            }

            let before = CacheScanner.directorySize(at: item.url, isCancelled: isCancelled)
            if isCancelled() { break }

            // 系统缓存强制进废纸篓，作为「删系统缓存」的最后一道保险
            let effectiveTrash = (forceTrashForSystem && item.category == .system) ? true : toTrash
            let outcome = removeContents(of: item.url, toTrash: effectiveTrash, isCancelled: isCancelled)

            switch outcome.kind {
            case .full:
                freed += before
            case .partial:
                // 内容基本已清空，从列表移除；释放大小按删除前的整目录近似（略偏高但可接受）
                freed += before
                partial.append(item.url.path)
            case .none:
                failed.append(item.url.path)
            }
        }

        return CleanResult(
            freedBytes: freed,
            failedPaths: failed,
            partialPaths: partial,
            skippedPaths: skipped
        )
    }

    /// 白名单匹配：目录边界前缀（/Caches/WeChat 只匹配 WeChat 目录本身，不误匹配 WeChatData）
    static func isWhitelisted(_ url: URL, whitelist: Set<String>) -> Bool {
        let path = url.path
        return whitelist.contains { entry in
            path == entry || path.hasPrefix(entry + "/")
        }
    }

    // MARK: - 删除结果

    private struct RemovalOutcome {
        enum Kind { case full, partial, none }
        let kind: Kind
    }

    /// 删除目录内的所有内容（保留目录本身）
    private static func removeContents(of dir: URL, toTrash: Bool, isCancelled: () -> Bool) -> RemovalOutcome {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return RemovalOutcome(kind: .none)
        }

        var removed = 0
        for item in contents {
            if isCancelled() { break }
            do {
                if toTrash {
                    try fm.trashItem(at: item, resultingItemURL: nil)
                } else {
                    try fm.removeItem(at: item)
                }
                removed += 1
            } catch {
                // 单个失败不中断，继续尝试其余条目
            }
        }

        // 目录本身为空：没有可删内容，视为"已清空"而非失败，避免误报进失败列表
        if contents.isEmpty {
            return RemovalOutcome(kind: .full)
        }
        if removed == 0 {
            return RemovalOutcome(kind: .none)
        } else if removed == contents.count {
            return RemovalOutcome(kind: .full)
        } else {
            return RemovalOutcome(kind: .partial)
        }
    }
}