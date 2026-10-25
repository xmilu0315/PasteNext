import AppKit
import ApplicationServices
import Foundation

@MainActor
enum PasteService {
    /// Status messages are pushed through this closure instead of reaching for
    /// `AppState.shared`: touching the singleton would instantiate the real
    /// history store inside any debug/secondary process and let it overwrite
    /// the user's history.
    static var statusSink: ((String) -> Void)?
    static func copy(_ item: ClipItem, image: NSImage?, monitor: ClipboardMonitor, paste: Bool, plainText: Bool = false,
                     pasteboard: NSPasteboard = .general, htmlFragment: Data? = nil) {
        let pb = pasteboard
        monitor.ignoreNextWrite()
        pb.clearContents()

        var wrote = false
        if plainText {
            // "Paste as plain text": a file clip becomes its paths, everything
            // else its text. No picture or markup is written in this mode.
            wrote = writeText(item.plainTextRepresentation, to: pb)
        } else {
            // A clip can carry a picture, text and files at once, so every part
            // that is present gets written.
            if item.kind == .files, let paths = item.filePaths, !paths.isEmpty {
                // A file inside another app's container is only resolvable if
                // THIS process can read it: the file URL we write carries our
                // own access rights, not the original copier's.
                let unreadable = paths.filter { !FileManager.default.isReadableFile(atPath: $0) }
                if !unreadable.isEmpty && !Permissions.fullDiskAccess {
                    Diagnostics.log("paste.blocked", [
                        "reason": "file-not-readable",
                        "count": String(unreadable.count),
                        "sample": String((unreadable.first ?? "").prefix(160))
                    ])
                    AppState.shared.statusMessage = L(
                        "需要完全磁盘访问权限才能粘贴其他应用的文件",
                        "Full Disk Access is required to paste files from other apps")
                }
                for path in paths {
                    Diagnostics.log("paste.file", [
                        "path": String(path.prefix(180)),
                        "exists": String(FileManager.default.fileExists(atPath: path)),
                        "readable": String(FileManager.default.isReadableFile(atPath: path))
                    ])
                }
                wrote = writeFiles(paths, to: pb)
            }

            if let image, writeImage(image, to: pb) { wrote = true }

            // Rich text is what carries words and picture together. Replaying
            // the archived HTML preserves the source's own order, structure and
            // formatting (the picture is inlined, since the markup only holds a
            // URL); without an archive it is synthesised from text + image.
            if let caption = item.captionText, item.kind != .files {
                if let htmlFragment, let replayed = replayHTML(htmlFragment, image: image) {
                    if pb.setString(replayed, forType: .html) { wrote = true }
                    if let rtf = rtf(fromHTML: replayed), pb.setData(rtf, forType: .rtf) { wrote = true }
                } else if let image,
                          writeRichText(text: caption, image: image,
                                        textFirst: item.textFirst, to: pb) {
                    wrote = true
                }
                // Always offer the bare words as well: pasting into a text field
                // or using ⇧↵ must still work.
                if pb.setString(caption, forType: .string) { wrote = true }
            }
        }

        // A write that produces nothing must never leave the user with an empty
        // clipboard: that is what made Finder play the "nothing to paste" sound
        // and wiped the file the user had just copied.
        if !wrote {
            let fallback = item.plainTextRepresentation
            if !fallback.isEmpty { pb.setString(fallback, forType: .string) }
            Diagnostics.log("paste.fallback", ["reason": "nothing-written"])
        }
        Diagnostics.log("paste.written", [
            "types": (pb.types ?? []).map(\.rawValue)
                .filter { !$0.hasPrefix("dyn.") && !$0.hasPrefix("CorePasteboard") }
                .sorted().joined(separator: ",")
        ])

        guard paste else { return }
        // Auto-paste needs Accessibility. Without it the clipboard is already
        // correct but no ⌘V is ever delivered, which looks like "nothing
        // happened" — so say so instead of failing silently.
        guard Permissions.accessibility else {
            Diagnostics.log("paste.blocked", ["reason": "accessibility-not-granted"])
            PasteService.statusSink?(L("需要辅助功能权限才能自动粘贴", "Accessibility permission required to auto-paste"))
            promptAccessibility()
            return
        }
        Diagnostics.log("paste.start", [
            "kind": item.kind.rawValue,
            "plainText": String(plainText),
            "target": AppState.shared.pasteTarget?.bundleIdentifier ?? "nil"
        ])
        // Hand the keystroke to the app that was in front before the panel appeared.
        // The panel is non-activating, so PasteNext may still hold key status and
        // a plain ⌘V would be swallowed by our own window.
        let target = AppState.shared.pasteTarget
        target?.activate()
        waitForFrontmost(target, attemptsLeft: 20) {
            MainActor.assumeIsolated { postPasteKeystroke() }
        }
    }

