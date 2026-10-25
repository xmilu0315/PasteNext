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
        // Decisive experiment: can a file that lives inside ANOTHER app's
        // container (TCC-protected) be pasted via PasteNext into Finder?
        if CommandLine.arguments.contains("--e2e-container") {
            func log(_ s: String) { print(s); fflush(stdout) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let fm = FileManager.default
                // The WeChat container file from the real history.
                let history = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/PasteNext/history.json")
                guard let data = try? Data(contentsOf: history),
                      let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    log("cannot read history"); NSApp.terminate(nil); return
                }
                var target: String? = nil
                for item in items {
                    for p in (item["filePaths"] as? [String]) ?? [] where p.contains("xinWeChat") {
                        if fm.fileExists(atPath: p) { target = p; break }
                    }
                    if target != nil { break }
                }
                guard let path = target else {
                    log("no container file available"); NSApp.terminate(nil); return
                }
                let readable = fm.isReadableFile(atPath: path)
                log("file: \((path as NSString).lastPathComponent)")
                log("readable from PasteNext: \(readable)")

                let dst = URL(fileURLWithPath: "/tmp/pn-cdst")
                try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
                for f in ((try? fm.contentsOfDirectory(at: dst, includingPropertiesForKeys: nil)) ?? []) {
                    try? fm.removeItem(at: f)
                }

                let pb = NSPasteboard.general
                AppState.shared.monitor.ignoreNextWrite()
                pb.clearContents()
                let pi = NSPasteboardItem()
                pi.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
                pb.writeObjects([pi])
                log("board seeded")

                if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                    finder.activate()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let source = CGEventSource(stateID: .combinedSessionState)
                    let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
                    let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                    down?.flags = .maskCommand
                    up?.flags = .maskCommand
                    down?.post(tap: .cgAnnotatedSessionEventTap)
                    up?.post(tap: .cgAnnotatedSessionEventTap)
                    log("posted ⌘V to Finder")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        let landed = ((try? fm.contentsOfDirectory(at: dst, includingPropertiesForKeys: nil)) ?? [])
                            .map(\.lastPathComponent)
                        log("dst contents: \(landed)")
                        log(landed.isEmpty ? "FAIL: 文件未能粘贴（TCC 拦截）" : "PASS: \(landed)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        // Prints what the current general pasteboard would be captured as.
        // The fastest way to answer "why did this copy look wrong?".
        if CommandLine.arguments.contains("--capture-check") {
            func log(_ s: String) { print(s); fflush(stdout) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let monitor = ClipboardMonitor()
                var result: (ClipItem, NSImage?)? = nil
                monitor.onCapture = { item, image in result = (item, image) }
                monitor.captureNowForTesting()
                if let (item, image) = result {
                    log("kind        : \(item.kind.rawValue)")
                    log("text        : '\(item.text.prefix(80))'")
                    log("captionText : \(item.captionText?.prefix(80) ?? "nil")")
                    log("imageSize   : \(item.imageSize ?? "nil")")
                    log("imageLoaded : \(image != nil)")
                } else {
                    log("*** NOTHING CAPTURED ***")
                }
                NSApp.terminate(nil)
            }
        }
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
