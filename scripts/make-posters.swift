#!/usr/bin/env swift
// Generates the block-style promotional posters for PasteNext.
// Reference layout language: soft gradient canvas, large bold headline,
// white rounded feature cards with colored SF Symbols, macOS window mockups.
//
// Output:
//   Marketing/posters/01-cover.png              (2560x1600, App Store)
//   Marketing/posters/02-light-and-privacy.png
//   Marketing/posters/03-keyboard.png
//   Marketing/posters/04-preview-and-edit.png
//   Marketing/posters/05-tags-and-batch.png
//   Marketing/posters/06-all-features.png
//   Marketing/posters/xianyu/x1-cover.png       (1080x1440, 3:4)
//   Marketing/posters/xianyu/x2-features.png
//   Marketing/posters/xianyu/x3-privacy.png
import AppKit
import Foundation

// MARK: - Paths

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let shotsDir = root.appendingPathComponent("Marketing/screenshots")
let outDir = root.appendingPathComponent("Marketing/posters")
let xianyuDir = outDir.appendingPathComponent("xianyu")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: xianyuDir, withIntermediateDirectories: true)
let iconURL = root.appendingPathComponent("Resources/AppIcon-1024.png")

// MARK: - Palette

let deepPurple = NSColor(calibratedRed: 0.29, green: 0.07, blue: 0.42, alpha: 1)
let deepInk = NSColor(calibratedRed: 0.08, green: 0.04, blue: 0.16, alpha: 1)
let violet = NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.95, alpha: 1)
let ink = NSColor(calibratedRed: 0.12, green: 0.11, blue: 0.17, alpha: 1)
let body = NSColor(calibratedRed: 0.41, green: 0.40, blue: 0.49, alpha: 1)
let white = NSColor.white

let cBlue = NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.98, alpha: 1)
let cGreen = NSColor(calibratedRed: 0.16, green: 0.74, blue: 0.45, alpha: 1)
let cOrange = NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.13, alpha: 1)
let cPink = NSColor(calibratedRed: 0.96, green: 0.32, blue: 0.52, alpha: 1)
let cPurple = NSColor(calibratedRed: 0.55, green: 0.33, blue: 0.96, alpha: 1)
let cTeal = NSColor(calibratedRed: 0.10, green: 0.70, blue: 0.75, alpha: 1)
let cRed = NSColor(calibratedRed: 0.94, green: 0.26, blue: 0.26, alpha: 1)

// MARK: - Fonts

let fHero = NSFont.systemFont(ofSize: 46, weight: .bold)
let fHeroSmall = NSFont.systemFont(ofSize: 40, weight: .bold)
let fSub = NSFont.systemFont(ofSize: 22, weight: .medium)
let fNote = NSFont.systemFont(ofSize: 17, weight: .regular)
let fCardTitle = NSFont.systemFont(ofSize: 22, weight: .semibold)
let fCardBody = NSFont.systemFont(ofSize: 14, weight: .regular)
let fChip = NSFont.systemFont(ofSize: 19, weight: .semibold)
let fKey = NSFont.systemFont(ofSize: 17, weight: .semibold)
let fBig = NSFont.systemFont(ofSize: 62, weight: .bold)
let fBigLabel = NSFont.systemFont(ofSize: 17, weight: .medium)
let fXHero = NSFont.systemFont(ofSize: 54, weight: .bold)
let fXSub = NSFont.systemFont(ofSize: 25, weight: .medium)
let fXCard = NSFont.systemFont(ofSize: 27, weight: .semibold)
let fXBody = NSFont.systemFont(ofSize: 18, weight: .regular)

// MARK: - Drawing helpers (top-left origin, points)

var currentRep: NSBitmapImageRep?

func makeContext(width: CGFloat, height: CGFloat, scale: CGFloat) -> NSGraphicsContext {
    canvasHeight = height
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    currentRep = rep
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    return ctx
}

/// Canvas height in points (the bitmap context is scaled by `scale`).
var canvasHeight: CGFloat = 0

/// Rect in top-left origin space.
func rectTop(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: canvasHeight - top - h, width: w, height: h)
}

func drawText(_ s: String, font: NSFont, color: NSColor,
              x: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat,
              align: NSTextAlignment = .left, spacing: CGFloat = 4) {
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.lineSpacing = spacing
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    attr.draw(with: rectTop(x, top, w, h), options: [.usesLineFragmentOrigin, .usesFontLeading])
}

func fillRound(_ rect: CGRect, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func strokeRound(_ rect: CGRect, _ radius: CGFloat, _ color: NSColor, _ width: CGFloat) {
    color.setStroke()
    let p = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    p.lineWidth = width
    p.stroke()
}

func shadowCard(_ rect: CGRect, _ radius: CGFloat, _ color: NSColor,
                blur: CGFloat = 22, dy: CGFloat = -7, alpha: CGFloat = 0.13) {
    NSGraphicsContext.current?.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: dy)
    s.set()
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
}

func symbol(_ name: String, size: CGFloat, colors: [NSColor]) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    var cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
    cfg = cfg.applying(NSImage.SymbolConfiguration(paletteColors: colors))
    return base.withSymbolConfiguration(cfg)
}

/// Draw an image inside a rounded rect, scaled to fill (aspect fill) and clipped.
func drawImageFill(_ url: URL, in rect: CGRect, radius: CGFloat, shadow: Bool = true) {
    guard let img = NSImage(contentsOf: url) else { return }
    NSGraphicsContext.current?.saveGraphicsState()
    if shadow {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.20)
        s.shadowBlurRadius = 28
        s.shadowOffset = NSSize(width: 0, height: -9)
        s.set()
    }
    let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    clip.addClip()
    // aspect fill
    let iw = img.size.width, ih = img.size.height
    let scale = max(rect.width / iw, rect.height / ih)
    let dw = iw * scale, dh = ih * scale
    img.draw(in: CGRect(x: rect.midX - dw / 2, y: rect.midY - dh / 2, width: dw, height: dh),
             from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.current?.restoreGraphicsState()
}


