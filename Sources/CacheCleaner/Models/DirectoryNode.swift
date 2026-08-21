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
enum DirectoryTreeBuilder {

    /// 构建目录树
    /// - Parameter rootURL: 扫描根目录（用于拼接每个文件夹节点的 URL）
    static func build(from files: [AnalyzedFile], rootURL: URL) -> [DirectoryNode] {
        var root: [DirectoryNode] = []

        for file in files {
            let parts = file.relativePath.split(separator: "/").map(String.init)
            insert(file: file, parts: parts, currentURL: rootURL, into: &root)
        }

        return sortedAndAggregated(root)
    }

    /// 按路径分段逐层插入
    private static func insert(
        file: AnalyzedFile,
        parts: [String],
        currentURL: URL,
        into nodes: inout [DirectoryNode]
    ) {
        guard let first = parts.first else { return }
        let folderURL = currentURL.appendingPathComponent(first)

        if parts.count == 1 {
            // 叶子：文件节点
            nodes.append(DirectoryNode(
                url: folderURL,
                name: first,
                file: file,
                children: nil,
                size: file.size,
                fileCount: 1
            ))
        } else {
            // 文件夹：找到则深入，否则新建
            if let idx = nodes.firstIndex(where: { $0.name == first && $0.isFolder }) {
                insert(
                    file: file,
                    parts: Array(parts.dropFirst()),
                    currentURL: folderURL,
                    into: &nodes[idx].children!
                )
            } else {
                var folder = DirectoryNode(
                    url: folderURL, name: first, file: nil, children: [],
                    size: 0, fileCount: 0
                )
                insert(
                    file: file,
                    parts: Array(parts.dropFirst()),
                    currentURL: folderURL,
                    into: &folder.children!
                )
                nodes.append(folder)
            }
        }
    }

    /// 递归聚合大小、统计文件数，并排序（文件夹在前按名称，文件按大小降序）
    private static func sortedAndAggregated(_ nodes: [DirectoryNode]) -> [DirectoryNode] {
        nodes.map { node in
            guard node.isFolder, var children = node.children else {
                return DirectoryNode(
                    url: node.url, name: node.name, file: node.file, children: nil,
                    size: node.size, fileCount: node.fileCount
                )
            }

            children = sortedAndAggregated(children)
            let size = children.reduce(Int64(0)) { $0 + $1.size }
            let count = children.reduce(0) { $0 + $1.fileCount }

            children.sort {
                if $0.isFolder != $1.isFolder { return $0.isFolder }
                if $0.isFolder {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.size > $1.size
            }

            return DirectoryNode(
                url: node.url, name: node.name, file: nil, children: children,
                size: size, fileCount: count
            )
        }
    }
}