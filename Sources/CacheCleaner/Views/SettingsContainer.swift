import SwiftUI

/// 设置面板容器：sheet 弹出时，底部加"完成"按钮
/// （Enter 默认提交；Esc 通过 onExitCommand 触发，都关闭 sheet）
struct SettingsContainer: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SettingsView()
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .onExitCommand { dismiss() }   // Esc 关闭
                    .padding(10)
            }
        }
        .frame(width: 500, height: 420)
    }
}