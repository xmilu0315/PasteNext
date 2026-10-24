#!/usr/bin/env swift
// Renders a proof of the PasteNext DMG window exactly as Finder would draw it:
// the background artwork plus the icons placed at the coordinates stored in
// the volume's .DS_Store, wrapped in a macOS window chrome.
//
// This is used to verify the layout without having to open the disk image.
//
// Usage: swift scripts/dmg/verify-layout.swift <project-root> <volume-dir>
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let volume = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "")
let bgURL = root.appendingPathComponent("Resources/dmg-background.png")
let iconURL = root.appendingPathComponent("Resources/AppIcon-1024.png")
let outURL = root.appendingPathComponent(".build/dmg-layout-proof.png")

guard let bg = NSImage(contentsOf: bgURL) else { exit(1) }
let W = bg.size.width
let H = bg.size.height

// ---- read the icon positions back from the built .DS_Store ---------------

struct IconPos { let name: String; let x: CGFloat; let y: CGFloat }

// The icon positions are supplied by scripts/dmg/dump-ds-store.py, which
// parses the binary .DS_Store that the node helper wrote.
struct IconList: Decodable {
    struct Entry: Decodable { let name: String; let x: Double; let y: Double }
    let icons: [Entry]
}

let icons: [IconPos] = {
    // The .DS_Store is parsed by scripts/dmg/dump-ds-store.py, which prints JSON.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [root.appendingPathComponent("scripts/dmg/dump-ds-store.py").path, volume.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard let list = try? JSONDecoder().decode(IconList.self, from: data) else { return [] }
    return list.icons.map { IconPos(name: $0.name, x: CGFloat($0.x), y: CGFloat($0.y)) }
}()

// ---- render ---------------------------------------------------------------

let TITLE_BAR: CGFloat = 22
let scale: CGFloat = 2
let canvasW = W
let canvasH = H + TITLE_BAR

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasW * scale), pixelsHigh: Int(canvasH * scale),
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: canvasW, height: canvasH)
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx

// window background
NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: canvasW, height: canvasH).fill()

// the artwork fills the content area (below the title bar)
bg.draw(in: CGRect(x: 0, y: 0, width: W, height: H))

// title bar
let bar = CGRect(x: 0, y: H, width: canvasW, height: TITLE_BAR)
NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
bar.fill()
for (i, color) in [NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
                    NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.18, alpha: 1),
                    NSColor(calibratedRed: 0.19, green: 0.78, blue: 0.35, alpha: 1)].enumerated() {
    color.setFill()
    NSBezierPath(ovalIn: CGRect(x: 14 + CGFloat(i) * 18, y: H + 6, width: 10, height: 10)).fill()
}

// ---- draw the icons at the stored positions -------------------------------

func drawIcon(at centre: CGPoint, isApp: Bool) {
    let size: CGFloat = 96
    // The artwork occupies the canvas from y=0 up to H, and Iloc is measured
    // from the window's bottom edge, which is the canvas' bottom edge.
    let r = CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
    if isApp, let icon = NSImage(contentsOf: iconURL) {
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 22, yRadius: 22).addClip()
        icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()
    } else {
        // the Applications folder
        NSColor(calibratedRed: 0.36, green: 0.62, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).fill()
        let tab = NSBezierPath(roundedRect: CGRect(x: r.minX + 6, y: r.maxY - 6, width: 46, height: 20), xRadius: 6, yRadius: 6)
        NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.90, alpha: 1).setFill()
        tab.fill()
    }
}

for icon in icons {
    // Iloc y is measured from the window's bottom-left.
    let centreFromBottom = icon.y
    let centre = CGPoint(x: icon.x, y: centreFromBottom)
    // The app sits on the left half of the window, the Applications alias
    // on the right half.
    let isApp = icon.x < W / 2
    drawIcon(at: centre, isApp: isApp)
    // caption below the icon
    let label = NSAttributedString(string: isApp ? "PasteNext.app" : "Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1)
    ])
    let size = label.size()
    label.draw(at: CGPoint(x: centre.x - size.width / 2, y: centre.y - 52 - size.height))
}

ctx.flushGraphics()
if let data = rep.representation(using: .png, properties: [:]) {
    try data.write(to: outURL)
    print("layout proof: \(outURL.path) (\(icons.count) icons)")
}
