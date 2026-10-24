#!/usr/bin/env swift
// Generates the long promotional poster for PasteNext.
// Output: Marketing/PasteNext-长图海报.png
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let shotsDir = root.appendingPathComponent("Marketing/screenshots")
let outURL = root.appendingPathComponent("Marketing/PasteNext-长图海报.png")
let iconURL = root.appendingPathComponent("Resources/AppIcon-1024.png")

// MARK: - Canvas

let W: CGFloat = 1200
let M: CGFloat = 60
let scale: CGFloat = 2

let indigo = NSColor(calibratedRed: 0.29, green: 0.16, blue: 0.66, alpha: 1)
let indigoDark = NSColor(calibratedRed: 0.10, green: 0.06, blue: 0.28, alpha: 1)
let violet = NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.92, alpha: 1)
let ink = NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.16, alpha: 1)
let sub = NSColor(calibratedRed: 0.42, green: 0.41, blue: 0.50, alpha: 1)
let page = NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
let card = NSColor.white
let hairline = NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.93, alpha: 1)

let featureRows: [(String, String, String)] = [
    ("wand.and.stars", "智能分类", "文本 / 代码 / 链接 / 颜色 / 图片 / 文件，六类自动识别，卡片样式各不相同"),
    ("keyboard", "全局热键", "⌃V 一键唤出浮窗，不打断你正在输入的浏览器或编辑器"),
    ("bolt.fill", "秒级回取", "↵ 或双击直接粘贴，⇧↵ 粘贴纯文本；文件卡片则粘贴绝对路径"),
    ("square.stack.3d.up", "批量整理", "⌘ 点选、⇧ 连选，一次完成删除、置顶、归档与排序"),
    ("tag", "标签分类", "自定义标签页签，可拖拽归类，右键重命名或删除"),
    ("lock.shield", "隐私优先", "密码管理器标记的内容永不捕获，历史全存本机、不联网")
]

struct Shot { let file: String; let title: String; let sub: String }
let mainShots = [
    Shot(file: "01-main-panel.jpg", title: "主界面", sub: "历史记录 · 分类页签 · 文件卡片"),
    Shot(file: "02-context-menu-file.jpg", title: "文件卡片右键", sub: "「粘贴为路径」「仅复制路径」"),
    Shot(file: "03-context-menu-text.jpg", title: "文本卡片右键", sub: "「粘贴为纯文本」按类型定制")
]
let settingShots = [
    Shot(file: "04-settings-general.png", title: "通用", sub: "语言、提示音、历史上限、监控间隔"),
    Shot(file: "05-settings-shortcuts.png", title: "快捷键", sub: "全局唤出与面板内操作一览"),
    Shot(file: "06-settings-privacy.png", title: "隐私与规则", sub: "拖拽 .app 即可排除应用"),
    Shot(file: "07-settings-about.png", title: "关于", sub: "版本、技术栈与作者信息")
]

// MARK: - Measure pass

func textHeight(_ s: String, font: NSFont, width: CGFloat) -> CGFloat {
    let attr = NSAttributedString(string: s, attributes: [.font: font])
    let r = attr.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin, .usesFontLeading])
    return ceil(r.height)
}

func lineHeight(_ font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) }

let fHero = NSFont.systemFont(ofSize: 76, weight: .bold)
let fTagline = NSFont.systemFont(ofSize: 30, weight: .medium)
let fSub = NSFont.systemFont(ofSize: 20, weight: .regular)
let fSection = NSFont.systemFont(ofSize: 40, weight: .bold)
let fCardTitle = NSFont.systemFont(ofSize: 23, weight: .semibold)
let fCardBody = NSFont.systemFont(ofSize: 17, weight: .regular)
let fShotTitle = NSFont.systemFont(ofSize: 21, weight: .semibold)
let fShotSub = NSFont.systemFont(ofSize: 15, weight: .regular)
let fBadge = NSFont.systemFont(ofSize: 16, weight: .medium)
let fFoot = NSFont.systemFont(ofSize: 34, weight: .semibold)
let fFootSmall = NSFont.systemFont(ofSize: 18, weight: .regular)

