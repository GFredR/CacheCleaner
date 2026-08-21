import Foundation
import AppKit

/// 完全磁盘访问权限（Full Disk Access）相关
enum PermissionService {

    /// 检测是否已授予完全磁盘访问权限。
    /// 原理：TCC 保护的目录对未授权进程会「伪装成存在但内容为空」，
    /// 所以只要任一受保护目录能枚举出内容，即可认为已授权。
    /// 候选目录尽量选「几乎必然有内容」的，减少「已授权但所有候选都空」的误判。
    static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let protectedCandidates = [
            home + "/Library/Messages",
            home + "/Library/Mail",
            home + "/Library/Safari",
            home + "/Library/Containers/com.apple.Safari",
            home + "/Library/Application Support/com.apple.TCC",
            home + "/Library/Application Support/com.apple.sharedfilelist",
            home + "/Library/Application Support/AddressBook",
            home + "/Library/Application Support/MobileSync"
        ]

        for path in protectedCandidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: path),
               !contents.isEmpty {
                return true
            }
        }
        return false
    }

    /// 打开系统设置里的「完全磁盘访问权限」面板
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
