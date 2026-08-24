import SwiftUI
import AppKit

/// 目录分析：拖入任意目录，按重要性分级展示文件（红=重要 / 黄=谨慎 / 绿=可清理）
struct DirectoryAnalysisView: View {
    @StateObject private var model = DirectoryAnalysisModel()
    @AppStorage("useTrash") private var useTrash = false
    @AppStorage("fontSize") private var fontSize: Double = 13
    @State private var isTargeted = false
    @State private var showCleanConfirm = false
    @State private var showProtectedConfirm = false
    @State private var showSettings = false
    /// 懒加载展开：只渲染已展开路径下的可见行；未展开的文件夹不实例化其子树
    @State private var expandedFolderIDs: Set<UUID> = []
    /// 每个已展开文件夹实际展示到第几个子节点（分批加载，避免一次插入几万行卡顿）
    @State private var revealedChildByFolder: [UUID: Int] = [:]
    /// 可见行缓存：仅当 tree/展开/分批次变化时重建；勾选只改 selectedIDs，不重建
    @State private var visibleRows: [DirectoryRowItem] = []
    /// 结构版本号：每次重建 visibleRows 时 +1，供 NSTableView 判定是否需要 reload
    @State private var tableRevision = 0

    /// 每次「加载更多」追加的行数。单批必须小：一次性插入过多行是展开卡顿的主因。
    private let revealBatch = 400

