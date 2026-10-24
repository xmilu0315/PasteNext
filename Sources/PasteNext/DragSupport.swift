import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum PasteDragType {
    static let tab = "com.pastenext.tab"
    static let card = "com.pastenext.card"
}

extension UTType {
    static let pasteNextTab = UTType(exportedAs: PasteDragType.tab)
    static let pasteNextCard = UTType(exportedAs: PasteDragType.card)
}

@MainActor
enum CardDragProvider {
    static func make(item: ClipItem, image: NSImage?) -> NSItemProvider {
        let provider = NSItemProvider()
        let pngData: Data? = {
            guard item.kind != .files,
                  let image,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        }()
        if let pngData {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                completion(pngData, nil)
                return nil
            }
            provider.suggestedName = "PasteNext-\(item.id.uuidString.prefix(8)).png"
        }
        if !item.text.isEmpty {
            let data = Data(item.text.utf8)
            provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        }
        if pngData == nil, let path = item.filePaths?.first {
            let data = Data(URL(fileURLWithPath: path).absoluteString.utf8)
            provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        }
        let identifier = Data(item.id.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: PasteDragType.card, visibility: .all) { completion in
            completion(identifier, nil)
            return nil
        }
        return provider
    }
}

// Local drops use the drag-start state rather than resolving the provider again;
// this avoids custom-UTI failures inside SwiftUI while retaining full external data.
struct TabDropDelegate: DropDelegate {
    let targetKey: String
    let state: AppState

    func validateDrop(info: DropInfo) -> Bool {
        state.draggingTabKey != nil || (state.draggingCardID != nil && targetKey.hasPrefix("tag:"))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: state.draggingCardID != nil ? .copy : .move)
    }

    func dropEntered(info: DropInfo) {
        guard let source = state.draggingTabKey, source != targetKey else { return }
        state.moveTab(source, before: targetKey)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let cardID = state.draggingCardID, let tag = state.tagName(for: targetKey) {
            state.addTag(tag, to: cardID)
            state.selectTab(targetKey)
            state.draggingCardID = nil
            return true
        }
        // Live reordering already happened in dropEntered.
        state.draggingTabKey = nil
        return true
    }
}

struct CardDropDelegate: DropDelegate {
    let targetID: ClipItem.ID
    let state: AppState

    func validateDrop(info: DropInfo) -> Bool { state.draggingCardID != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func dropEntered(info: DropInfo) {
        guard let source = state.draggingCardID, source != targetID else { return }
        state.moveCard(source, before: targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        // Live reordering already happened in dropEntered.
        state.draggingCardID = nil
        return true
    }
}
