import AppKit
import SwiftUI

struct ClipCard: View, Equatable {
    let item: ClipItem
    let selected: Bool
    let image: NSImage?
    var compact = false
    /// 1-based position in the visible list, shown as the ⌘n shortcut hint.
    var shortcutIndex: Int? = nil

    static func == (lhs: ClipCard, rhs: ClipCard) -> Bool {
        lhs.item == rhs.item && lhs.selected == rhs.selected && lhs.image === rhs.image
            && lhs.compact == rhs.compact && lhs.shortcutIndex == rhs.shortcutIndex
    }

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 9 : 12) {
            SourceIcon(item: item, size: compact ? 26 : 32)
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                HStack(spacing: 5) {
                    if item.isPinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundColor(.orange) }
                    if item.isRemote { Image(systemName: "iphone").font(.system(size: 9)).foregroundColor(.secondary) }
                    Text(item.sourceName ?? L("未知来源", "Unknown source"))
                        .font(.system(size: compact ? 10 : 11, weight: .medium)).foregroundColor(.secondary).lineLimit(1)
                    Spacer()
                    if !item.itemTags.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "tag.fill").font(.system(size: 7))
                            Text(item.itemTags.prefix(2).joined(separator: " "))
                                .font(.system(size: 8, weight: .medium)).lineLimit(1)
                        }
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05)).cornerRadius(3)
                    }
                    Text(item.createdAt.relativeDescription).font(.system(size: 9)).foregroundColor(.secondary)
                    if let shortcutIndex {
                        Text("⌘\(shortcutIndex)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(selected ? .accentColor : .secondary)
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .background((selected ? Color.accentColor : Color.primary).opacity(0.10))
                            .cornerRadius(3)
                            .help(L("按 ⌘\(shortcutIndex) 直接粘贴", "Press ⌘\(shortcutIndex) to paste"))
                    }
                }
                cardContent
            }
        }
        .padding(compact ? 10 : 13)
        .frame(maxWidth: .infinity, minHeight: compact ? 64 : 78, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color.black.opacity(0.05), lineWidth: selected ? 2 : 0.5))
        .shadow(color: .black.opacity(selected ? 0.09 : 0.035), radius: selected ? 6 : 3, y: 2)
        .padding(.vertical, 1)
    }

    @ViewBuilder private var cardContent: some View {
        // A clip can carry a picture, text and files all at once, so show every
        // part that is present instead of only the one that defined `kind`.
        VStack(alignment: .leading, spacing: 6) {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: compact ? 78 : 118, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            switch item.kind {
            case .color:
                colorSwatch
            case .files:
                filesRow
            case .image:
                // The picture could not be read back; fall back to the text that
                // came with it, and only then to a placeholder.
                if image == nil {
                    if let caption = item.captionText {
                        Text(caption).font(.system(size: compact ? 11 : 13))
                            .lineLimit(compact ? 2 : 4).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Label(L("图片不可用", "Image unavailable"), systemImage: "photo")
                    }
                }
            case .text, .link, .code:
                if let caption = item.captionText {
                    kindText(caption)
                }
            }
        }
    }

    /// The text block for the non-picture kinds, keeping each one's own look.
    @ViewBuilder private func kindText(_ text: String) -> some View {
        switch item.kind {
        case .code:
            Text(text).font(.system(size: compact ? 10 : 12, design: .monospaced)).foregroundColor(.white.opacity(0.92))
                .lineLimit(compact ? 3 : 5).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
        case .link:
            Label(item.displayTitle, systemImage: "safari").font(.system(size: compact ? 11 : 13, weight: .medium)).foregroundColor(.blue).lineLimit(2)
        default:
            Text(item.displayTitle).font(.system(size: compact ? 11 : 13))
                .lineLimit(compact ? 2 : 4).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var colorSwatch: some View {
        HStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: item.text) ?? .clear).frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.1)))
            Text(item.text).font(.system(size: 15, weight: .semibold, design: .monospaced))
        }
    }

    private var filesRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "doc.fill").font(.system(size: compact ? 15 : 17)).foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle).font(.system(size: compact ? 11 : 13, weight: .medium)).lineLimit(2)
                if let path = item.filePaths?.first {
                    Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                        .font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var background: some ShapeStyle {
        if item.kind == .code { return AnyShapeStyle(Color(red: 0.15, green: 0.17, blue: 0.21).opacity(0.94)) }
        return AnyShapeStyle(item.stableColor.opacity(0.66))
    }
}

struct SourceIcon: View {
    let item: ClipItem
    var size: CGFloat = 32
    var body: some View {
        Group {
            if item.isRemote {
                Image(systemName: "iphone").resizable().aspectRatio(contentMode: .fit).padding(8).foregroundColor(.accentColor)
            } else if let path = item.sourcePath, FileManager.default.fileExists(atPath: path) {
                Image(nsImage: AppIconCache.shared.icon(for: path)).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: item.kind.icon).resizable().aspectRatio(contentMode: .fit).padding(8).foregroundColor(.accentColor)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius: size > 28 ? 8 : 6))
    }
}

final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() { cache.countLimit = 60 }
    func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}

extension Date {
    var relativeDescription: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return L("刚刚", "Now") }
        if interval < 3600 { return "\(Int(interval / 60))\(L(" 分钟前", "m ago"))" }
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: self)
        if Calendar.current.isDateInToday(self) {
            return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        }
        return String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0)
    }
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#") else { return nil }
        value.removeFirst()
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let hasAlpha = value.count == 8
        self.init(.sRGB,
                  red: Double((number >> (hasAlpha ? 24 : 16)) & 0xff) / 255,
                  green: Double((number >> (hasAlpha ? 16 : 8)) & 0xff) / 255,
                  blue: Double((number >> (hasAlpha ? 8 : 0)) & 0xff) / 255,
                  opacity: hasAlpha ? Double(number & 0xff) / 255 : 1)
    }
}