/// Returns a CGImage with the top `points` rows removed (the macOS menu bar
/// or the window title bar).
/// The pixel size of a screenshot after the system chrome is removed.
func shotMetrics(_ shot: URL, cropTopPx: Int) -> CGSize? {
    guard let img = NSImage(contentsOf: shot),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let cut = min(max(cropTopPx, 0), cg.height - 1)
    return CGSize(width: cg.width, height: cg.height - cut)
}

/// A screenshot card.
///
/// The whole screenshot is shown — nothing of the app's own content is ever
/// cropped away. Only the system chrome that is baked into the capture (the
/// macOS menu bar on the panel shots, the traffic lights + title bar on the
/// settings shots) is trimmed, so no window furniture shows up in the poster.
///
/// The card keeps the screenshot's own proportions, so the height depends on
/// the image; the used height is returned so the caller can lay things out.
@discardableResult
func shotCard(_ shot: URL, x: CGFloat, top: CGFloat, w: CGFloat,
              radius: CGFloat = 14, rimColor: NSColor = violet, cropTopPx: Int = 0) -> CGFloat {
    guard let img = NSImage(contentsOf: shot),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
    let cut = min(max(cropTopPx, 0), cg.height - 1)
    guard let cropped = cg.cropping(to: CGRect(x: 0, y: cut, width: cg.width, height: cg.height - cut)) else {
        return 0
    }
    // Fit the entire image: the card is exactly as tall as the screenshot.
    let scale = w / CGFloat(cropped.width)
    let h = CGFloat(cropped.height) * scale
    let frame = rectTop(x, top, w, h)

    // Soft drop shadow under the card.
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // The screenshot, in full, clipped to the card's rounded corners.
    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
    NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        .draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.current?.restoreGraphicsState()

    // A one-pixel brand rim to separate the card from the poster background.
    strokeRound(frame, radius, rimColor.withAlphaComponent(0.28), 1.2)
    return h
}

/// A settings-window screenshot, drawn with the same treatment as `shotCard`.
@discardableResult
func shotWindow(_ shot: URL, x: CGFloat, top: CGFloat, w: CGFloat,
                radius: CGFloat = 12, rimColor: NSColor = violet, cropTopPx: Int = 0) -> CGFloat {
    shotCard(shot, x: x, top: top, w: w, radius: radius, rimColor: rimColor, cropTopPx: cropTopPx)
}

/// Feature card: rounded white surface, colored symbol, title, body text.
func featureCard(x: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat,
                 icon: String, iconColors: [NSColor], title: String, bodyText: String,
                 surface: NSColor = .white, titleColor: NSColor = ink, bodyColor: NSColor = body,
                 iconSize: CGFloat = 30) {
    let rect = rectTop(x, top, w, h)
    shadowCard(rect, 18, surface, blur: 20, dy: -6, alpha: 0.10)
    if let ic = symbol(icon, size: iconSize, colors: iconColors) {
        ic.draw(in: rectTop(x + 24, top + 24, iconSize + 4, iconSize + 4))
    }
    drawText(title, font: fCardTitle, color: titleColor,
             x: x + 24, top: top + 24 + iconSize + 14, w: w - 48, h: 30)
    drawText(bodyText, font: fCardBody, color: bodyColor,
             x: x + 24, top: top + 24 + iconSize + 48, w: w - 48, h: h - (24 + iconSize + 48) - 14, spacing: 3)
}

/// Rounded pill chip with a label.
func chip(_ text: String, font: NSFont, x: CGFloat, top: CGFloat, padX: CGFloat = 18,
          h: CGFloat = 38, fill: NSColor, textColor: NSColor) -> CGFloat {
    let attr = NSAttributedString(string: text, attributes: [.font: font])
    let w = ceil(attr.size().width) + padX * 2
    let rect = rectTop(x, top, w, h)
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2).fill()
    drawText(text, font: font, color: textColor, x: x, top: top, w: w, h: h, align: .center)
    return x + w
}

/// Keyboard key cap.
func keyCap(_ text: String, x: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat = 30) {
    let rect = rectTop(x, top, w, h)
    NSGraphicsContext.current?.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(0.16)
    s.shadowBlurRadius = 4
    s.shadowOffset = NSSize(width: 0, height: -1.5)
    s.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    strokeRound(rect, 6, NSColor.black.withAlphaComponent(0.16), 1)
    drawText(text, font: fKey, color: ink, x: x, top: top, w: w, h: h, align: .center)
}

/// Soft radial glow used to lift dark canvases.
func glow(_ rect: CGRect, color: NSColor) {
    if let g = NSGradient(starting: color, ending: color.withAlphaComponent(0)) {
        g.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: NSPoint(x: 0.5, y: 0.5))
    }
}

/// Linear gradient background.
func gradient(_ rect: CGRect, colors: [NSColor], angle: CGFloat) {
    NSGradient(colors: colors)?.draw(in: rect, angle: angle)
}

/// Save the current context to a PNG.
func save(_ ctx: NSGraphicsContext, to url: URL, width: CGFloat, height: CGFloat, scale: CGFloat) {
    ctx.flushGraphics()
    guard let rep = currentRep, let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
    print("poster: \(url.lastPathComponent) (\(Int(width * scale))×\(Int(height * scale)))")
}

// MARK: - Shared content

/// Height in pixels of the macOS menu bar baked into the panel screenshots.
let MENU_BAR_PX = 68
/// Height in pixels of the traffic lights + title bar in the settings screenshots.
let TITLE_BAR_PX = 56

struct Feature {
    let icon: String
    let colors: [NSColor]
    let title: String
    let body: String
}

