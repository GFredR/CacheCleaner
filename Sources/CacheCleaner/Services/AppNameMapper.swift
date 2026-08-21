import Foundation

/// 根据 bundle id 反查 App 显示名（如 com.tencent.xinWeChat → 微信）
enum AppNameMapper {

    private static var nameCache: [String: String] = [:]
    /// 缓存可能被后台扫描线程写入，加锁防数据竞争
    private static let cacheLock = NSLock()

    static func displayName(forBundleID bundleID: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = nameCache[bundleID] { return cached }
        guard let name = lookup(bundleID) else { return nil }
        nameCache[bundleID] = name
        return name
    }

    /// 枚举常见 App 目录，读 Info.plist 建立 bundle id → 显示名 映射
    private static func lookup(_ bundleID: String) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            home.appendingPathComponent("Applications")
        ]

        for dir in searchDirs {
            guard let apps = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for app in apps where app.pathExtension == "app" {
                let plistURL = app.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plistURL),
                      let plist = try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil
                      ) as? [String: Any],
                      let bid = plist["CFBundleIdentifier"] as? String,
                      bid == bundleID
                else { continue }

                let name = (plist["CFBundleDisplayName"] as? String)
                    ?? (plist["CFBundleName"] as? String)
                    ?? app.deletingPathExtension().lastPathComponent
                return name
            }
        }
        return nil
    }
}
