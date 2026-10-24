#!/usr/bin/env swift
import AppKit
import Foundation

// Vector master for PasteNext app icon: deep indigo squircle + two white cards + forward arrow.
let size = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon-1024.png")
let iconset = output.deletingLastPathComponent().appendingPathComponent("PasteNext.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon() -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("Unable to create bitmap") }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let outer = NSRect(x: 62, y: 62, width: 900, height: 900)
    let background = NSBezierPath(roundedRect: outer, xRadius: 220, yRadius: 220)
    background.addClip()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.25, green: 0.13, blue: 0.58, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.08, blue: 0.36, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.05, blue: 0.23, alpha: 1)
    ])!
    gradient.draw(in: outer, angle: -35)

    let glow = NSBezierPath(ovalIn: NSRect(x: 90, y: 640, width: 860, height: 480))
    NSColor(calibratedRed: 0.46, green: 0.29, blue: 0.95, alpha: 0.24).setFill()
    glow.fill()

    // Back card.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.84, green: 0.84, blue: 0.90, alpha: 1).setFill()
    let back = NSBezierPath(roundedRect: NSRect(x: 252, y: 252, width: 420, height: 400), xRadius: 74, yRadius: 74)
    back.fill()

    // Front card.
    NSColor.white.setFill()
    let front = NSBezierPath(roundedRect: NSRect(x: 330, y: 330, width: 430, height: 430), xRadius: 84, yRadius: 84)
    front.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Forward arrow.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 430, y: 522))
    arrow.line(to: NSPoint(x: 580, y: 522))
    arrow.line(to: NSPoint(x: 580, y: 470))
    arrow.line(to: NSPoint(x: 690, y: 545))
    arrow.line(to: NSPoint(x: 580, y: 620))
    arrow.line(to: NSPoint(x: 580, y: 568))
    arrow.line(to: NSPoint(x: 430, y: 568))
    arrow.close()
    NSColor(calibratedRed: 0.28, green: 0.22, blue: 0.80, alpha: 1).setFill()
    arrow.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let png = drawIcon()
try png.write(to: output)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixel = base * scale
        let suffix = scale == 1 ? "" : "@2x"
        let url = iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png")
        let result = Process()
        result.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        result.arguments = ["-z", "\(pixel)", "\(pixel)", output.path, "--out", url.path]
        try result.run()
        result.waitUntilExit()
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.deletingLastPathComponent().appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(output.path)