let sellPoints: [Feature] = [
    Feature(icon: "macwindow", colors: [cBlue], title: "macOS 27 原生",
            body: "以 macOS 27 SDK 构建，全面适配最新系统与深色模式"),
    Feature(icon: "memorychip", colors: [cGreen], title: "轻量 · 极低占用",
            body: "常驻内存实测约 28MB，轮询式监听几乎不占 CPU"),
    Feature(icon: "lock.open", colors: [cPurple], title: "不加密 · 纯本地",
            body: "不设密码、不上云、不联网，明文存本机，想查就查"),
    Feature(icon: "heart", colors: [cOrange], title: "一次捐赠 · 永久使用",
            body: "一次捐赠即永久使用，没有订阅、没有到期、没有功能阉割"),
    Feature(icon: "keyboard", colors: [cTeal], title: "全键盘操作",
            body: "全局热键唤出，回车即贴，⇧回车贴路径，全程不碰鼠标"),
    Feature(icon: "folder", colors: [cPink], title: "全格式文件",
            body: "任意格式文件原样复制粘贴，绝不变成奇怪的缩略图")
]

let coreFeatures: [Feature] = [
    Feature(icon: "wand.and.rays", colors: [cBlue], title: "智能分类",
            body: "文本 / 代码 / 链接 / 颜色 / 图片 / 文件 六类自动识别"),
    Feature(icon: "bolt.fill", colors: [cOrange], title: "秒级回取",
            body: "回车或双击直接粘贴，⇧回车粘贴纯文本或文件路径"),
    Feature(icon: "square.stack.3d.up", colors: [cPurple], title: "批量整理",
            body: "⌘ 点选、⇧ 连选，一次完成删除、置顶、归档与排序"),
    Feature(icon: "tag.fill", colors: [cPink], title: "标签分类",
            body: "自定义标签页签，可拖拽归类，右键重命名或删除"),
    Feature(icon: "eye", colors: [cTeal], title: "预览编辑",
            body: "空格快速预览，右键即可编辑原文再粘贴"),
    Feature(icon: "lock.shield", colors: [cGreen], title: "隐私优先",
            body: "密码管理器内容永不捕获，历史全存本机不外传")
]

let gridFeatures: [Feature] = [
    Feature(icon: "wand.and.rays", colors: [cBlue], title: "智能分类", body: "六类内容自动识别"),
    Feature(icon: "keyboard", colors: [cTeal], title: "全键盘控制", body: "全局热键一键唤出"),
    Feature(icon: "bolt.fill", colors: [cOrange], title: "秒级回取", body: "回车即贴不打断思路"),
    Feature(icon: "tag.fill", colors: [cPink], title: "智能标签", body: "自定义页签拖拽归类"),
    Feature(icon: "eye", colors: [cPurple], title: "预览编辑", body: "空格预览右键改写"),
    Feature(icon: "square.stack.3d.up", colors: [cBlue], title: "批量整理", body: "多选后批量操作"),
    Feature(icon: "folder", colors: [cGreen], title: "文件原样粘贴", body: "任意格式都还原"),
    Feature(icon: "tray.full", colors: [cOrange], title: "自定义排除", body: "拖入 .app 即屏蔽")
]

let shortcuts: [(String, String)] = [
    ("⌃V", "唤出剪贴板面板"),
    ("↵", "粘贴选中内容"),
    ("⇧↵", "粘贴纯文本 / 文件路径"),
    ("↑ ↓", "选择上一条 / 下一条"),
    ("⌘←→", "切换标签页"),
    ("Space", "快速预览"),
    ("⌘F", "搜索历史"),
    ("⌘P", "置顶 / 取消常驻"),
    ("⌘↑↓", "上移 / 下移排序"),
    ("⌘⌫", "删除选中内容")
]

// MARK: - Poster 01 · Cover (selling points)

func posterCover(width: CGFloat, height: CGFloat, scale: CGFloat, to url: URL) {
    let ctx = makeContext(width: width, height: height, scale: scale)
    gradient(rectTop(0, 0, width, height), colors: [
        NSColor(calibratedRed: 0.97, green: 0.94, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.94, green: 0.92, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.90, green: 0.94, blue: 1.0, alpha: 1)
    ], angle: 20)

    let M: CGFloat = 60
    let contentW = width - M * 2

    // Brand lockup: icon + wordmark, centred as one horizontal group.
    let iconSize: CGFloat = 92
    let wordmark = "PasteNext"
    let wmFont = NSFont.systemFont(ofSize: 38, weight: .bold)
    let wmW = ceil((wordmark as NSString).size(withAttributes: [.font: wmFont]).width)
    let groupW = iconSize + 22 + wmW
    let groupX = (width - groupW) / 2
    drawImageFill(iconURL, in: rectTop(groupX, 46, iconSize, iconSize), radius: 21)
    drawText(wordmark, font: wmFont, color: ink,
             x: groupX + iconSize + 22, top: 46 + (iconSize - 48) / 2, w: wmW + 4, h: 48)

    drawText("比 Paste 和 PasteNow 更先进的剪贴板管理器",
             font: fHero, color: ink, x: M, top: 172, w: contentW, h: 62, align: .center)
    drawText("原生 macOS 27  ·  轻量极低占用  ·  不加密  ·  一次捐赠永久使用",
             font: fSub, color: body, x: M, top: 240, w: contentW, h: 34, align: .center)

    // Left: panel mockup
    shotCard(shotsDir.appendingPathComponent("01-main-panel.jpg"),
             x: 84, top: 292, w: 268, cropTopPx: MENU_BAR_PX)

    // Right: 2x3 selling-point cards
    let gridX: CGFloat = 440
    let cardW = (width - gridX - M - 22) / 2
    let cardH: CGFloat = 144
    for (i, f) in sellPoints.enumerated() {
        let col = i % 2, row = i / 2
        let x = gridX + CGFloat(col) * (cardW + 22)
        let top = 300 + CGFloat(row) * (cardH + 18)
        featureCard(x: x, top: top, w: cardW, h: cardH,
                    icon: f.icon, iconColors: f.colors, title: f.title, bodyText: f.body,
                    iconSize: 26)
    }

    save(ctx, to: url, width: width, height: height, scale: scale)
}