    private func rebuildVisibleRows() {
        visibleRows = buildVisibleRows()
        tableRevision += 1
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.rootURL == nil && !model.isScanning {
                dropZone
            } else {
                header
                Divider()
                listArea
                Divider()
                footer
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .alert("清理失败", isPresented: errorPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("确认清理", isPresented: $showCleanConfirm) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                model.cleanSelected(useTrash: useTrash)
            }
        } message: {
            Text(cleanConfirmText)
                .font(.system(size: 12))
        }
        .alert("⚠️ 确认删除重要/谨慎文件", isPresented: $showProtectedConfirm) {
            Button("取消", role: .cancel) {}
            Button("我确认，仍要删除", role: .destructive) {
                model.cleanSelected(useTrash: useTrash)
            }
        } message: {
            Text(protectedConfirmText)
                .font(.system(size: 12))
        }
        .alert("清理完成", isPresented: reportPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.cleanReport ?? "")
        }
        .sheet(isPresented: $showSettings) {
            SettingsContainer()
        }
        .onAppear {
            rebuildVisibleRows()
        }
        .onChange(of: model.rootURL) { _ in
            expandedFolderIDs = []
            revealedChildByFolder = [:]
            visibleRows = []
            tableRevision += 1
        }
        .onChange(of: model.tree) { _ in
            rebuildVisibleRows()
        }
        .onChange(of: expandedFolderIDs) { _ in
            rebuildVisibleRows()
        }
        .onChange(of: revealedChildByFolder) { _ in
            rebuildVisibleRows()
        }
    }

    // MARK: - 拖拽处理

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data, let path = String(data: data, encoding: .utf8) {
                url = URL(fileURLWithPath: path)
            } else if let u = item as? URL {
                url = u
            }
            guard let url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                return
            }
            DispatchQueue.main.async {
                model.analyze(url)
            }
        }
    }

    // MARK: - 拖拽区（无结果时）

    private var dropZone: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: isTargeted ? "folder.badge.plus" : "arrow.down.doc")
                .font(.system(size: 52))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text(isTargeted ? "松开以分析此目录" : "拖入一个目录进行分析")
                .font(.title3.weight(.semibold))
            Text("App 会扫描其中的所有文件，按重要性标记颜色：\n🟢 可清理（缓存/临时/日志） · 🟡 谨慎（压缩包/未知） · 🔴 重要勿删（文档/代码/数据库）")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("或点击选择目录…") { openPanel() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .padding(10)
        }
        .padding(14)
    }

    // MARK: - 头部（统计卡）

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.rootName)
                        .font(.system(size: fontSize + 5, weight: .bold))
                        .lineLimit(1)
                    if let root = model.rootURL {
                        Text(root.path)
                            .font(.system(size: fontSize - 1))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Button {
                    model.cancelScan()
                    model.rootURL = nil
                    model.files = []
                    model.tree = []
                } label: {
                    Label("更换目录", systemImage: "folder")
                        .font(.system(size: fontSize))
                }
                .disabled(model.isCleaning)
                .help("重新选择要分析的目录")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: fontSize + 2))
                }
                .help("设置（字体大小、白名单等）")
                .buttonStyle(.borderless)
                .accessibilityLabel("设置")
                .accessibilityHint("打开字体大小、白名单、主题等设置")
            }

            HStack(spacing: 8) {
                statCard(level: .important)
                statCard(level: .cautious)
                statCard(level: .safeToClean)
                Spacer()
            }
        }
        .padding(12)
    }

    private func statCard(level: ImportanceLevel) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(level.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(level.label)")
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.secondary)
                Text("\(model.count(of: level)) 个 · \(byteString(model.size(of: level)))")
                    .font(.system(size: fontSize, weight: .medium))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(level.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 列表区域（树形）

    @ViewBuilder
    private var listArea: some View {
        if model.isScanning {
            scanningView
        } else if model.tree.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("该目录下没有文件")
                    .font(.headline)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if visibleRows.isEmpty {
            // 结构生成中（tree 已就绪但首帧尚未 buildVisibleRows）
            VStack(spacing: 8) {
                Spacer()
                ProgressView()
                Text("正在生成目录…")
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            DirectoryTable(
                model: model,
                rows: visibleRows,
                revision: tableRevision,
                fontSize: fontSize,
                isFolderExpanded: { id in expandedFolderIDs.contains(id) },
                onToggleExpand: { node in toggleExpand(node) },
                onLoadMore: { info in loadMore(info) }
            )
        }
    }

    /// 构造可见行集合的具体实现
    private func buildVisibleRows() -> [DirectoryRowItem] {
        var items: [DirectoryRowItem] = []
        func collect(_ nodes: [DirectoryNode], depth: Int) {
            for n in nodes {
                items.append(DirectoryRowItem(node: n, depth: depth))
                if n.isFolder, expandedFolderIDs.contains(n.id) {
                    let children = n.children ?? []
                    let revealed = effectiveRevealed(n.id)
                    for c in children.prefix(revealed) {
                        collect([c], depth: depth + 1)
                    }
                    let remaining = children.count - revealed
                    if remaining > 0 {
                        items.append(DirectoryRowItem.more(folderID: n.id, depth: depth + 1, remaining: remaining))
                    }
                }
            }
        }
        collect(model.tree, depth: 0)
        return items
    }

    /// 某个展开文件夹当前应展示的子节点数（未点过「加载更多」→ 首次只展示一批）
    private func effectiveRevealed(_ folderID: UUID) -> Int {
        revealedChildByFolder[folderID] ?? revealBatch
    }

    /// 展开/折叠某个文件夹
    private func toggleExpand(_ node: DirectoryNode) {
        guard node.isFolder else { return }
        if expandedFolderIDs.contains(node.id) {
            expandedFolderIDs.remove(node.id)
            revealedChildByFolder[node.id] = nil
        } else {
            expandedFolderIDs.insert(node.id)
            revealedChildByFolder[node.id] = nil
        }
    }

    /// 「加载更多」：给该文件夹再追加一批子节点（不加动画，避免批量插入行抖动）
    private func loadMore(_ more: DirectoryLoadMoreInfo) {
        revealedChildByFolder[more.folderID, default: revealBatch] += revealBatch
    }

    /// 扫描中视图：进度条 + 百分比 + 已处理数/总数 + 当前路径 + 取消按钮
    private var scanningView: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text(scanTitleText)
                .font(.system(size: fontSize + 1, weight: .medium))

            // 进度条：总量已知时显示确定进度，否则退化为 indeterminate
            if model.totalFiles > 0 {
                ProgressView(value: Double(model.processedCount),
                             total: Double(max(model.totalFiles, 1))) {
                    EmptyView()
                } currentValueLabel: {
                    Text(scanPercentText)
                        .font(.system(size: fontSize - 1).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 420)
            } else {
                // 预扫描阶段：显示进度条 + 百分比
                ProgressView(value: model.countProgress) {
                    EmptyView()
                } currentValueLabel: {
                    Text(countPercentText)
                        .font(.system(size: fontSize - 1).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 420)
            }

            // 已处理数 / 当前路径
            Text(scanProgressDetailText)
                .font(.system(size: fontSize - 1).monospacedDigit())
                .foregroundStyle(.secondary)

            Text(model.currentPath)
                .font(.system(size: fontSize - 2))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 460)

            Button("取消") { model.cancelScan() }
                .font(.system(size: fontSize))
                .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// 扫描阶段标题
    private var scanTitleText: String {
        model.scanPhase == .preparing ? "准备中…" : "正在扫描…"
    }

    /// 已处理 / 总数
    private var scanProgressDetailText: String {
        guard model.totalFiles > 0 else { return "正在计算文件总数…" }
        return "已处理 \(model.processedCount) / \(model.totalFiles) 个文件"
    }

    /// 预扫描阶段百分比
    private var countPercentText: String {
        String(format: "%.0f%%", model.countProgress * 100)
    }

    /// 百分比
    private var scanPercentText: String {
        guard model.totalFiles > 0 else { return "" }
        let pct = Int(Double(model.processedCount) / Double(model.totalFiles) * 100)
        return "\(pct)%"
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(model.selectedCount) 个文件 · 可释放 \(model.selectedSizeString)")
                    .font(.system(size: fontSize))
                    .monospacedDigit()
                if model.hasProtectedSelected {
                    Label("包含 \(model.selectedProtectedFiles.count) 个重要/谨慎文件，删除需二次确认",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.orange)
                }
            }
            if useTrash {
                Label("将移入废纸篓", systemImage: "trash")
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("全选可清理项") {
                model.selectAllCleanable()
            }
            .font(.system(size: fontSize - 1))
            .disabled(model.count(of: .safeToClean) == 0 || model.isCleaning)

            Button(role: .destructive) {
                requestClean()
            } label: {
                Label(cleanButtonTitle, systemImage: "trash")
                    .font(.system(size: fontSize))
                    .frame(minWidth: 104)
            }
            .disabled(model.selectedCount == 0 || model.isCleaning || model.isScanning)
        }
        .padding(12)
    }

    /// 清理按钮文案：选中受保护文件时显式提醒
    private var cleanButtonTitle: String {
        model.hasProtectedSelected
            ? "清理选中项（含重要）"
            : "清理可清理项"
    }

    /// 清理入口：若选中了受保护(红/黄)文件则走强确认，否则按原逻辑
    private func requestClean() {
        if model.hasProtectedSelected {
            showProtectedConfirm = true
        } else if useTrash {
            model.cleanSelected(useTrash: true)
        } else {
            showCleanConfirm = true
        }
    }

    /// 清理确认文本：列出即将删除的具体可清理文件，避免用户基于不全信息删除
    private var cleanConfirmText: String {
        let count = model.selectedCount
        var msg = "将删除 \(count) 个可清理文件，预计释放 \(model.selectedSizeString)。\n（重要/谨慎文件选中时需另外强确认，此弹窗不涉及）"
        let items = model.files.filter {
            model.selectedIDs.contains($0.id) && $0.level == .safeToClean
        }
        guard !items.isEmpty else { return msg }
        msg += "\n\n即将删除："
        let shown = items.prefix(15)
        for item in shown {
            msg += "\n  · \(item.relativePath)"
        }
        if items.count > 15 {
            msg += "\n  · …等共 \(items.count) 项"
        }
        return msg
    }

    /// 受保护(重要/谨慎)文件删除前的强硬确认：默认不含红/黄，除非用户主动勾选并二次确认
    private var protectedConfirmText: String {
        let list = model.selectedProtectedFiles
        var msg = "你选中了 \(list.count) 个重要（红色）或谨慎（黄色）文件，这类文件通常不建议删除，可能会造成不可恢复的损失。\n"
        msg += "仍要删除共 \(model.selectedCount) 个文件，预计释放 \(model.selectedSizeString) 吗？\n\n受保护文件将一并删除："
        let shown = list.prefix(15)
        for item in shown {
            msg += "\n  · [\(item.level.label)] \(item.relativePath)"
        }
        if list.count > 15 {
            msg += "\n  · …等共 \(list.count) 个受保护文件"
        }
        return msg
    }

    // MARK: - 辅助

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "分析"
        panel.message = "选择要分析的目录"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                model.analyze(url)
            }
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        SizeFormatter.string(from: bytes)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var reportPresented: Binding<Bool> {
        Binding(
            get: { model.cleanReport != nil },
            set: { if !$0 { model.cleanReport = nil } }
        )
    }
}

