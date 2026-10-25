import AppKit
import Foundation

@MainActor
enum SelfTest {
    static func run() {
        var failures: [String] = []
        var asserted = 0
        func expect(_ condition: Bool, _ name: String) {
            asserted += 1
            if !condition { failures.append(name) }
        }
        // Permission status is environment, not correctness — report, don't assert.
        print("version: \(AppInfo.version)  permissions: accessibility=\(Permissions.accessibility) fullDiskAccess=\(Permissions.fullDiskAccess)")
        fflush(stdout)

        expect(ClipClassifier.classify("https://pastenow.app") == .link, "link classification")
        expect(ClipClassifier.classify("#5F2EEA") == .color, "color classification")
        expect(ClipClassifier.classify("import UIKit\nclass ViewController {\n}") == .code, "code classification")
        expect(ClipClassifier.classify("Hello, this is a simple text message.") == .text, "text classification")
        expect(Palette.color(for: .text) == Palette.color(for: .text), "stable palette")
        // Every content kind must be visually distinct, otherwise the tint is
        // just decoration.
        let kinds = ClipKind.allCases
        for i in kinds.indices {
            for j in kinds.indices where i != j {
                expect(Palette.isDistinct(kinds[i], kinds[j]), "distinct tint for \(kinds[i].rawValue) vs \(kinds[j].rawValue)")
            }
        }
        var pinned = ClipItem(kind: .text, text: "hello")
        pinned.isPinned = true
        expect(ClipCategory.pinned.contains(pinned), "pinned filter")
        do {
            let data = try JSONEncoder.pasteNext.encode([pinned])
            let decoded = try JSONDecoder.pasteNext.decode([ClipItem].self, from: data)
            expect(decoded.first?.text == "hello" && decoded.first?.isPinned == true, "persistence round trip")
        } catch { failures.append("persistence round trip: \(error)") }

        // Simulate a screenshot tool: image + text + TransientType on one pasteboard item.
        let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest"))
        board.clearContents()
        let image = NSImage(size: NSSize(width: 24, height: 16))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 16).fill()
        image.unlockFocus()
        if let tiff = image.tiffRepresentation {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(tiff, forType: .tiff)
            pasteboardItem.setString("PixPin_2026-10-24.png", forType: .string)
            pasteboardItem.setString("", forType: .init("org.nspasteboard.TransientType"))
            board.writeObjects([pasteboardItem])
            let monitor = ClipboardMonitor(pasteboard: board)
            var captured: ClipItem?
            var capturedImage: NSImage?
            monitor.onCapture = { item, image, _ in captured = item; capturedImage = image }
            monitor.captureNowForTesting()
            expect(captured?.kind == .image, "screenshot pasteboard classified as image")
            expect(capturedImage != nil, "screenshot pixels materialized")
        } else {
            failures.append("screenshot test image")
        }

        // PixPin "copy image as file" can expose only a temporary PNG file URL.
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("PasteNext-selftest-\(UUID().uuidString).png")
            do {
                try pngData.write(to: fileURL)
                let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.file"))
                board.clearContents()
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)
                pasteboardItem.setString("com.trolltech.anymime.PixPinData", forType: .init("com.trolltech.anymime.PixPinData"))
                board.writeObjects([pasteboardItem])
                let monitor = ClipboardMonitor(pasteboard: board)
                var captured: ClipItem?
                monitor.onCapture = { item, _, _ in captured = item }
                monitor.captureNowForTesting()
                expect(captured?.kind == .image, "PixPin file-URL screenshot classified as image")
                try? FileManager.default.removeItem(at: fileURL)