// MARK: - Poster 02 · Light & privacy (dark canvas)

func posterPrivacy(width: CGFloat, height: CGFloat, scale: CGFloat, to url: URL) {
    let ctx = makeContext(width: width, height: height, scale: scale)
    gradient(rectTop(0, 0, width, height), colors: [deepPurple, deepInk], angle: -60)
    glow(rectTop(-220, -280, width + 440, 720), color: violet.withAlphaComponent(0.40))
    glow(rectTop(width - 520, height - 460, 700, 700), color: NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.55, alpha: 1).withAlphaComponent(0.26))

    let M: CGFloat = 60
    let contentW = width - M * 2

    drawText("轻量 · 极低占用 · 不加密",
             font: fHero, color: .white, x: M, top: 72, w: contentW, h: 62, align: .center)
    drawText("不订阅、不联网、不加密 —— 剪贴板历史就该属于你自己",
             font: fSub, color: NSColor.white.withAlphaComponent(0.78), x: M, top: 138, w: contentW, h: 34, align: .center)

    // Three big metric cards
    let cardW = (contentW - 2 * 28) / 3
    let cardTop: CGFloat = 210
    let cardH: CGFloat = 250
    let metrics: [(String, String, String, NSColor, String)] = [
        ("28", "MB", "常驻内存实测\n后台几乎不占 CPU", cGreen, "memorychip"),
        ("0", "次", "后台网络请求\n不上云、不上传", cBlue, "globe"),
        ("1", "次", "买断价格\n永久使用无到期", cOrange, "creditcard")
    ]
    for (i, m) in metrics.enumerated() {
        let x = M + CGFloat(i) * (cardW + 28)
        let rect = rectTop(x, cardTop, cardW, cardH)
        shadowCard(rect, 22, NSColor.white.withAlphaComponent(0.96), blur: 26, dy: -8, alpha: 0.20)
        if let ic = symbol(m.4, size: 30, colors: [m.3]) {
            ic.draw(in: rectTop(x + 26, cardTop + 24, 34, 34))
        }
        let numFont = NSFont.systemFont(ofSize: 62, weight: .bold)
        drawText(m.0, font: numFont, color: ink, x: x + 26, top: cardTop + 62, w: 120, h: 72)
        drawText(m.1, font: NSFont.systemFont(ofSize: 26, weight: .semibold), color: m.3,
                 x: x + 26 + ceil(m.0 == "0" ? 42 : 74), top: cardTop + 96, w: 120, h: 34)
        drawText(m.2, font: fNote, color: body, x: x + 26, top: cardTop + 150, w: cardW - 52, h: 76, spacing: 5)
    }

    // Bottom comparison strip
    let stripTop = cardTop + cardH + 30
    let stripRect = rectTop(M, stripTop, contentW, 208)
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: stripRect, xRadius: 18, yRadius: 18).fill()
    NSColor.white.withAlphaComponent(0.18).setStroke()
    let bp = NSBezierPath(roundedRect: stripRect, xRadius: 18, yRadius: 18)
    bp.lineWidth = 1
    bp.stroke()

    let rows: [(String, String)] = [
        ("不设密码、不加密历史", "想查就查，数据只在你自己的硬盘上"),
        ("可逐个排除敏感应用", "把 .app 拖进设置即可跳过它"),
        ("密码管理器内容永不捕获", "1Password / KeeWeb 等标记自动跳过")
    ]
    for (i, r) in rows.enumerated() {
        let y = stripTop + 30 + CGFloat(i) * 52
        if let ic = symbol("checkmark.seal.fill", size: 20, colors: [cGreen]) {
            ic.draw(in: rectTop(M + 30, y + 2, 24, 24))
        }
        drawText(r.0, font: NSFont.systemFont(ofSize: 20, weight: .semibold), color: .white,
                 x: M + 66, top: y, w: 340, h: 30)
        drawText(r.1, font: NSFont.systemFont(ofSize: 17, weight: .regular),
                 color: NSColor.white.withAlphaComponent(0.62),
                 x: M + 406, top: y + 3, w: contentW - 436, h: 28)
    }

    // Footer
    drawText("一次捐赠 · 永久使用 · 无订阅 · 作者 xmilu0315@foxmail.com",
             font: NSFont.systemFont(ofSize: 17, weight: .medium),
             color: NSColor.white.withAlphaComponent(0.56),
             x: M, top: height - 66, w: contentW, h: 28, align: .center)

    save(ctx, to: url, width: width, height: height, scale: scale)
}

// MARK: - Poster 03 · Keyboard control

func posterKeyboard(width: CGFloat, height: CGFloat, scale: CGFloat, to url: URL) {
    let ctx = makeContext(width: width, height: height, scale: scale)
    gradient(rectTop(0, 0, width, height), colors: [
        NSColor(calibratedRed: 0.93, green: 0.95, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.90, green: 0.93, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.99, alpha: 1)
    ], angle: -70)

    let M: CGFloat = 60
    let contentW = width - M * 2

    drawText("支持全键盘控制",
             font: fHero, color: ink, x: M, top: 70, w: contentW, h: 62, align: .center)
    drawText("自定义全局热键，让效率更高 —— 手上不用离开键盘",
             font: fSub, color: body, x: M, top: 136, w: contentW, h: 34, align: .center)

    // Left: mac window mockup
    shotWindow(shotsDir.appendingPathComponent("05-settings-shortcuts.png"),
               x: 92, top: 202, w: 520, cropTopPx: TITLE_BAR_PX)

    // Right: shortcut list card
    let listX: CGFloat = 700
    let listRect = rectTop(listX, 214, width - listX - M, 470)
    shadowCard(listRect, 22, .white, blur: 24, dy: -8, alpha: 0.12)
    drawText("键盘操作", font: NSFont.systemFont(ofSize: 24, weight: .semibold), color: ink,
             x: listX + 34, top: 246, w: 300, h: 32)

    var y: CGFloat = 296
    for (key, label) in shortcuts {
        let keyW = max(46, ceil((key as NSString).size(withAttributes: [.font: fKey]).width) + 20)
        keyCap(key, x: listX + 34, top: y, w: keyW)
        drawText(label, font: NSFont.systemFont(ofSize: 18, weight: .regular), color: body,
                 x: listX + 34 + keyW + 18, top: y + 2, w: width - listX - M - 60 - keyW, h: 28)
        y += 38
    }

    save(ctx, to: url, width: width, height: height, scale: scale)
}

