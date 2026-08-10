import Foundation

@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()
    @Published private(set) var projects: [ProjectRecord] = []
    @Published private(set) var segments: [ScriptSegmentRecord] = []
    @Published private(set) var favorites: [SavedAssetRecord] = []
    @Published private(set) var history: [SearchHistoryRecord] = []
    @Published private(set) var downloads: [DownloadRecord] = []

    private let fileURL: URL?

    init(inMemory: Bool = false, fileURL: URL? = nil) {
        if inMemory { self.fileURL = nil }
        else if let fileURL { self.fileURL = fileURL }
        else {
            let directory = PlatformPaths.applicationData
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let current = directory.appendingPathComponent("FootageFlow.database.json")
            let legacy = directory.deletingLastPathComponent().appendingPathComponent("FootageFinder/FootageFinder.database.json")
            Self.migrateDatabaseIfNeeded(current: current, legacy: legacy)
            self.fileURL = current
        }
        load()
    }

    static func migrateDatabaseIfNeeded(current: URL, legacy: URL) {
        guard !FileManager.default.fileExists(atPath: current.path) else { return }
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        try? FileManager.default.copyItem(at: legacy, to: current)
    }

    @discardableResult func addProject(name: String) -> ProjectRecord {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = ProjectRecord(name: clean.isEmpty ? tr("project.untitled") : clean)
        projects.append(project); save(); return project
    }
    func deleteProject(id: UUID) {
        projects.removeAll { $0.id == id }; segments.removeAll { $0.projectID == id }
        favorites = favorites.map { item in var value = item; if value.projectID == id { value.projectID = nil }; return value }
        history = history.map { item in var value = item; if value.projectID == id { value.projectID = nil }; return value }
        downloads = downloads.map { item in var value = item; if value.projectID == id { value.projectID = nil }; return value }
        save()
    }
    func updateProject(_ project: ProjectRecord) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updated = project; updated.updatedAt = .now; projects[index] = updated; save()
    }
    func replaceSegments(projectID: UUID?, values: [ScriptSegmentRecord]) {
        segments.removeAll { $0.projectID == projectID }; segments += values; touchProject(projectID); save()
    }
    func toggleFavorite(asset: MediaAsset, projectID: UUID?, segmentIndex: Int? = nil) {
        if let index = favorites.firstIndex(where: { $0.stableID == asset.stableID && $0.projectID == projectID }) { favorites.remove(at: index) }
        else { favorites.append(SavedAssetRecord(asset: asset, projectID: projectID, segmentIndex: segmentIndex)) }
        touchProject(projectID)
        save()
    }
    func isFavorite(_ asset: MediaAsset, projectID: UUID?) -> Bool { favorites.contains { $0.stableID == asset.stableID && $0.projectID == projectID } }
    func addHistory(_ record: SearchHistoryRecord) { history.insert(record, at: 0); if history.count > 300 { history.removeLast(history.count - 300) }; touchProject(record.projectID); save() }
    func deleteHistory(id: UUID) { history.removeAll { $0.id == id }; save() }
    func clearHistory() { history = []; save() }
    func addDownload(_ record: DownloadRecord) {
        guard !downloads.contains(where: { $0.localPath == record.localPath }) else { return }
        downloads.insert(record, at: 0); touchProject(record.projectID); save()
    }
    func deleteDownloadRecord(id: UUID) { downloads.removeAll { $0.id == id }; save() }

    func forceSave() { save() }

    private func touchProject(_ projectID: UUID?) {
        guard let projectID, let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].updatedAt = .now
    }

    private func load() {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let fileURL, let data = try? Data(contentsOf: fileURL), let database = try? decoder.decode(PersistentDatabase.self, from: data) else { return }
        projects = database.projects; segments = database.segments; favorites = database.favorites; history = database.history; downloads = database.downloads
    }
    private func save() {
        guard let fileURL else { return }
        let database = PersistentDatabase(projects: projects, segments: segments, favorites: favorites, history: history, downloads: downloads)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(database) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
