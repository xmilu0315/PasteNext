import SwiftUI

final class NewTagModel: ObservableObject {
    @Published var name = ""
}

struct NewTagView: View {
    @ObservedObject var state: AppState
    @StateObject private var model = NewTagModel()
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "tag.fill").foregroundStyle(.tint)
                Text(L("新建标签", "New Tag")).font(.headline)
                Spacer()
            }
            TextField(L("标签名称，例如：邮件模板", "Tag name, e.g. Email Template"), text: $model.name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(add)
            Text(L("标签会显示在顶部分类栏，可给任意剪贴板卡片添加多个标签。", "Tags appear in the filter bar and can be applied to any clip."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("创建", "Create")) { add() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 340)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { nameFocused = true } }
    }
    private func add() {
        guard !model.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state.addTag(model.name)
        dismiss()
    }
}

final class RenameTagModel: ObservableObject {
    @Published var oldName = ""
    @Published var name = ""
    init(oldName: String) {
        self.oldName = oldName
        self.name = oldName
    }
}

struct RenameTagView: View {
    @ObservedObject var state: AppState
    @StateObject private var model: RenameTagModel
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(state: AppState) {
        self.state = state
        _model = StateObject(wrappedValue: RenameTagModel(oldName: state.renameSourceTag))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "pencil").foregroundStyle(.tint)
                Text(L("重命名标签", "Rename Tag")).font(.headline)
                Spacer()
            }
            TextField(L("标签名称", "Tag name"), text: $model.name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(save)
            Text(L("所有使用该标签的剪贴板卡片都会同步更新。", "Every clip using this tag will be updated."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("保存", "Save")) { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty || model.name == model.oldName)
            }
        }
        .padding(20).frame(width: 340)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { nameFocused = true }
        }
    }

    private func save() {
        state.renameTag(model.oldName, to: model.name)
        dismiss()
    }
}
final class TagEditorModel: ObservableObject {
    @Published var selected: Set<String>
    @Published var newName = ""
    init(tags: [String]) { selected = Set(tags) }
}

struct TagEditorView: View {
    let item: ClipItem
    @ObservedObject var state: AppState
    @StateObject private var model: TagEditorModel
    @Environment(\.dismiss) private var dismiss

    init(item: ClipItem, state: AppState) {
        self.item = item
        self.state = state
        _model = StateObject(wrappedValue: TagEditorModel(tags: item.itemTags))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("管理标签", "Manage Tags")).font(.headline)
            Text(item.displayTitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    if state.allTags.isEmpty {
                        Text(L("还没有标签，在下方创建第一个。", "No tags yet. Create your first one below."))
                            .font(.callout).foregroundColor(.secondary).padding(.vertical, 8)
                    }
                    ForEach(state.allTags, id: \.self) { tag in
                        Toggle(isOn: Binding(
                            get: { model.selected.contains(tag) },
                            set: { enabled in if enabled { model.selected.insert(tag) } else { model.selected.remove(tag) } }
                        )) {
                            Label("#\(tag)", systemImage: "tag").font(.system(size: 13))
                        }.toggleStyle(.checkbox)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 7) {
                TextField(L("新标签", "New tag"), text: $model.newName)
                    .textFieldStyle(.roundedBorder).onSubmit(createAndSelect)
                Button { createAndSelect() } label: { Image(systemName: "plus") }
                    .disabled(model.newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("保存", "Save")) {
                    state.setTags(Array(model.selected), for: item)
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(18).frame(width: 330, height: 390)
    }

    private func createAndSelect() {
        let name = model.newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        state.ensureTagTab(name)
        model.selected.insert(name)
        model.newName = ""
    }
}
