import Foundation

/// 线程安全的取消标志：因为后台统计/删除跑在 `Task.detached` 里，
/// `Task.isCancelled` 只反映当前 task 自身、不会被父级取消传播，
/// 因此用显式标志让用户点「取消」能真正中断后台工作。
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        _cancelled = false
        lock.unlock()
    }
}

/// 白名单持久化：缓存清理页与目录分析页共用同一份（UserDefaults）。
/// 保证「用户设置的白名单」在两条删除路径下都是全局保护。
enum WhitelistStore {
    static let key = "whitelist"

    static func paths() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// 命中白名单（目录边界前缀匹配）
    static func isWhitelisted(_ url: URL) -> Bool {
        CacheCleanerService.isWhitelisted(url, whitelist: Set(paths()))
    }

    static func add(_ path: String) {
        var list = paths()
        guard !list.contains(path) else { return }
        list.append(path)
        UserDefaults.standard.set(list, forKey: key)
    }

    static func remove(_ path: String) {
        var list = paths()
        list.removeAll { $0 == path }
        UserDefaults.standard.set(list, forKey: key)
    }
}