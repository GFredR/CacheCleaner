import AppKit
import Foundation

/// 生成 dmg 安装器背景图（660×420，圆角深青底 + 居中拖拽示意）。
/// 左侧：App 图标占位；右侧：Applications 文件夹；中间箭头；顶部"CacheCleaner"标题。
let args = CommandLine.arguments
guard args.count >= 2 else {
    print("用法: swift build-dmg-background.swift <输出路径.png> [图标路径.png]")
    exit(1)
}
let outPath = args[1]
let iconPath = args.count >= 3 ? args[2] : nil

let size = NSSize(width: 660, height: 420)
let img = NSImage(size: size)
img.lockFocus()

// 背景：圆角深青渐变
let bgRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 18, yRadius: 18)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.42, alpha: 1),
    NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.30, alpha: 1)
])!
gradient.draw(in: bgPath, angle: -90)

// 顶部标题
let title = "CacheCleaner"
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
    .foregroundColor: NSColor.white
]
let titleSize = (title as NSString).size(withAttributes: titleAttrs)
(title as NSString).draw(
    at: NSPoint(x: (size.width - titleSize.width) / 2, y: size.height - 80),
    withAttributes: titleAttrs
)

// 副标题
let subtitle = "拖拽左侧图标到 Applications 文件夹即可安装"
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.75)
]
let subSize = (subtitle as NSString).size(withAttributes: subAttrs)
(subtitle as NSString).draw(
    at: NSPoint(x: (size.width - subSize.width) / 2, y: 32),
    withAttributes: subAttrs
)

// 左右两个图标占位框（带细描边白边）
let iconSide: CGFloat = 144
let leftIconX: CGFloat = 90
let rightIconX: CGFloat = size.width - 90 - iconSide
let iconY: CGFloat = (size.height - iconSide) / 2 - 10

func drawIconBox(at rect: NSRect, icon: NSImage?) {
    let path = NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24)
    NSColor.white.withAlphaComponent(0.15).setFill()
    path.fill()
    NSColor.white.withAlphaComponent(0.4).setStroke()
    path.lineWidth = 1
    path.stroke()

    if let icon {
        icon.size = NSSize(width: rect.width - 16, height: rect.height - 16)
        icon.draw(
            in: NSRect(x: rect.origin.x + 8, y: rect.origin.y + 8,
                       width: rect.width - 16, height: rect.height - 16),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    } else {
        // 占位文字
        let placeholder = "图标"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6)
        ]
        let s = (placeholder as NSString).size(withAttributes: attrs)
        (placeholder as NSString).draw(
            at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2),
            withAttributes: attrs
        )
    }
}

let leftRect = NSRect(x: leftIconX, y: iconY, width: iconSide, height: iconSide)
let rightRect = NSRect(x: rightIconX, y: iconY, width: iconSide, height: iconSide)

let appIcon = iconPath.flatMap { NSImage(contentsOfFile: $0) }
drawIconBox(at: leftRect, icon: appIcon)

// 右侧 Applications 文件夹图标（用 SF Symbols 风格简单绘制）
let folderIcon = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 110, weight: .regular)) ?? nil
drawIconBox(at: rightRect, icon: folderIcon)

// 中间箭头（白色曲线 + 箭头头）
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: leftRect.maxX + 30, y: size.height / 2 - 10))
arrow.line(to: NSPoint(x: rightRect.minX - 30, y: size.height / 2 - 10))
arrow.lineWidth = 4
arrow.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.85).setStroke()
arrow.stroke()

// 箭头头部
let head = NSBezierPath()
head.move(to: NSPoint(x: rightRect.minX - 30, y: size.height / 2 - 10))
head.line(to: NSPoint(x: rightRect.minX - 50, y: size.height / 2 + 12))
head.move(to: NSPoint(x: rightRect.minX - 30, y: size.height / 2 - 10))
head.line(to: NSPoint(x: rightRect.minX - 50, y: size.height / 2 - 32))
head.lineWidth = 4
head.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.85).setStroke()
head.stroke()

img.unlockFocus()

// 保存为 PNG
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("保存失败")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
print("已生成 \(outPath)")