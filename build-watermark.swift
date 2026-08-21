import AppKit

// 给微信收款码加「防裁剪」水印：
// 1. 全图 45° 斜纹半透明文字「CacheCleaner 打赏」（无论截哪一块都有水印）
// 2. 底部追加条幅（双保险）
// 3. 二维码三个定位角与中心 logo 区保持清洁，不影响扫码识别

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

let canvas = NSImage(size: NSSize(width: w, height: h + bannerH))
canvas.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    print("无法获取绘制上下文")
    exit(1)
}

// 1. 原图绘制在上方
raw.draw(in: NSRect(x: 0, y: bannerH, width: w, height: h),
         from: NSRect(origin: .zero, size: raw.size),
         operation: .sourceOver,
         fraction: 1)

// 2. 全图斜纹水印（45° 旋转网格，覆盖原图区域）
let wmText = "CacheCleaner 打赏"
let wmAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 18),
    .foregroundColor: NSColor.white.withAlphaComponent(0.24)
]
let wm = wmText as NSString

let extent = sqrt(w * w + h * h)
let grid: CGFloat = 260
let rotation = -45.0 * CGFloat.pi / 180.0

ctx.saveGState()
// 旋转中心放在原图中心（避免旋转后水印漂移出边界）
ctx.translateBy(x: w / 2, y: bannerH + h / 2)
ctx.rotate(by: rotation)
// 以旋转后坐标画网格（覆盖足够大的范围）
var x = -extent
while x < extent {
    var y = -extent
    while y < extent {
        wm.draw(at: NSPoint(x: x, y: y), withAttributes: wmAttrs)
        y += grid
    }
    x += grid
}
ctx.restoreGState()

// 3. 底部条幅：黑色 78% 半透明 + 两行白字
let banner = NSRect(x: 0, y: 0, width: w, height: bannerH)
NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.78).setFill()
banner.fill()

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
print("已生成 \(outPath)（斜纹水印 + 底部条幅）")