import Foundation

final class PersistentStore {
  private(set) var database: PersistentDatabase
  private let fileURL: URL?

  var projects: [ProjectRecord] { database.projects }
  var segments: [ScriptSegmentRecord] { database.segments }
  var favorites: [SavedAssetRecord] { database.favorites }
  var history: [SearchHistoryRecord] { database.history }
  var downloads: [DownloadRecord] { database.downloads }

  init(inMemory: Bool = false, fileURL: URL? = nil) {
    if inMemory {
      self.fileURL = nil
    } else if let fileURL {
      self.fileURL = fileURL
    } else {
      let directory = PlatformPaths.applicationData
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let current = directory.appendingPathComponent("FootageFlow.database.json")
      #if os(macOS)
        let legacy = directory.deletingLastPathComponent().appendingPathComponent(
          "FootageFinder/FootageFinder.database.json")
        Self.migrateDatabaseIfNeeded(current: current, legacy: legacy)
      #endif
      self.fileURL = current
    }
    database = Self.load(from: self.fileURL) ?? PersistentDatabase()
  }

  static func migrateDatabaseIfNeeded(current: URL, legacy: URL) {
    guard !FileManager.default.fileExists(atPath: current.path) else { return }
    guard FileManager.default.fileExists(atPath: legacy.path) else { return }
    try? FileManager.default.copyItem(at: legacy, to: current)
  }

  @discardableResult func addProject(name: String) -> ProjectRecord {
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let project = ProjectRecord(name: clean.isEmpty ? tr("project.untitled") : clean)
    database.projects.append(project)
    save()
    return project
  }

  func deleteProject(id: UUID) {
    database.projects.removeAll { $0.id == id }
    database.segments.removeAll { $0.projectID == id }
    database.favorites = database.favorites.map { item in
      var value = item
      if value.projectID == id { value.projectID = nil }
      return value
    }
    database.history = database.history.map { item in
      var value = item
      if value.projectID == id { value.projectID = nil }
      return value
    }
    database.downloads = database.downloads.map { item in
      var value = item
      if value.projectID == id { value.projectID = nil }
      return value
    }
    save()
  }

  func updateProject(_ project: ProjectRecord) {
    guard let index = database.projects.firstIndex(where: { $0.id == project.id }) else { return }
    var updated = project
    updated.updatedAt = .now
    database.projects[index] = updated
    save()
  }

  func replaceSegments(projectID: UUID?, values: [ScriptSegmentRecord]) {
    database.segments.removeAll { $0.projectID == projectID }
    database.segments += values
    touchProject(projectID)
    save()
  }

  func toggleFavorite(asset: MediaAsset, projectID: UUID?, segmentIndex: Int? = nil) {
    if let index = database.favorites.firstIndex(where: {
      $0.stableID == asset.stableID && $0.projectID == projectID
    }) {
      database.favorites.remove(at: index)
    } else {
      database.favorites.append(
        SavedAssetRecord(asset: asset, projectID: projectID, segmentIndex: segmentIndex))
    }
    touchProject(projectID)
    save()
  }

  func addFavorite(asset: MediaAsset, projectID: UUID?, segmentIndex: Int? = nil) {
    guard !isFavorite(asset, projectID: projectID) else { return }
    database.favorites.append(
      SavedAssetRecord(asset: asset, projectID: projectID, segmentIndex: segmentIndex))
    touchProject(projectID)
    save()
  }

  func isFavorite(_ asset: MediaAsset, projectID: UUID?) -> Bool {
    database.favorites.contains { $0.stableID == asset.stableID && $0.projectID == projectID }
  }

  func addHistory(_ record: SearchHistoryRecord) {
    database.history.insert(record, at: 0)
    if database.history.count > 300 {
      database.history.removeLast(database.history.count - 300)
    }
    touchProject(record.projectID)
    save()
  }

  func deleteHistory(id: UUID) {
    database.history.removeAll { $0.id == id }
    save()
  }

  func clearHistory() {
    database.history = []
    save()
  }

  func addDownload(_ record: DownloadRecord) {
    guard !database.downloads.contains(where: { $0.localPath == record.localPath }) else { return }
    database.downloads.insert(record, at: 0)
    touchProject(record.projectID)
    save()
  }

  func deleteDownloadRecord(id: UUID) {
    database.downloads.removeAll { $0.id == id }
    save()
  }

  func forceSave() { save() }

  private func touchProject(_ projectID: UUID?) {
    guard let projectID,
      let index = database.projects.firstIndex(where: { $0.id == projectID })
    else { return }
    database.projects[index].updatedAt = .now
  }

  private static func load(from fileURL: URL?) -> PersistentDatabase? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? decoder.decode(PersistentDatabase.self, from: data)
  }

  private func save() {
    guard let fileURL else { return }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(database) else { return }
    try? FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }
}
