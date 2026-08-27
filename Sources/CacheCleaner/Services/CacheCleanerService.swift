import Foundation
import Darwin

/// 单个文件删除失败的原因归类（用于报告里告诉用户该关 App 还是查权限）
struct RemovalFailure: Hashable {
    enum Reason: String {
        case permission = "权限不足"
        case inUse = "文件被占用"
        case other = "其他错误"
    }
    let path: String
    let reason: Reason
}

/// 清理结果报告
struct CleanResult {
    let freedBytes: Int64
    /// 完全没能删（一个条目都没删掉），保留在列表中等待用户回退（用户可重试）
    let failedPaths: [String]
    /// 只删了一部分（其余条目可能被占用/无权限），内容已基本清空，从列表移除
    let partialPaths: [String]
    let skippedPaths: [String]
    /// 文件级失败明细（含原因归类），跨所有目录累计
    let failures: [RemovalFailure]

    var totalFailed: Int { failedPaths.count + partialPaths.count }

    /// 失败原因汇总文案，如「权限不足 2 · 文件被占用 1 · 其他错误 1」
    var failureSummary: String? {
        guard !failures.isEmpty else { return nil }
        var counts: [RemovalFailure.Reason: Int] = [:]
        for f in failures { counts[f.reason, default: 0] += 1 }
        return RemovalFailure.Reason.allCasesWithOrder
            .compactMap { reason in counts[reason].map { "\(reason.rawValue) \($0)" } }
            .joined(separator: " · ")
    }
}

extension RemovalFailure.Reason {
    /// 汇总文案的展示顺序固定，避免字典遍历导致每次报告顺序乱跳
    static var allCasesWithOrder: [RemovalFailure.Reason] { [.permission, .inUse, .other] }
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
    ///   - onProgress: 每开始处理一项时回调（done 为已完成数、total 为总数、currentName 为当前项名称）。
    ///     注意：回调在后台线程执行，UI 更新需自行切回主线程
    static func clean(
        items: [CacheItem],
        toTrash: Bool,
        skipRunning: Bool,
        whitelist: Set<String>,
        forceTrashForSystem: Bool,
        isCancelled: @escaping () -> Bool,
        onProgress: ((_ done: Int, _ total: Int, _ currentName: String) -> Void)? = nil
    ) -> CleanResult {
        // 实时获取当前运行中的 app（避免扫描到清理之间的时间差导致误删正在使用的 App 缓存）
        let runningNow = skipRunning ? CacheScanner.runningBundleIDs() : []
        let nameTokens = skipRunning ? CacheScanner.runningAppNameTokens() : []
        // 白名单预规范化（补 realpath 形态），避免逐条目反复 realpath
        let whitelist = normalizedWhitelist(Array(whitelist))

        var freed: Int64 = 0
        var failed: [String] = []
        var partial: [String] = []
        var skipped: [String] = []
        var failures: [RemovalFailure] = []

        for (index, item) in items.enumerated() {
            if isCancelled() { break }
            onProgress?(index, items.count, item.name)

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
            failures.append(contentsOf: outcome.failures)

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
            skippedPaths: skipped,
            failures: failures
        )
    }

    /// 白名单匹配：目录边界前缀（/Caches/WeChat 只匹配 WeChat 目录本身，不误匹配 WeChatData）
    static func isWhitelisted(_ url: URL, whitelist: Set<String>) -> Bool {
        guard !whitelist.isEmpty else { return false }
        let path = url.path
        if whitelist.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return true
        }
        // 同一路径可能有两种写法（/var ↔ /private/var、用户自建符号链接）。
        // 白名单若由 normalizedWhitelist 预处理过，realpath 形态已在集合里；
        // 这里再把文件侧规范化一次做兜底（每次调用至多 1 次 realpath）。
        guard let realPath = Self.realpathOrNil(path) else { return false }
        return whitelist.contains { realPath == $0 || realPath.hasPrefix($0 + "/") }
    }

    /// 把白名单每条记录补上 realpath 形态。
    /// 调用方在逐文件过滤前调用一次，避免 isWhitelisted 内部对每条记录反复 realpath。
    static func normalizedWhitelist(_ paths: [String]) -> Set<String> {
        guard !paths.isEmpty else { return [] }
        var result = Set(paths)
        for path in paths {
            if let real = Self.realpathOrNil(path), real != path {
                result.insert(real)
            }
        }
        return result
    }

    /// realpath 规范化：返回路径的真实形态；路径不存在时返回 nil
    private static func realpathOrNil(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard path.withCString({ Darwin.realpath($0, &buffer) }) != nil else { return nil }
        return String(cString: buffer)
    }

    // MARK: - 删除结果

    private struct RemovalOutcome {
        enum Kind { case full, partial, none }
        let kind: Kind
        var failures: [RemovalFailure] = []
    }

    /// 删除目录内的所有内容（保留目录本身）。单条失败不中断，失败原因归类进 failures
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
        var failures: [RemovalFailure] = []
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
                if isNoSuchFile(error) {
                    // 枚举之后文件已被别处删除，目标（清掉内容）已达成，按成功计
                    removed += 1
                } else {
                    // 单个失败不中断，继续尝试其余条目
                    failures.append(RemovalFailure(path: item.path, reason: classifyRemovalError(error)))
                }
            }
        }

        // 目录本身为空：没有可删内容，视为"已清空"而非失败，避免误报进失败列表
        if contents.isEmpty {
            return RemovalOutcome(kind: .full, failures: failures)
        }
        if removed == 0 {
            return RemovalOutcome(kind: .none, failures: failures)
        } else if removed == contents.count {
            return RemovalOutcome(kind: .full, failures: failures)
        } else {
            return RemovalOutcome(kind: .partial, failures: failures)
        }
    }

    // MARK: - 错误归类

    /// 删除错误 → 用户可理解的原因（权限不足 / 被占用 / 其他）
    private static func classifyRemovalError(_ error: Error) -> RemovalFailure.Reason {
        let ns = error as NSError
        // Cocoa 层直接暴露的权限错误
        if ns.code == NSFileWriteNoPermissionError || ns.code == NSFileReadNoPermissionError {
            return .permission
        }
        // 底层 POSIX errno（removeItem/trashItem 的拒绝原因大多在这层）
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain {
            switch underlying.code {
            case Int(EPERM), Int(EACCES): return .permission
            case Int(EBUSY), Int(EAGAIN): return .inUse
            default: break
            }
        }
        return .other
    }

    private static func isNoSuchFile(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.code == NSFileNoSuchFileError { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(ENOENT) {
            return true
        }
        return false
    }

    // MARK: - 废纸篓

    /// 废纸篓当前占用大小（后台线程调用）
    static func trashSize() -> Int64 {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        return CacheScanner.directorySize(at: trash, isCancelled: { false })
    }

    /// 清空废纸篓（删除 ~/.Trash 的内容，目录本身保留）。
    /// 加锁文件（uchg）或权限问题会失败并计数，不中断其余条目
    static func emptyTrash(isCancelled: () -> Bool) -> (freed: Int64, failedCount: Int) {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let before = CacheScanner.directorySize(at: trash, isCancelled: isCancelled)
        let outcome = removeContents(of: trash, toTrash: false, isCancelled: isCancelled)
        // 一条都没删掉时不计入释放量
        let freed = outcome.kind == .none ? 0 : before
        return (freed, outcome.failures.count)
    }
}