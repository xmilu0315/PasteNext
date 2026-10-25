import AppKit
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    private let directory: URL
    private let historyURL: URL
    private let imagesDirectory: URL
    private var saveWork: DispatchWorkItem?
    private let imageCache = NSCache<NSString, NSImage>()
    var limit: Int = 500 { didSet { trim(); scheduleSave() } }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("PasteNext", isDirectory: true)
        imageCache.countLimit = 40
        historyURL = directory.appendingPathComponent("history.json")
        imagesDirectory = directory.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        load()
    }

    func add(_ item: ClipItem, image: NSImage? = nil) {
        var new = item
        if let existing = items.firstIndex(where: { isSameClip($0, item) }) {
            // The same content is already in the history. Keep the card's
            // identity and everything the user set on it, but treat this as a
            // fresh copy — see the sort index below.
            let old = items.remove(at: existing)
            new.id = old.id
            new.isPinned = old.isPinned
            new.title = old.title
            new.imageFilename = old.imageFilename
            new.tags = old.tags
        }
        // A new copy always lands on top. Re-copying something already in the
        // list used to refresh only its timestamp, which left the card stranded
        // at its old position while it claimed to have "just" been copied.
        let highest = items.compactMap(\.sortIndex).max() ?? Date().timeIntervalSinceReferenceDate
        new.sortIndex = highest + 1
        if let image, new.kind == .image, new.imageFilename == nil {
            new.imageFilename = saveImage(image, id: new.id)
        }
        items.insert(new, at: 0)
        trim()
        scheduleSave()
    }

    func update(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        scheduleSave()
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        scheduleSave()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        if let name = item.imageFilename, !items.contains(where: { $0.imageFilename == name }) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
        scheduleSave()
    }

    func reorder(_ ordered: [ClipItem]) {
        let base = (items.compactMap(\.sortIndex).max() ?? Date().timeIntervalSinceReferenceDate) + Double(ordered.count + 10)
        for (offset, item) in ordered.enumerated() {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { continue }
            items[index].sortIndex = base - Double(offset)
        }
        scheduleSave()
    }

    func clearUnpinned() {
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        for item in removed {
            if let name = item.imageFilename, !items.contains(where: { $0.imageFilename == name }) {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
            }
        }
        scheduleSave()
    }

    func image(for item: ClipItem) -> NSImage? {
        guard let name = item.imageFilename else { return nil }
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        guard let image = NSImage(contentsOf: imagesDirectory.appendingPathComponent(name)) else { return nil }
        imageCache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Two clips are the same only when kind, text and (when present) the file paths match.
    /// Path-aware matching matters because two different Finder files used to share the
    /// same "screenshot 512x512" text, so the newer copy silently replaced the older card.
    private func isSameClip(_ lhs: ClipItem, _ rhs: ClipItem) -> Bool {
        guard lhs.kind == rhs.kind, lhs.text == rhs.text else { return false }
        // A picture-only clip carries no text, so two different screenshots would
        // otherwise look identical and the newer one would silently replace the
        // older. The pixel size is what tells them apart.
        guard lhs.imageSize == rhs.imageSize else { return false }
        if lhs.filePaths != nil || rhs.filePaths != nil {
            return (lhs.filePaths ?? []) == (rhs.filePaths ?? [])
        }
        return true
    }

    private func trim() {
        guard items.count > limit else { return }
        var kept: [ClipItem] = []
        var removed: [ClipItem] = []
        for item in items {
            if kept.count < limit || item.isPinned { kept.append(item) } else { removed.append(item) }
        }
        items = kept
        for item in removed {
            if let name = item.imageFilename, !items.contains(where: { $0.imageFilename == name }) {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
            }
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = items
        let url = historyURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder.pasteNext.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL),
              let saved = try? JSONDecoder.pasteNext.decode([ClipItem].self, from: data) else { return }
        // Older versions could save a Finder file copy as an image because Finder also
        // exposes an icon/preview. Normalize non-image files back to real files.
        var normalized: [ClipItem] = []
        var staleImages: [String] = []
        for var item in saved {
            // One-time migration: older builds stored a generated description
            // ("Screenshot · 800×600") as the clip's text for picture-only clips.
            // Text is now always the real text, so move that description into
            // imageSize and clear the text.
            if item.imageSize == nil, item.kind == .image {
                let patterns = ["截图 · ", "Screenshot · ", "图片 · ", "Image · "]
                if let hit = patterns.first(where: { item.text.hasPrefix($0) }) {
                    item.imageSize = String(item.text.dropFirst(hit.count)).trimmingCharacters(in: .whitespaces)
                    item.text = ""
                } else if item.text == "图片" || item.text == "Image" {
                    item.text = ""
                }
            }
            let isImageFile = item.filePaths?.allSatisfy { path in
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                return ["png", "jpg", "jpeg", "tiff", "tif", "heic", "webp", "gif", "bmp"].contains(ext)
            } ?? false
            if item.kind == .image, item.filePaths != nil, !isImageFile {
                item.kind = .files
                item.text = item.filePaths?.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n") ?? item.text
                if let name = item.imageFilename {
                    staleImages.append(name)
                    item.imageFilename = nil
                }
            }
            normalized.append(item)
        }
        items = normalized.sorted { lhs, rhs in
            lhs.isPinned == rhs.isPinned ? lhs.createdAt > rhs.createdAt : lhs.isPinned
        }
        for name in staleImages where !items.contains(where: { $0.imageFilename == name }) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }

    private func saveImage(_ image: NSImage, id: UUID) -> String? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]), data.count <= 12_000_000 else { return nil }
        let name = "\(id.uuidString).png"
        try? data.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }
}

extension JSONEncoder {
    static var pasteNext: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
extension JSONDecoder {
    static var pasteNext: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
