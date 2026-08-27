import SwiftUI
import AppKit

/// 按应用聚合的组行：组头三态勾选 + 展开显示组内各缓存项
struct AppGroupRowView: View {
    let group: CacheCleanerModel.AppGroup
    @ObservedObject var model: CacheCleanerModel
    let fontSize: Double
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                model.toggleGroup(group)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: checkImageName)
                        .font(.system(size: fontSize + 2))
                        .foregroundStyle(checkImageName == "square" ? Color.secondary : Color.accentColor)

                    Image(systemName: "folder.fill")
                        .font(.system(size: fontSize + 2))
                        .foregroundStyle(.teal)

                    Text(group.name)
                        .font(.system(size: fontSize, weight: .medium))
                        .lineLimit(1)
                    Text("\(group.items.count) 项")
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.secondary)

                    Spacer()
                    Text(group.sizeString)
                        .font(.system(size: fontSize).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 84, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .background(
                    Rectangle()
                        .fill(groupTintColor)
                )
            }
            .buttonStyle(.plain)
            .help("勾选/取消整组")
            .accessibilityLabel("勾选整组 \(group.name)")
            .onHover { inside in
                if inside {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            if expanded {
                ForEach(group.items) { item in
                    CacheRowView(
                        item: item,
                        model: model,
                        onToggle: { model.toggleSelection(item) }
                    )
                }
            }
        }
    }

    private var checkImageName: String {
        switch model.selectionState(group) {
        case .none: return "square"
        case .partial: return "minus.square.fill"
        case .all: return "checkmark.square.fill"
        }
    }

    /// 组头背景随三态变化：全选深高亮、半选浅高亮、未选透明
    private var groupTintColor: Color {
        switch model.selectionState(group) {
        case .none: return .clear
        case .partial: return Color.accentColor.opacity(0.06)
        case .all: return Color.accentColor.opacity(0.12)
        }
    }
}

/// 缓存列表单行：勾选 + 分类色条 + 图标 + 名称/路径 + 实心分类徽标 + 大小
struct CacheRowView: View {
    let item: CacheItem
    @ObservedObject var model: CacheCleanerModel
    let onToggle: () -> Void
    @AppStorage("fontSize") private var fontSize: Double = 13

    /// 行内直接订阅 model 实时计算勾选态。
    /// 此前 isSelected 由父视图创建时传入，父视图不重算时行内容不刷新——勾了也不显示对钩
    private var isSelected: Bool {
        model.selectedIDs.contains(item.id)
    }

    var body: some View {
        Button(action: onToggle) {
            rowContent
        }
        .buttonStyle(.plain)
        .help("勾选/取消")
        .accessibilityLabel(isSelected ? "取消勾选 \(item.name)" : "勾选 \(item.name)")
        .onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .contextMenu {
            if item.isWhitelisted {
                Button {
                    model.removeWhitelistAndRefresh(item.url.path)
                } label: {
                    Label("移出白名单", systemImage: "shield.slash")
                }
            } else {
                Button {
                    model.addWhitelistAndRefresh(item.url.path)
                } label: {
                    Label("加入白名单（永不清理）", systemImage: "shield.badge.plus")
                }
            }
            Divider()
            Button("在访达中查看") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("复制路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            // 左侧分类色条：一眼看出缓存类型
            RoundedRectangle(cornerRadius: 1.5)
                .fill(categoryColor)
                .frame(width: 4)
                .padding(.vertical, 3)

            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: fontSize + 2))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Image(systemName: item.category.systemImage)
                    .font(.system(size: fontSize + 2))
                    .foregroundStyle(categoryColor)
                    .frame(width: 22)
                    .accessibilityLabel(item.category.rawValue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: fontSize))
                        .lineLimit(1)
                    Text(item.url.path)
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if item.isRunning {
                    Label("运行中", systemImage: "play.circle")
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.orange)
                }
                if item.isWhitelisted {
                    Label("白名单", systemImage: "shield")
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.blue)
                }

                // 实心分类徽标：强调「这是哪类缓存」
                Text(item.category.rawValue)
                    .font(.system(size: fontSize - 2, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(categoryColor, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(.white)

                Text(item.sizeString)
                    .font(.system(size: fontSize).monospacedDigit())
                    .foregroundStyle(item.size >= 1_000_000_000 ? .primary : .secondary)
                    .frame(minWidth: 84, alignment: .trailing)
            }
            .padding(.leading, 10)
            .padding(.trailing, 2)
        }
        .padding(.vertical, 3)
        // 选中整行高亮（无圆角，贴 macOS 原生列表选中观感）
        .background(
            Rectangle()
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    private var categoryColor: Color {
        switch item.category {
        case .system: return .gray
        case .application: return .teal
        case .sandbox: return .purple
        case .developer: return .brown
        }
    }
}
