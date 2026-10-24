import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

final class SettingsModel: ObservableObject {
    @Published var shortcut = Shortcut.stored
    @Published var recording = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var errorMessage = ""
    @Published var showClearConfirm = false
    @Published var isDonationPopoverShown = false
}

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @ObservedObject var state: AppState
    @AppStorage("language") private var language = "system"
    @AppStorage("captureSoundName") private var captureSoundName = CaptureSound.click.rawValue
    @AppStorage("ignoreTransientItems") private var ignoreTransientItems = false
    @AppStorage("historyLimit") private var historyLimit = 500
    @AppStorage("pollInterval") private var pollInterval = 0.5

    var body: some View {
        TabView {
            general.tabItem { Label(L("通用", "General"), systemImage: "gearshape") }
            shortcuts.tabItem { Label(L("快捷键", "Shortcuts"), systemImage: "keyboard") }
            rules.tabItem { Label(L("隐私与规则", "Privacy & Rules"), systemImage: "hand.raised") }
            about.tabItem { Label(L("关于", "About"), systemImage: "info.circle") }
        }
        .frame(width: 560, height: 430)
        .padding(18)
        .onChange(of: historyLimit) { state.store.limit = max(50, $0) }
        .onChange(of: pollInterval) { state.setPollInterval($0) }
        .onChange(of: language) { _ in state.objectWillChange.send() }
        .alert(L("清空未置顶历史？", "Clear unpinned history?"), isPresented: $model.showClearConfirm) {
            Button(L("取消", "Cancel"), role: .cancel) {}
            Button(L("清空", "Clear"), role: .destructive) { state.store.clearUnpinned() }
        } message: { Text(L("此操作不可撤销，置顶内容会保留。", "This cannot be undone. Pinned clips will be kept.")) }
        .alert(L("设置未生效", "Setting could not be changed"), isPresented: .constant(!model.errorMessage.isEmpty)) {
            Button(L("好", "OK")) { model.errorMessage = "" }
        } message: { Text(model.errorMessage) }
    }

    private var general: some View {
        Form {
            Section {
                Picker(L("界面语言", "Language"), selection: $language) {
                    Text(L("跟随系统", "System")).tag("system")
                    Text("简体中文").tag("chinese")
                    Text("English").tag("english")
                }
                LabeledContent(L("捕获提示音", "Capture sound")) {
                    HStack(spacing: 8) {
                        Picker("", selection: $captureSoundName) {
                            ForEach(CaptureSound.allCases) { sound in
                                Text(sound.title).tag(sound.rawValue)
                            }
                        }
                        .labelsHidden().frame(width: 150)
                        Button {
                            CaptureSound.play(CaptureSound(rawValue: captureSoundName) ?? .click)
                        } label: { Image(systemName: "speaker.wave.2") }
                            .buttonStyle(.borderless)
                            .disabled(captureSoundName == CaptureSound.none.rawValue)
                            .help(L("试听", "Preview"))
                    }
                }
                Toggle(L("忽略临时内容（可能漏掉截图）", "Ignore transient clips (may skip screenshots)"), isOn: $ignoreTransientItems)
                    .help(L("默认关闭。只有当你希望严格跳过临时剪贴板内容时再开启。", "Off by default. Enable only if you want to skip transient clipboard content."))
                Toggle(L("登录时自动启动", "Launch at login"), isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { value in
                        if let error = state.setLaunchAtLogin(value) {
                            model.errorMessage = error
                            model.launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Picker(L("历史上限", "History limit"), selection: $historyLimit) {
                    Text("100").tag(100); Text("500").tag(500); Text("1000").tag(1000); Text("2000").tag(2000)
                }
                Picker(L("剪贴板监控间隔", "Clipboard poll interval"), selection: $pollInterval) {
                    Text("0.1 \(L("秒", "s"))").tag(0.1)
                    Text("0.5 \(L("秒", "s"))").tag(0.5)
                    Text("1 \(L("秒", "s"))").tag(1.0)
                }
                .help(L("更短更灵敏但唤醒略多；0.5 秒通常已足够。", "Shorter is more responsive but wakes the CPU slightly more; 0.5s is usually enough."))
            } header: { Text(L("基础设置", "Basics")) }
            Section {
                LabeledContent(L("历史存储位置", "History location")) {
                    Text("~/Library/Application Support/PasteNext").font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                }
                Button(L("清空未置顶历史…", "Clear Unpinned History…"), role: .destructive) { model.showClearConfirm = true }
            } header: { Text(L("本地数据", "Local Data")) }
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section {
                LabeledContent(L("激活 PasteNext", "Activate PasteNext")) {
                    ZStack {
                        ShortcutRecorder(shortcut: $model.shortcut, isRecording: $model.recording).frame(width: 1, height: 1)
                        Button(model.recording ? L("请按下新快捷键…", "Press new shortcut…") : model.shortcut.display) { model.recording.toggle() }
                            .buttonStyle(.bordered).frame(minWidth: 145)
                    }
                }
                Text(L("点击右侧按钮，再按下包含 ⌘ / ⌥ / ⌃ / ⇧ 的组合键。无需辅助功能权限即可激活窗口。", "Click the button, then press a combination using ⌘ / ⌥ / ⌃ / ⇧. No Accessibility permission is needed to show the window."))
                    .font(.caption).foregroundColor(.secondary)
            } header: { Text(L("全局快捷键", "Global Shortcut")) }
            Section {
                ShortcutRow(keys: "↑ / ↓", action: L("选择上一条 / 下一条", "Select previous / next"))
                ShortcutRow(keys: "⌘ ← / →", action: L("切换标签页", "Switch tab"))
                ShortcutRow(keys: "↵", action: L("粘贴选中内容", "Paste selected clip"))
                ShortcutRow(keys: "双击", action: L("粘贴选中内容（等同回车）", "Paste selected clip (same as Return)"))
                ShortcutRow(keys: "⇧ ↵", action: L("粘贴为纯文本 / 文件路径", "Paste as plain text / file path"))
                ShortcutRow(keys: "⇧ 双击", action: L("粘贴为纯文本 / 文件路径", "Paste as plain text / file path"))
                ShortcutRow(keys: "Space", action: L("快速预览", "Quick preview"))
                ShortcutRow(keys: "⌘ F", action: L("搜索", "Search"))
                ShortcutRow(keys: "⌘ R", action: L("重置界面状态", "Reset view"))
                ShortcutRow(keys: "⌘ ⌫", action: L("删除选中内容", "Delete selected clip"))
                ShortcutRow(keys: "⌘ P", action: L("置顶 / 取消常驻选中内容", "Pin / unpin selected clips"))
                ShortcutRow(keys: "⌘ ↑ / ↓", action: L("上移 / 下移选中内容", "Move selected clips up / down"))
                Text(L("文件卡片按 ⇧ ↵ 或 ⇧ 双击时，粘贴的是文件的绝对路径；其他内容粘贴为纯文本。", "For file clips, ⇧ ↵ or ⇧ double-click pastes the absolute file path; other clips are pasted as plain text."))
                    .font(.caption).foregroundColor(.secondary)
            } header: { Text(L("键盘操作", "Keyboard Controls")) }
        }.formStyle(.grouped)
    }

    private var rules: some View {
        Form {
            Section {
                Text(L("始终跳过密码管理器标记的敏感内容、临时内容与自动生成内容。所有历史仅保存在本机，不联网、不上传。", "Sensitive, transient and auto-generated clips marked by source apps are always skipped. History stays on this Mac; no network upload."))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                excludedAppsEditor
                Text(L("默认排除 1Password 与 KeeWeb。接力内容默认正常记录并标注 iPhone 来源。", "1Password and KeeWeb are excluded by default. Universal Clipboard is recorded and marked with an iPhone icon."))
                    .font(.caption).foregroundColor(.secondary)
            } header: { Text(L("剪贴板隐私", "Clipboard Privacy")) }
            Section {
                LabeledContent(L("自动粘贴权限", "Auto-paste permission")) {
                    Button(L("检查并授权", "Check & Authorize")) { PasteService.promptAccessibility() }
                }
                Text(L("仅自动按下 ⌘V 时需要辅助功能权限；全局激活快捷键不依赖此权限。", "Accessibility is only needed to simulate ⌘V; the global activation shortcut works without it."))
                    .font(.caption).foregroundColor(.secondary)
            } header: { Text(L("系统权限", "System Permission")) }
        }.formStyle(.grouped)
    }

    private var excludedAppsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(.secondary.opacity(0.35))
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(spacing: 5) {
                    Image(systemName: "plus.square.on.square").font(.system(size: 18, weight: .medium))
                    Text(L("把 .app 拖到这里，或点击选择本机应用", "Drag a .app here, or click to choose an installed app"))
                        .font(.caption).multilineTextAlignment(.center)
                }.foregroundColor(.secondary).padding(.horizontal, 12)
            }
            .frame(height: 66)
            .contentShape(Rectangle())
            .onTapGesture(perform: chooseExcludedApp)
            .onDrop(of: [UTType.fileURL], delegate: AppBundleDropDelegate(state: state))

            if state.monitor.ignoredBundleIDs.isEmpty {
                Text(L("暂无排除应用", "No excluded apps")).font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(state.monitor.ignoredBundleIDs.sorted(), id: \.self) { bundleID in
                    HStack(spacing: 10) {
                        Image(nsImage: appIcon(for: bundleID)).resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(appName(for: bundleID)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(bundleID).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) { state.removeIgnoredBundleID(bundleID) } label: {
                            Image(systemName: "trash").foregroundColor(.red)
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 2)
                }
            }
        }
    }

    private func chooseExcludedApp() {
        let panel = NSOpenPanel()
        panel.title = L("选择要排除的应用", "Choose an app to exclude")
        panel.allowedContentTypes = [UTType.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier {
            state.addIgnoredBundleID(bundleID)
        }
    }

    private func appInfo(for bundleID: String) -> (name: String, path: String?) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return (app.localizedName ?? bundleID, app.bundleURL?.path)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            return (name, url.path)
        }
        return (bundleID, nil)
    }
    private func appName(for bundleID: String) -> String { appInfo(for: bundleID).name }
    private func appIcon(for bundleID: String) -> NSImage {
        if let path = appInfo(for: bundleID).path, FileManager.default.fileExists(atPath: path) {
            return AppIconCache.shared.icon(for: path)
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    private var about: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().aspectRatio(contentMode: .fit).frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
            Text("PasteNext").font(.system(size: 30, weight: .bold, design: .rounded))
            Text(L("版本 1.3.6 · 原生 macOS 剪贴板历史", "Version 1.3.6 · Native macOS clipboard history")).foregroundColor(.secondary)
            Divider().padding(.horizontal, 70)
            Text(L("轻量轮询 changeCount，仅在变化时读取内容。\n支持 macOS 通用剪贴板（接力），本地存储，无后台网络请求。", "Lightweight changeCount polling; reads content only on change.\nUniversal Clipboard support, local storage, no background network requests."))
                .multilineTextAlignment(.center).font(.callout).foregroundColor(.secondary)
            HStack(spacing: 6) {
                Text(L("作者邮箱", "Author Email")).font(.caption).foregroundColor(.secondary)
                Text("xmilu0315@foxmail.com").font(.caption).textSelection(.enabled)
            }
            donateButton
            Text("SwiftUI + AppKit · No third-party dependencies").font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Donation

    /// A quiet entry point: the payment codes only appear on hover, so the
    /// About page keeps its clean look.
    private var donateButton: some View {
        Button {
            model.isDonationPopoverShown = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "heart")
                    .font(.system(size: 10, weight: .semibold))
                Text(L("支持作者", "Support the Author"))
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.09))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering in
            if hovering { model.isDonationPopoverShown = true }
        }
        .popover(isPresented: $model.isDonationPopoverShown, arrowEdge: .bottom) {
            donationPanel
        }
    }

    private var donationPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                donationQR(named: "donate-wechat", title: L("微信收款码", "WeChat"))
                donationQR(named: "donate-alipay", title: L("支付宝收款码", "Alipay"))
            }
            Text(L("如果 PasteNext 帮到了你，欢迎请作者喝杯咖啡 ☕", "If PasteNext is useful to you, consider buying the author a coffee ☕"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 260)
        }
        .padding(14)
        .background(.regularMaterial)
        }

    private func donationQR(named name: String, title: String) -> some View {
        VStack(spacing: 5) {
            if let image = NSImage(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 132, height: 132)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

struct AppBundleDropDelegate: DropDelegate {
    let state: AppState

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.fileURL]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension == "app",
                  let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            DispatchQueue.main.async { state.addIgnoredBundleID(bundleID) }
        }
        return true
    }
}

struct ShortcutRow: View {
    let keys: String
    let action: String
    var body: some View {
        LabeledContent(action) {
            Text(keys).font(.system(.caption, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1)).cornerRadius(5)
        }
    }
}