    // MARK: - Pasteboard writers

    /// Writes files the way Finder does: as plain data, never as `NSURL` objects.
    ///
    /// `NSPasteboard.writeObjects(_:)` with `NSURL` does not put a plain URL on
    /// the board — it stores a *promise* that the receiving app has to fulfil
    /// through the writing process. PasteNext is ad-hoc signed and unsandboxed,
    /// so that promise can never be consumed: `NSPasteboard.types` still lists
    /// `public.file-url`, Finder still cannot paste it, and the user hears the
    /// "empty clipboard" sound. Writing the payload as plain data puts a
    /// self-contained copy on the board that every app can read.
    private static func writeFiles(_ paths: [String], to pb: NSPasteboard) -> Bool {
        var wrote = false
        // 1. The classic Finder payload: an array of POSIX paths. This is what
        //    makes Finder accept the paste.
        if pb.setPropertyList(paths, forType: .init("NSFilenamesPboardType")) { wrote = true }
        // 2. The uniform type identifier, as plain text. macOS derives the
        //    CorePasteboard and dyn. flavours from this on its own.
        let urls = paths.map { NSURL(fileURLWithPath: $0) }
        if let first = urls.first?.absoluteString, pb.setString(first, forType: .fileURL) { wrote = true }
        // 3. Several files at once go into the multi-URI type.
        if urls.count > 1 {
            let list = urls.compactMap(\.absoluteString).joined(separator: "\n")
            if pb.setString(list, forType: .init("text/uri-list")) { wrote = true }
        }
        return wrote
    }

    /// Writes the clip as rich text so a word processor receives the words AND
    /// the picture from one paste, in the order they were copied.
    ///
    /// AppKit's own RTF export silently drops `NSTextAttachment` images (the
    /// result contains no `\pict` at all), so the RTF is generated directly —
    /// the standard `\*\shppict{\pict\pngblip …}` form that Word and Pages
    /// understand. HTML with an inline data URI is written as well, because
    /// several editors prefer that flavour.
    private static func writeRichText(text: String, image: NSImage,
                                      textFirst: Bool, to pb: NSPasteboard) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        let width = max(1, Int(image.size.width))
        let height = max(1, Int(image.size.height))
        var wrote = false

