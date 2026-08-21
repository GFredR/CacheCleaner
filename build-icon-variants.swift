import AppKit

// MARK: - 按 Apple HIG 规范批量生成图标变体
// 用法: swift build-icon-variants.swift <variant> <输出路径.png>
// variant: trash | disk | wand
// 规范：1024 方形全出血；垂直渐变（顶亮底暗）+ 顶部径向光晕；单主体 + 少量金星点缀；无文字。

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift build-icon-variants.swift <variant> <输出路径.png>")
    exit(1)
}
let variant = args[1]
let outPath = args[2]
let size: CGFloat = 1024

// MARK: - 工具

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let result = NSImage(size: image.size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: image.size))
    color.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    result.unlockFocus()
    return result
}

func symbol(_ name: String, pointSize: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        print("⚠️ 符号不存在: \(name)")
        return NSImage()
    }
    let img = tinted(base, color)
    img.size = NSSize(width: pointSize, height: pointSize)
    return img
}

func draw(_ image: NSImage, centeredAt center: NSPoint, size s: CGFloat) {
    image.draw(in: NSRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s))
}

func drawStar(_ s: CGFloat, _ center: NSPoint, _ color: NSColor) {
    draw(symbol("star.fill", pointSize: s, color: color), centeredAt: center, size: s)
}

// 渐变背景 + 顶部径向光晕（圆角矩形，圆角外透明；Apple 圆角比例 22.37%）
func drawBackground(top: NSColor, bottom: NSColor) {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.2237   // Apple squircle 圆角比例
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    let g = NSGradient(colors: [top, bottom])!
    g.draw(in: path, angle: -90)

    // 顶部中央径向光晕（模拟光照，Apple 风格），裁剪到圆角内
    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    let glowCenter = NSPoint(x: size / 2, y: size * 0.92)
    let glowRadius: CGFloat = 520
    let glow = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.14), 0.0),
        (NSColor.white.withAlphaComponent(0.0), 1.0)
    )!
    glow.draw(
        in: NSBezierPath(ovalIn: NSRect(
            x: glowCenter.x - glowRadius, y: glowCenter.y - glowRadius,
            width: glowRadius * 2, height: glowRadius * 2
        )),
        relativeCenterPosition: NSPoint(x: 0, y: 0)
    )
    NSGraphicsContext.current?.restoreGraphicsState()
}

let amber = NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.25, alpha: 1)       // #FFD640
let white = NSColor.white
let cyan = NSColor(calibratedRed: 0.39, green: 0.82, blue: 1.0, alpha: 1)        // #64D2FF

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

switch variant {
// V1 垃圾桶·清空：苹果蓝渐变 + 白色垃圾桶 + 金星
case "trash":
    drawBackground(top: NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1),     // #0A84FF
                   bottom: NSColor(calibratedRed: 0.0, green: 0.11, blue: 0.28, alpha: 1))  // #001B48
    draw(symbol("trash.fill", pointSize: 480, color: white), centeredAt: NSPoint(x: 512, y: 420), size: 480)
    drawStar(150, NSPoint(x: 760, y: 780), amber)
    drawStar(100, NSPoint(x: 300, y: 740), amber)
    drawStar(80,  NSPoint(x: 620, y: 910), amber)

// V3 清理火花·青绿：teal 渐变 + sparkles 主体（"焕新"隐喻直接）
case "sparkles":
    drawBackground(top: NSColor(calibratedRed: 0.05, green: 0.78, blue: 0.65, alpha: 1),     // #0DC7A6 亮青绿
                   bottom: NSColor(calibratedRed: 0.04, green: 0.22, blue: 0.32, alpha: 1))  // #0B3852 深青蓝
    draw(symbol("sparkles", pointSize: 540, color: white, weight: .semibold),
         centeredAt: NSPoint(x: 512, y: 470), size: 540)
    drawStar(140, NSPoint(x: 760, y: 780), amber)
    drawStar(90,  NSPoint(x: 290, y: 760), amber)

// V4 魔法棒·焕新：紫色渐变 + 白色魔法棒 + 大金星
case "wand":
    drawBackground(top: NSColor(calibratedRed: 0.75, green: 0.36, blue: 0.95, alpha: 1),     // #BF5AF2
                   bottom: NSColor(calibratedRed: 0.18, green: 0.04, blue: 0.35, alpha: 1))  // #2E0A5A
    draw(symbol("wand.and.stars", pointSize: 460, color: white), centeredAt: NSPoint(x: 500, y: 400), size: 460)
    drawStar(170, NSPoint(x: 730, y: 770), amber)
    drawStar(110, NSPoint(x: 320, y: 730), amber)

// V4 盾牌·深蓝：苹果深蓝渐变 + 白色盾牌+勾（"安全清理"隐喻）
case "shield":
    drawBackground(top: NSColor(calibratedRed: 0.10, green: 0.40, blue: 0.82, alpha: 1),     // #1A66D1 苹果蓝
                   bottom: NSColor(calibratedRed: 0.04, green: 0.13, blue: 0.32, alpha: 1))  // #0A2152 深蓝
    draw(symbol("checkmark.shield.fill", pointSize: 500, color: white),
         centeredAt: NSPoint(x: 512, y: 430), size: 500)
    drawStar(150, NSPoint(x: 760, y: 770), amber)
    drawStar(100, NSPoint(x: 300, y: 740), amber)
    drawStar(80,  NSPoint(x: 620, y: 910), amber)

// V5 火花·粉：苹果粉紫渐变 + sparkles 主体（"焕新"多彩版本）
case "sparkles-pink":
    drawBackground(top: NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.55, alpha: 1),     // #FF388C 苹果粉
                   bottom: NSColor(calibratedRed: 0.45, green: 0.06, blue: 0.30, alpha: 1))  // #73104C 深紫
    draw(symbol("sparkles", pointSize: 540, color: white, weight: .semibold),
         centeredAt: NSPoint(x: 512, y: 470), size: 540)
    drawStar(140, NSPoint(x: 760, y: 780), amber)
    drawStar(90,  NSPoint(x: 290, y: 760), amber)

default:
    print("未知 variant: \(variant)")
    exit(1)
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("保存失败")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
print("已生成 \(outPath) (\(variant))")