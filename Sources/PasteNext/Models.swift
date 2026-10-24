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

    var itemTags: [String] { tags ?? [] }
    var effectiveSortIndex: Double { sortIndex ?? createdAt.timeIntervalSinceReferenceDate }
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? kind.title : clean
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
    var stableColor: Color { Palette.color(for: text) }
}

enum Palette {
    static let colors: [Color] = [
        Color(red: 0.96, green: 0.87, blue: 0.73),
        Color(red: 0.80, green: 0.89, blue: 0.98),
        Color(red: 0.84, green: 0.93, blue: 0.84),
        Color(red: 0.94, green: 0.83, blue: 0.91),
        Color(red: 0.86, green: 0.83, blue: 0.97),
        Color(red: 0.79, green: 0.92, blue: 0.91)
    ]
    static func color(for value: String) -> Color {
        // FNV-1a is stable across launches and much cheaper than hashing on every row redraw.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return colors[Int(hash % UInt64(colors.count))]
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
        default: return item.kind.rawValue == rawValue
        }
    }
}