// MARK: - Poster 04 · Preview & edit

func posterPreview(width: CGFloat, height: CGFloat, scale: CGFloat, to url: URL) {
    let ctx = makeContext(width: width, height: height, scale: scale)
    gradient(rectTop(0, 0, width, height), colors: [
        deepPurple,
        NSColor(calibratedRed: 0.18, green: 0.06, blue: 0.34, alpha: 1),
        deepInk
    ], angle: -90)
    glow(rectTop(width / 2 - 420, -300, 840, 720), color: violet.withAlphaComponent(0.34))

    let M: CGFloat = 60
    let contentW = width - M * 2

    drawText("预览和编辑",
             font: fHero, color: .white, x: M, top: 66, w: contentW, h: 62, align: .center)
    drawText("按空格键预览，点击右键可以对原文本进行编辑",
             font: fSub, color: NSColor.white.withAlphaComponent(0.76), x: M, top: 132, w: contentW, h: 34, align: .center)

    // Two screenshots of exactly the same size, placed side by side.
    let pairW: CGFloat = 296
    let pairTop: CGFloat = 196
    let pairGap: CGFloat = 26
    shotCard(shotsDir.appendingPathComponent("01-main-panel.jpg"),
             x: 92, top: pairTop, w: pairW, cropTopPx: MENU_BAR_PX)
    shotCard(shotsDir.appendingPathComponent("03-context-menu-text.jpg"),
             x: 92 + pairW + pairGap, top: pairTop, w: pairW, cropTopPx: MENU_BAR_PX)

    // Right: feature list
    let listX: CGFloat = 800
    let items: [(String, String, String, NSColor)] = [
        ("eye", "空格快速预览", "不用切回 App 就看内容", cTeal),
        ("pencil.tip", "右键编辑原文", "改完再粘贴，一次到位", cOrange),
        ("arrow.right.circle.fill", "回车直接粘贴", "文件卡片粘贴原文件", cBlue)
    ]
    var y: CGFloat = 236
    for (icon, title, sub, color) in items {
        let rect = rectTop(listX, y, width - listX - M, 116)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
        if let ic = symbol(icon, size: 26, colors: [color]) {
            ic.draw(in: rectTop(listX + 26, y + 26, 32, 32))
        }
        drawText(title, font: NSFont.systemFont(ofSize: 21, weight: .semibold), color: .white,
                 x: listX + 72, top: y + 24, w: width - listX - M - 96, h: 30)
        drawText(sub, font: NSFont.systemFont(ofSize: 15, weight: .regular),
                 color: NSColor.white.withAlphaComponent(0.62),
                 x: listX + 72, top: y + 58, w: width - listX - M - 96, h: 26)
        y += 132
    }

    save(ctx, to: url, width: width, height: height, scale: scale)
}

// MARK: - Poster 05 · Tags & batch

func posterTags(width: CGFloat, height: CGFloat, scale: CGFloat, to url: URL) {
    let ctx = makeContext(width: width, height: height, scale: scale)
    gradient(rectTop(0, 0, width, height), colors: [
        NSColor(calibratedRed: 0.36, green: 0.10, blue: 0.50, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.08, blue: 0.34, alpha: 1),
        deepInk
    ], angle: -90)
    glow(rectTop(-260, height - 520, 760, 760), color: violet.withAlphaComponent(0.30))

    let M: CGFloat = 60
    let contentW = width - M * 2

    drawText("标签与批量整理",
             font: fHero, color: .white, x: M, top: 66, w: contentW, h: 62, align: .center)
    drawText("⌘ 点选多张、⇧ 连选一段，成批删除、置顶或归入标签",
             font: fSub, color: NSColor.white.withAlphaComponent(0.76), x: M, top: 132, w: contentW, h: 34, align: .center)

    // Tag chips
    var cx: CGFloat = M
    let tags: [(String, NSColor)] = [("全部", NSColor.white.withAlphaComponent(0.92)),
                                    ("常用", NSColor.white.withAlphaComponent(0.20)),
                                    ("今天", NSColor.white.withAlphaComponent(0.20)),
                                    ("电话号码", NSColor.white.withAlphaComponent(0.20)),
                                    ("代码片段", NSColor.white.withAlphaComponent(0.20))]
    for (t, c) in tags {
        cx = chip(t, font: fChip, x: cx, top: 196, h: 42, fill: c,
                  textColor: c.alphaComponent > 0.5 ? ink : .white) + 14
    }

    // Left: panel screenshot showing tags
    shotCard(shotsDir.appendingPathComponent("01-main-panel.jpg"),
             x: 84, top: 262, w: 300, cropTopPx: MENU_BAR_PX)

    // Right: batch-operation cards
    let gridX: CGFloat = 470
    let cardW = (width - gridX - M - 20) / 2
    let ops: [Feature] = [
        Feature(icon: "cursorarrow.rays", colors: [cBlue], title: "⌘ 多选", body: "点一张，再点另一张，两张一起选中"),
        Feature(icon: "arrow.left.arrow.right", colors: [cTeal], title: "⇧ 连选", body: "按住 Shift 从第 3 张连选到第 5 张"),
        Feature(icon: "tray.full", colors: [cPink], title: "批量删除", body: "选中后按 ⌘⌫ 一次清空"),
        Feature(icon: "pin.fill", colors: [cOrange], title: "批量置顶", body: "重要内容一次性锁定在顶部")
    ]
    for (i, f) in ops.enumerated() {
        let col = i % 2, row = i / 2
        featureCard(x: gridX + CGFloat(col) * (cardW + 20), top: 268 + CGFloat(row) * 160,
                    w: cardW, h: 142, icon: f.icon, iconColors: f.colors,
                    title: f.title, bodyText: f.body, iconSize: 26)
    }

    // Bottom: tag management note
    let noteTop: CGFloat = 268 + 2 * 160 + 8
    let noteRect = rectTop(gridX, noteTop, width - gridX - M, 84)
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: noteRect, xRadius: 16, yRadius: 16).fill()
    drawText("标签页签可右键重命名或删除，拖动卡片即可归类到任意标签",
             font: NSFont.systemFont(ofSize: 17, weight: .medium),
             color: NSColor.white.withAlphaComponent(0.82),
             x: gridX + 26, top: noteTop + 26, w: width - gridX - M - 52, h: 30)

    save(ctx, to: url, width: width, height: height, scale: scale)
}

