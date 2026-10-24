import AppKit
import SwiftUI

/// Finds the NSScrollView backing a SwiftUI ScrollView and switches it to
/// macOS' overlay scroller: thin, appears while scrolling, fades out when idle.
struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onWindowChange = { [weak view] in
            guard let view else { return }
            view.configureScrollView()
        }
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        var onWindowChange: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            onWindowChange?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.onWindowChange?()
            }
        }

        func configureScrollView() {
            guard let scrollView = findScrollView() else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.hasVerticalScroller = true
        }

        private func findScrollView() -> NSScrollView? {
            var candidate: NSView? = self
            while let current = candidate {
                if let scrollView = current as? NSScrollView { return scrollView }
                if let scrollView = current.enclosingScrollView { return scrollView }
                candidate = current.superview
            }
            return nil
        }
    }
}
