import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let hidePasteNextPanel = Notification.Name("PasteNext.hidePanel")
    static let showPasteNextSettings = Notification.Name("PasteNext.showSettings")
    static let pasteNextDidCapture = Notification.Name("PasteNext.didCapture")
}

struct ContentView: View {
    @ObservedObject var state: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            folderBar
            Divider().opacity(0.55)
            clipList
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .trailing) { PanelResizeHandle(edge: .right).frame(width: 10) }
        .overlay(alignment: .bottom) { PanelResizeHandle(edge: .bottom).frame(height: 10) }
        .overlay(alignment: .bottomTrailing) { PanelResizeHandle(edge: .corner).frame(width: 24, height: 24) }
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.7))
        .onMoveCommand { direction in
            switch direction {
            case .up: state.moveSelection(-1)
            case .down: state.moveSelection(1)
            case .left: state.stepTab(-1)
            case .right: state.stepTab(1)
            default: break
            }
        }
        .background(keyboardCommands)
        // Removing a collected clip also removes it from its tag, so it must be
        // an explicit choice rather than a side effect of deleting in the list.
        .alert(L("其中含有收藏的卡片", "Some of these clips are saved"),
               isPresented: Binding(
                    get: { state.pendingDeletion != nil },
                    set: { if !$0 { state.pendingDeletion = nil } })) {
            Button(L("取消", "Cancel"), role: .cancel) { state.pendingDeletion = nil }
            Button(L("仍要删除", "Delete Anyway"), role: .destructive) { state.confirmPendingDeletion() }
        } message: {
            Text(L("选中的卡片里有 \(state.pendingCollectedCount) 条已常驻。删除后会从历史中移除（文件夹里的存档副本不受影响）。",
                   "\(state.pendingCollectedCount) of the selected clips are pinned. Deleting removes them from history; copies saved in folders are unaffected."))
        }
        .sheet(item: $state.previewItem) { item in PreviewView(item: item, state: state) }
        .sheet(item: $state.editingItem) { item in EditClipView(item: item, state: state) }
        .sheet(item: $state.folderEditorItem) { item in FolderPickerView(item: item, state: state) }
        .sheet(isPresented: $state.showingNewFolder) { NewFolderView(state: state) }
        .sheet(isPresented: $state.showingRenameFolder) { RenameFolderView(state: state) }
        .onReceive(NotificationCenter.default.publisher(for: .hidePasteNextPanel)) { _ in
            NSApp.keyWindow?.orderOut(nil)
        }
        .onAppear {
            if state.selectedID == nil { state.selectedID = state.filteredItems.first?.id }
            if state.mouseMonitor == nil {
                state.mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                    guard event.window is PasteNextPanel else { return event }
                    let isSecondaryClick = event.type == .rightMouseDown
                        || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
                    if isSecondaryClick {
                        if let id = state.hoveredCardID, !state.isSelected(id) {
                            DispatchQueue.main.async { state.handleCardClick(id, command: false, shift: false) }
                        }
                        return event
                    }
                    if event.clickCount == 1, let id = state.hoveredCardID {
                        let command = event.modifierFlags.contains(.command)
                        let shift = event.modifierFlags.contains(.shift)
                        DispatchQueue.main.async { state.handleCardClick(id, command: command, shift: shift) }
                        return event
                    }
                    if event.clickCount == 2,
                       let id = state.hoveredCardID,
                       let item = state.store.items.first(where: { $0.id == id }) {
                        // Shift + double click pastes the file path instead of the file.
                        let asPath = event.modifierFlags.contains(.shift)
                        DispatchQueue.main.async { state.paste(item, plainText: asPath) }
                    }
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = state.mouseMonitor {
                NSEvent.removeMonitor(monitor)
                state.mouseMonitor = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteNextDidCapture)) { _ in
            state.selectedIDs = []
            state.selectionAnchor = nil
        }
        .onChange(of: state.search) { _ in
            state.selectedIDs = []
            state.selectionAnchor = nil
            state.selectedID = state.filteredItems.first?.id
        }
        .onChange(of: state.category) { _ in
            state.selectedIDs = []
            state.selectionAnchor = nil
            state.selectedID = state.filteredItems.first?.id
        }
        .onChange(of: state.selectedFolder) { _ in
            state.selectedIDs = []
            state.selectionAnchor = nil
            state.selectedID = state.filteredItems.first?.id
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
            TextField(L("搜索剪贴板…", "Type to search…"), text: $state.search)
                .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
            if !state.search.isEmpty {
                Button { state.search = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary) }
                    .buttonStyle(.plain)
            } else {
                Text("⌘F").font(.system(size: 10)).foregroundColor(.secondary.opacity(0.8))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06)).cornerRadius(4)
            }
            Button { state.monitor.isPaused.toggle() } label: {
                Image(systemName: state.monitor.isPaused ? "play.circle" : "pause.circle")
                    .font(.system(size: 15)).foregroundColor(state.monitor.isPaused ? .orange : .secondary)
            }.buttonStyle(.plain).help(state.monitor.isPaused ? L("继续记录", "Resume") : L("暂停记录", "Pause"))
            Button { openSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 15)).foregroundColor(.secondary)
            }.buttonStyle(.plain).help(L("设置", "Settings"))
        }
        .padding(.horizontal, 13).frame(height: 44)
    }

    private var folderBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(state.tabOrder.enumerated()), id: \.offset) { index, key in
                        if state.folderName(for: key) != nil, index > 0,
                           state.folderName(for: state.tabOrder[index - 1]) == nil {
                            Divider()
                                .frame(height: 15)
                                .padding(.horizontal, 2)
                        }
                        tabChip(key)
                    }
                    Button { state.showingNewFolder = true } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22).background(Color.primary.opacity(0.06)).clipShape(Circle())
                    }.buttonStyle(.plain).help(L("新建文件夹", "New folder"))
                }
                .padding(.horizontal, 11).padding(.bottom, 9)
            }
            .onChange(of: state.activeTabKey) { key in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(key, anchor: .center) }
            }
        }
    }

    private func tabChip(_ key: String) -> some View {
        let active = state.activeTabKey == key
        return HStack(spacing: 3) {
            if let icon = state.tabIcon(key) { Image(systemName: icon).font(.system(size: 8)) }
            Text(state.tabTitle(key)).font(.system(size: 11, weight: active ? .semibold : .regular))
                .lineLimit(1)
        }
        .foregroundColor(active ? .accentColor : .secondary)
        .padding(.horizontal, 8).frame(height: 22)
        .background(active ? Color.accentColor.opacity(0.13) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { state.selectTab(key) }
        .onDrag {
            state.draggingTabKey = key
            return tabItemProvider(key)
        }
        .onDrop(of: [UTType.utf8PlainText, UTType.pasteNextTab, UTType.pasteNextCard], delegate: TabDropDelegate(targetKey: key, state: state))
        .help(state.folderName(for: key).map {
            L("拖入卡片可归档到「\($0)」；拖动可排序", "Drop a clip here to save it into \($0); drag to reorder")
        } ?? L("拖动可调整顺序", "Drag to reorder"))
        .modifier(TabContextMenu(key: key, state: state))
        .id(key)
    }

    private func tabItemProvider(_ key: String) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(key.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: PasteDragType.tab, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    @ViewBuilder private var clipList: some View {
        if state.filteredItems.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: state.search.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.system(size: 29, weight: .light)).foregroundColor(.secondary.opacity(0.55))
                Text(state.search.isEmpty ? L("复制点什么，历史会出现在这里", "Copy something and it appears here") : L("没有匹配的内容", "No matching clips"))
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                if state.selectedFolder != nil {
                    Button(L("返回全部", "Back to All")) { state.selectTab("all") }
                        .buttonStyle(.link).font(.caption)
                }
                Spacer()
            }.frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(state.filteredItems.enumerated()), id: \.element.id) { _, item in
                            clipRow(item, position: state.shortcutAssignments[item.id])
                        }
                    }
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: state.filteredItems.map(\.id))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(OverlayScrollerConfigurator().frame(width: 0, height: 0))
                }
                .coordinateSpace(name: "pasteClipScroll")
                .onChange(of: state.scrollGeneration) { _ in
                    if let id = state.selectedID { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(state.monitor.isPaused ? Color.orange : Color.green).frame(width: 5, height: 5)
            Text(state.monitor.isPaused ? L("已暂停", "Paused") : state.statusMessage.isEmpty ? L("正在记录", "Monitoring") : state.statusMessage)
                .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            // Count first, then the shortcut hints separated by middle dots.
            Text("\(state.filteredItems.count)/\(state.store.items.count)").font(.system(size: 10)).monospacedDigit().foregroundColor(.secondary)
            if state.selectedIDs.count > 1 {
                Text(L("已选 \(state.selectedIDs.count) 项", "\(state.selectedIDs.count) selected"))
                    .font(.system(size: 10, weight: .medium)).foregroundColor(.accentColor)
            }
            footerSeparator
            secondaryPasteHint
            footerSeparator
            Text("↵ \(L("粘贴", "Paste"))")
                .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.8))
            footerSeparator
            Text("⌘←→ \(L("切换", "Switch"))")
                .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 13).frame(height: 29)
        .background(Color.primary.opacity(0.025))
    }

    private var footerSeparator: some View {
        Text("·").font(.system(size: 10)).foregroundColor(.secondary.opacity(0.55))
    }

    /// Contextual hint for the secondary paste action (⇧↵ / ⇧double-click).
    @ViewBuilder private var secondaryPasteHint: some View {
        if let item = state.selectedItem() {
            let isFile = item.kind == .files
            Text(isFile ? "⇧↵ \(L("路径", "Path"))" : "⇧↵ \(L("纯文本", "Plain Text"))")
                .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.8))
                .help(isFile
                      ? L("⇧↵ 或 ⇧双击：粘贴文件绝对路径", "⇧↵ or ⇧double-click: paste the absolute path")
                      : L("⇧↵ 或 ⇧双击：以纯文本粘贴", "⇧↵ or ⇧double-click: paste as plain text"))
        }
    }

    private var keyboardCommands: some View {
        Group {
            Button("") { if let item = state.selectedItem() { state.paste(item) } }.keyboardShortcut(.return, modifiers: [])
            Button("") { if let item = state.selectedItem() { state.paste(item, plainText: true) } }.keyboardShortcut(.return, modifiers: [.shift])
            Button("") { state.previewItem = state.selectedItem() }.keyboardShortcut(.space, modifiers: [])
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: [.command])
            Button("") { state.delete(ids: Array(state.selectedIDs)) }.keyboardShortcut(.delete, modifiers: [.command])
            Button("") { state.togglePin(ids: Array(state.selectedIDs)) }.keyboardShortcut("p", modifiers: [.command])
            Button("") { state.moveSelectedItems(-1) }.keyboardShortcut(.upArrow, modifiers: [.command])
            Button("") { state.moveSelectedItems(1) }.keyboardShortcut(.downArrow, modifiers: [.command])
            Button("") { state.search = ""; state.category = .all; state.selectedFolder = nil; state.selectedID = state.store.items.first?.id }
                .keyboardShortcut("r", modifiers: [.command])
            Button("") { NSApp.keyWindow?.orderOut(nil) }.keyboardShortcut("w", modifiers: [.command])
        }.frame(width: 0, height: 0).opacity(0)
    }

    private func clipRow(_ item: ClipItem, position: Int?) -> some View {
        let card = ClipCard(item: item, selected: state.isSelected(item.id), image: state.store.image(for: item),
                            compact: true, shortcutIndex: position)
            .equatable()
            .id(item.id)
        return card
            .onHover { hovering in
                state.hoveredCardID = hovering ? item.id : nil
            }
            .onDrag {
                state.draggingCardID = item.id
                return CardDragProvider.make(item: item, image: state.store.image(for: item))
            }
            .onDrop(of: [UTType.utf8PlainText, UTType.pasteNextCard], delegate: CardDropDelegate(targetID: item.id, state: state))
            .contextMenu { contextMenu(item) }
            .help(L("拖动可排序；拖到文件夹标签可归档；也可直接拖进 Word 等应用",
                    "Drag to reorder, drop on a folder tab to save a copy, or drag into Word and other apps"))
    }

    @ViewBuilder private func contextMenu(_ item: ClipItem) -> some View {
        let targets = state.targetIDs(including: item.id)
        let multi = targets.count > 1
        let isFile = item.kind == .files
        Button { state.paste(item) } label: { Label(L("粘贴", "Paste"), systemImage: "arrow.down.doc") }
        Button { state.paste(item, plainText: true) } label: {
            Label(isFile ? L("粘贴为路径", "Paste as Path") : L("粘贴为纯文本", "Paste as Plain Text"),
                  systemImage: isFile ? "folder" : "textformat")
        }
        Divider()
        Button { state.togglePin(ids: targets) } label: {
            Label(pinTitle(for: targets), systemImage: pinSymbol(for: targets))
        }
        if item.isSaved {
            // A saved copy can only be removed from its folder — that IS the
            // manual deletion the user asked for.
            Button { state.removeFromFolder(ids: targets) } label: {
                Label(L("从文件夹移除", "Remove from Folder"), systemImage: "folder.badge.minus")
            }
        } else {
            if !state.allFolders.isEmpty {
                Menu(L("归档到文件夹", "Save to Folder")) {
                    ForEach(state.allFolders, id: \.self) { folder in
                        Button { state.archive(ids: targets, to: folder) } label: {
                            Label(folder, systemImage: "folder")
                        }
                    }
                }
            }
            Button { state.folderEditorItem = item } label: {
                Label(L("归档到文件夹…", "Save to Folder…"), systemImage: "folder.badge.plus")
            }
        }
        Button { state.previewItem = item } label: { Label(L("预览", "Preview"), systemImage: "eye") }
        if item.kind != .image { Button { state.editingItem = item } label: { Label(L("编辑文本", "Edit Text"), systemImage: "pencil") } }
        Divider()
        if multi {
            Button { state.moveSelectedItems(-1) } label: { Label(L("上移", "Move Up"), systemImage: "arrow.up") }
            Button { state.moveSelectedItems(1) } label: { Label(L("下移", "Move Down"), systemImage: "arrow.down") }
        }
        Button(role: .destructive) { state.delete(ids: targets) } label: {
            Label(multi ? L("删除 \(targets.count) 项", "Delete \(targets.count) items") : L("删除", "Delete"), systemImage: "trash")
        }
    }

    private func pinTitle(for ids: [ClipItem.ID]) -> String {
        let items = state.store.items.filter { ids.contains($0.id) }
        if items.isEmpty { return L("设为常驻", "Pin") }
        let allPinned = items.allSatisfy { $0.isPinned }
        return allPinned ? L("取消常驻", "Unpin") : L("设为常驻", "Pin")
    }
    private func pinSymbol(for ids: [ClipItem.ID]) -> String {
        let items = state.store.items.filter { ids.contains($0.id) }
        return items.allSatisfy { $0.isPinned } ? "pin.slash" : "pin"
    }

    private func togglePin(_ item: ClipItem) {
        state.store.togglePin(item)
        if state.category == .pinned && item.isPinned { state.selectedID = state.filteredItems.first?.id }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .showPasteNextSettings, object: nil)
    }
}

struct TabContextMenu: ViewModifier {
    let key: String
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        Group {
            if let folder = state.folderName(for: key) {
                content.contextMenu {
                    Button {
                        state.renameSourceFolder = folder
                        state.showingRenameFolder = true
                    } label: { Label(L("重命名文件夹…", "Rename Folder…"), systemImage: "pencil") }
                    Button(role: .destructive) { state.deleteFolder(folder) } label: {
                        Label(L("删除文件夹及其内容", "Delete Folder and Contents"), systemImage: "trash")
                    }
                }
            } else {
                content
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material; view.blendingMode = blendingMode; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material; view.blendingMode = blendingMode
    }
}