// MARK: - Poster 06 · Feature grid

func posterGrid(width: CGFloat, height: CGFloat, scale: CGFloat, to url: URL) {
    let ctx = makeContext(width: width, height: height, scale: scale)
    gradient(rectTop(0, 0, width, height), colors: [
        NSColor(calibratedRed: 0.30, green: 0.08, blue: 0.44, alpha: 1),
        NSColor(calibratedRed: 0.14, green: 0.07, blue: 0.30, alpha: 1),
        deepInk
    ], angle: -90)
    glow(rectTop(width / 2 - 500, -340, 1000, 780), color: violet.withAlphaComponent(0.30))

    let M: CGFloat = 60
    let contentW = width - M * 2

    drawText("十余项功能，待你探索",
             font: fHero, color: .white, x: M, top: 62, w: contentW, h: 62, align: .center)
    drawText("更多实用功能，持续更新中……",
             font: fSub, color: NSColor.white.withAlphaComponent(0.74), x: M, top: 128, w: contentW, h: 34, align: .center)

    let cols = 3
    let cardW = (contentW - CGFloat(cols - 1) * 22) / CGFloat(cols)
    let cardH: CGFloat = 140
    let gridTop: CGFloat = 196
    // The middle slot of the last row is the brand tile (mirrors the reference layout).
    let brandSlot = 4
    for (i, f) in gridFeatures.enumerated() {
        let col = i % cols, row = i / cols
        let x = M + CGFloat(col) * (cardW + 22)
        let top = gridTop + CGFloat(row) * (cardH + 20)
        let rect = rectTop(x, top, cardW, cardH)
        shadowCard(rect, 18, NSColor.white.withAlphaComponent(0.95), blur: 20, dy: -6, alpha: 0.16)
        if let ic = symbol(f.icon, size: 26, colors: f.colors) {
            ic.draw(in: rectTop(x + 24, top + 22, 32, 32))
        }
        drawText(f.title, font: NSFont.systemFont(ofSize: 20, weight: .semibold), color: ink,
                 x: x + 24, top: top + 60, w: cardW - 48, h: 30)
        drawText(f.body, font: fCardBody, color: body,
                 x: x + 24, top: top + 94, w: cardW - 48, h: 40, spacing: 3)
    }

    // Brand tile in the middle of the grid
    let brandCol = brandSlot % cols, brandRow = brandSlot / cols
    let bx = M + CGFloat(brandCol) * (cardW + 22)
    let bTop = gridTop + CGFloat(brandRow) * (cardH + 20)
    let brandRect = rectTop(bx, bTop, cardW, cardH)
    let bg = NSGradient(colors: [NSColor(calibratedRed: 0.72, green: 0.86, blue: 1.0, alpha: 1),
                                 NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.94, alpha: 1)])!
    bg.draw(in: brandRect, angle: 0)
    drawText("PasteNext", font: NSFont.systemFont(ofSize: 32, weight: .bold),
             color: NSColor(calibratedRed: 0.22, green: 0.20, blue: 0.34, alpha: 1),
             x: bx, top: bTop + 40, w: cardW, h: 42, align: .center)
    drawText("粘贴，就该这么简单",
             font: NSFont.systemFont(ofSize: 15, weight: .medium),
             color: NSColor(calibratedRed: 0.35, green: 0.33, blue: 0.48, alpha: 1),
             x: bx, top: bTop + 88, w: cardW, h: 26, align: .center)

    // Footer chips
    var cx: CGFloat = (width - 520) / 2
    for t in ["原生 macOS 27", "零第三方依赖", "一次捐赠永久使用"] {
        cx = chip(t, font: fChip, x: cx, top: height - 76, h: 40,
                  fill: NSColor.white.withAlphaComponent(0.14),
                  textColor: NSColor.white.withAlphaComponent(0.88)) + 14
    }

    save(ctx, to: url, width: width, height: height, scale: scale)
}

// MARK: - Xianyu vertical posters (3:4)