let contentW = W - M * 2
let mainShotW = (contentW - 60) / 3
let mainShotH = mainShotW * 1824 / 1072
let setShotW = (contentW - 40) / 2
let setShotH = setShotW * 1122 / 1220
let featureH: CGFloat = 132

// heights
let headerH: CGFloat = 606
let featTitleH: CGFloat = 104
let featRows2: CGFloat = CGFloat(featureRows.count / 2)
let featBlockH: CGFloat = featTitleH + featRows2 * (featureH + 26) + 40
let shotTitleH: CGFloat = 104
let mainBlockH: CGFloat = shotTitleH + mainShotH + 76
let setBlockH: CGFloat = shotTitleH + (setShotH + 78) * 2 + 30
let footerH: CGFloat = 330
let totalH: CGFloat = headerH + featBlockH + mainBlockH + setBlockH + footerH

// MARK: - Draw

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(totalH * scale),
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: totalH)
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
// The bitmap rep is 2× its point size, so the context CTM already gives us 2× rendering.

func Y(_ top: CGFloat) -> CGFloat { totalH - top }
func R(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: Y(top + h), width: w, height: h) }

func drawText(_ s: String, font: NSFont, color: NSColor, rect: CGRect, align: NSTextAlignment = .left, lineSpacing: CGFloat = 4) {
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.lineSpacing = lineSpacing
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    attr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

func rounded(_ rect: CGRect, radius: CGFloat, fill: NSColor, shadow: (CGFloat, CGFloat)? = nil) {
    NSGraphicsContext.current?.saveGraphicsState()
    if let (blur, dy) = shadow {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.10)
        s.shadowBlurRadius = blur
        s.shadowOffset = NSSize(width: 0, height: dy)
        s.set()
    }
    let p = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    p.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
}

func strokeRounded(_ rect: CGRect, radius: CGFloat, color: NSColor, width: CGFloat) {
    color.setStroke()
    let p = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    p.lineWidth = width
    p.stroke()
}

func drawImage(_ url: URL, in rect: CGRect, radius: CGFloat, shadow: Bool = true) {
    guard let img = NSImage(contentsOf: url) else { return }
    NSGraphicsContext.current?.saveGraphicsState()
    if shadow {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.16)
        s.shadowBlurRadius = 26
        s.shadowOffset = NSSize(width: 0, height: -8)
        s.set()
    }
    let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    clip.addClip()
    img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.current?.restoreGraphicsState()
    strokeRounded(rect, radius: radius, color: NSColor.black.withAlphaComponent(0.10), width: 1)
}

func badge(_ text: String, at x: CGFloat, top: CGFloat) -> CGFloat {
    let attr = NSAttributedString(string: text, attributes: [.font: fBadge])
    let w = ceil(attr.size().width) + 36
    let rect = R(x, top, w, 40)
    NSColor.white.withAlphaComponent(0.14).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
    drawText(text, font: fBadge, color: NSColor.white.withAlphaComponent(0.92), rect: rect, align: .center)
    return x + w + 12
}

func symbol(_ name: String, size: CGFloat, colors: [NSColor]) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    var cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
    cfg = cfg.applying(NSImage.SymbolConfiguration(paletteColors: colors))
    return base.withSymbolConfiguration(cfg)
}

// Background
page.setFill()
NSRect(x: 0, y: 0, width: W, height: totalH).fill()

// MARK: Header
let headerRect = R(0, 0, W, headerH)
let hg = NSGradient(colors: [indigo, indigoDark])!
hg.draw(in: headerRect, angle: -90)

let iconSize: CGFloat = 184
drawImage(iconURL, in: R((W - iconSize) / 2, 66, iconSize, iconSize), radius: 40, shadow: true)

drawText("PasteNext", font: fHero, color: .white, rect: R(M, 278, contentW, 96), align: .center)
drawText("原生 macOS 剪贴板历史管理器", font: fTagline, color: NSColor.white.withAlphaComponent(0.88), rect: R(M, 372, contentW, 46), align: .center)
drawText("轻量轮询 · 仅在变化时读取 · 全程本地不联网", font: fSub, color: NSColor.white.withAlphaComponent(0.68), rect: R(M, 428, contentW, 34), align: .center)

