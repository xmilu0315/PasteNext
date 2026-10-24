import AppKit
import ApplicationServices
import Foundation

@MainActor
enum PasteService {
    static func copy(_ item: ClipItem, image: NSImage?, monitor: ClipboardMonitor, paste: Bool, plainText: Bool = false) {
        let pb = NSPasteboard.general
        monitor.ignoreNextWrite()
        pb.clearContents()
        if item.kind == .image, let image, !plainText {
            guard let tiff = image.tiffRepresentation else { return }
            pb.setData(tiff, forType: .tiff)
        } else if item.kind == .files, let paths = item.filePaths, !plainText {
            // Write the file URLs AND a plain-text fallback so every target app
            // (Finder, Word, Mail) recognises the payload.
            let urls = paths.map { NSURL(fileURLWithPath: $0) }
            pb.writeObjects(urls)
            if pb.types?.contains(.fileURL) != true, let first = urls.first, let absolute = first.absoluteString {
                pb.setString(absolute, forType: .fileURL)
            }
        } else {
            // "Plain text" for a file clip means its absolute path.
            pb.setString(item.plainTextRepresentation, forType: .string)
        }
        guard paste else { return }
        guard AXIsProcessTrusted() else {
            promptAccessibility()
            return
        }
        // Hand the keystroke to the app that was in front before the panel appeared.
        // The panel is non-activating, so PasteNext may still hold key status and
        // a plain ⌘V would be swallowed by our own window.
        let target = AppState.shared.pasteTarget
        target?.activate()
        waitForFrontmost(target, attemptsLeft: 20) {
            MainActor.assumeIsolated { postPasteKeystroke() }
        }
    }

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
