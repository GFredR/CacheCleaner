import SwiftUI
import AppKit

/// 目录分析：拖入任意目录，按重要性分级展示文件（红=重要 / 黄=谨慎 / 绿=可清理）
struct DirectoryAnalysisView: View {
    @StateObject private var model = DirectoryAnalysisModel()
    @AppStorage("useTrash") private var useTrash = false
    @AppStorage("fontSize") private var fontSize: Double = 13
    @State private var isTargeted = false
    @State private var showCleanConfirm = false
    @State private var showSettings = false

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
            Text("将删除 \(model.selectedCount) 个可清理文件，预计释放 \(model.selectedSizeString)。\n重要（红色）和谨慎（黄色）的文件不会被删除。")
        }
        .alert("清理完成", isPresented: reportPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.cleanReport ?? "")
        }
        .sheet(isPresented: $showSettings) {
            SettingsContainer()
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
        } else {
            List {
                ForEach(model.tree) { node in
                    OutlineGroup([node], children: \.children) { item in
                        DirectoryNodeRow(node: item)
                            .environmentObject(model)
                    }
                }
            }
            .listStyle(.inset)
        }
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
                ProgressView()
                    .controlSize(.large)
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
        model.totalFiles == 0 ? "准备中…" : "正在扫描…"
    }

    /// 已处理 / 总数
    private var scanProgressDetailText: String {
        guard model.totalFiles > 0 else { return "正在计算文件总数…" }
        return "已处理 \(model.processedCount) / \(model.totalFiles) 个文件"
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
            Text("已选 \(model.selectedCount) 个可清理文件 · 可释放 \(model.selectedSizeString)")
                .font(.system(size: fontSize))
                .monospacedDigit()
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
                if useTrash {
                    model.cleanSelected(useTrash: true)
                } else {
                    showCleanConfirm = true
                }
            } label: {
                Label("清理可清理项", systemImage: "trash")
                    .font(.system(size: fontSize))
                    .frame(minWidth: 90)
            }
            .disabled(model.selectedCount == 0 || model.isCleaning || model.isScanning)
        }
        .padding(12)
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
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

/// 目录树的一行：文件夹可展开/折叠，文件行展示重要性颜色与勾选
struct DirectoryNodeRow: View {
    @EnvironmentObject var model: DirectoryAnalysisModel
    @AppStorage("fontSize") private var fontSize: Double = 13
    let node: DirectoryNode

    var body: some View {
        Group {
            if node.isFolder {
                folderRow
            } else if let file = node.file {
                fileRow(file)
            }
        }
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
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: fontSize + 2))
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.system(size: fontSize, weight: .medium))
                    .lineLimit(1)
                Text("\(node.fileCount) 个文件")
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(node.sizeString)
                .font(.system(size: fontSize).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 84, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func fileRow(_ file: AnalyzedFile) -> some View {
        HStack(spacing: 10) {
            if file.level == .safeToClean {
                Button {
                    model.toggleSelection(file)
                } label: {
                    Image(systemName: model.selectedIDs.contains(file.id)
                          ? "checkmark.square.fill" : "square")
                        .font(.system(size: fontSize + 1))
                        .foregroundStyle(model.selectedIDs.contains(file.id)
                                         ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: file.level.systemImage)
                    .font(.system(size: fontSize))
                    .foregroundStyle(file.level.color)
                    .frame(width: 20)
            }

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