                // Qt/PixPin private MIME wrappers may contain the PNG after a binary header.
                let wrapped = Data([0x51, 0x54, 0x00, 0x2A]) + pngData
                let wrappedBoard = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.qt"))
                wrappedBoard.clearContents()
                let wrappedItem = NSPasteboardItem()
                wrappedItem.setData(wrapped, forType: .init("com.trolltech.anymime.PixPinData"))
                wrappedBoard.writeObjects([wrappedItem])
                let wrappedMonitor = ClipboardMonitor(pasteboard: wrappedBoard)
                var wrappedCapture: ClipItem?
                wrappedMonitor.onCapture = { item, _, _ in wrappedCapture = item }
                wrappedMonitor.captureNowForTesting()
                expect(wrappedCapture?.kind == .image, "PixPin private MIME screenshot classified as image")
            } catch {
                failures.append("PixPin file-URL screenshot: \(error)")
            }
        }

        // A Finder file copy carries both the file URL and an icon preview: it must stay a file.
        if let tiff = image.tiffRepresentation {
            let docURL = FileManager.default.temporaryDirectory.appendingPathComponent("PasteNext-selftest-\(UUID().uuidString).xlsx")
            do {
                try Data("fake spreadsheet payload".utf8).write(to: docURL)
                let fileBoard = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.finderfile"))
                fileBoard.clearContents()
                let fileItem = NSPasteboardItem()
                fileItem.setString(docURL.absoluteString, forType: .fileURL)
                fileItem.setData(tiff, forType: .tiff)
                fileBoard.writeObjects([fileItem])
                let fileMonitor = ClipboardMonitor(pasteboard: fileBoard)
                var fileCapture: ClipItem?
                fileMonitor.onCapture = { item, _, _ in fileCapture = item }
                fileMonitor.captureNowForTesting()
                expect(fileCapture?.kind == .files, "Finder file copy stays a file")
                expect(fileCapture?.filePaths?.first == docURL.path, "Finder file copy keeps its path")
                try? FileManager.default.removeItem(at: docURL)
            } catch {
                failures.append("Finder file copy: \(error)")
            }
        }

        // A path-only clipboard (string URL, no NSURL object) must still be captured.
        do {
            let docURL = FileManager.default.temporaryDirectory.appendingPathComponent("PasteNext-selftest-\(UUID().uuidString).pdf")
            do {
                try Data("%PDF-1.4 fake".utf8).write(to: docURL)
                let pathBoard = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.pathonly"))
                pathBoard.clearContents()
                let pathItem = NSPasteboardItem()
                pathItem.setString(docURL.path, forType: .fileURL)
                pathBoard.writeObjects([pathItem])
                let pathMonitor = ClipboardMonitor(pasteboard: pathBoard)
                var pathCapture: ClipItem?
                pathMonitor.onCapture = { item, _, _ in pathCapture = item }
                pathMonitor.captureNowForTesting()
                expect(pathCapture?.kind == .files, "path-only clipboard captured as file")
                expect(pathCapture?.filePaths?.first == docURL.path, "path-only clipboard keeps its path")
                try? FileManager.default.removeItem(at: docURL)
            } catch {
                failures.append("path-only clipboard: \(error)")
            }
        }

        // A file clip's plain-text form is its absolute path, not its display name.
        let pathItem = ClipItem(kind: .files, text: "report.xlsx", filePaths: ["/tmp/reports/report.xlsx"])
        expect(pathItem.plainTextRepresentation == "/tmp/reports/report.xlsx", "file plain text is its absolute path")
        let textItem = ClipItem(kind: .text, text: "hello world")
        expect(textItem.plainTextRepresentation == "hello world", "text plain text is unchanged")

        expect(CaptureSound.canLoad(.click), "generated click sound")
        expect(CaptureSound.canLoad(.tick) && CaptureSound.canLoad(.pop), "generated alternate sounds")

        let dragItem = ClipItem(kind: .image, text: "Screenshot")
        let provider = CardDragProvider.make(item: dragItem, image: image)
        expect(provider.registeredTypeIdentifiers.contains(PasteDragType.card), "internal card drag type")
        expect(provider.registeredTypeIdentifiers.contains("public.png"), "external image drag type")

        // End-to-end: an image+text copy (what a browser selection or a WeChat
        // draft produces) must come back as one clip holding BOTH.
        do {
            let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.imagetext"))
            board.clearContents()
            let img = NSImage(size: NSSize(width: 40, height: 24))
            img.lockFocus()
            NSColor.systemTeal.setFill()
            NSRect(x: 0, y: 0, width: 40, height: 24).fill()
            img.unlockFocus()
            let item = NSPasteboardItem()
            if let tiff = img.tiffRepresentation { item.setData(tiff, forType: .tiff) }
            item.setString("60度的蔚来萤火虫电池！值不值？", forType: .string)
            board.writeObjects([item])
            let monitor = ClipboardMonitor(pasteboard: board)
            var captured: ClipItem?
            monitor.onCapture = { clip, image, _ in captured = clip; _ = image }
            monitor.captureNowForTesting()
            expect(captured?.kind == .image, "image+text copy is an image clip")
            expect(captured?.captionText == "60度的蔚来萤火虫电池！值不值？",
                   "image+text copy keeps its text as a caption")
            expect(captured?.text == "60度的蔚来萤火虫电池！值不值？",
                   "image+text copy stores the real text, not a description")
        }

        // An HTML-only payload with a local <img> must still yield the picture.
        do {
            let pngURL = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-html-img-\(UUID().uuidString).png")
            let img = NSImage(size: NSSize(width: 30, height: 20))
            img.lockFocus()
            NSColor.systemBlue.setFill()
            NSRect(x: 0, y: 0, width: 30, height: 20).fill()
            img.unlockFocus()
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: pngURL)
            }
            let html = "<html><body><p>captioned text</p><img src=\"\(pngURL.absoluteString)\"></body></html>"
            let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.htmlimg"))
            board.clearContents()
            let pi = NSPasteboardItem()
            pi.setString(html, forType: .init("public.html"))
            pi.setString("captioned text", forType: .string)
            board.writeObjects([pi])
            let monitor = ClipboardMonitor(pasteboard: board)
            var captured: ClipItem?
            monitor.onCapture = { clip, _, _ in captured = clip }
            monitor.captureNowForTesting()
            expect(captured?.kind == .image, "HTML-embedded image is detected")
            expect(captured?.captionText == "captioned text", "HTML clip keeps its text")
            try? FileManager.default.removeItem(at: pngURL)
        }

        // A picture copied together with text must keep the text, and the
        // generated "Screenshot · WxH" description must never be mistaken
        // for a caption.
        let mixed = ClipItem(kind: .image, text: "60度的蔚来萤火虫电池！值不值？")
        expect(mixed.captionText == "60度的蔚来萤火虫电池！值不值？", "image clip keeps its caption")
        // A picture-only clip carries no text at all; its description comes
        // from imageSize, so nothing can ever be mistaken for a caption.
        let pictureOnly = ClipItem(kind: .image, text: "", imageSize: "800×600")
        expect(pictureOnly.captionText == nil, "picture-only clip has no caption")
        expect(pictureOnly.displayTitle.contains("800×600"), "picture-only clip describes itself by size")

        // ---- The full content matrix -------------------------------------
        // Every realistic clipboard shape must come back with ALL of its parts:
        // a copy can carry a picture, text and files at the same time, and none
        // of them may be dropped on the way in or on the way out.
        /// Runs the real capture on a scratch board. The build block returns any
        /// temporary files it created so they can be removed *after* the capture
        /// has read them.
        func probeBoard(_ name: String, _ build: @MainActor (NSPasteboard) -> [URL]) -> (ClipItem?, NSImage?) {
            let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.matrix.\(UUID().uuidString)"))
            board.clearContents()
            let scratch = build(board)
            defer { scratch.forEach { try? FileManager.default.removeItem(at: $0) } }
            let monitor = ClipboardMonitor(pasteboard: board)
            var result: (ClipItem, NSImage?)? = nil
            monitor.onCapture = { item, image, _ in result = (item, image) }
            monitor.captureNowForTesting()
            return (result?.0, result?.1)
        }
        func solidImage(_ color: NSColor, _ w: CGFloat, _ h: CGFloat) -> NSImage {
            let img = NSImage(size: NSSize(width: w, height: h))
            img.lockFocus(); color.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill(); img.unlockFocus()
            return img
        }
        func pngData(_ img: NSImage) -> Data? {
            guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }

        let cases: [(String, ClipKind, Bool, Bool, Bool)] = [
            // name,                          kind,     hasText, hasImage, hasFiles
            ("picture only",                   .image,   false,   true,    false),
            ("text only",                      .text,    true,    false,   false),
            ("picture + text (one item)",      .image,   true,    true,    false),
            ("picture + text (two items)",     .image,   true,    true,    false),
            ("html picture + text",            .image,   true,    true,    false),
            ("png flavour + text",             .image,   true,    true,    false),
            ("rtf picture + text",             .image,   true,    true,    false),
            ("webarchive picture + text",      .image,   true,    true,    false),
        ]
        var index = 0
        for (name, kind, hasText, hasImage, _) in cases {
            let (item, image) = probeBoard(name) { board in
                let img = solidImage(.systemTeal, 64, 44)
                switch index {
                case 0:
                    let i = NSPasteboardItem()
                    if let t = img.tiffRepresentation { i.setData(t, forType: .tiff) }
                    board.writeObjects([i])
                    return []
                case 1:
                    let i = NSPasteboardItem(); i.setString("纯文字内容", forType: .string)
                    board.writeObjects([i])
                    return []
                case 2:
                    let i = NSPasteboardItem()
                    if let t = img.tiffRepresentation { i.setData(t, forType: .tiff) }
                    i.setString("图片加文字", forType: .string)
                    board.writeObjects([i])
                    return []
                case 3:
                    let a = NSPasteboardItem()
                    if let t = img.tiffRepresentation { a.setData(t, forType: .tiff) }
                    let b = NSPasteboardItem(); b.setString("图片加文字", forType: .string)
                    board.writeObjects([a, b])
                    return []
                case 4:
                    let png = FileManager.default.temporaryDirectory.appendingPathComponent("matrix-html-\(UUID().uuidString).png")
                    if let d = pngData(img) { try? d.write(to: png) }
                    let i = NSPasteboardItem()
                    i.setString("<html><body><p>图片加文字</p><img src=\"\(png.absoluteString)\"></body></html>", forType: .init("public.html"))
                    i.setString("图片加文字", forType: .string)
                    board.writeObjects([i])
                    return [png]
                case 5:
                    let i = NSPasteboardItem()
                    if let d = pngData(img) { i.setData(d, forType: .png) }
                    i.setString("图片加文字", forType: .string)
                    board.writeObjects([i])
                    return []
                case 6:
                    // RTF with a hex-encoded PNG blob, the way Word and TextEdit do it.
                    let hex = (pngData(img) ?? Data()).map { String(format: "%02x", $0) }.joined()
                    let rtf = #"{\rtf1{\*\shppict{\pict\pngblip "# + hex + #"}}}"#
                    let i = NSPasteboardItem()
                    i.setData(rtf.data(using: .utf8)!, forType: .init("public.rtf"))
                    i.setString("图片加文字", forType: .string)
                    board.writeObjects([i])
                    return []
                default:
                    // Web archive with a base64 image subresource.
                    guard let png = pngData(img) else { return [] }
                    let archive: [String: Any] = [
                        "WebMainResource": ["WebResourceData": Data(), "WebResourceMIMEType": "text/html", "WebResourceURL": "about:blank"],
                        "WebSubresources": [["WebResourceData": png, "WebResourceMIMEType": "image/png", "WebResourceURL": "about:blank"]]
                    ]
                    guard let plist = try? PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0) else { return [] }
                    let i = NSPasteboardItem()
                    i.setData(plist, forType: .init("com.apple.webarchive"))
                    i.setString("图片加文字", forType: .string)
                    board.writeObjects([i])
                    return []
                }
            }
            index += 1

            expect(item != nil, "matrix \(name): something is captured")
            if let item {
                expect(item.kind == kind, "matrix \(name): kind is \(kind.rawValue), got \(item.kind.rawValue)")
                if hasText {
                    expect(item.captionText == "图片加文字" || item.captionText == "纯文字内容",
                           "matrix \(name): text survives")
                } else {
                    expect(item.captionText == nil, "matrix \(name): no text is invented")
                }
                if hasImage {
                    expect(image != nil, "matrix \(name): the picture is loaded")
                    expect(item.imageSize != nil, "matrix \(name): the picture size is recorded")
                } else {
                    expect(image == nil, "matrix \(name): no picture is invented")
                }
            }
        }

        // ---- UTF-16 text decoding (WeChat and other Qt apps) ----------------
        // macOS derives a broken public.utf8-plain-text from UTF-16 payloads,
        // so reading .string yields mojibake. The raw original flavour must be
        // read instead.
        do {
            let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.utf16"))
            board.clearContents()
            let item = NSPasteboardItem()
            item.setString("测试文本ABC", forType: .init("public.utf16-external-plain-text"))
            board.writeObjects([item])
            let monitor = ClipboardMonitor(pasteboard: board)
            var captured: ClipItem?
            monitor.onCapture = { clip, _, _ in captured = clip }
            monitor.captureNowForTesting()
            expect(captured?.text == "测试文本ABC",
                   "UTF-16 text decodes correctly (not mojibake), got: \(captured?.text ?? "nil")")
        }

        // ---- Complementary merge of staged image+text copies ---------------
        do {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("pastenext-selftest-merge-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let store = HistoryStore(directory: scratch, load: false)
            let image = solidImage(.systemTeal, 64, 44)

            // Stage 1: only the picture arrives.
            let pictureOnly = ClipItem(kind: .image, text: "",
                                       sourceBundleID: "com.tencent.xinWeChat", imageSize: "64×44")
            store.mergeOrAdd(pictureOnly, image: image)
            // Stage 2: only the caption arrives — it must merge into the same card.
            let captionOnly = ClipItem(kind: .text, text: "图注文字",
                                       sourceBundleID: "com.tencent.xinWeChat")
            store.mergeOrAdd(captionOnly, image: nil)

            expect(store.items.count == 1, "staged image+text merges into one card")
            expect(store.items.first?.captionText == "图注文字", "merge keeps the caption")
            expect(store.items.first?.imageFilename != nil, "merge keeps the picture")
            expect(store.items.first?.kind == .image, "merged clip is an image clip")

            // A much later, unrelated copy must NOT merge: `later` is "now"
            // while `oldPicture` is 20 seconds old, beyond the 8s window.
            let later = ClipItem(kind: .text, text: "另一条",
                                 sourceBundleID: "com.tencent.xinWeChat")
            let store2 = HistoryStore(directory: scratch, load: false)
            let oldPicture = ClipItem(kind: .image, text: "",
                                      createdAt: Date().addingTimeInterval(-20),
                                      sourceBundleID: "com.tencent.xinWeChat", imageSize: "64×44")
            store2.mergeOrAdd(oldPicture, image: image)
            store2.mergeOrAdd(later, image: nil)
            expect(store2.items.count == 2, "a copy far apart in time does not merge")
        }

        // ---- The data the default selection relies on ----------------------
        // reloadSelection focuses store.items.first, so that must always be the
        // most recent copy.
        do {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("pastenext-selftest-order-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let store = HistoryStore(directory: scratch, load: false)
            store.add(ClipItem(kind: .text, text: "较旧内容"))
            store.add(ClipItem(kind: .text, text: "最新内容"))
            expect(store.items.first?.text == "最新内容", "store.items is newest-first")
        }

        // ---- The exact staged copy from the diagnostics log ----------------
        // WeChat delivered: picture only (1x), caption only, then the final
        // picture+caption+file with a Retina 2x picture. Spans ~7 seconds.
        // All three stages must collapse into ONE complete card.
        do {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("pastenext-selftest-wechat-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let store = HistoryStore(directory: scratch, load: false)
            let small = solidImage(.systemTeal, 108, 80)
            let big = solidImage(.systemTeal, 216, 160)
            let now = Date()

            // Stage 1: picture only, no caption. (+0.0s)
            var item = ClipItem(kind: .image, text: "",
                                createdAt: now,
                                sourceBundleID: "com.tencent.xinWeChat", imageSize: "1082×800")
            store.mergeOrAdd(item, image: small)
            // Stage 2: caption only. (+4.6s)
            item = ClipItem(kind: .text, text: "据报道，在首销当天…",
                            createdAt: now.addingTimeInterval(4.6),
                            sourceBundleID: "com.tencent.xinWeChat")
            store.mergeOrAdd(item, image: nil)
            // Stage 3: everything, with the 2x picture. (+7.0s)
            item = ClipItem(kind: .image, text: "据报道，在首销当天…",
                            createdAt: now.addingTimeInterval(7.0),
                            sourceBundleID: "com.tencent.xinWeChat",
                            filePaths: ["/tmp/wechat-temp.png"], imageSize: "2164×1600")
            store.mergeOrAdd(item, image: big)

            expect(store.items.count == 1,
                   "three staged copies collapse into one card, got \(store.items.count)")
            expect(store.items.first?.captionText == "据报道，在首销当天…", "merge keeps the caption")
            expect(store.items.first?.imageSize == "2164×1600", "merge takes the final Retina picture")
            expect(store.items.first?.filePaths?.count == 1, "merge keeps the file path")
        }

        // ---- UTF-16 little-endian without a BOM (the WeChat mojibake case) --
        // Genuine UTF-16LE bytes decoded as big-endian produced "⺕㥥饑齓…" in
        // the history. decodeText must pick the byte order from the payload.
        do {
            let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.utf16le"))
            board.clearContents()
            let item = NSPasteboardItem()
            var le = Data()
            for scalar in "iPhone 17 蔚来".unicodeScalars {
                le.append(UInt8(scalar.value & 0xFF))
                le.append(UInt8((scalar.value >> 8) & 0xFF))
            }
            item.setData(le, forType: .init("public.utf16-external-plain-text"))
            board.writeObjects([item])
            let monitor = ClipboardMonitor(pasteboard: board)
            var captured: ClipItem?
            monitor.onCapture = { clip, _, _ in captured = clip }
            monitor.captureNowForTesting()
            expect(captured?.text == "iPhone 17 蔚来",
                   "UTF-16LE without BOM decodes correctly, got: \(captured?.text ?? "nil")")
        }

        // ---- A file card never absorbs an unrelated image copy --------------
        do {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("pastenext-selftest-filemerge-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let store = HistoryStore(directory: scratch, load: false)
            let fileClip = ClipItem(kind: .files, text: "doc.pdf",
                                    sourceBundleID: "com.apple.finder",
                                    filePaths: ["/tmp/doc.pdf"])
            store.mergeOrAdd(fileClip)
            let imageOnly = ClipItem(kind: .image, text: "",
                                     sourceBundleID: "com.apple.finder", imageSize: "64×44")
            store.mergeOrAdd(imageOnly, image: solidImage(.systemTeal, 64, 44))
            expect(store.items.count == 2, "a file card is complete; an image copy stays separate")
            expect(store.items.last?.kind == .files, "the file card keeps its kind")
            expect(store.items.last?.filePaths?.count == 1, "the file card keeps its path")
        }

        // ---- ⌘1…⌘9 skip pinned cards ---------------------------------------
        do {
            let pinned = ClipItem(kind: .text, text: "常驻", isPinned: true)
            let first = ClipItem(kind: .text, text: "最新")
            let second = ClipItem(kind: .text, text: "次新")
            let map = AppState.shortcutAssignments(for: [pinned, first, second])
            expect(map[pinned.id] == nil, "pinned cards take no shortcut slot")
            expect(map[first.id] == 1, "the newest non-pinned card is ⌘1")
            expect(map[second.id] == 2, "the next non-pinned card is ⌘2")
        }

        // ---- Remote image fetch (browser image+text selections) -------------
        // Chromium puts only text/html with a remote <img> on the board — no
        // image data. The fetch path is what makes those copies complete.
        // 127.0.0.1 keeps the test self-contained; skipped if the helper server
        // is not running.
        do {
            let server = URL(string: "http://127.0.0.1:8765/pic.png")!
            var reachable = false
            let sem = DispatchSemaphore(value: 0)
            var probe = URLRequest(url: server)
            probe.timeoutInterval = 1.5
            // Bypass the system proxy: the loopback helper must be reached
            // directly even on machines whose proxy intercepts localhost.
            let config = URLSessionConfiguration.default
            config.connectionProxyDictionary = [:]
            URLSession(configuration: config).dataTask(with: probe) { d, r, _ in
                reachable = (r as? HTTPURLResponse)?.statusCode == 200 && (d?.count ?? 0) > 64
                sem.signal()
            }.resume()
            sem.wait()

            if reachable {
                let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.remoteimg"))
                board.clearContents()
                let item = NSPasteboardItem()
                item.setString("<html><body><p>浏览器图文的文字</p><img src=\"http://127.0.0.1:8765/pic.png\"></body></html>",
                               forType: .init("public.html"))
                item.setString("浏览器图文的文字", forType: .string)
                board.writeObjects([item])
                let monitor = ClipboardMonitor(pasteboard: board)
                var captured: ClipItem?
                monitor.onCapture = { clip, _, _ in captured = clip }
                // The fetch is asynchronous by design (never on the capture path):
                // the card is created text-only, then the picture lands via
                // onRemoteImage and the card updates in place.
                var remoteImage: NSImage?
                monitor.onRemoteImage = { _, image in remoteImage = image }
                monitor.captureNowForTesting()
                expect(captured?.captionText == "浏览器图文的文字", "remote-image copy keeps its text")
                expect(captured?.kind == .text, "remote-image copy is captured immediately as text")
                // The delivery hops to the main queue, so the wait must run the
                // run loop instead of blocking it.
                let deadline = Date().addingTimeInterval(12)
                while remoteImage == nil && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                }
                expect(remoteImage != nil, "remote image is fetched in the background and delivered")
            }
        }

        // ---- Backward compatibility of the history file --------------------
        // A missing non-optional key used to make the whole file undecodable,
        // which silently emptied the store and wiped the user's history.
        do {
            let legacy = """
            [{"id":"11111111-1111-1111-1111-111111111111","kind":"text","text":"旧格式条目",
              "createdAt":"2026-10-25T10:00:00Z","isPinned":false,"isRemote":false}]
            """
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let items = try? decoder.decode([ClipItem].self, from: Data(legacy.utf8)) {
                expect(items.count == 1, "legacy history decodes")
                expect(items.first?.text == "旧格式条目", "legacy text survives")
                expect(items.first?.textFirst == false, "missing textFirst defaults to false")
                expect(items.first?.imageSize == nil, "missing imageSize defaults to nil")
            } else {
                expect(false, "legacy history decodes")
            }
        }

        // ---- Content order (text first vs picture first) --------------------
        do {
            func orderBoard(_ html: String) -> ClipItem? {
                let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.order.\(UUID().uuidString)"))
                board.clearContents()
                let image = solidImage(.systemTeal, 40, 30)
                let item = NSPasteboardItem()
                if let tiff = image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
                item.setString(html, forType: .init("public.html"))
                item.setString("正文文字", forType: .string)
                board.writeObjects([item])
                let monitor = ClipboardMonitor(pasteboard: board)
                var captured: ClipItem?
                monitor.onCapture = { clip, _, _ in captured = clip }
                monitor.captureNowForTesting()
                return captured
            }
            let textFirst = orderBoard("<html><body><p>正文文字</p><img src=\"pic.png\"></body></html>")
            expect(textFirst?.textFirst == true, "text before picture is recorded")
            let imageFirst = orderBoard("<html><body><img src=\"pic.png\"><p>正文文字</p></body></html>")
            expect(imageFirst?.textFirst == false, "picture before text is recorded")
        }

        // ---- Rich-text paste carries both halves, in order ----------------
        do {
            func richBoard(_ textFirst: Bool) -> NSPasteboard {
                let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.rtf.\(UUID().uuidString)"))
                let image = solidImage(.systemPink, 48, 32)
                let clip = ClipItem(kind: .image, text: "图注文字在正文中", imageSize: "48×32",
                                    textFirst: textFirst)
                PasteService.copy(clip, image: image, monitor: ClipboardMonitor(pasteboard: board),
                                  paste: false, pasteboard: board)
                return board
            }

            let board = richBoard(true)
            expect(board.data(forType: .rtf) != nil, "paste writes an RTF flavour")
            expect(board.string(forType: .html)?.contains("data:image/png;base64,") == true,
                   "paste writes HTML with an inline picture")
            expect(board.string(forType: .string) == "图注文字在正文中", "paste keeps the plain text")

            // Structure: the text must precede the picture when that is the
            // order it was copied in, and follow it otherwise.
            let rtfText = String(data: board.data(forType: .rtf) ?? Data(), encoding: .utf8) ?? ""
            expect(rtfText.contains("pngblip"), "RTF embeds the picture")
            expect(rtfText.contains("\\u22270"), "RTF escapes the caption")

            let htmlTextFirst = board.string(forType: .html) ?? ""
            let textAt = htmlTextFirst.range(of: "图注文字")?.lowerBound
            let imgAt = htmlTextFirst.range(of: "<img")?.lowerBound
            expect(textAt != nil && imgAt != nil && textAt! < imgAt!, "text-first order is preserved")

            let reversed = richBoard(false).string(forType: .html) ?? ""
            let textAt2 = reversed.range(of: "图注文字")?.lowerBound
            let imgAt2 = reversed.range(of: "<img")?.lowerBound
            expect(textAt2 != nil && imgAt2 != nil && imgAt2! < textAt2!, "picture-first order is preserved")
        }

        // ---- Replaying the original HTML -----------------------------------
        // The archived markup is the only faithful record of the source's own
        // order; the paste inlines the captured picture into it.
        do {
            let source = "<html><body><p>文字在前的一段话</p><img src=\"https://example.com/pic.png\"></body></html>"
            let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.replay"))
            let image = solidImage(.systemBlue, 48, 32)
            let clip = ClipItem(kind: .image, text: "文字在前的一段话", imageSize: "48×32", textFirst: true)
            PasteService.copy(clip, image: image, monitor: ClipboardMonitor(pasteboard: board),
                              paste: false, pasteboard: board,
                              htmlFragment: source.data(using: .utf8))
            let out = board.string(forType: .html) ?? ""
            expect(out.contains("data:image/png;base64,"), "replay inlines the captured picture")
            let textAt = out.range(of: "文字在前的一段话")?.lowerBound
            let imgAt = out.range(of: "<img")?.lowerBound
            expect(textAt != nil && imgAt != nil && textAt! < imgAt!,
                   "replay keeps the source order (text before picture)")
            expect(!out.contains("example.com"), "replay drops the dead remote URL")
        }

        // ---- The paste side ------------------------------------------------
        // An image+text clip must put BOTH on the board, so a rich-text target
        // (a WeChat input box, for instance) receives the picture and the words.
        do {
            // A scratch board, never NSPasteboard.general: the self-test must
            // not clobber what the user has actually copied.
            let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.pasteboth"))
            let img = solidImage(.systemPink, 48, 32)
            let clip = ClipItem(kind: .image, text: "图文一起粘贴", imageSize: "48×32")
            PasteService.copy(clip, image: img, monitor: ClipboardMonitor(pasteboard: board), paste: false, pasteboard: board)
            expect(board.data(forType: .tiff) != nil, "paste: the picture goes on the board")
            expect(board.string(forType: .string) == "图文一起粘贴", "paste: the text goes on the board too")
            // Plain-text mode writes only the words.
            board.clearContents()
            PasteService.copy(clip, image: img, monitor: ClipboardMonitor(pasteboard: board), paste: false, plainText: true, pasteboard: board)
            expect(board.string(forType: .string) == "图文一起粘贴", "paste as plain text: only the words")
            expect(board.data(forType: .tiff) == nil, "paste as plain text: no picture")
        }

        // ⌘1…⌘9: the digit key codes are not sequential on macOS, so compare
        // the whole mapping against the documented Carbon values.
        let expectedDigits: [UInt16: Int] = [
            18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
            22: 6, 26: 7, 28: 8, 25: 9
        ]
        expect(PasteNextPanel.digitKeyCodes == expectedDigits, "⌘1…⌘9 key code mapping")

        // A file clip must land on the pasteboard as plain data (the format
        // Finder accepts), not as an NSURL promise it cannot consume.
        do {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("PasteNext-selftest-write-\(UUID().uuidString).txt")
            try Data("payload".utf8).write(to: fileURL)
            let board = NSPasteboard(name: NSPasteboard.Name("com.pastenext.selftest.filewrite"))
            let clip = ClipItem(kind: .files, text: fileURL.lastPathComponent, filePaths: [fileURL.path])
            PasteService.copy(clip, image: nil, monitor: ClipboardMonitor(pasteboard: board), paste: false, pasteboard: board)
            expect(board.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] == [fileURL.path],
                   "file clip writes NSFilenamesPboardType")
            expect(board.string(forType: .fileURL) == fileURL.absoluteString,
                   "file clip writes public.file-url as plain text")
            let objs = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
            expect(objs.count == 1, "file clip URL is readable back")
            try? FileManager.default.removeItem(at: fileURL)
        } catch { failures.append("file clipboard write: \(error)") }

        // The donation QR codes must be present in the app bundle. They are
        // copied in by scripts/build-app.sh, so this only applies to a real .app.
        if Bundle.main.bundlePath.hasSuffix(".app") {
            expect(NSImage(named: "donate-wechat") != nil, "donation WeChat QR bundled")
            expect(NSImage(named: "donate-alipay") != nil, "donation Alipay QR bundled")
        }

        if failures.isEmpty {
            print("PasteNext self-test: \(asserted - failures.count)/\(asserted) passed\(failures.isEmpty ? "" : " — \(failures.count) FAILED")")
            exit(0)
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }
}