func xianyuCover(width: CGFloat, height: CGFloat, scale: CGFloat, to url: URL) {
    let ctx = makeContext(width: width, height: height, scale: scale)
    gradient(rectTop(0, 0, width, height), colors: [
        NSColor(calibratedRed: 0.97, green: 0.94, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.93, green: 0.92, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.90, green: 0.94, blue: 1.0, alpha: 1)
    ], angle: 20)

    let M: CGFloat = 54
    let contentW = width - M * 2

    let iconSize: CGFloat = 150
    drawImageFill(iconURL, in: rectTop((width - iconSize) / 2, 74, iconSize, iconSize), radius: 34)
    drawText("PasteNext", font: fXHero, color: ink, x: M, top: 246, w: contentW, h: 62, align: .center)
    drawText("比 Paste 和 PasteNow 更先进的剪贴板管理器",
             font: NSFont.systemFont(ofSize: 30, weight: .semibold), color: body,
             x: M, top: 316, w: contentW, h: 76, align: .center, spacing: 6)

    // badges
    var bx: CGFloat = 0
    let badges = ["macOS 27", "轻量低占用", "不加密", "一次捐赠"]
    let totalBadgeW: CGFloat = badges.reduce(0.0) { acc, _ in acc + 150 }
    bx = (width - totalBadgeW) / 2
    for b in badges {
        bx = chip(b, font: NSFont.systemFont(ofSize: 18, weight: .semibold), x: bx, top: 404, h: 42,
                  fill: NSColor.white.withAlphaComponent(0.75), textColor: body) + 10
    }

    // panel screenshot — scaled to fit the space that is left for it
    let shotTop: CGFloat = 468
    let shotH = shotCard(shotsDir.appendingPathComponent("01-main-panel.jpg"),
                         x: (width - 258) / 2, top: shotTop, w: 258, cropTopPx: MENU_BAR_PX)

    // selling points
    let spTop: CGFloat = shotTop + shotH + 26
    for (i, f) in sellPoints.enumerated() {
        let col = i % 2, row = i / 2
        let cardW = (contentW - 20) / 2
        featureCard(x: M + CGFloat(col) * (cardW + 20), top: spTop + CGFloat(row) * 140,
                    w: cardW, h: 126, icon: f.icon, iconColors: f.colors,
                    title: f.title, bodyText: f.body, iconSize: 24)
    }

    let footTop: CGFloat = spTop + 3 * 140 + 4
    let footRect = rectTop(M, footTop, contentW, height - footTop - 36)
    NSColor.white.withAlphaComponent(0.72).setFill()
    NSBezierPath(roundedRect: footRect, xRadius: 18, yRadius: 18).fill()
    drawText("一次捐赠 · 永久使用 · 无订阅",
             font: NSFont.systemFont(ofSize: 23, weight: .bold), color: ink,
             x: M, top: footTop + 16, w: contentW, h: 32, align: .center)
    drawText("全部分享仅存本机 · 不加密 · 不联网 · Apple Silicon / Intel 通用",
             font: NSFont.systemFont(ofSize: 15, weight: .regular), color: body,
             x: M, top: footTop + 52, w: contentW, h: 26, align: .center)

    save(ctx, to: url, width: width, height: height, scale: scale)
}

func xianyuFeatures(width: CGFloat, height: CGFloat, scale: CGFloat, to url: URL) {
    let ctx = makeContext(width: width, height: height, scale: scale)
    gradient(rectTop(0, 0, width, height), colors: [deepPurple, deepInk], angle: -90)
    glow(rectTop(-200, -240, width + 400, 640), color: violet.withAlphaComponent(0.38))

    let M: CGFloat = 54
    let contentW = width - M * 2

    drawText("十余项功能，待你探索",
             font: fXHero, color: .white, x: M, top: 76, w: contentW, h: 64, align: .center)
    drawText("更多实用功能，持续更新中……",
             font: fXSub, color: NSColor.white.withAlphaComponent(0.74), x: M, top: 150, w: contentW, h: 36, align: .center)

    let cardW = (contentW - 20) / 2
    for (i, f) in gridFeatures.enumerated() {
        let col = i % 2, row = i / 2
        let rect = rectTop(M + CGFloat(col) * (cardW + 20), 226 + CGFloat(row) * 224, cardW, 200)
        shadowCard(rect, 18, NSColor.white.withAlphaComponent(0.96), blur: 18, dy: -6, alpha: 0.18)
        if let ic = symbol(f.icon, size: 28, colors: f.colors) {
            ic.draw(in: rectTop(M + CGFloat(col) * (cardW + 20) + 24, 226 + CGFloat(row) * 224 + 26, 36, 36))
        }
        drawText(f.title, font: fXCard, color: ink,
                 x: M + CGFloat(col) * (cardW + 20) + 24, top: 226 + CGFloat(row) * 224 + 78, w: cardW - 48, h: 38)
        drawText(f.body, font: fXBody, color: body,
                 x: M + CGFloat(col) * (cardW + 20) + 24, top: 226 + CGFloat(row) * 224 + 124, w: cardW - 48, h: 52, spacing: 3)
    }

    // Brand tile in the middle of the grid
    let brandCol = 1, brandRow = 2
    let bx = M + CGFloat(brandCol) * (cardW + 20)
    let bTop = 226 + CGFloat(brandRow) * 224
    let brandRect = rectTop(bx, bTop, cardW, 200)
    let bg = NSGradient(colors: [NSColor(calibratedRed: 0.72, green: 0.86, blue: 1.0, alpha: 1),
                                 NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.94, alpha: 1)])!
    bg.draw(in: brandRect, angle: 0)
    drawText("PasteNext", font: NSFont.systemFont(ofSize: 36, weight: .bold),
             color: NSColor(calibratedRed: 0.22, green: 0.20, blue: 0.34, alpha: 1),
             x: bx, top: bTop + 58, w: cardW, h: 48, align: .center)
    drawText("粘贴，就该这么简单",
             font: NSFont.systemFont(ofSize: 17, weight: .medium),
             color: NSColor(calibratedRed: 0.35, green: 0.33, blue: 0.48, alpha: 1),
             x: bx, top: bTop + 116, w: cardW, h: 30, align: .center)

    let footTop: CGFloat = 226 + 4 * 224 + 18
    let footRect = rectTop(M, footTop, contentW, 132)
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: footRect, xRadius: 18, yRadius: 18).fill()
    drawText("全键盘控制 · 智能分类 · 批量整理 · 标签管理",
             font: NSFont.systemFont(ofSize: 22, weight: .semibold), color: .white,
             x: M, top: footTop + 30, w: contentW, h: 34, align: .center)
    drawText("原生 macOS 27 应用 · 一次捐赠永久使用",
             font: NSFont.systemFont(ofSize: 18, weight: .regular),
             color: NSColor.white.withAlphaComponent(0.64),
             x: M, top: footTop + 72, w: contentW, h: 30, align: .center)

    save(ctx, to: url, width: width, height: height, scale: scale)
}

