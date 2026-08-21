import SwiftUI
import AppKit

/// 缓存列表单行：勾选 + 分类色条 + 图标 + 名称/路径 + 实心分类徽标 + 大小
struct CacheRowView: View {
    let item: CacheItem
    let isSelected: Bool
    let onToggle: () -> Void
    @AppStorage("fontSize") private var fontSize: Double = 13

    var body: some View {
        HStack(spacing: 0) {
            // 左侧分类色条：一眼看出缓存类型
            RoundedRectangle(cornerRadius: 1.5)
                .fill(categoryColor)
                .frame(width: 4)
                .padding(.vertical, 3)

            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: fontSize + 2))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("勾选/取消")
                .accessibilityLabel(isSelected ? "取消勾选 \(item.name)" : "勾选 \(item.name)")

                Image(systemName: item.category.systemImage)
                    .font(.system(size: fontSize + 2))
                    .foregroundStyle(.secondary)
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
        .contextMenu {
            Button("在访达中查看") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("复制路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
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
