#!/usr/bin/env swift
// Crops the donation QR codes out of the screenshots they were saved from,
// normalises them to the same size and gives them a matching frame.
//
// The two codes come from different apps, so they differ in resolution,
// quiet zone and card style. Vision locates the QR matrix in each source
// image; the script then trims it, scales both to the same size and renders
// them on a common brand-coloured card with a caption.
//
// Usage: swift scripts/make-donation-qr.swift <project-root> <wechat.jpg> <alipay.jpg>
import AppKit
import Foundation
import Vision

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let wechatURL = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "")
let alipayURL = URL(fileURLWithPath: CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "")

let outDir = root.appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// The final tile size in points (rendered at 2x for Retina).
let TILE: CGFloat = 240
let SCALE: CGFloat = 2
let PADDING: CGFloat = 14          // inner padding around the code
let CORNER: CGFloat = 18
let PLATE_RADIUS: CGFloat = 10

// Brand colours taken from the app icon: indigo → violet.
let BRAND_TOP = NSColor(calibratedRed: 0.36, green: 0.26, blue: 0.74, alpha: 1)
let BRAND_BOTTOM = NSColor(calibratedRed: 0.17, green: 0.10, blue: 0.44, alpha: 1)

/// Finds the QR code in an image and returns its pixel rectangle.
func detectCode(_ url: URL) -> CGRect? {
    guard let image = NSImage(contentsOf: url),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    guard (try? handler.perform([request])) != nil,
          let result = request.results?.first else { return nil }
    let b = result.boundingBox
    let x = b.origin.x * CGFloat(cg.width)
    let yTop = (1 - b.origin.y - b.height) * CGFloat(cg.height)
    return CGRect(x: x, y: yTop, width: b.width * CGFloat(cg.width), height: b.height * CGFloat(cg.height))
}

/// Crops the detected code out of the source image.
func croppedCode(_ url: URL) -> NSImage? {
    guard let image = NSImage(contentsOf: url),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let rect = detectCode(url) else { return nil }
    // Vision's rect already uses the top-left origin that CGImage uses.
    guard let crop = cg.cropping(to: rect) else { return nil }
    return NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height))
}

/// Draws the code into the current context as a square of the given side
/// length, keeping the modules crisp (no interpolation smoothing).
func drawCode(_ code: NSImage, in rect: CGRect) {
    guard let cg = code.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let ctx = NSGraphicsContext.current!
    let g = ctx.cgContext
    g.saveGState()
    g.interpolationQuality = .none
    g.draw(cg, in: rect)
    g.restoreGState()
}

/// Renders the final tile: brand card, white plate, code, caption, badge.
func renderTile(code: NSImage, caption: String) -> NSImage? {
    let size = NSSize(width: TILE, height: TILE)
    let image = NSImage(size: size)
    image.lockFocus()
    let ctx = NSGraphicsContext.current!
    let cg = ctx.cgContext

    // Brand gradient card
    let rect = NSRect(x: 0, y: 0, width: TILE, height: TILE)
    let path = NSBezierPath(roundedRect: rect, xRadius: CORNER, yRadius: CORNER)
    cg.saveGState()
    path.addClip()
    let gradient = NSGradient(colors: [BRAND_TOP, BRAND_BOTTOM])!
    gradient.draw(in: rect, angle: -90)
    if let glow = NSGradient(starting: NSColor.white.withAlphaComponent(0.15), ending: NSColor.clear) {
        glow.draw(in: NSBezierPath(ovalIn: NSRect(x: -TILE * 0.4, y: TILE * 0.45, width: TILE * 1.3, height: TILE * 1.3)),
                  relativeCenterPosition: NSPoint(x: 0.5, y: 0.5))
    }
    cg.restoreGState()

    // White plate that holds the code
    let plateSide = TILE - PADDING * 2
    let plate = NSRect(x: PADDING, y: PADDING + 15, width: plateSide, height: plateSide)
    NSGraphicsContext.current?.saveGraphicsState()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: plate, xRadius: PLATE_RADIUS, yRadius: PLATE_RADIUS).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // The code inside the plate, with a quiet zone
    let quiet: CGFloat = 11
    let codeSide = plateSide - quiet * 2
    // The code is drawn with the aspect fill so the whole matrix is kept.
    let codeRect = NSRect(x: plate.minX + quiet, y: plate.minY + quiet, width: codeSide, height: codeSide)
    cg.saveGState()
    NSBezierPath(rect: codeRect).addClip()
    drawCode(code, in: codeRect)
    cg.restoreGState()

    // Caption below the plate
    let captionFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    let attr = NSAttributedString(string: caption, attributes: [
        .font: captionFont,
        .foregroundColor: NSColor.white.withAlphaComponent(0.95)
    ])
    let csize = attr.size()
    attr.draw(at: NSPoint(x: (TILE - csize.width) / 2, y: 8))

    image.unlockFocus()
    return image
}

/// Writes an NSImage as a PNG at 2x.
func writePNG(_ image: NSImage, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(image.size.width * SCALE), pixelsHigh: Int(image.size.height * SCALE),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = image.size
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    image.draw(in: NSRect(origin: .zero, size: image.size))
    ctx.flushGraphics()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
        print("donation qr: \(url.lastPathComponent) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
    }
}

guard let wechatCode = croppedCode(wechatURL),
      let alipayCode = croppedCode(alipayURL) else {
    print("error: could not find the QR codes in the source images")
    exit(1)
}

if let tile = renderTile(code: wechatCode, caption: "微信收款码 · WeChat") {
    writePNG(tile, to: outDir.appendingPathComponent("donate-wechat.png"))
}
if let tile = renderTile(code: alipayCode, caption: "支付宝收款码 · Alipay") {
    writePNG(tile, to: outDir.appendingPathComponent("donate-alipay.png"))
}
