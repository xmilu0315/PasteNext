#!/usr/bin/env swift
// Generates the drag-and-drop guide background used inside the PasteNext DMG.
//
// Outputs:
//   Resources/dmg-background.png      640x330  (1x, the size appdmg reads)
//   Resources/dmg-background@2x.png   1280x800 (Retina companion)
//
// The artwork paints only the arrow and the captions. The app icon and the
// Applications folder are drawn by Finder itself on top of this background,
// so the picture must not duplicate them.
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let outURL = root.appendingPathComponent("Resources/dmg-background.png")

let W: CGFloat = 640
let H: CGFloat = 330

// Icon slot centres, in the background's own top-left coordinate space.
// These must match the coordinates written into the DMG's .DS_Store.
let APP_SLOT = CGPoint(x: 124, y: 100)
let APPS_SLOT = CGPoint(x: 515, y: 100)

func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: H - top - h, width: w, height: h)
}

func drawText(_ s: String, font: NSFont, color: NSColor,
              x: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat, align: NSTextAlignment = .center) {
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.lineSpacing = 3
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    attr.draw(with: rect(x, top, w, h), options: [.usesLineFragmentOrigin, .usesFontLeading])
}

/// Draws the whole artwork into the current graphics context.
func drawArtwork() {
    // Soft light gradient with a subtle violet glow.
    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.99, alpha: 1),
        NSColor(calibratedRed: 0.89, green: 0.91, blue: 0.96, alpha: 1)
    ])!
    bg.draw(in: rect(0, 0, W, H), angle: 90)

    if let glow = NSGradient(starting: NSColor(calibratedRed: 0.62, green: 0.56, blue: 0.98, alpha: 0.14),
                             ending: NSColor.clear) {
        glow.draw(in: NSBezierPath(ovalIn: rect(-140, -180, W + 280, 520)),
                  relativeCenterPosition: NSPoint(x: 0.5, y: 0.5))
    }

    // Arrow between the two icon slots.
    let arrowY = (APP_SLOT.y + APPS_SLOT.y) / 2
    let arrowX1 = APP_SLOT.x + 96
    let arrowX2 = APPS_SLOT.x - 96
    let arrowColor = NSColor(calibratedRed: 0.42, green: 0.40, blue: 0.54, alpha: 0.9)

    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: arrowX1, y: H - arrowY))
    shaft.line(to: NSPoint(x: arrowX2 - 16, y: H - arrowY))
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    arrowColor.setStroke()
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: arrowX2 - 19, y: H - arrowY + 14))
    head.line(to: NSPoint(x: arrowX2, y: H - arrowY))
    head.line(to: NSPoint(x: arrowX2 - 19, y: H - arrowY - 14))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    arrowColor.setStroke()
    head.stroke()

    // Headline + hint, placed below the icon row.
    drawText("将 PasteNext 拖到「应用程序」文件夹中完成安装",
             font: NSFont.systemFont(ofSize: 17, weight: .medium),
             color: NSColor(calibratedRed: 0.40, green: 0.39, blue: 0.52, alpha: 1),
             x: 0, top: 232, w: W, h: 26)

    drawText("首次启动后，在「系统设置 → 隐私与安全性」授予辅助功能权限即可自动粘贴",
             font: NSFont.systemFont(ofSize: 13, weight: .regular),
             color: NSColor(calibratedRed: 0.52, green: 0.51, blue: 0.62, alpha: 1),
             x: 0, top: 264, w: W, h: 22)
}

/// Renders the artwork at the given pixel scale and returns the PNG data.
func render(scale: CGFloat) -> Data? {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    // Leave rep.size in pixels so the context CTM stays 1:1, then scale the
    // drawing explicitly (setting rep.size to points would double-scale).
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    if scale != 1 {
        ctx.cgContext.scaleBy(x: scale, y: scale)
    }
    drawArtwork()
    ctx.flushGraphics()
    return rep.representation(using: .png, properties: [:])
}

// 1x — appdmg reads this file's pixel size to size the window, so it must be
// exactly 640x400 to match the declared window width/height.
if let data = render(scale: 1) {
    try data.write(to: outURL)
    print("dmg background: \(outURL.path) (\(Int(W))×\(Int(H)))")
}

// 2x — Retina companion, picked up by Finder alongside the 1x art.
if let data = render(scale: 2) {
    let out2 = outURL.deletingLastPathComponent()
        .appendingPathComponent(outURL.deletingPathExtension().lastPathComponent + "@2x.png")
    try data.write(to: out2)
    print("dmg background @2x: \(out2.path) (\(Int(W * 2))×\(Int(H * 2)))")
}