// MARK: - 树节点行

/// 「加载更多」信息：某文件夹剩余未展示的子文件数
struct DirectoryLoadMoreInfo {
    let folderID: UUID
    let depth: Int
    let remaining: Int
}

/// 懒加载可见行的扁平项：正常节点 或 批量加载哨兵行
struct DirectoryRowItem: Identifiable {
    let node: DirectoryNode?
    let depth: Int
    let more: DirectoryLoadMoreInfo?
    var id: String {
        if let more { return "more-\(more.folderID)" }
        return node!.id.uuidString
    }

    init(node: DirectoryNode?, depth: Int, more: DirectoryLoadMoreInfo? = nil) {
        self.node = node
        self.depth = depth
        self.more = more
    }

    static func more(folderID: UUID, depth: Int, remaining: Int) -> DirectoryRowItem {
        DirectoryRowItem(node: nil, depth: depth,
                         more: DirectoryLoadMoreInfo(folderID: folderID, depth: depth, remaining: remaining))
    }
}

/// 目录树的一行：文件夹可展开/折叠，文件行展示重要性颜色与勾选
struct DirectoryNodeRow: View {
    @EnvironmentObject var model: DirectoryAnalysisModel
    @AppStorage("fontSize") private var fontSize: Double = 13
    let node: DirectoryNode
    /// 缩进层级（0=顶层）
    let depth: Int
    /// 文件夹是否处于展开态（驱动折叠箭头方向）
    var isExpanded: Bool = false
    /// 点击折叠箭头时的回调（由外层维护展开集合）
    var onToggleExpand: () -> Void = {}

