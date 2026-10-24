import AppKit
import SwiftUI

struct PreviewView: View {
    let item: ClipItem
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SourceIcon(item: item)
                VStack(alignment: .leading) {
                    Text(item.displayTitle).font(.headline).lineLimit(1)
                    Text("\(item.sourceName ?? "") · \(item.createdAt.formatted())").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }.buttonStyle(.plain)
            }.padding()
            Divider()
            ScrollView {
                Group {
                    if item.kind == .image, let image = state.store.image(for: item) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 640, maxHeight: 480)
                    } else {
                        Text(item.text).font(item.kind == .code ? .system(.body, design: .monospaced) : .body)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(24)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(item.stableColor.opacity(0.18))
            Divider()
            HStack {
                Text("\(item.text.utf8.count) \(L("字节", "bytes"))").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(L("编辑", "Edit")) { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { state.editingItem = item } }
                Button(L("粘贴", "Paste")) { dismiss(); state.paste(item) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }.frame(minWidth: 600, idealWidth: 680, minHeight: 480, idealHeight: 560)
    }
}

final class EditClipModel: ObservableObject {
    @Published var text: String
    @Published var title: String
    init(item: ClipItem) { text = item.text; title = item.title ?? "" }
}

struct EditClipView: View {
    let item: ClipItem
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: EditClipModel
    init(item: ClipItem, state: AppState) {
        self.item = item
        self.state = state
        _model = StateObject(wrappedValue: EditClipModel(item: item))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.text.isEmpty ? L("新建片段", "New Clip") : L("编辑片段", "Edit Clip")).font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text(L("标题（可选）", "Title (optional)")).font(.caption).foregroundColor(.secondary)
                TextField(L("给这段内容起个名字", "Name this clip"), text: $model.title).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L("内容", "Content")).font(.caption).foregroundColor(.secondary)
                TextEditor(text: $model.text).font(.system(.body, design: item.kind == .code ? .monospaced : .default))
                    .frame(minHeight: 260).padding(5).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            }
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("保存", "Save")) { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(model.text.isEmpty)
            }
        }.padding(22).frame(width: 540, height: 440)
    }
    private func save() {
        var updated = item
        updated.text = model.text
        updated.title = model.title.isEmpty ? nil : model.title
        updated.kind = ClipClassifier.classify(model.text)
        if state.store.items.contains(where: { $0.id == item.id }) { state.store.update(updated) }
        else { state.store.add(updated) }
        dismiss()
    }
}
