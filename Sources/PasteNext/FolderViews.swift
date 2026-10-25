import SwiftUI

// MARK: - Creating a folder

final class NewFolderModel: ObservableObject {
    @Published var name = ""
}

struct NewFolderView: View {
    @ObservedObject var state: AppState
    @StateObject private var model = NewFolderModel()
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "folder.badge.plus").foregroundStyle(.tint)
                Text(L("新建文件夹", "New Folder")).font(.headline)
                Spacer()
            }
            TextField(L("文件夹名称，例如：常用", "Folder name, e.g. Favorites"), text: $model.name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(create)
            Text(L("文件夹用来长期保存剪贴板内容。把卡片拖到文件夹上即可归档一份独立副本。",
                   "Folders hold clips you want to keep. Drop a card onto one to save an independent copy."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("创建", "Create")) { create() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 360)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { nameFocused = true } }
    }

    private func create() {
        guard !model.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state.addFolder(model.name)
        dismiss()
    }
}

// MARK: - Renaming a folder

final class RenameFolderModel: ObservableObject {
    @Published var oldName = ""
    @Published var name = ""
    init(oldName: String) {
        self.oldName = oldName
        self.name = oldName
    }
}

struct RenameFolderView: View {
    @ObservedObject var state: AppState
    @StateObject private var model: RenameFolderModel
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(state: AppState) {
        self.state = state
        _model = StateObject(wrappedValue: RenameFolderModel(oldName: state.renameSourceFolder))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "pencil").foregroundStyle(.tint)
                Text(L("重命名文件夹", "Rename Folder")).font(.headline)
                Spacer()
            }
            TextField(L("文件夹名称", "Folder name"), text: $model.name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(save)
            Text(L("文件夹里已归档的内容会一起移到新名字下。", "Everything saved in this folder moves with the new name."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("保存", "Save")) { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty || model.name == model.oldName)
            }
        }
        .padding(20).frame(width: 360)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { nameFocused = true } }
    }

    private func save() {
        state.renameFolder(model.oldName, to: model.name)
        dismiss()
    }
}

// MARK: - Archiving a clip into a folder

/// The one place that explains what filing a clip away actually does, since the
/// result (an independent copy) is the whole point of folders.
final class FolderPickerModel: ObservableObject {
    @Published var newName = ""
}

struct FolderPickerView: View {
    let item: ClipItem
    @ObservedObject var state: AppState
    @StateObject private var model = FolderPickerModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "folder").foregroundStyle(.tint)
                Text(L("归档到文件夹", "Save to Folder")).font(.headline)
                Spacer()
            }
            Text(item.displayTitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
            Text(L("归档会创建一份独立副本：之后删除这条记录、或清空「全部」，这份副本都不会消失。",
                   "Saving creates an independent copy: deleting this entry or clearing the history will not affect it."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if state.allFolders.isEmpty {
                        Text(L("还没有文件夹，在下面新建一个。", "No folders yet. Create one below."))
                            .font(.callout).foregroundColor(.secondary).padding(.vertical, 8)
                    }
                    ForEach(state.allFolders, id: \.self) { folder in
                        Button {
                            state.archive(item, to: folder)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill").foregroundColor(.accentColor)
                                Text(folder).font(.system(size: 13))
                                Spacer()
                                Text("\(state.store.savedItems(in: folder).count)")
                                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 5).padding(.horizontal, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 190)

            HStack(spacing: 7) {
                TextField(L("新建文件夹", "New folder"), text: $model.newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createAndSave)
                Button { createAndSave() } label: { Image(systemName: "plus") }
                    .disabled(model.newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(18).frame(width: 360, height: 400)
    }

    private func createAndSave() {
        let name = model.newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        state.ensureFolderTab(name)
        state.archive(item, to: name)
        dismiss()
    }
}
