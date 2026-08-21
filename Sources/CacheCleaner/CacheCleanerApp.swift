import SwiftUI
import AppKit

@main
struct CacheCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = CacheCleanerModel()
    @AppStorage("appearance") private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 780, minHeight: 540)
                .preferredColorScheme(appearanceMode.colorScheme)
                .onAppear { applyAppearance() }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }

    /// 应用外观：AppKit 全局（macOS 13 保底）+ SwiftUI 窗口级（14+）双保险
    private func applyAppearance() {
        NSApp.appearance = appearanceMode.nsAppearance
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SPM 构建的 executable 是非 bundle 进程，需手动激活，
        // 否则窗口不会自动前置、Dock 无图标
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
