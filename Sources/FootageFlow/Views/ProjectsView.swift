import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedID: UUID?
    @State private var newName = ""
    @State private var showNewProject = false
    @State private var confirmDelete = false

    private var selected: ProjectRecord? { selectedID.flatMap { id in store.projects.first { $0.id == id } } }
    private var recentProjects: [ProjectRecord] { store.projects.sorted { $0.updatedAt > $1.updatedAt } }

    var body: some View {
        let _ = localization.language
        HSplitView {
            VStack(spacing: 0) {
                HStack { Text(tr("project.title")).font(.title2.bold()); Spacer(); Button { showNewProject = true } label: { Image(systemName: "plus") }.help(tr("project.new")) }.padding()
                List(recentProjects, selection: $selectedID) { project in
                    VStack(alignment: .leading, spacing: 3) { Text(project.name); Text(tr("project.updated", project.updatedAt.formatted(date: .abbreviated, time: .shortened))).font(.caption).foregroundStyle(.secondary) }.tag(project.id)
                }
            }.frame(minWidth: 250, idealWidth: 300)
            if let project = selected {
                ProjectDetail(project: project, onDelete: { confirmDelete = true })
            } else {
                ContentUnavailableView(tr("project.selectOrCreate"), systemImage: "folder", description: Text(tr("project.selectDescription")))
            }
        }
        .sheet(isPresented: $showNewProject) {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("project.new")).font(.title2.bold())
                TextField(tr("project.name"), text: $newName).textFieldStyle(.roundedBorder).onSubmit { createProject() }
                HStack { Spacer(); Button(tr("common.cancel")) { showNewProject = false }; Button(tr("common.create")) { createProject() }.buttonStyle(.borderedProminent).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }.padding(24).frame(width: 420)
        }
        .alert(tr("project.deleteTitle"), isPresented: $confirmDelete) {
            Button(tr("common.cancel"), role: .cancel) { }
            Button(tr("project.delete"), role: .destructive) { if let selectedID { store.deleteProject(id: selectedID); self.selectedID = nil } }
        } message: { Text(tr("project.deleteHelp")) }
    }

    private func createProject() {
        let project = store.addProject(name: newName); selectedID = project.id; newName = ""; showNewProject = false
    }
}

private struct ProjectDetail: View {
    let project: ProjectRecord
    let onDelete: () -> Void
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        let _ = localization.language
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField(tr("project.name"), text: Binding(get: { project.name }, set: { value in var updated = project; updated.name = value; store.updateProject(updated) }))
                    .textFieldStyle(.plain).font(.largeTitle.bold())
                Button { openProjectFolder() } label: { Label(tr("project.openFolder"), systemImage: "folder") }
                Button(role: .destructive, action: onDelete) { Label(tr("project.delete"), systemImage: "trash") }
            }
            HStack(spacing: 20) {
                Label(tr("project.favoriteCount", store.favorites.filter { $0.projectID == project.id }.count), systemImage: "heart")
                Label(tr("project.downloadCount", store.downloads.filter { $0.projectID == project.id }.count), systemImage: "arrow.down.circle")
                Label(tr("project.searchCount", store.history.filter { $0.projectID == project.id }.count), systemImage: "magnifyingglass")
            }.foregroundStyle(.secondary)
            Text(tr("project.script")).font(.headline)
            TextEditor(text: Binding(get: { project.script }, set: { value in var updated = project; updated.script = value; store.updateProject(updated) }))
                .font(.body).padding(8).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }.padding(22)
    }

    private func openProjectFolder() {
        let existingDirectory = store.downloads.first { $0.projectID == project.id }.map { URL(fileURLWithPath: $0.localPath).deletingLastPathComponent() }
        let directory = existingDirectory ?? DownloadPathSafety.projectDirectory(projectName: project.name)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        DesktopPlatform.shared.open(directory)
    }
}
