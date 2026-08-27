import SwiftUI

/// 空间洞察：分析指定目录里的大文件 & 重复文件，支持 Finder 定位、删到废纸篓、清理多余副本
struct SpaceInsightView: View {
    // @StateObject：SwiftUI 订阅其 objectWillChange，@Published 变化才会驱动重绘。
    // 用 @State 会导致选目录/扫描后界面毫无反应（曾因此"完全不好使"）。
    @StateObject private var model = SpaceInsightModel()
    @AppStorage("fontSize") private var fontSize: Double = 13
    @State private var confirmDeleteLargest = false
    @State private var groupToClean: DuplicateGroup?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .alert("扫描失败", isPresented: alertPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .alert("删除到大文件废纸篓？", isPresented: $confirmDeleteLargest) {
            Button("删除 \(model.selectedLargeFiles.count) 个文件", role: .destructive) {
                model.trashSelectedLargeFiles()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将选中的 \(model.selectedLargeFiles.count) 个大文件移入废纸篓，可恢复。共 \(SizeFormatter.string(from: model.selectedLargeBytes))。")
        }
        .alert("清理多余副本？", isPresented: cleanupPresented, presenting: groupToClean) { group in
            Button("清理 \(group.files.count - 1) 份", role: .destructive) {
                model.cleanupDuplicateGroup(group.id)
                groupToClean = nil
            }
            Button("取消", role: .cancel) { groupToClean = nil }
        } message: { group in
            Text("每组保留 \(group.files[0].url.lastPathComponent)，其余 \(group.files.count - 1) 份副本移入废纸篓（可恢复），释放约 \(group.wastedString)。")
        }
        .alert("删除完成", isPresented: deleteReportPresented, presenting: model.deleteReport) { _ in
            Button("好", role: .cancel) {}
        } message: { report in
            Text(report.summary)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("空间洞察")
                    .font(.system(size: fontSize + 5, weight: .bold))
                Text(model.rootName.isEmpty ? "选择一个目录，查看其中的大文件和重复文件"
                     : "正在检查：\(model.rootName) · 已扫描 \(model.scannedCount) 个文件")
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if model.isScanning {
                Button("取消") { model.cancelScan() }
                    .font(.system(size: fontSize - 1))
            } else {
                Button {
                    model.chooseDirectory()
                } label: {
                    Label(model.rootURL == nil ? "选择目录" : "更换目录",
                          systemImage: "folder.badge.plus")
                    .font(.system(size: fontSize))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    private var modePicker: some View {
        Picker("", selection: $model.mode) {
            ForEach(SpaceInsightModel.Mode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
        .onChange(of: model.mode) { newMode in
            model.switchMode(newMode)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.rootURL == nil {
            emptyRoot
        } else if model.isScanning {
            scanningView
        } else if model.mode == .largest {
            largestList
        } else {
            duplicateList
        }
    }

    private var emptyRoot: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: fontSize + 30))
                .foregroundStyle(.tertiary)
            Text("还没有选择目录")
                .font(.system(size: fontSize + 4, weight: .semibold))
            Text("点击上方「选择目录」，工具会分析其中的最大文件与重复文件，可定位或在 Finder 中操作")
                .font(.system(size: fontSize - 1))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
            Text("正在扫描 \(model.scannedCount) 个文件…")
                .font(.system(size: fontSize - 1))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private var largestList: some View {
        VStack(spacing: 0) {
            modePicker.padding(.vertical, 8)
            if !model.largestFiles.isEmpty {
                selectionBar
            }
            Divider()
            if model.largestFiles.isEmpty {
                emptyResult("没有发现大文件")
            } else {
                List {
                    ForEach(Array(model.largestFiles.enumerated()), id: \.element.id) { index, file in
                        LargeFileRow(
                            rank: index + 1,
                            file: file,
                            fontSize: fontSize,
                            isSelected: model.selectedLargeFileIDs.contains(file.id),
                            onToggle: { model.toggleLargeFileSelection(file.id) },
                            onReveal: { model.revealInFinder(file.url) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    /// 大文件勾选操作栏：全选 / 清空 / 已选统计 / 删除到废纸篓
    private var selectionBar: some View {
        HStack(spacing: 10) {
            Button(model.selectedLargeFileIDs.count == model.largestFiles.count ? "取消全选" : "全选") {
                if model.selectedLargeFileIDs.count == model.largestFiles.count {
                    model.clearLargeFileSelection()
                } else {
                    model.selectAllLargest()
                }
            }
            .font(.system(size: fontSize - 1))
            Text("已选 \(model.selectedLargeFileIDs.count) 个 · \(SizeFormatter.string(from: model.selectedLargeBytes))")
                .font(.system(size: fontSize - 1))
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                guard !model.selectedLargeFileIDs.isEmpty else { return }
                confirmDeleteLargest = true
            } label: {
                Label("删除到废纸篓", systemImage: "trash")
                    .font(.system(size: fontSize - 1))
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedLargeFileIDs.isEmpty || model.isDeleting)
            if model.isDeleting {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var duplicateList: some View {
        VStack(spacing: 0) {
            modePicker.padding(.vertical, 8)
            Divider()
            if model.duplicateGroups.isEmpty {
                emptyResult("没有发现重复文件")
            } else {
                let total = model.duplicateGroups.reduce(0) { $0 + $1.wastedBytes }
                List {
                    Text("发现 \(model.duplicateGroups.count) 组重复文件，共可释放 \(SizeFormatter.string(from: total))")
                        .font(.system(size: fontSize - 1))
                        .foregroundStyle(.secondary)
                    ForEach(model.duplicateGroups) { group in
                        DuplicateGroupRow(group: group, fontSize: fontSize, isDeleting: model.isDeleting) {
                            groupToClean = group
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func emptyResult(_ text: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: fontSize + 24))
                .foregroundStyle(.green)
            Text(text)
                .font(.system(size: fontSize + 2, weight: .medium))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var cleanupPresented: Binding<Bool> {
        Binding(
            get: { groupToClean != nil },
            set: { if !$0 { groupToClean = nil } }
        )
    }

    private var deleteReportPresented: Binding<Bool> {
        Binding(
            get: { model.deleteReport != nil },
            set: { if !$0 { model.deleteReport = nil } }
        )
    }
}

private struct LargeFileRow: View {
    let rank: Int
    let file: LargeFileItem
    let fontSize: Double
    let isSelected: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: fontSize + 2))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "取消选择" : "选择")
            .accessibilityLabel(isSelected ? "取消选择 \(file.url.lastPathComponent)" : "选择 \(file.url.lastPathComponent)")

            Text("#\(rank)")
                .font(.system(size: fontSize - 1, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)
                .monospacedDigit()
            Image(systemName: "doc.fill")
                .font(.system(size: fontSize))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.system(size: fontSize, weight: .medium))
                    .lineLimit(1)
                Text(file.url.path)
                    .font(.system(size: fontSize - 3))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: onReveal) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: fontSize - 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("在 Finder 中显示")
            .accessibilityLabel("在 Finder 中显示 \(file.url.lastPathComponent)")

            Text(file.sizeString)
                .font(.system(size: fontSize).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 84, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

private struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    let fontSize: Double
    let isDeleting: Bool
    let onCleanup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: fontSize))
                    .foregroundStyle(.orange)
                Text("\(group.files.count) 份相同 · 单份 \(group.sizeString) · 可释放 \(group.wastedString)")
                    .font(.system(size: fontSize, weight: .medium))
                Spacer()
                Button {
                    onCleanup()
                } label: {
                    Label("清理多余副本", systemImage: "trash")
                        .font(.system(size: fontSize - 1))
                }
                .buttonStyle(.bordered)
                .disabled(isDeleting)
                .help("保留一份，其余移入废纸篓（可恢复）")
            }
            ForEach(group.files) { file in
                HStack(spacing: 8) {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(file.url.path)
                        .font(.system(size: fontSize - 3))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}