import AppKit
import Foundation

@MainActor
enum SelfTest {
    static func run() {
        var failures: [String] = []
        func expect(_ condition: Bool, _ name: String) {
            if !condition { failures.append(name) }
        }
        expect(ClipClassifier.classify("https://pastenow.app") == .link, "link classification")
        expect(ClipClassifier.classify("#5F2EEA") == .color, "color classification")
        expect(ClipClassifier.classify("import UIKit\nclass ViewController {\n}") == .code, "code classification")
        expect(ClipClassifier.classify("Hello, this is a simple text message.") == .text, "text classification")
        expect(Palette.color(for: "same") == Palette.color(for: "same"), "stable palette")
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
            monitor.onCapture = { item, image in captured = item; capturedImage = image }
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
                monitor.onCapture = { item, _ in captured = item }
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
                wrappedMonitor.onCapture = { item, _ in wrappedCapture = item }
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
                fileMonitor.onCapture = { item, _ in fileCapture = item }
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
                pathMonitor.onCapture = { item, _ in pathCapture = item }
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

        // The donation QR codes must be present in the app bundle.
        expect(NSImage(named: "donate-wechat") != nil, "donation WeChat QR bundled")
        expect(NSImage(named: "donate-alipay") != nil, "donation Alipay QR bundled")

        if failures.isEmpty {
            print("PasteNext self-test: 23/23 passed")
            exit(0)
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }
}
