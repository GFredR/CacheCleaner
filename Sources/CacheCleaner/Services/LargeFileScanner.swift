import Foundation
import CryptoKit

/// 「空间洞察」里展示的大文件项
struct LargeFileItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let size: Int64

    init(url: URL, size: Int64) {
        self.id = UUID()
        self.url = url
        self.size = size
    }

    var sizeString: String { SizeFormatter.string(from: size) }
}

/// 一组重复文件（size 相同 + 内容哈希相同）
struct DuplicateGroup: Identifiable {
    let id = UUID()
    /// 组内每个文件的单文件大小
    let size: Int64
    var files: [LargeFileItem]

    var sizeString: String { SizeFormatter.string(from: size) }

    /// 可释放的冗余大小 = size ×（保留 1 份外的数量）
    var wastedBytes: Int64 {
        size * Int64(max(0, files.count - 1))
    }
    var wastedString: String { SizeFormatter.string(from: wastedBytes) }
}

/// 只读空间扫描器：最大文件 + 重复文件检测。
/// 全程只读（不标记删除、不写磁盘状态），可增量汇报进度、可取消。
final class LargeFileScanner {

    /// 扫描目录内最大的 N 个大文件
    func scanLargeFiles(
        at url: URL,
        limit: Int,
        isCancelled: @escaping () -> Bool = { false },
        onProgress: @escaping (Int) -> Void = { _ in }
    ) async -> [LargeFileItem] {
        await Task.detached(priority: .userInitiated) {
            Self.scanLargeFilesSync(at: url, limit: limit, onProgress: onProgress, isCancelled: isCancelled)
        }.value
    }

    /// 扫描重复文件：按 (size) 粗分组，组内 >=2 个再哈希精确判重
    func scanDuplicates(
        at url: URL,
        isCancelled: @escaping () -> Bool = { false },
        onProgress: @escaping (Int) -> Void = { _ in }
    ) async -> [DuplicateGroup] {
        await Task.detached(priority: .userInitiated) {
            Self.scanDuplicatesSync(at: url, onProgress: onProgress, isCancelled: isCancelled)
        }.value
    }

    // MARK: - 同步核心

    private static func scanLargeFilesSync(
        at url: URL,
        limit: Int,
        onProgress: (Int) -> Void,
        isCancelled: () -> Bool
    ) -> [LargeFileItem] {
        var heap: [LargeFileItem] = []
        var processed = 0
        forEachRegularFile(at: url, isCancelled: isCancelled) { fileURL, size in
            processed += 1
            if processed % 200 == 0 { onProgress(processed) }
            if size <= 0 { return }
            let item = LargeFileItem(url: fileURL, size: size)
            if heap.count < limit {
                heap.append(item)
                heap.sort { $0.size > $1.size }
            } else if size > heap.last?.size ?? 0 {
                heap[heap.count - 1] = item
                heap.sort { $0.size > $1.size }
            }
        }
        return heap
    }

    private static func scanDuplicatesSync(
        at url: URL,
        onProgress: (Int) -> Void,
        isCancelled: () -> Bool
    ) -> [DuplicateGroup] {
        // 第一遍：按 size 收集（内存里只留 path + size，符合只读扫描）
        var bySize: [Int64: [URL]] = [:]
        var processed = 0
        forEachRegularFile(at: url, isCancelled: isCancelled) { fileURL, size in
            processed += 1
            if processed % 200 == 0 { onProgress(processed) }
            if size <= 0 { return }
            bySize[size, default: []].append(fileURL)
        }
        if isCancelled() { return [] }

        // 第二遍：仅对 size 相同且 >=2 的组算哈希精确判重（减少 IO 热点）
        var groups: [DuplicateGroup] = []
        var hashed = 0
        let totalToHash = bySize.values.reduce(0) { $0 + ($1.count >= 2 ? $1.count : 0) }
        for (size, urls) in bySize where urls.count >= 2 {
            if isCancelled() { break }
            var byHash: [String: [LargeFileItem]] = [:]
            for fileURL in urls {
                if isCancelled() { break }
                if let digest = sha256Digest(of: fileURL) {
                    byHash[digest, default: []].append(LargeFileItem(url: fileURL, size: size))
                }
                hashed += 1
                if hashed % 20 == 0, totalToHash > 0 {
                    onProgress(hashed)
                }
            }
            for items in byHash.values where items.count >= 2 {
                groups.append(DuplicateGroup(size: size, files: items))
            }
        }
        // 按可释放量降序
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    // MARK: - 枚举与哈希

    /// 递归枚举常规文件并回调其大小；返回前已按符号链接跳过
    private static func forEachRegularFile(
        at url: URL,
        isCancelled: () -> Bool,
        _ body: (URL, Int64) -> Void
    ) {
        let fm = FileManager.default
        let rootURL = url.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return }
        while let fileURL = enumerator.nextObject() as? URL {
            if isCancelled() { return }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile != true { continue }
            body(fileURL, Int64(values.fileSize ?? 0))
        }
    }

    private static func sha256Digest(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        // 分块读，避免大文件一次读入内存
        var keepGoing = true
        while keepGoing {
            let chunk: Data
            do { chunk = try handle.read(upToCount: 1 << 20) ?? Data() }
            catch { return nil }
            if chunk.isEmpty { keepGoing = false }
            else { hasher.update(data: chunk) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}