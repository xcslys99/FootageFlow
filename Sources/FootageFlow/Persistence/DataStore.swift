import Foundation

@MainActor
final class DataStore: ObservableObject {
  static let shared = DataStore()
  @Published private(set) var projects: [ProjectRecord] = []
  @Published private(set) var segments: [ScriptSegmentRecord] = []
  @Published private(set) var favorites: [SavedAssetRecord] = []
  @Published private(set) var history: [SearchHistoryRecord] = []
  @Published private(set) var downloads: [DownloadRecord] = []

  private let repository: PersistentStore

  init(inMemory: Bool = false, fileURL: URL? = nil) {
    repository = PersistentStore(inMemory: inMemory, fileURL: fileURL)
    synchronize()
  }

  nonisolated static func migrateDatabaseIfNeeded(current: URL, legacy: URL) {
    PersistentStore.migrateDatabaseIfNeeded(current: current, legacy: legacy)
  }

  @discardableResult func addProject(name: String) -> ProjectRecord {
    let project = repository.addProject(name: name)
    synchronize()
    return project
  }

  func deleteProject(id: UUID) {
    repository.deleteProject(id: id)
    synchronize()
  }

  func updateProject(_ project: ProjectRecord) {
    repository.updateProject(project)
    synchronize()
  }

  func replaceSegments(projectID: UUID?, values: [ScriptSegmentRecord]) {
    repository.replaceSegments(projectID: projectID, values: values)
    synchronize()
  }

  func toggleFavorite(asset: MediaAsset, projectID: UUID?, segmentIndex: Int? = nil) {
    repository.toggleFavorite(asset: asset, projectID: projectID, segmentIndex: segmentIndex)
    synchronize()
  }

  func isFavorite(_ asset: MediaAsset, projectID: UUID?) -> Bool {
    repository.isFavorite(asset, projectID: projectID)
  }

  func addHistory(_ record: SearchHistoryRecord) {
    repository.addHistory(record)
    synchronize()
  }

  func deleteHistory(id: UUID) {
    repository.deleteHistory(id: id)
    synchronize()
  }

  func clearHistory() {
    repository.clearHistory()
    synchronize()
  }

  func addDownload(_ record: DownloadRecord) {
    repository.addDownload(record)
    synchronize()
  }

  func deleteDownloadRecord(id: UUID) {
    repository.deleteDownloadRecord(id: id)
    synchronize()
  }

  func forceSave() { repository.forceSave() }

  private func synchronize() {
    projects = repository.projects
    segments = repository.segments
    favorites = repository.favorites
    history = repository.history
    downloads = repository.downloads
  }
}
