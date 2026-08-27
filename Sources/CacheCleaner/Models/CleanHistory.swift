import Foundation

/// 清理来源
enum CleanHistorySource: String, Codable {
    case cacheCleaner
    case directoryAnalysis
    case trash

    var displayName: String {
        switch self {
        case .cacheCleaner: return "缓存清理"
        case .directoryAnalysis: return "目录分析"
        case .trash: return "废纸篓"
        }
    }
}

/// 一条清理历史记录，用于「清理历史」页展示本次清理效果
struct CleanHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let source: CleanHistorySource
    let useTrash: Bool
    let freedBytes: Int64
    let deletedCount: Int
    let failedCount: Int
    let skippedCount: Int

    init(
        source: CleanHistorySource,
        useTrash: Bool,
        freedBytes: Int64,
        deletedCount: Int,
        failedCount: Int,
        skippedCount: Int
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.useTrash = useTrash
        self.freedBytes = freedBytes
        self.deletedCount = deletedCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
    }

    var freedString: String {
        SizeFormatter.string(from: freedBytes)
    }
}

/// 清理历史持久化（UserDefaults，JSON 数组）。
/// 两个清理入口（缓存清理 / 目录分析）共用同一份，便于用户回看整体效果。
enum CleanHistoryStore {
    static let key = "cleanHistory"
    /// 最多保留最近 N 条，避免无限累积
    static let maxEntries = 50

    static func entries() -> [CleanHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CleanHistoryEntry].self, from: data)) ?? []
    }

    static func add(_ entry: CleanHistoryEntry) {
        var list = entries()
        list.insert(entry, at: 0)
        if list.count > maxEntries {
            list = Array(list.prefix(maxEntries))
        }
        save(list)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func save(_ list: [CleanHistoryEntry]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}