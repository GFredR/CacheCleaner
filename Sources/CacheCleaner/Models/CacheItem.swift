import Foundation

/// 缓存分类
enum CacheCategory: String, CaseIterable, Identifiable {
    case system = "系统"
    case application = "应用"
    case sandbox = "沙盒"
    case developer = "开发"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .system: return "gearshape.2"
        case .application: return "app"
        case .sandbox: return "shippingbox"
        case .developer: return "hammer"
        }
    }
}

/// 一条可清理的缓存项
struct CacheItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var name: String
    var category: CacheCategory
    /// bundle id / 容器 id（用于清理时实时判断运行状态；nil 时退化为用目录名判断）
    var bundleID: String?
    var size: Int64
    var isRunning: Bool
    var isWhitelisted: Bool

    init(
        url: URL,
        name: String,
        category: CacheCategory,
        bundleID: String? = nil,
        size: Int64 = 0,
        isRunning: Bool = false,
        isWhitelisted: Bool = false
    ) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.category = category
        self.bundleID = bundleID
        self.size = size
        self.isRunning = isRunning
        self.isWhitelisted = isWhitelisted
    }

    var sizeString: String {
        SizeFormatter.string(from: size)
    }
}
