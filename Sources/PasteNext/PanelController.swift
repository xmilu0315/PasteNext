import AppKit
import SwiftUI

final class PasteNextPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS virtual key codes for the digits 1-9. They are not sequential.
    /// Exposed for the self-test: the mapping is not sequential, so a
    /// typo here silently breaks a shortcut.
    static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
        22: 6, 26: 7, 28: 8, 25: 9
    ]

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 123 || event.keyCode == 124 {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers == .command {
                AppState.shared.stepTab(event.keyCode == 123 ? -1 : 1)
                return
            }
        } else if event.type == .keyDown, event.keyCode == 125 || event.keyCode == 126 {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers.isEmpty {
                AppState.shared.moveSelection(event.keyCode == 125 ? 1 : -1)
                return
            }
        }
        // ⌘1…⌘9 paste the n-th card. This lives in the panel's own event path,
        // so it only fires while the PasteNext window is open and focused — it
        // is deliberately NOT a global hotkey, because ⌘1…⌘9 belong to other apps.
        if event.type == .keyDown,
           let digit = Self.digitKeyCodes[event.keyCode],
           event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
            AppState.shared.pasteItem(at: digit - 1)
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()
    private var panel: PasteNextPanel?
    private var lastResign = Date.distantPast
    private var panelSize: NSSize {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: "panelWidth")
        let height = defaults.double(forKey: "panelHeight")
        return NSSize(width: width > 330 ? width : 382, height: height > 420 ? height : 620)
    }
    /// Screen-space frame of the PasteNext menu-bar item, supplied by AppDelegate.
    var anchorProvider: (() -> NSRect?)?

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .hidePasteNextPanel, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            if Date().timeIntervalSince(lastResign) < 0.25 { return }
            show()
        }
    }

    func toggleFromStatusItem() { toggle() }

    func show() {
        let panel = panel ?? makePanel()
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            AppState.shared.previousApp = front
        }
        position(panel)
        // Non-activating panel: keep the previous app focused (e.g. a browser address bar).
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        AppState.shared.reloadSelection()
    }

    func hide() {
        AppState.shared.draggingCardID = nil
        AppState.shared.draggingTabKey = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> PasteNextPanel {
        let height = min(panelSize.height, max(420, (NSScreen.main?.visibleFrame.height ?? 720) - 24))
        let panel = PasteNextPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: panelSize.width, height: height)),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 330, height: 420)
        panel.maxSize = NSSize(width: 980, height: 980)
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        let host = NSHostingView(rootView: ContentView(state: AppState.shared))
        host.wantsLayer = true
        host.layer?.cornerRadius = 14
        host.layer?.masksToBounds = true
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let anchor = anchorProvider?()
        let targetPoint = anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(targetPoint) })
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        var x = (anchor?.minX ?? frame.minX) - 4
        if x + size.width > frame.maxX - 8 { x = frame.maxX - size.width - 8 }
        x = max(frame.minX + 8, x)
        // visibleFrame already excludes the menu bar; 3pt keeps the panel visually attached to it.
        let y = frame.maxY - size.height - 3
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: false)
        #if DEBUG
        print("PasteNext panel anchor=\(String(describing: anchor)) target=\(panel.frame)")
        #endif
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel?.attachedSheet == nil else { return }
        lastResign = Date()
        hide()
    }

    func windowDidResize(_ notification: Notification) {
        guard let size = panel?.frame.size else { return }
        UserDefaults.standard.set(Double(size.width), forKey: "panelWidth")
        UserDefaults.standard.set(Double(size.height), forKey: "panelHeight")
    }

    func windowDidBecomeKey(_ notification: Notification) {
        lastResign = .distantPast
    }
}