    /// 每级缩进宽度（px）
    private let indentStep: CGFloat = 16

    var body: some View {
        Group {
            if node.isFolder {
                folderRow
            } else if let file = node.file {
                fileRow(file)
            }
        }
        .padding(.leading, CGFloat(depth) * indentStep)
        .contextMenu {
            contextMenuItems
        }
    }

    /// 右键菜单：文件额外有「打开」，文件夹/文件都有「在访达中查看」「复制路径」
    @ViewBuilder
    private var contextMenuItems: some View {
        if !node.isFolder, let file = node.file {
            Button("打开") {
                NSWorkspace.shared.open(file.url)
            }
            Divider()
        }
        Button("在访达中查看") {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
        Button("复制路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }
    }

    private var folderRow: some View {
        let state = model.selectionState(of: node)
        let sel = model.selectedFiles(in: node)
        let total = model.totalFiles(in: node)
        return HStack(spacing: 8) {
            // 折叠箭头：仅文件夹有，未展开子树不会实例化 → 展开/折叠快
            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: fontSize - 2, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 16, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "折叠此文件夹" : "展开此文件夹")

            Button {
                model.toggleFolder(node)
            } label: {
                Image(systemName: folderCheckboxSymbol(state))
                    .font(.system(size: fontSize + 1))
                    .foregroundStyle(state == .none ? Color.secondary : Color.accentColor)
                    .frame(width: 20, height: 18, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(total == 0)
            .help("勾选/取消此文件夹内全部 \(total) 个文件")

            Image(systemName: "folder.fill")
                .font(.system(size: fontSize + 2))
                .foregroundStyle(sel > 0 ? Color.accentColor : Color.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.system(size: fontSize, weight: .medium))
                        .lineLimit(1)
                    if sel > 0 {
                        Text("已选 \(sel)")
                            .font(.system(size: fontSize - 3, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                Text(folderSubtitleText)
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(sel > 0 ? Color.accentColor : Color.secondary)
            }
            Spacer()
            Text(node.sizeString)
                .font(.system(size: fontSize).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 84, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    /// 文件夹三态复选框图标
    private func folderCheckboxSymbol(_ state: DirectorySelectionState) -> String {
        switch state {
        case .all: return "checkmark.square.fill"
        case .partial: return "minus.square.fill"
        case .none: return "square"
        }
    }

    /// 文件夹副标题：显示文件数与已选状态（折叠时也能看出勾了什么）
    private var folderSubtitleText: String {
        let sel = model.selectedFiles(in: node)
        let total = model.totalFiles(in: node)
        return sel > 0
            ? "共 \(total) 个文件 · 已选 \(sel)"
            : "共 \(total) 个文件"
    }

    private func fileRow(_ file: AnalyzedFile) -> some View {
        HStack(spacing: 10) {
            // 占位折叠箭头列：与文件夹行保持对齐
            Color.clear.frame(width: 14, height: 16)

            // 复选框列：所有文件都可勾选；受保护(红/黄)默认不勾，勾选后删除需二次强确认
            Button {
                model.toggleSelection(file)
            } label: {
                Image(systemName: model.isSelected(file) ? "checkmark.square.fill" : "square")
                    .font(.system(size: fontSize + 1))
                    .foregroundStyle(model.isSelected(file) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(file.level == .safeToClean
                  ? "可安全清理（点击勾选）"
                  : "\(file.level.label)文件受保护，勾选后删除需二次确认")

            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent)
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                Text(file.relativePath)
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // 实心分类徽标
            Text(file.level.label)
                .font(.system(size: fontSize - 2, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(file.level.color, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)

            Text(file.sizeString)
                .font(.system(size: fontSize).monospacedDigit())
                .foregroundStyle(file.size >= 100_000_000 ? .primary : .secondary)
                .frame(minWidth: 84, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}