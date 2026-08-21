import SwiftUI
import AppKit

/// 设置窗口：通用（含外观字体/主题）+ 白名单
struct SettingsView: View {
    @EnvironmentObject var model: CacheCleanerModel
    @AppStorage("fontSize") private var fontSize: Double = 13
    @AppStorage("appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue
    @State private var newWhitelistPath = ""
    @State private var whitelist: [String] = []

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }

            whitelistTab
                .tabItem { Label("白名单", systemImage: "shield.lefthalf.filled") }
        }
        .frame(width: 500, height: 360)
        .onAppear { refresh() }
    }

    // MARK: - 通用

    private var generalTab: some View {
        Form {
            Toggle("跳过正在运行的 App 的缓存", isOn: $model.skipRunningApps)
            Text("避免清理正在使用中的应用，防止出现异常或数据丢失。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("清理时移入废纸篓（可恢复）", isOn: $model.useTrash)
            Text("移入废纸篓后可从废纸篓恢复，但清理速度明显变慢；关闭则直接删除。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Section("外观") {
                HStack {
                    Text("列表字体大小")
                    Spacer()
                    Slider(value: $fontSize, in: 11...18, step: 0.5)
                        .frame(width: 180)
                    Text("\(fontSize, specifier: "%.1f") pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Text("应用于缓存列表与目录分析列表的文字。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("主题", selection: Binding(
                    get: { appearanceRaw },
                    set: { newValue in
                        appearanceRaw = newValue
                        // AppKit 全局外观，macOS 13+ 即时生效
                        let mode = AppearanceMode(rawValue: newValue) ?? .system
                        NSApp.appearance = mode.nsAppearance
                    }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("浅色 / 深色 / 跟随系统，切换即时生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("重新检测「完全磁盘访问权限」") {
                model.checkPermission()
            }
        }
        .padding()
        .formStyle(.grouped)
    }

    // MARK: - 白名单

    private var whitelistTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("白名单中的缓存路径在清理时会被强制跳过（前缀匹配）。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("输入路径后点添加，或点浏览…选择文件夹", text: $newWhitelistPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addFromField() }   // Enter 也能添加
                Button("浏览…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    panel.prompt = "添加到白名单"
                    panel.message = "选择一个或多个文件夹，其下缓存清理时将被跳过"
                    if panel.runModal() == .OK {
                        // 选中即自动添加（用户预期：选了 = 保存了）
                        for url in panel.urls {
                            model.addWhitelist(url.path)
                        }
                        refresh()
                    }
                }
                Button("添加") { addFromField() }
                .disabled(newWhitelistPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if whitelist.isEmpty {
                Spacer()
                Text("暂无白名单")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(whitelist, id: \.self) { path in
                        HStack {
                            Image(systemName: "shield")
                                .foregroundStyle(.blue)
                            Text(path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.removeWhitelist(path)
                                refresh()
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("从白名单移除")
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func refresh() {
        whitelist = model.whitelistPaths()
    }

    /// 从 TextField 读取并添加（用于 Enter 提交 + 「添加」按钮）
    private func addFromField() {
        let path = newWhitelistPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        guard !path.isEmpty else { return }
        model.addWhitelist(path)
        newWhitelistPath = ""
        refresh()
    }
}
