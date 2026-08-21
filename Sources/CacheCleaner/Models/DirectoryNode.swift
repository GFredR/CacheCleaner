import Foundation

/// 目录树节点：文件夹或文件
struct DirectoryNode: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    /// 文件节点对应的分析结果；文件夹节点为 nil
    let file: AnalyzedFile?
    /// 子节点（仅文件夹）；文件节点为 nil 以满足 OutlineGroup 的可选 children 要求
    var children: [DirectoryNode]?
    /// 该节点大小：文件为自身大小，文件夹为子树聚合
    var size: Int64
    /// 子树文件数（仅文件夹有意义）
    var fileCount: Int

    var isFolder: Bool { file == nil }
    var level: ImportanceLevel? { file?.level }

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// 从 AnalyzedFile 平面列表构建目录树
/// 实现：按路径第一段字典分组 + 递归（每层截断路径前缀），整体 O(n·depth)，避免逐文件线性查找。
enum DirectoryTreeBuilder {

    static func build(from files: [AnalyzedFile], rootURL: URL) -> [DirectoryNode] {
        let entries = files.map { file -> ([String], AnalyzedFile) in
            let parts = file.relativePath
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            return (parts, file)
        }
        return buildLevel(entries, rootURL: rootURL)
    }

    /// 构建一层：按「剩余路径第一段」分组（目录 → 递归，文件 → 叶子），再排序
    private static func buildLevel(
        _ entries: [([String], AnalyzedFile)],
        rootURL: URL
    ) -> [DirectoryNode] {
        var folderGroups: [String: [([String], AnalyzedFile)]] = [:]
        var leaves: [([String], AnalyzedFile)] = []

        for entry in entries {
            let parts = entry.0
            if parts.count <= 1 {
                leaves.append(entry)
            } else {
                // 递归时截断第一段（这是防止无限递归的关键）
                folderGroups[parts[0], default: []].append(
                    (Array(parts.dropFirst()), entry.1)
                )
            }
        }

        var nodes: [DirectoryNode] = []

        for (name, subEntries) in folderGroups {
            let folderURL = rootURL.appendingPathComponent(name)
            let children = buildLevel(subEntries, rootURL: folderURL)
            let size = children.reduce(Int64(0)) { $0 + $1.size }
            let count = children.reduce(0) { $0 + $1.fileCount }
            nodes.append(DirectoryNode(
                url: folderURL, name: name, file: nil, children: children,
                size: size, fileCount: count
            ))
        }

        for entry in leaves {
            let file = entry.1
            let url = rootURL.appendingPathComponent(file.url.lastPathComponent)
            nodes.append(DirectoryNode(
                url: url, name: file.url.lastPathComponent, file: file, children: nil,
                size: file.size, fileCount: 1
            ))
        }

        // 排序：文件夹在前按名称，文件按大小降序
        return nodes.sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            if $0.isFolder {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.size > $1.size
        }
    }
}