        if let rtf = rtfDocument(text: text, png: png, width: width, height: height,
                                 textFirst: textFirst) {
            if pb.setData(rtf, forType: .rtf) { wrote = true }
        }
        // Keep the HTML payload reasonable; very large pictures stay RTF-only.
        if png.count <= 8_000_000,
           let html = htmlDocument(text: text, png: png, textFirst: textFirst) {
            if pb.setString(html, forType: .html) { wrote = true }
        }
        return wrote
    }

    /// Rebuilds the archived HTML with the captured picture inlined, so the
    /// paste reproduces the source document instead of a reconstruction.
    private static func replayHTML(_ data: Data, image: NSImage?) -> String? {
        guard var html = String(data: data, encoding: .utf8), !html.isEmpty else { return nil }
        guard let image else {
            // A text-only clip: the markup is already self-contained.
            return html
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              png.count <= 8_000_000 else { return nil }
        let dataURI = "data:image/png;base64," + png.base64EncodedString()
        // Point the first <img> at the captured bytes; leave the rest alone.
        if let range = html.range(of: "src\\s*=\\s*[\"'][^\"']*[\"']",
                                  options: [.regularExpression, .caseInsensitive]) {
            html.replaceSubrange(range, with: "src=\"\(dataURI)\"")
        } else {
            return nil
        }
        return html
    }

    /// Converts HTML into RTF so word processors get the same structure.
    private static func rtf(fromHTML html: String) -> Data? {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil),
              attributed.length > 0 else { return nil }
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    /// RTF with an embedded PNG, honouring the copied order.
    private static func rtfDocument(text: String, png: Data,
                                    width: Int, height: Int, textFirst: Bool) -> Data? {
        func escape(_ value: String) -> String {
            var out = ""
            for scalar in value.unicodeScalars {
                switch scalar {
                case "\\": out += "\\\\"
                case "{": out += "\\{"
                case "}": out += "\\}"
                case "\n": out += "\\par "
                case "\r": break
                case "\t": out += "\\tab "
                default:
                    if scalar.value < 128 {
                        out.unicodeScalars.append(scalar)
                    } else {
                        // RTF escapes every non-ASCII scalar as \uN?
                        out += "\\u\(Int(scalar.value))?"
                    }
                }
            }
            return out
        }
        let hex = png.map { String(format: "%02x", $0) }.joined()
        let picture = "{\\*\\shppict{\\pict\\pngblip\\picw\(width)\\pich\(height)"
            + "\\picwgoal\(width * 15)\\pichgoal\(height * 15) \(hex)}}"
        let paragraph = "\\f0\\fs26 \(escape(text))\\par "
        let body = textFirst ? paragraph + "\n" + picture : picture + "\n" + paragraph
        let rtf = "{\\rtf1\\ansi\\ansicpg936\\deff0"
            + "{\\fonttbl{\\f0\\fnil\\fcharset134 PingFang SC;}}\n\(body)\n}"
        return rtf.data(using: .utf8)
    }

    /// HTML with an inline data URI, honouring the copied order.
    private static func htmlDocument(text: String, png: Data, textFirst: Bool) -> String? {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
        }
        let base64 = png.base64EncodedString()
        let paragraph = "<p>\(escape(text))</p>"
        let picture = "<p><img src=\"data:image/png;base64,\(base64)\"></p>"
        let body = textFirst ? paragraph + picture : picture + paragraph
        return "<html><body>\(body)</body></html>"
    }

    private static func writeImage(_ image: NSImage, to pb: NSPasteboard) -> Bool {
        if let tiff = image.tiffRepresentation, pb.setData(tiff, forType: .tiff) { return true }
        // Images built straight from a CGImage can have no TIFF representation.
        if let png = image.pngData(), pb.setData(png, forType: .png) { return true }
        return false
    }

    private static func writeText(_ text: String, to pb: NSPasteboard) -> Bool {
        guard !text.isEmpty else { return false }
        return pb.setString(text, forType: .string)
    }

    // MARK: - Keystroke delivery

    /// Polls (without blocking the main run loop) until the target app is really
    /// frontmost, then runs the action.
    private static func waitForFrontmost(_ target: NSRunningApplication?, attemptsLeft: Int, action: @escaping @Sendable () -> Void) {
        guard let target else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { action() }
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { action() }
            return
        }
        guard attemptsLeft > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { action() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitForFrontmost(target, attemptsLeft: attemptsLeft - 1, action: action)
        }
    }

    private static func postPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

extension NSImage {
    /// PNG bytes of the image, rendered at its natural size.
    fileprivate func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
