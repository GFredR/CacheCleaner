import SwiftUI
import AppKit

/// 主窗口：双 Tab（缓存清理 / 目录分析）
struct ContentView: View {
    var body: some View {
        TabView {
            CacheCleanerView()
                .tabItem { Label("缓存清理", systemImage: "trash") }
            DirectoryAnalysisView()
                .tabItem { Label("目录分析", systemImage: "folder.badge.gearshape") }
        }
    }
}

/// 缓存清理页（原主界面）
struct CacheCleanerView: View {
    @EnvironmentObject var model: CacheCleanerModel
    @AppStorage("fontSize") private var fontSize: Double = 13
    @State private var showCleanConfirm = false
    @State private var showPermissionAlert = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.permissionState == .denied {
                permissionBanner
            }

            contentArea

            Divider()
            footer
        }
        .onAppear {
            if model.permissionState == .unknown {
                model.checkPermission()
            }
        }
        .alert("确认清理", isPresented: $showCleanConfirm) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) { model.cleanSelected() }
        } message: {
            Text(model.useTrash
                 ? "将把 \(model.selectedCount) 项缓存移入废纸篓，预计释放 \(model.selectedSizeString)。\n可在废纸篓中恢复，正在使用的 App 可能需要重启。"
                 : "将删除 \(model.selectedCount) 项缓存，预计释放 \(model.selectedSizeString)。\n此操作不可撤销，正在使用的 App 可能需要重启。")
        }
        .alert("清理完成", isPresented: reportPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.cleanReport?.details ?? "")
        }
        .alert("需要完全磁盘访问权限", isPresented: $showPermissionAlert) {
            Button("打开系统设置") {
                PermissionService.openSystemSettings()
            }
            Button("继续扫描（结果可能不完整）", role: .destructive) {
                model.startScan()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("未授权完全磁盘访问权限时，沙盒容器的缓存扫不到。\n建议先授予权限再扫描，以获得全部 App 的缓存。")
        }
        .sheet(isPresented: $showSettings) {
            SettingsContainer()
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("缓存清理")
                    .font(.system(size: fontSize + 5, weight: .bold))
                Text("已发现 \(model.items.count) 项缓存 · 共 \(model.totalSizeString)")
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            permissionIndicator

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: fontSize + 2))
            }
            .help("设置（字体大小、白名单等）")
            .buttonStyle(.borderless)

            Button {
                startScanWithPermissionCheck()
            } label: {
                Label(scanButtonTitle, systemImage: "magnifyingglass")
                    .font(.system(size: fontSize))
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isScanning)
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private var scanButtonTitle: String {
        if model.isScanning { return "扫描中…" }
        return model.items.isEmpty ? "开始扫描" : "重新扫描"
    }

    /// 未授权时弹窗引导授权，已授权直接开始
    private func startScanWithPermissionCheck() {
        if model.permissionState == .denied {
            showPermissionAlert = true
        } else {
            model.startScan()
        }
    }

    private var permissionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.permissionState == .granted ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(model.permissionState == .granted ? "已授权" : "未授权")
                .font(.system(size: fontSize - 2))
                .foregroundStyle(.secondary)
        }
        .help("完全磁盘访问权限状态")
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            Text("需要「完全磁盘访问权限」才能扫到所有 App 的缓存。开启后扫描结果才完整。")
                .font(.system(size: fontSize - 1))
            Spacer()
            Button("打开系统设置") { PermissionService.openSystemSettings() }
                .font(.system(size: fontSize - 1))
            Button {
                model.checkPermission()
            } label: {
                HStack(spacing: 4) {
                    if model.isCheckingPermission {
                        ProgressView().controlSize(.mini)
                    }
                    Text(model.isCheckingPermission ? "检测中…" : "重新检测")
                }
            }
            .font(.system(size: fontSize - 1))
            .disabled(model.isCheckingPermission)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - 列表区域

    @ViewBuilder
    private var contentArea: some View {
        if model.isScanning {
            VStack(spacing: 12) {
                Spacer()
                ProgressView(value: model.scanProgress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 420)
                Text("正在统计 \(model.currentPath)")
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("取消") { model.cancelScan() }
                    .font(.system(size: fontSize - 1))
                Spacer()
            }
            .padding()
        } else if model.items.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "externaldrive.badge.questionmark")
                    .font(.system(size: fontSize + 30))
                    .foregroundStyle(.tertiary)
                Text("还没有扫描结果")
                    .font(.system(size: fontSize + 4, weight: .semibold))
                Text("点击右上角「开始扫描」查找电脑里的缓存")
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(model.items) { item in
                    CacheRowView(
                        item: item,
                        isSelected: model.selectedIDs.contains(item.id),
                        onToggle: { model.toggleSelection(item) }
                    )
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 12) {
            Text("已选 \(model.selectedCount) 项 · 可释放 \(model.selectedSizeString)")
                .font(.system(size: fontSize))
                .monospacedDigit()
            if model.useTrash {
                Label("将移入废纸篓", systemImage: "trash")
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("勾选安全项（非运行中/非白名单）") {
                    model.selectAllSafe()
                }
                Button("全选所有项（含运行中）") {
                    model.selectAll()
                }
            } label: {
                Label("选择", systemImage: "checkmark.circle")
                    .font(.system(size: fontSize - 1))
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 90)
            .disabled(model.items.isEmpty || model.isScanning)
            .help("批量勾选：安全项 / 全部")

            Button("清除选择") {
                model.clearSelection()
            }
            .font(.system(size: fontSize - 1))
            .disabled(model.selectedCount == 0)

            Button(role: .destructive) {
                if model.useTrash {
                    model.cleanSelected()
                } else {
                    showCleanConfirm = true
                }
            } label: {
                Label("清理所选", systemImage: "trash")
                    .font(.system(size: fontSize))
                    .frame(minWidth: 90)
            }
            .disabled(model.selectedCount == 0 || model.isCleaning || model.isScanning)
        }
        .padding(12)
    }

    private var reportPresented: Binding<Bool> {
        Binding(
            get: { model.cleanReport != nil },
            set: { if !$0 { model.cleanReport = nil } }
        )
    }
}