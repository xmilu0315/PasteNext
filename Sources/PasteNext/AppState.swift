import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    let store = HistoryStore()
    let monitor = ClipboardMonitor()
    @Published var selectedID: ClipItem.ID?
    @Published var selectedIDs: Set<ClipItem.ID> = []
    @Published var search = ""
    @Published var category: ClipCategory = .all
    @Published var selectedTag: String?
    @Published var previewItem: ClipItem?
    @Published var editingItem: ClipItem?
    @Published var tagEditorItem: ClipItem?
    @Published var showingNewTag = false
    @Published var showingRenameTag = false
    @Published var renameSourceTag = ""
    @Published var captureCount = 0
    @Published var scrollGeneration = 0
    @Published var statusMessage = ""
    @Published var customTags: [String] = UserDefaults.standard.stringArray(forKey: "customTags") ?? []
    @Published var tabOrder: [String] = UserDefaults.standard.stringArray(forKey: "tabOrder") ?? []
    var previousApp: NSRunningApplication?
    var draggingCardID: ClipItem.ID?
    var draggingTabKey: String?
    var hoveredCardID: ClipItem.ID?
    var selectionAnchor: ClipItem.ID?
    var mouseMonitor: Any?
    private var monitorObserver: AnyCancellable?
    static let builtinTabs = ["all", "pinned", "today"]

    init() {
        CaptureSound.migrateStoredValue()
        UserDefaults.standard.removeObject(forKey: "menuBarIconStyle")
        normalizeTabs()
        // Remember the last app that was in front besides PasteNext. Sampling it
        // only when the panel opens is unreliable: clicking the menu-bar item
        // can already make PasteNext the frontmost app.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in self?.previousApp = app }
        }
        store.limit = max(50, UserDefaults.standard.integer(forKey: "historyLimit") == 0 ? 500 : UserDefaults.standard.integer(forKey: "historyLimit"))
        monitor.onCapture = { [weak self] item, image, html in
            guard let self else { return }
            self.store.mergeOrAdd(item, image: image, htmlData: html)
            self.captureCount += 1
            self.selectedID = self.store.items.first(where: { existing in
                if existing.kind != item.kind { return false }
                if existing.filePaths != nil || item.filePaths != nil {
                    return (existing.filePaths ?? []) == (item.filePaths ?? [])
                }
                return existing.text == item.text
            })?.id
            if let newID = self.selectedID {
                self.selectedIDs = [newID]
                self.selectionAnchor = newID
            }
            self.statusMessage = item.isRemote ? L("已接收接力内容", "Received from Universal Clipboard") : L("已捕获新内容", "Captured new clip")
            NotificationCenter.default.post(name: .pasteNextDidCapture, object: nil)
        }
        monitor.onSound = {
            CaptureSound.playSelected()
        }
        PasteService.statusSink = { [weak self] message in
            Task { @MainActor in self?.statusMessage = message }
        }
        monitor.onRemoteImage = { [weak self] id, image in
            Task { @MainActor in
                guard let self else { return }
                self.store.attachImage(id: id, image: image)
                self.captureCount += 1
                NotificationCenter.default.post(name: .pasteNextDidCapture, object: nil)
            }
        }
        monitorObserver = monitor.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        monitor.start()
    }

    var filteredItems: [ClipItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.items.filter { item in
            let tagMatches = selectedTag.map { item.itemTags.contains($0) } ?? true
            return category.contains(item) && tagMatches && (query.isEmpty || item.text.lowercased().contains(query) || item.displayTitle.lowercased().contains(query) || (item.sourceName?.lowercased().contains(query) ?? false))
        }.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.effectiveSortIndex != rhs.effectiveSortIndex { return lhs.effectiveSortIndex > rhs.effectiveSortIndex }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func select(_ item: ClipItem) { selectedID = item.id }
    /// Called every time the panel opens.
    ///
    /// Always focus the most recent copy, so Return or ⌘1 pastes it right away.
    /// `store.items` is newest-first, so its first element is exactly that
    /// clip — even when pinned cards sort above it in the list. Keeping the
    /// previous selection here used to leave the highlight on a stale card.
    func reloadSelection() {
        if let latest = store.items.first, filteredItems.contains(where: { $0.id == latest.id }) {
            selectedID = latest.id
        } else {
            selectedID = filteredItems.first?.id
        }
        selectedIDs = selectedID.map { [$0] } ?? []
        selectionAnchor = selectedID
        // Opening the panel must also bring the newest card into view: the list
        // keeps whatever scroll offset it had, which could be pages deep.
        scrollGeneration &+= 1
    }
    func selectedItem() -> ClipItem? {
        if let selectedID, let item = filteredItems.first(where: { $0.id == selectedID }) { return item }
        return filteredItems.first
    }
    func isSelected(_ id: ClipItem.ID) -> Bool { selectedIDs.contains(id) }
    func selectedClipItems() -> [ClipItem] { filteredItems.filter { selectedIDs.contains($0.id) } }
    func targetIDs(including id: ClipItem.ID) -> [ClipItem.ID] {
        selectedIDs.contains(id) && selectedIDs.count > 1 ? Array(selectedIDs) : [id]
    }

    func handleCardClick(_ id: ClipItem.ID, command: Bool, shift: Bool) {
        if shift {
            let list = filteredItems
            let anchor = selectionAnchor ?? selectedID ?? id
            guard let from = list.firstIndex(where: { $0.id == anchor }),
                  let to = list.firstIndex(where: { $0.id == id }) else { return }
            let range = from <= to ? from...to : to...from
            selectedIDs = Set(range.map { list[$0].id })
            selectedID = id
            selectionAnchor = anchor
            return
        }
        if command {
            if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
            selectedID = id
            selectionAnchor = id
            return
        }
        selectedIDs = [id]
        selectedID = id
        selectionAnchor = id
    }

    func delete(ids: [ClipItem.ID]) {
        for id in ids {
            if let item = store.items.first(where: { $0.id == id }) { store.delete(item) }
            selectedIDs.remove(id)
        }
        if let selectedID, !store.items.contains(where: { $0.id == selectedID }) { self.selectedID = filteredItems.first?.id }
        objectWillChange.send()
    }

    func togglePin(ids: [ClipItem.ID]) {
        let items = store.items.filter { ids.contains($0.id) }
        guard !items.isEmpty else { return }
        let target = !items.allSatisfy { $0.isPinned }
        for item in items {
            var updated = item
            updated.isPinned = target
            store.update(updated)
        }
        objectWillChange.send()
    }

    func addTagToSelection(_ tag: String, ids: [ClipItem.ID]? = nil) {
        let targetIDs = ids ?? Array(selectedIDs)
        guard !targetIDs.isEmpty else { return }
        for item in store.items.filter({ targetIDs.contains($0.id) }) where !item.itemTags.contains(tag) {
            var updated = item
            updated.tags = (item.itemTags + [tag]).sorted()
            store.update(updated)
        }
        normalizeTabs()
        objectWillChange.send()
    }

    func removeTagFromSelection(_ tag: String, ids: [ClipItem.ID]? = nil) {
        let targetIDs = ids ?? Array(selectedIDs)
        guard !targetIDs.isEmpty else { return }
        for item in store.items.filter({ targetIDs.contains($0.id) }) where item.itemTags.contains(tag) {
            var updated = item
            updated.tags = item.itemTags.filter { $0 != tag }
            store.update(updated)
        }
        objectWillChange.send()
    }

    func moveSelectedItems(_ offset: Int) {
        let list = filteredItems
        guard !selectedIDs.isEmpty, !list.isEmpty else { return }
        var ordered = list
        if offset < 0 {
            for index in 1..<ordered.count where selectedIDs.contains(ordered[index].id) && !selectedIDs.contains(ordered[index - 1].id) {
                ordered.swapAt(index, index - 1)
            }
        } else {
            for index in stride(from: ordered.count - 2, through: 0, by: -1) where selectedIDs.contains(ordered[index].id) && !selectedIDs.contains(ordered[index + 1].id) {
                ordered.swapAt(index, index + 1)
            }
        }
        store.reorder(ordered)
        objectWillChange.send()
    }
    func moveSelection(_ offset: Int) {
        let list = filteredItems
        guard !list.isEmpty else { return }
        let current = list.firstIndex(where: { $0.id == selectedID }) ?? 0
        let next = min(max(current + offset, 0), list.count - 1)
        selectedID = list[next].id
        selectedIDs = [list[next].id]
        selectionAnchor = list[next].id
        scrollGeneration &+= 1
    }
    /// The app that should receive the paste. Falls back to the current
    /// frontmost app when it is not PasteNext itself.
    var pasteTarget: NSRunningApplication? {
        if let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            return previousApp
        }
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front
        }
        return nil
    }

    /// Writes the clip to the pasteboard and delivers ⌘V to the target app.
    func paste(_ item: ClipItem, plainText: Bool = false) {
        NotificationCenter.default.post(name: .hidePasteNextPanel, object: nil)
        PasteService.copy(item, image: store.image(for: item), monitor: monitor, paste: true,
                          plainText: plainText, htmlFragment: store.fragment(named: item.htmlFilename))
        // Pasting is an explicit "this is the one" — float it to the front so it
        // becomes ⌘1 and the clipboard already holds it.
        store.promote(id: item.id)
        statusMessage = L("已粘贴", "Pasted")
    }
    /// ⌘1…⌘9 map onto the most recent **non-pinned** clips. Pinned cards are
    /// permanent fixtures at the top of the list; giving them shortcut slots
    /// would push the clips the user actually copies around.
    var shortcutAssignments: [UUID: Int] { Self.shortcutAssignments(for: filteredItems) }

    /// Pure so the self-test can exercise it without touching live state.
    static func shortcutAssignments(for items: [ClipItem]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        var index = 0
        for item in items where !item.isPinned {
            index += 1
            guard index <= 9 else { break }
            result[item.id] = index
        }
        return result
    }

    /// Pastes the n-th most recent non-pinned card, for ⌘1…⌘9 (verbatim) and
    /// ⌘⇧1…⌘⇧9 (values only).
    /// The index follows what the user actually sees, so it also respects the
    /// active tab and the search filter.
    func pasteItem(at index: Int, plainText: Bool = false) {
        let items = filteredItems.filter { !$0.isPinned }
        guard index >= 0, index < items.count else { return }
        paste(items[index], plainText: plainText)
    }


    func addTag(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !customTags.contains(clean) {
            customTags.append(clean)
            UserDefaults.standard.set(customTags, forKey: "customTags")
        }
        normalizeTabs()
        selectedTag = clean
        category = .all
    }
    var allTags: [String] {
        Array(Set(customTags + store.items.flatMap(\.itemTags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var activeTabKey: String {
        if let selectedTag { return "tag:\(selectedTag)" }
        switch category {
        case .pinned: return "pinned"
        case .today: return "today"
        default: return "all"
        }
    }

    func tabTitle(_ key: String) -> String {
        switch key {
        case "all": return L("全部", "All")
        case "pinned": return L("常驻", "Pinned")
        case "today": return L("今天", "Today")
        default: return "#" + String(key.dropFirst(4))
        }
    }
    func tabIcon(_ key: String) -> String? {
        switch key {
        case "all": return nil
        case "pinned": return "pin.fill"
        case "today": return nil
        default: return nil
        }
    }
    func tagName(for key: String) -> String? {
        key.hasPrefix("tag:") ? String(key.dropFirst(4)) : nil
    }

    func setPollInterval(_ value: Double) {
        UserDefaults.standard.set(value, forKey: "pollInterval")
        monitor.stop()
        monitor.start()
    }

    func addIgnoredBundleID(_ bundleID: String) {
        monitor.ignoredBundleIDs.insert(bundleID)
        UserDefaults.standard.set(monitor.ignoredBundleIDs.sorted().joined(separator: ","), forKey: "ignoredApps")
    }

    func removeIgnoredBundleID(_ bundleID: String) {
        monitor.ignoredBundleIDs.remove(bundleID)
        UserDefaults.standard.set(monitor.ignoredBundleIDs.sorted().joined(separator: ","), forKey: "ignoredApps")
    }

    func selectTab(_ key: String) {
        if let tag = tagName(for: key) { selectedTag = tag; category = .all; return }
        selectedTag = nil
        switch key {
        case "pinned": category = .pinned
        case "today": category = .today
        default: category = .all
        }
    }

    func stepTab(_ offset: Int) {
        guard !tabOrder.isEmpty else { return }
        let current = tabOrder.firstIndex(of: activeTabKey) ?? 0
        let next = (current + offset + tabOrder.count) % tabOrder.count
        selectTab(tabOrder[next])
    }

    func moveTab(_ source: String, before target: String) {
        guard source != target,
              let sourceIndex = tabOrder.firstIndex(of: source),
              let targetIndex = tabOrder.firstIndex(of: target) else { return }
        var next = tabOrder
        next.remove(at: sourceIndex)
        guard let shiftedTarget = next.firstIndex(of: target) else { return }
        // Dragging to the right lands after the target; dragging left lands before it.
        let insertion = sourceIndex < targetIndex ? shiftedTarget + 1 : shiftedTarget
        next.insert(source, at: min(insertion, next.count))
        tabOrder = next
        UserDefaults.standard.set(next, forKey: "tabOrder")
    }

    func ensureTagTab(_ tag: String) {
        if !customTags.contains(tag) {
            customTags.append(tag)
            UserDefaults.standard.set(customTags, forKey: "customTags")
        }
        normalizeTabs()
    }

    func renameTag(_ oldName: String, to newRawName: String) {
        let newName = newRawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != oldName, !customTags.contains(newName),
              let index = customTags.firstIndex(of: oldName) else { return }
        customTags[index] = newName
        UserDefaults.standard.set(customTags, forKey: "customTags")
        tabOrder = tabOrder.map { $0 == "tag:\(oldName)" ? "tag:\(newName)" : $0 }
        UserDefaults.standard.set(tabOrder, forKey: "tabOrder")
        for item in store.items where item.itemTags.contains(oldName) {
            var updated = item
            updated.tags = item.itemTags.map { $0 == oldName ? newName : $0 }.sorted()
            store.update(updated)
        }
        if selectedTag == oldName { selectedTag = newName }
        normalizeTabs()
    }

    func deleteTag(_ name: String) {
        customTags.removeAll { $0 == name }
        UserDefaults.standard.set(customTags, forKey: "customTags")
        tabOrder.removeAll { $0 == "tag:\(name)" }
        UserDefaults.standard.set(tabOrder, forKey: "tabOrder")
        for item in store.items where item.itemTags.contains(name) {
            var updated = item
            let tags = item.itemTags.filter { $0 != name }
            updated.tags = tags.isEmpty ? nil : tags
            store.update(updated)
        }
        if selectedTag == name { selectedTag = nil; category = .all }
        normalizeTabs()
    }

    func addTag(_ tag: String, to itemID: ClipItem.ID) {
        guard let item = store.items.first(where: { $0.id == itemID }), !item.itemTags.contains(tag) else { return }
        var updated = item
        updated.tags = (item.itemTags + [tag]).sorted()
        store.update(updated)
        normalizeTabs()
    }

    func moveCard(_ itemID: ClipItem.ID, before targetID: ClipItem.ID) {
        guard itemID != targetID, let dragged = store.items.first(where: { $0.id == itemID }) else { return }
        var ordered = filteredItems
        guard let from = ordered.firstIndex(where: { $0.id == itemID }),
              let originalTarget = ordered.firstIndex(where: { $0.id == targetID }) else { return }
        ordered.remove(at: from)
        guard let shiftedTarget = ordered.firstIndex(where: { $0.id == targetID }) else { return }
        let insertion = from < originalTarget ? shiftedTarget + 1 : shiftedTarget
        ordered.insert(dragged, at: min(insertion, ordered.count))
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            store.reorder(ordered)
            selectedID = itemID
            objectWillChange.send()
        }
    }

    private func normalizeTabs() {
        var next = tabOrder.filter { Self.builtinTabs.contains($0) || tagName(for: $0) != nil }
        for key in Self.builtinTabs where !next.contains(key) {
            if key == "all" { next.insert(key, at: 0) } else { next.append(key) }
        }
        for tag in customTags where !next.contains("tag:\(tag)") { next.append("tag:\(tag)") }
        for tag in allTags where !next.contains("tag:\(tag)") { next.append("tag:\(tag)") }
        if next != tabOrder {
            tabOrder = next
            UserDefaults.standard.set(next, forKey: "tabOrder")
        }
    }
    func setTags(_ tags: [String], for item: ClipItem) {
        var updated = item
        updated.tags = Array(Set(tags)).sorted()
        store.update(updated)
        if let index = store.items.firstIndex(where: { $0.id == item.id }) {
            tagEditorItem = store.items[index]
        }
    }
    func delete(_ item: ClipItem) {
        store.delete(item)
        selectedID = filteredItems.first?.id
    }
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch { return error.localizedDescription }
    }
}
