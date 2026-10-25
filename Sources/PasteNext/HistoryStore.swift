import AppKit
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    private let directory: URL
    private let historyURL: URL
    private let imagesDirectory: URL
    private let fragmentsDirectory: URL
    private var saveWork: DispatchWorkItem?
    private let imageCache = NSCache<NSString, NSImage>()
    var limit: Int = 500 { didSet { trim(); scheduleSave() } }

    /// Creates the store.
    ///
    /// `directory` is injectable so a test can run against a throwaway location
    /// instead of the user's real history, and `load` controls whether existing
    /// history is read back. Without both, the self-test would overwrite the
    /// live `history.json` and leave test data behind.
    init(directory: URL? = nil, load: Bool = true) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = directory ?? base.appendingPathComponent("PasteNext", isDirectory: true)
        self.directory = dir
        imageCache.countLimit = 40
        historyURL = dir.appendingPathComponent("history.json")
        imagesDirectory = dir.appendingPathComponent("Images", isDirectory: true)
        fragmentsDirectory = dir.appendingPathComponent("Fragments", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: fragmentsDirectory, withIntermediateDirectories: true)
        if load { self.load() }
    }

    /// Records a clip, folding it into the previous one when both are part of
    /// the same staged copy.
    ///
    /// WeChat publishes an image+text copy in stages over several seconds — the
    /// diagnostics log shows a 7-second span: picture only, then caption only,
    /// then picture+caption+file (with the picture arriving at Retina 2x in the
    /// final stage). Each stage *replaces* the whole pasteboard, so every
    /// intermediate card is stale data: the user copied one thing, not three.
    ///
    /// A stage therefore supersedes the previous card when it comes from the
    /// same app shortly after, and either fills the previous card's missing
    /// half or is a superset of it (same text, plus an image/file). Anything
    /// else is a genuinely new copy and gets its own card.
    func mergeOrAdd(_ item: ClipItem, image: NSImage? = nil, htmlData: Data? = nil) {
        let window: TimeInterval = 8.0
        // "The previous clip" means the most recently *captured* one, not
        // whatever sits at index 0: pasting promotes an old card to the front,
        // and that must not be mistaken for the last copy.
        guard let last = items.max(by: { $0.createdAt < $1.createdAt }),
              last.sourceBundleID == item.sourceBundleID,
              let gap = Optional(item.createdAt.timeIntervalSince(last.createdAt)),
              gap >= 0, gap < window else {
            add(item, image: image, htmlData: htmlData)
            return
        }
        // A file card is complete on its own. Folding an unrelated image copy
        // into one destroyed the file clip (the paste then carried a picture
        // where the document should have been).
        guard last.kind != .files, item.kind != .files else {
            add(item, image: image, htmlData: htmlData)
            return
        }

        let lastHasText = last.captionText != nil
        let newHasText = item.captionText != nil
        let lastHasImage = last.imageFilename != nil
        let newHasImage = image != nil

        let fillsMissingHalf =
            (!lastHasText && newHasText) || (!lastHasImage && newHasImage)
        // Same text (or the previous card had none) plus the same or more
        // content — the final stage of a staged write.
        let supersedes = newHasText && newHasImage &&
            (last.captionText == nil || item.captionText == last.captionText)

        guard fillsMissingHalf || supersedes else {
            add(item, image: image, htmlData: htmlData)
            return
        }

        var merged = last
        if newHasText { merged.text = item.text }
        if newHasImage, let image, let name = saveImage(image, id: merged.id) {
            // The final stage usually carries the better (Retina) rendition.
            if let old = last.imageFilename, old != name {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(old))
            }
            merged.imageFilename = name
        }
        if let size = item.imageSize { merged.imageSize = size }
        if item.filePaths != nil { merged.filePaths = item.filePaths }
        if let htmlData, let name = saveFragment(data: htmlData, id: merged.id) {
            merged.htmlFilename = name
        }
        if item.title != nil { merged.title = item.title }
        if item.sourceName != nil { merged.sourceName = item.sourceName }
        // First sighting wins on ordering: whichever half arrived first is also
        // where it sat in the copied content.
        if !lastHasText && newHasText { merged.textFirst = true }
        if !lastHasImage && newHasImage { merged.textFirst = false }
        merged.createdAt = item.createdAt
        // With both halves present this is an image clip; the picture is what
        // the user cares about, the caption rides along.
        if merged.imageFilename != nil { merged.kind = .image }
        update(merged)
        Diagnostics.log("capture.merged", [
            "kind": merged.kind.rawValue,
            "hasText": String(merged.captionText != nil),
            "hasImage": String(merged.imageFilename != nil),
            "gap": String(format: "%.1fs", gap),
            "superseded": String(supersedes)
        ])
    }

    func add(_ item: ClipItem, image: NSImage? = nil, htmlData: Data? = nil) {
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
        if let htmlData, let name = saveFragment(data: htmlData, id: new.id) {
            new.htmlFilename = name
        }
        items.insert(new, at: 0)
        trim()
        scheduleSave()
    }

    /// Stores the original HTML payload next to the clip and returns its name.
    func saveFragment(data: Data, id: UUID) -> String? {
        let name = "\(id.uuidString).html"
        do {
            try data.write(to: fragmentsDirectory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            Diagnostics.log("fragment.save.failed", ["error": error.localizedDescription])
            return nil
        }
    }

    /// The archived HTML payload, if this clip has one.
    func fragment(named name: String?) -> Data? {
        guard let name else { return nil }
        return try? Data(contentsOf: fragmentsDirectory.appendingPathComponent(name))
    }

    /// Moves a clip to the front of the list.
    ///
    /// Pasting a card is the strongest signal that this is the clip the user
    /// wants, so it becomes the next ⌘1 instead of staying buried in history.
    func promote(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        let highest = items.compactMap(\.sortIndex).max() ?? Date().timeIntervalSinceReferenceDate
        item.sortIndex = highest + 1
        items.insert(item, at: 0)
        objectWillChange.send()
        scheduleSave()
        Diagnostics.log("store.promoted", ["kind": item.kind.rawValue])
    }

    /// Attaches a late-arriving remote image to an existing clip.
    ///
    /// Browser image+text copies carry only an `<img>` URL, so the card is
    /// created first and the picture lands a moment later.
    func attachImage(id: UUID, image: NSImage) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].imageFilename == nil else { return }
        items[index].imageFilename = saveImage(image, id: id)
        items[index].imageSize = "\(Int(image.size.width))×\(Int(image.size.height))"
        if items[index].kind == .text, items[index].captionText != nil {
            items[index].kind = .image
        }
        objectWillChange.send()
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
            // Two protections against the same class of data loss:
            // 1. Never stamp a drastically smaller history over a healthy one.
            // 2. Never overwrite a file this build cannot parse — keep a copy
            //    first, so a corrupt write is always recoverable.
            if let onDisk = try? Data(contentsOf: url), !onDisk.isEmpty {
                if let existing = try? JSONDecoder.pasteNext.decode([ClipItem].self, from: onDisk) {
                    if existing.count >= 5, snapshot.count * 2 < existing.count {
                        Diagnostics.log("store.save.blocked", [
                            "reason": "shrink",
                            "memory": String(snapshot.count),
                            "onDisk": String(existing.count)
                        ])
                        return
                    }
                } else if onDisk.count > 512 {
                    // Unparsable but non-trivial: keep a copy AND refuse to
                    // write. A store that could not read the file must never
                    // replace it — that is how a healthy history got wiped.
                    let stamp = Int(Date().timeIntervalSince1970)
                    let backup = url.deletingLastPathComponent()
                        .appendingPathComponent("history.corrupt-\(stamp).json")
                    try? onDisk.write(to: backup)
                    Diagnostics.log("store.save.blocked", [
                        "reason": "unparsable-on-disk",
                        "bytes": String(onDisk.count),
                        "backup": backup.lastPathComponent
                    ])
                    return
                }
            }
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
