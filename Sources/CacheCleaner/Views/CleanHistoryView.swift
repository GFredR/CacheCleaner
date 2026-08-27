import SwiftUI

/// 清理历史页：展示每次清理释放了多少、删了哪些来源，强化「工具确实有用」的正反馈
struct CleanHistoryView: View {
    @AppStorage("fontSize") private var fontSize: Double = 13
    @State private var entries: [CleanHistoryEntry] = []
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear { reload() }
        .alert("清空清理历史", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                CleanHistoryStore.clear()
                reload()
            }
        } message: {
            Text("将删除全部清理历史记录，此操作不可撤销。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("清理历史")
                    .font(.system(size: fontSize + 5, weight: .bold))
                Text("共 \(entries.count) 条 · 累计释放 \(totalFreed)")
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("清空历史", role: .destructive) {
                showClearConfirm = true
            }
            .font(.system(size: fontSize - 1))
            .disabled(entries.isEmpty)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: fontSize + 30))
                    .foregroundStyle(.tertiary)
                Text("还没有清理记录")
                    .font(.system(size: fontSize + 4, weight: .semibold))
                Text("在「缓存清理」或「目录分析」里清理过一次后，这里会显示本次效果")
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(entries) { entry in
                    CleanHistoryRow(entry: entry, fontSize: fontSize)
                }
            }
            .listStyle(.inset)
        }
    }

    private var totalFreed: String {
        let sum = entries.reduce(0) { $0 + $1.freedBytes }
        return SizeFormatter.string(from: sum)
    }

    private func reload() {
        entries = CleanHistoryStore.entries()
    }
}

private struct CleanHistoryRow: View {
    let entry: CleanHistoryEntry
    let fontSize: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.useTrash ? "trash" : "trash.fill")
                .font(.system(size: fontSize + 2))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.source.displayName)
                        .font(.system(size: fontSize, weight: .medium))
                    Text(timestampText)
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.tertiary)
                }
                subtitle
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(entry.freedString)")
                    .font(.system(size: fontSize).monospacedDigit())
                    .foregroundStyle(.green)
                Text("删除 \(entry.deletedCount) 项")
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var timestampText: String {
        entry.timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private var subtitle: some View {
        HStack(spacing: 6) {
            if entry.failedCount > 0 {
                Text("\(entry.failedCount) 项失败")
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.orange)
            }
            if entry.skippedCount > 0 {
                Text("\(entry.skippedCount) 项跳过")
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.secondary)
            }
            if entry.failedCount == 0 && entry.skippedCount == 0 {
                Text("已全部清理完成")
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.secondary)
            }
        }
    }
}