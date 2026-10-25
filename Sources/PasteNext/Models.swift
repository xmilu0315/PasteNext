import AppKit
import Foundation
import SwiftUI

enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case text, link, code, color, image, files
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .files: return "folder"
        }
    }
    var title: String {
        switch self {
        case .text: return L("文本", "Text")
        case .link: return L("链接", "Links")
        case .code: return L("代码", "Code")
        case .color: return L("颜色", "Colors")
        case .image: return L("图片", "Images")
        case .files: return L("文件", "Files")
        }
    }
}

struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ClipKind
    var text: String
    var createdAt = Date()
    var isPinned = false
    var title: String?
    var sourceBundleID: String?
    var sourceName: String?
    var sourcePath: String?
    var isRemote = false
    var imageFilename: String?
    var filePaths: [String]?
    var tags: [String]? = nil
    var sortIndex: Double? = nil
    /// Pixel size of the picture ("800×600").
    ///
    /// A picture-only clip has no text, so this is what tells two screenshots
    /// apart when de-duplicating, and what the card shows as its description.
    var imageSize: String? = nil

    var itemTags: [String] { tags ?? [] }
    var effectiveSortIndex: Double { sortIndex ?? createdAt.timeIntervalSinceReferenceDate }
    /// The text this clip carries, if any.
    ///
    /// A clipboard copy can hold a picture, text and files all at once, so this
    /// is deliberately independent of `kind`: an image+text copy reports its
    /// text here even though its primary kind is `.image`.
    var captionText: String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let caption = captionText {
            return caption.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        }
        // Picture-only clips carry no text; describe them from their size.
        if let size = imageSize { return L("图片 · ", "Image · ") + size }
        return kind.title
    }

    /// The text representation used by "paste as plain text" / "paste as path".
    /// Files resolve to their absolute path, everything else to its stored text.
    var plainTextRepresentation: String {
        if kind == .files {
            let paths = filePaths ?? []
            return paths.isEmpty ? text : paths.joined(separator: "\n")
        }
        return text
    }
    var stableColor: Color { Palette.color(for: kind) }
}

/// Card background tints, one per content type.
///
/// The colour used to be a hash of the clip's text, which looked arbitrary: two
/// similar clips got unrelated colours and the colour carried no information.
/// Keying it on the content type instead makes the list readable at a glance —
/// the tint tells you what kind of clip it is, which is the same classification
/// the app already does for icons and filtering.
enum Palette {
    /// Text is by far the most common kind, so it stays close to neutral and
    /// lets the five specialised tints stand out.
    static func color(for kind: ClipKind) -> Color {
        switch kind {
        case .text:  return Color(red: 0.965, green: 0.965, blue: 0.975)
        case .link:  return Color(red: 0.800, green: 0.890, blue: 0.980)
        case .code:  return Color(red: 0.860, green: 0.830, blue: 0.970)
        case .color: return Color(red: 0.940, green: 0.830, blue: 0.910)
        case .image: return Color(red: 0.790, green: 0.920, blue: 0.910)
        case .files: return Color(red: 0.960, green: 0.870, blue: 0.730)
        }
    }

    /// True when two kinds are meant to look different.
    static func isDistinct(_ lhs: ClipKind, _ rhs: ClipKind) -> Bool {
        color(for: lhs) != color(for: rhs)
    }
}

enum ClipClassifier {
    static func classify(_ text: String, hasImage: Bool = false, hasFiles: Bool = false) -> ClipKind {
        if hasFiles { return .files }
        if hasImage { return .image }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^#[0-9a-fA-F]{6}$|^#[0-9a-fA-F]{8}$", options: .regularExpression) != nil { return .color }
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil, !trimmed.contains("\n") { return .link }
        let codeSignals = ["func ", "class ", "struct ", "import ", "def ", "return ", "const ", "let ", "var ", "public ", "private ", "#include", "=>", "</", "{\n"]
        if trimmed.contains("\n") && codeSignals.contains(where: trimmed.contains) { return .code }
        return .text
    }
}

enum ClipCategory: String, CaseIterable, Identifiable {
    case all, pinned, today, text, link, code, image, files
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L("全部", "All")
        case .pinned: return L("置顶", "Pinned")
        case .today: return L("今天", "Today")
        default: return ClipKind(rawValue: rawValue)?.title ?? rawValue
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .pinned: return "pin"
        case .today: return "calendar"
        default: return ClipKind(rawValue: rawValue)?.icon ?? "doc"
        }
    }
    func contains(_ item: ClipItem) -> Bool {
        switch self {
        case .all: return true
        case .pinned: return item.isPinned
        case .today: return Calendar.current.isDateInToday(item.createdAt)
        default:
            guard let wanted = ClipKind(rawValue: rawValue) else { return true }
            // The primary kind always qualifies. On top of that, a clip shows up
            // under every tab whose content it actually carries, so an
            // image+text copy appears under 图片 and under 文本 alike instead of
            // only under whichever one happened to win the `kind` vote.
            if item.kind == wanted { return true }
            switch wanted {
            case .image: return item.imageFilename != nil
            case .files: return item.filePaths != nil
            case .text:  return item.captionText != nil
            case .link, .code, .color: return false
            }
        }
    }
}