var bx = (W - 3 * 150) / 2
for b in ["macOS 13+", "SwiftUI + AppKit", "零第三方依赖"] {
    bx = badge(b, at: bx, top: 498)
}

// MARK: Features
let featTop = headerH
drawText("核心特性", font: fSection, color: ink, rect: R(M, featTop + 38, contentW, 54))
drawText("Everything you need, nothing you don't", font: fSub, color: sub, rect: R(M, featTop + 38, contentW, 54), align: .right)

for (i, feat) in featureRows.enumerated() {
    let col = i % 2, row = i / 2
    let cw = (contentW - 30) / 2
    let x = M + CGFloat(col) * (cw + 30)
    let y = featTop + featTitleH + CGFloat(row) * (featureH + 26)
    let rect = R(x, y, cw, featureH)
    rounded(rect, radius: 22, fill: card, shadow: (22, -6))
    if let ic = symbol(feat.0, size: 30, colors: [violet, indigo]) {
        ic.draw(in: R(x + 28, y + 26, 34, 34))
    }
    drawText(feat.1, font: fCardTitle, color: ink, rect: R(x + 76, y + 24, cw - 104, 36))
    drawText(feat.2, font: fCardBody, color: sub, rect: R(x + 28, y + 70, cw - 56, 56), lineSpacing: 5)
}

// MARK: Main screenshots
let mainTop = headerH + featBlockH
drawText("界面一览", font: fSection, color: ink, rect: R(M, mainTop + 38, contentW, 54))
drawText("Main interface & context menus", font: fSub, color: sub, rect: R(M, mainTop + 38, contentW, 54), align: .right)

for (i, shot) in mainShots.enumerated() {
    let x = M + CGFloat(i) * (mainShotW + 30)
    let y = mainTop + shotTitleH
    drawImage(shotsDir.appendingPathComponent(shot.file), in: R(x, y, mainShotW, mainShotH), radius: 18)
    drawText(shot.title, font: fShotTitle, color: ink, rect: R(x, y + mainShotH + 14, mainShotW, 30))
    drawText(shot.sub, font: fShotSub, color: sub, rect: R(x, y + mainShotH + 44, mainShotW, 26))
}

// MARK: Settings screenshots
let setTop = mainTop + mainBlockH
drawText("设置", font: fSection, color: ink, rect: R(M, setTop + 38, contentW, 54))
drawText("Preferences", font: fSub, color: sub, rect: R(M, setTop + 38, contentW, 54), align: .right)

for (i, shot) in settingShots.enumerated() {
    let col = i % 2, row = i / 2
    let x = M + CGFloat(col) * (setShotW + 40)
    let y = setTop + shotTitleH + CGFloat(row) * (setShotH + 78)
    drawImage(shotsDir.appendingPathComponent(shot.file), in: R(x, y, setShotW, setShotH), radius: 16)
    drawText(shot.title, font: fShotTitle, color: ink, rect: R(x, y + setShotH + 12, setShotW, 30))
    drawText(shot.sub, font: fShotSub, color: sub, rect: R(x, y + setShotH + 42, setShotW, 26))
}

// MARK: Footer
let footTop = setTop + setBlockH
let footRect = R(0, footTop, W, footerH)
NSGradient(colors: [indigoDark, NSColor(calibratedRed: 0.06, green: 0.04, blue: 0.16, alpha: 1)])!
    .draw(in: footRect, angle: -90)
drawText("把刚才复制的任何东西，随手贴回去。", font: fFoot, color: .white, rect: R(M, footTop + 64, contentW, 52), align: .center)
drawText("PasteNext 1.3.6 · macOS 13+ · SwiftUI + AppKit · 无第三方依赖", font: fFootSmall, color: NSColor.white.withAlphaComponent(0.66), rect: R(M, footTop + 132, contentW, 32), align: .center)
drawText("全部历史仅保存在本机，不联网、不上传　·　xmilu0315@foxmail.com", font: fFootSmall, color: NSColor.white.withAlphaComponent(0.52), rect: R(M, footTop + 182, contentW, 32), align: .center)

gctx.flushGraphics()
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: outURL)
print("poster: \(outURL.path) (\(Int(W * scale))×\(Int(totalH * scale)))")
