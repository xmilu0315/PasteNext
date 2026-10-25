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
                     pasteboard: NSPasteboard = .general) {
        let pb = pasteboard
        monitor.ignoreNextWrite()
        pb.clearContents()

        var wrote = false
        if plainText {
            // "Paste as plain text": a file clip becomes its paths, everything
            // else its text. No picture is written in this mode.
            wrote = writeText(item.plainTextRepresentation, to: pb)
        } else {
            // A clip can carry a picture, text and files at the same time. Write
            // every part that is present so the target app receives the whole
            // thing instead of only whichever part happened to define `kind`.
            if item.kind == .files, let paths = item.filePaths, !paths.isEmpty {
                // A file that lives inside another app's container is only
                // resolvable if THIS process can read it: the file URL we write
                // carries our own access rights, not the original copier's. When
                // Full Disk Access is missing, WeChat temp files and the like
                // become dead URLs for every target app.
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
            if let image {
                if writeImage(image, to: pb) { wrote = true }
            }
            // A plain file clip already put its name on the board as part of the
            // file payload; adding a bare string would make some apps paste the
            // name instead of the file.
            if let caption = item.captionText, item.kind != .files {
                if pb.setString(caption, forType: .string) { wrote = true }
            }
        }

        // A write that produces nothing must never leave the user with an empty
        // clipboard: that is what made Finder play the "nothing to paste" sound
        // and wiped the file the user had just copied.
        if !wrote {
            // A write that produced nothing must never leave the user with an
            // empty clipboard: that is what made Finder play the "nothing to
            // paste" sound and wiped the file the user had just copied.
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
