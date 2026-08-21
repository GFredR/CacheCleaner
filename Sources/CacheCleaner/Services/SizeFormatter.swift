import Foundation

/// 统一的字节大小格式化（避免 ByteCountFormatter 在某些 locale 下输出"Zero KB"）
/// 单位固定 KB/MB/GB/TB，数字小数位按值自适应：≥100 不带小数，≥10 保留 1 位，否则 2 位。
/// 0 字节也显示"0 KB"（与"0 KB"预期一致）。
enum SizeFormatter {

    private static let units = ["KB", "MB", "GB", "TB"]

    static func string(from bytes: Int64) -> String {
        let value = Double(bytes)
        if value < 1024 {
            return "0 KB"
        }
        var v = value / 1024
        var idx = 0
        while v >= 1024 && idx < units.count - 1 {
            v /= 1024
            idx += 1
        }
        let format: String
        if v >= 100 { format = "%.0f %@" }
        else if v >= 10 { format = "%.1f %@" }
        else { format = "%.2f %@" }
        return String(format: format, v, units[idx])
    }
}