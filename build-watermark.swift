import AppKit

// 给微信收款码加水印（防被滥用为诈骗二维码）。
// 方案：在原图底部追加 110px 高黑色半透明条幅，白字粗体标注用途。
// 不修改二维码识别区（保留三个定位方块和中央 logo）。

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift build-watermark.swift <原图> <输出路径>")
    exit(1)
}
let inputPath = args[1]
let outPath = args[2]

guard let raw = NSImage(contentsOfFile: inputPath) else {
    print("无法读取 \(inputPath)")
    exit(1)
}

let w = raw.size.width
let h = raw.size.height
let bannerH: CGFloat = 110
let fontSize: CGFloat = 42

// 画布：原图高度 + 底部条幅
let canvas = NSImage(size: NSSize(width: w, height: h + bannerH))
canvas.lockFocus()

// 原图绘制在上方
raw.draw(in: NSRect(x: 0, y: bannerH, width: w, height: h),
         from: NSRect(origin: .zero, size: raw.size),
         operation: .sourceOver,
         fraction: 1)

// 底部条幅：黑色 78% 半透明
let banner = NSRect(x: 0, y: 0, width: w, height: bannerH)
NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.78).setFill()
banner.fill()

// 条幅文字：两行，白字
let line1 = NSAttributedString(string: "CacheCleaner 开源打赏专用",
                               attributes: [
                                .font: NSFont.boldSystemFont(ofSize: 36),
                                .foregroundColor: NSColor.white
                               ])
let line2 = NSAttributedString(string: "请勿用作其他用途 · 感谢支持",
                               attributes: [
                                .font: NSFont.systemFont(ofSize: 26),
                                .foregroundColor: NSColor.white.withAlphaComponent(0.88)
                               ])

let s1 = line1.size()
let s2 = line2.size()
let totalTextH = s1.height + 6 + s2.height
let startY = (bannerH - totalTextH) / 2

line1.draw(at: NSPoint(x: (w - s1.width) / 2, y: startY + s2.height + 6))
line2.draw(at: NSPoint(x: (w - s2.width) / 2, y: startY))

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .png, properties: [:]) else {
    print("保存失败")
    exit(1)
}
try data.write(to: URL(fileURLWithPath: outPath))
print("已生成 \(outPath)（原图 \(Int(w))x\(Int(h)) + 底部 \(Int(bannerH))px 水印条幅）")