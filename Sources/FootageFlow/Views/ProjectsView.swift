import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var selectedID: UUID?
    @State private var newName = ""
    @State private var showNewProject = false
    @State private var confirmDelete = false

    private var selected: ProjectRecord? { selectedID.flatMap { id in store.projects.first { $0.id == id } } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack { Text("我的项目").font(.title2.bold()); Spacer(); Button { showNewProject = true } label: { Image(systemName: "plus") } }.padding()
                List(store.projects, selection: $selectedID) { project in
                    VStack(alignment: .leading, spacing: 3) { Text(project.name); Text("更新于 \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }.tag(project.id)
                }
            }.frame(minWidth: 250, idealWidth: 300)
            if let project = selected {
                ProjectDetail(project: project, onDelete: { confirmDelete = true })
            } else {
                ContentUnavailableView("选择或新建项目", systemImage: "folder", description: Text("收藏、下载和文稿会按项目归类"))
            }
        }
        .sheet(isPresented: $showNewProject) {
            VStack(alignment: .leading, spacing: 16) {
                Text("新建项目").font(.title2.bold())
                TextField("项目名称", text: $newName).textFieldStyle(.roundedBorder).onSubmit { createProject() }
                HStack { Spacer(); Button("取消") { showNewProject = false }; Button("创建") { createProject() }.buttonStyle(.borderedProminent).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }.padding(24).frame(width: 420)
        }
        .alert("删除项目记录？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) { }
            Button("删除项目", role: .destructive) { if let selectedID { store.deleteProject(id: selectedID); self.selectedID = nil } }
        } message: { Text("不会删除已经下载到本地的素材文件。") }
    }

    private func createProject() {
        let project = store.addProject(name: newName); selectedID = project.id; newName = ""; showNewProject = false
    }
}

private struct ProjectDetail: View {
    let project: ProjectRecord
    let onDelete: () -> Void
    @EnvironmentObject private var store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("项目名称", text: Binding(get: { project.name }, set: { value in var updated = project; updated.name = value; store.updateProject(updated) }))
                    .textFieldStyle(.plain).font(.largeTitle.bold())
                Button(role: .destructive, action: onDelete) { Label("删除项目", systemImage: "trash") }
            }
            HStack(spacing: 20) {
                Label("收藏 \(store.favorites.filter { $0.projectID == project.id }.count)", systemImage: "heart")
                Label("下载 \(store.downloads.filter { $0.projectID == project.id }.count)", systemImage: "arrow.down.circle")
                Label("搜索 \(store.history.filter { $0.projectID == project.id }.count)", systemImage: "magnifyingglass")
            }.foregroundStyle(.secondary)
            Text("项目文稿").font(.headline)
            TextEditor(text: Binding(get: { project.script }, set: { value in var updated = project; updated.script = value; store.updateProject(updated) }))
                .font(.body).padding(8).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }.padding(22)
    }
}
