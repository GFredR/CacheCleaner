#!/usr/bin/env swift
// 渲染 1024x1024 占位 AppIcon PNG（可替换）
// 用法: swift build-icon.swift <输出路径.png>
import Foundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("用法: swift build-icon.swift <输出路径.png>")
    exit(1)
}
let outPath = args[1]

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// 圆角矩形底色（teal 渐变）
let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                          xRadius: size * 0.225, yRadius: size * 0.225)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.65, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.40, blue: 0.55, alpha: 1)
])!
gradient.draw(in: bgPath, angle: -90)

// 扫帚：手柄 + 刷头
let handle = NSBezierPath()
handle.move(to: NSPoint(x: 720, y: 760))
handle.line(to: NSPoint(x: 380, y: 420))
handle.lineWidth = 60
handle.lineCapStyle = .round
NSColor(calibratedRed: 1, green: 0.85, blue: 0.55, alpha: 1).setStroke()
handle.stroke()

// 刷头梯形（用两条线 + 横线）
let head = NSBezierPath()
head.move(to: NSPoint(x: 360, y: 410))
head.line(to: NSPoint(x: 240, y: 250))
head.move(to: NSPoint(x: 480, y: 380))
head.line(to: NSPoint(x: 360, y: 220))
head.lineWidth = 50
head.lineCapStyle = .round
NSColor.white.setStroke()
head.stroke()

// 扫出的星星（两笔交叉）
let star = NSBezierPath()
star.move(to: NSPoint(x: 180, y: 580))
star.line(to: NSPoint(x: 280, y: 680))
star.move(to: NSPoint(x: 180, y: 680))
star.line(to: NSPoint(x: 280, y: 580))
star.lineWidth = 32
star.lineCapStyle = .round
NSColor.systemYellow.setStroke()
star.stroke()

img.unlockFocus()

// 导出 PNG
let tiff = img.tiffRepresentation!
guard let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .png, properties: [:]) else {
    print("PNG 导出失败")
    exit(1)
}
try data.write(to: URL(fileURLWithPath: outPath))
print("已生成图标: \(outPath) (\(size)x\(size))")