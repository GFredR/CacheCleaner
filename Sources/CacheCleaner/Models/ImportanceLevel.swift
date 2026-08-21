import Foundation
import SwiftUI

/// 文件重要性等级（与可清理性挂钩）
enum ImportanceLevel: Int, CaseIterable, Identifiable {
    case safeToClean = 0   // 绿：可安全清理
    case cautious = 1      // 黄：谨慎（可能有用）
    case important = 2     // 红：重要，勿删

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .safeToClean: return "可清理"
        case .cautious: return "谨慎"
        case .important: return "重要"
        }
    }

    var color: Color {
        switch self {
        case .safeToClean: return .green
        case .cautious: return .orange
        case .important: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .safeToClean: return "checkmark.circle.fill"
        case .cautious: return "exclamationmark.triangle.fill"
        case .important: return "lock.fill"
        }
    }

    var order: Int { rawValue }
}

/// 文件重要性分类器：集中管理所有规则，便于调整
enum ImportanceClassifier {

    // MARK: - 可安全清理（绿）：明确是缓存 / 临时 / 日志 / 编译产物

    private static let safeExtensions: Set<String> = [
        "tmp", "temp", "cache", "cachedata", "log", "pyc", "pyo",
        "o", "obj", "class", "dsym", "xcuserstate", "swp", "swo",
        "thumbs.db", "part", "crdownload", "coredump",
        "crash", "session", "lock", "pid", "etl", "etltmp",
        "gch", "dia", "llvm", "bc", "tbd"
    ]

    /// 精确文件名（如 .DS_Store 的 pathExtension 提取不到期望值，用全名匹配）
    private static let safeFileNames: Set<String> = [
        "ds_store", "thumbs.db", "desktop.ini", ".ds_store"
    ]

    private static let safeDirNames: Set<String> = [
        "Caches", "Cache", "caches", "cache", "tmp", "temp", "Temp",
        "Logs", "logs", "DerivedData", "xcuserdata", "build", "Build",
        "node_modules", "Pods", ".gradle", ".build", "__MACOSX",
        ".cache", ".npm", ".yarn", "target", "dist", ".next", ".nuxt"
    ]

    // MARK: - 重要（红）：文档 / 代码 / 数据库 / 媒体 / 密钥 / 配置

    private static let importantExtensions: Set<String> = [
        // 文档
        "doc", "docx", "pdf", "txt", "md", "rtf", "pages", "numbers",
        "keynote", "xls", "xlsx", "csv", "ppt", "pptx", "odt", "ods",
        "odp", "epub", "mobi",
        // 图片 / 设计
        "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "bmp",
        "tiff", "raw", "psd", "ai", "sketch", "fig",
        // 视频 / 音频
        "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v",
        "mp3", "wav", "flac", "aac", "m4a", "ogg", "wma",
        // 源代码
        "swift", "m", "mm", "h", "c", "cpp", "hpp", "cc", "java",
        "kt", "py", "js", "ts", "jsx", "tsx", "vue", "go", "rs",
        "rb", "php", "sh", "bat", "sql", "cs", "dart", "scala", "lua",
        // 数据库
        "db", "sqlite", "sqlite3", "sqlitedb", "crdb",
        // 密钥 / 证书
        "pem", "key", "crt", "cer", "p12", "pfx", "asc", "gpg",
        // 配置 / 项目文件
        "plist", "json", "yaml", "yml", "toml", "conf", "cfg", "ini",
        "env", "xml", "pbxproj", "entitlements", "xcworkspacedata",
        "gitignore", "gitmodules"
    ]

    private static let importantFileNames: Set<String> = [
        "README", "README.md", "LICENSE", "LICENSE.txt", "Makefile",
        "Dockerfile", "Podfile", "Package.swift", ".gitignore",
        ".gitmodules", ".env", ".env.example", "Cargo.toml", "go.mod",
        "pom.xml", "build.gradle", "settings.gradle", "Info.plist"
    ]

    // MARK: - 谨慎（黄）：压缩包 / 可执行 / 归档 / 备份 / 未知

    private static let cautiousExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso",
        "img", "app", "exe", "msi", "ipa", "apk", "deb", "rpm",
        "dll", "dylib", "framework", "a", "so", "jar", "war",
        "bak", "old", "backup", "orig", "rej", "swf", "fla", "xcf",
        "pch", "numbers-tef", "pages-tef", "key-tef"
    ]

    // MARK: - 路径规则：命中这些目录段的文件整体视为可清理

    private static let safePathSegments: [String] = [
        "/Caches/", "/caches/", "/Cache/", "/cache/",
        "/tmp/", "/Temp/", "/temp/",
        "/Logs/", "/logs/",
        "/DerivedData/", "/xcuserdata/",
        "/node_modules/", "/Pods/", "/.gradle/", "/.build/",
        "/__MACOSX/", "/.cache/", "/target/", "/dist/", "/.next/"
    ]

    // MARK: - 判定入口

    static func classify(url: URL) -> ImportanceLevel {
        let path = url.path
        let name = url.lastPathComponent
        let nameLower = name.lowercased()
        let ext = url.pathExtension.lowercased()

        // 规则 0a：可清理目录段命中（缓存/构建产物目录下的内容，即使扩展名是重要类型也算缓存）
        for segment in safePathSegments where path.contains(segment) {
            return .safeToClean
        }

        // 规则 0b：.git 目录及其内容都重要
        if path.contains("/.git/") || name == ".git" { return .important }

        // 规则 1：重要文件名（README / LICENSE / 构建脚本等）
        if importantFileNames.contains(name) { return .important }

        // 规则 2：可安全清理的精确文件名（.DS_Store 等）
        if safeFileNames.contains(nameLower) { return .safeToClean }

        // 规则 3：重要扩展名
        if importantExtensions.contains(ext) { return .important }

        // 规则 4：可安全清理扩展名
        if safeExtensions.contains(ext) { return .safeToClean }

        // 规则 5：可安全清理目录名（目录本身）
        if safeDirNames.contains(name) { return .safeToClean }

        // 规则 6：谨慎扩展名（压缩包 / 可执行 / 备份）
        if cautiousExtensions.contains(ext) { return .cautious }

        // 规则 7：兜底——无扩展名的可执行文件 / 未知类型，谨慎处理
        return .cautious
    }
}
