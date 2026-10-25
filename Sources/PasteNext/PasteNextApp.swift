import AppKit
import QuartzCore
import SwiftUI

@main
struct PasteNextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    init() {
        if CommandLine.arguments.contains("--self-test") { SelfTest.run() }
    }

    var body: some Scene {
        Settings { SettingsView(state: state) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var captureAnimationToken = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        PanelController.shared.anchorProvider = { [weak self] in self?.statusButtonScreenFrame() }
        HotKeyManager.shared.onActivate = { PanelController.shared.toggle() }
        HotKeyManager.shared.register()
        let ignored = UserDefaults.standard.string(forKey: "ignoredApps") ?? ""
        if !ignored.isEmpty {
            AppState.shared.monitor.ignoredBundleIDs = Set(ignored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }
        NotificationCenter.default.addObserver(forName: .showPasteNextSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.openSettings() }
        }
        NotificationCenter.default.addObserver(forName: .pasteNextDidCapture, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.animateStatusIcon() }
        }
        // No window is created at launch. The panel exists only while the user asks for it.
        #if DEBUG
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { PanelController.shared.show() }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                PanelController.shared.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let view = NSApp.windows.first(where: { $0 is PasteNextPanel })?.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    NSApp.terminate(nil)
                }
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-about"), CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            let showPanel = CommandLine.arguments.contains("--with-donation")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let view = AboutSnapshotView(state: AppState.shared, showDonation: showPanel)
                let hosting = NSHostingView(rootView: view)
                hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 420)
                let window = NSWindow(contentRect: hosting.frame,
                                     styleMask: [.titled, .closable],
                                     backing: .buffered, defer: false)
                window.contentView = hosting
                window.center()
                hosting.layoutSubtreeIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { NSApp.terminate(nil); return }
                    hosting.cacheDisplay(in: hosting.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    NSApp.terminate(nil)
                }
            }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { HotKeyManager.shared.unregister() }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // Menu-bar icon: the system clipboard glyph.
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "PasteNext")
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("PasteNext")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "PasteNext"
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            PanelController.shared.toggleFromStatusItem()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        addMenuItem(menu, L("打开剪贴板", "Open Clipboard"), #selector(showPanel))
        addMenuItem(menu, AppState.shared.monitor.isPaused ? L("继续记录", "Resume Monitoring") : L("暂停记录", "Pause Monitoring"), #selector(togglePause))
        menu.addItem(.separator())
        addMenuItem(menu, L("设置…", "Settings…"), #selector(openSettings))
        menu.addItem(.separator())
        addMenuItem(menu, L("退出 PasteNext", "Quit PasteNext"), #selector(quit))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func addMenuItem(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func statusButtonScreenFrame() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        let inWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(inWindow)
    }

    private func animateStatusIcon() {
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true
        // A quick in-place shake: the artwork itself never changes.
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -1.6, 1.4, -0.9, 0.5, 0]
        shake.keyTimes = [0, 0.2, 0.42, 0.62, 0.82, 1]
        shake.duration = 0.24
        shake.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        button.layer?.add(shake, forKey: "pasteNextIconShake")
    }

    @objc private func showPanel() { PanelController.shared.show() }
    @objc private func togglePause() { AppState.shared.monitor.isPaused.toggle() }
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