func xianyuPrivacy(width: CGFloat, height: CGFloat, scale: CGFloat, to url: URL) {
    let ctx = makeContext(width: width, height: height, scale: scale)
    gradient(rectTop(0, 0, width, height), colors: [
        NSColor(calibratedRed: 0.97, green: 0.95, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.91, green: 0.94, blue: 1.0, alpha: 1)
    ], angle: 20)

    let M: CGFloat = 54
    let contentW = width - M * 2

    drawText("轻量 · 不加密 · 纯本地",
             font: fXHero, color: ink, x: M, top: 76, w: contentW, h: 64, align: .center)
    drawText("剪贴板历史就该属于你自己",
             font: fXSub, color: body, x: M, top: 150, w: contentW, h: 36, align: .center)

    let cardW = (contentW - 20) / 2
    let metrics: [(String, String, String, NSColor, String)] = [
        ("28", "MB", "常驻内存实测", cGreen, "memorychip"),
        ("0", "次", "后台网络请求", cBlue, "globe")
    ]
    for (i, m) in metrics.enumerated() {
        let x = M + CGFloat(i) * (cardW + 20)
        let rect = rectTop(x, 216, cardW, 168)
        shadowCard(rect, 20, .white, blur: 20, dy: -6, alpha: 0.11)
        if let ic = symbol(m.4, size: 26, colors: [m.3]) {
            ic.draw(in: rectTop(x + 24, 238, 32, 32))
        }
        drawText(m.0, font: NSFont.systemFont(ofSize: 54, weight: .bold), color: ink,
                 x: x + 24, top: 272, w: 130, h: 64)
        drawText(m.1, font: NSFont.systemFont(ofSize: 22, weight: .semibold), color: m.3,
                 x: x + 24 + (m.0 == "0" ? 38 : 68), top: 296, w: 110, h: 32)
        drawText(m.2, font: fXBody, color: body, x: x + 24, top: 336, w: cardW - 48, h: 28)
    }

    // privacy settings screenshot
    shotWindow(shotsDir.appendingPathComponent("06-settings-privacy.png"),
               x: (width - 520) / 2, top: 396, w: 520, cropTopPx: TITLE_BAR_PX)

    let notes: [Feature] = [
        Feature(icon: "lock.open", colors: [cPurple], title: "不加密", body: "不设密码，明文存本机，想查就查"),
        Feature(icon: "hand.raised.fill", colors: [cOrange], title: "可排除应用", body: "把 .app 拖进来就跳过它"),
        Feature(icon: "lock.shield", colors: [cGreen], title: "密码管理器", body: "1Password 等标记内容永不捕获"),
        Feature(icon: "creditcard", colors: [cBlue], title: "一次买断", body: "没有订阅，没有到期，没有阉割")
    ]
    for (i, f) in notes.enumerated() {
        let col = i % 2, row = i / 2
        featureCard(x: M + CGFloat(col) * (cardW + 20), top: 976 + CGFloat(row) * 154,
                    w: cardW, h: 138, icon: f.icon, iconColors: f.colors,
                    title: f.title, bodyText: f.body, iconSize: 24)
    }

    let footTop: CGFloat = 976 + 2 * 154 + 16
    let footRect = rectTop(M, footTop, contentW, 96)
    NSColor.white.withAlphaComponent(0.72).setFill()
    NSBezierPath(roundedRect: footRect, xRadius: 16, yRadius: 16).fill()
    drawText("一次捐赠 · 永久使用 · 无订阅",
             font: NSFont.systemFont(ofSize: 23, weight: .bold), color: ink,
             x: M, top: footTop + 16, w: contentW, h: 32, align: .center)
    drawText("作者：xmilu0315@foxmail.com",
             font: NSFont.systemFont(ofSize: 17, weight: .regular), color: body,
             x: M, top: footTop + 54, w: contentW, h: 28, align: .center)

    save(ctx, to: url, width: width, height: height, scale: scale)
}

// MARK: - Run

let AW: CGFloat = 1280   // App Store landscape canvas (points)
let AH: CGFloat = 800
let SCALE: CGFloat = 2
let XW: CGFloat = 1080
let XH: CGFloat = 1440

posterCover(width: AW, height: AH, scale: SCALE, to: outDir.appendingPathComponent("01-cover.png"))
posterPrivacy(width: AW, height: AH, scale: SCALE, to: outDir.appendingPathComponent("02-light-and-privacy.png"))
posterKeyboard(width: AW, height: AH, scale: SCALE, to: outDir.appendingPathComponent("03-keyboard.png"))
posterPreview(width: AW, height: AH, scale: SCALE, to: outDir.appendingPathComponent("04-preview-and-edit.png"))
posterTags(width: AW, height: AH, scale: SCALE, to: outDir.appendingPathComponent("05-tags-and-batch.png"))
posterGrid(width: AW, height: AH, scale: SCALE, to: outDir.appendingPathComponent("06-all-features.png"))

xianyuCover(width: XW, height: XH, scale: 1, to: xianyuDir.appendingPathComponent("x1-cover.png"))
xianyuFeatures(width: XW, height: XH, scale: 1, to: xianyuDir.appendingPathComponent("x2-features.png"))
xianyuPrivacy(width: XW, height: XH, scale: 1, to: xianyuDir.appendingPathComponent("x3-privacy.png"))

print("done")
