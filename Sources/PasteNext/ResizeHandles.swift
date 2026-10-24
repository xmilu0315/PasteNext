import AppKit
import SwiftUI

enum ResizeEdge {
    case right, bottom, corner
}

struct PanelResizeHandle: NSViewRepresentable {
    let edge: ResizeEdge
    func makeNSView(context: Context) -> ResizeHandleView { ResizeHandleView(edge: edge) }
    func updateNSView(_ nsView: ResizeHandleView, context: Context) {}
}

final class ResizeHandleView: NSView {
    private let edge: ResizeEdge
    private var startMouse = NSPoint.zero
    private var startFrame = CGRect.zero
    private var isHovering = false

    init(edge: ResizeEdge) {
        self.edge = edge
        super.init(frame: .zero)
        wantsLayer = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        discardCursorRects()
        let cursor: NSCursor
        switch edge {
        case .right, .corner: cursor = .resizeLeftRight
        case .bottom: cursor = .resizeUpDown
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovering else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
        switch edge {
        case .right:
            NSRect(x: bounds.width - 2, y: 0, width: 2, height: bounds.height).fill()
        case .bottom:
            NSRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
        case .corner:
            let corner = NSRect(x: bounds.width - 22, y: 0, width: 22, height: 22)
            NSBezierPath(roundedRect: corner, xRadius: 10, yRadius: 10).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startFrame = window?.frame ?? .zero
        switch edge {
        case .right, .corner: NSCursor.resizeLeftRight.push()
        case .bottom: NSCursor.resizeUpDown.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - startMouse.x
        let dy = current.y - startMouse.y
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var width = startFrame.width
        var height = startFrame.height
        if edge == .right || edge == .corner { width += dx }
        if edge == .bottom || edge == .corner { height -= dy }
        width = max(330, min(980, visible.width - 20, width))
        height = max(420, min(980, visible.height - 12, height))
        let top = startFrame.maxY
        let frame = CGRect(x: startFrame.minX, y: top - height, width: width, height: height)
        window.setFrame(frame, display: true, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        if let window {
            UserDefaults.standard.set(Double(window.frame.width), forKey: "panelWidth")
            UserDefaults.standard.set(Double(window.frame.height), forKey: "panelHeight")
        }
    }
}
