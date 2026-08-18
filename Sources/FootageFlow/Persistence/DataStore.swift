import Foundation

@MainActor
final class DataStore: ObservableObject {
  static let shared = DataStore()
  @Published private(set) var projects: [ProjectRecord] = []
  @Published private(set) var segments: [ScriptSegmentRecord] = []
  @Published private(set) var favorites: [SavedAssetRecord] = []
  @Published private(set) var history: [SearchHistoryRecord] = []
  @Published private(set) var downloads: [DownloadRecord] = []
  @Published private(set) var reviewedAssets: [ProjectReviewRecord] = []
  @Published private(set) var duplicateDecisions: [DuplicateDecisionRecord] = []

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

  func addFavorite(asset: MediaAsset, projectID: UUID?, segmentIndex: Int? = nil) {
    repository.addFavorite(asset: asset, projectID: projectID, segmentIndex: segmentIndex)
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

  func setReviewed(projectID: UUID, stableAssetID: String, reviewed: Bool) {
    repository.setReviewed(projectID: projectID, stableAssetID: stableAssetID, reviewed: reviewed)
    synchronize()
  }

  func setDuplicateDecision(projectID: UUID, pairKey: String, decision: DuplicateDecision) {
    repository.setDuplicateDecision(projectID: projectID, pairKey: pairKey, decision: decision)
    synchronize()
  }

  func resetDuplicateDecisions(projectID: UUID) {
    repository.resetDuplicateDecisions(projectID: projectID)
    synchronize()
  }

  func removeAssetFromProject(projectID: UUID, stableAssetID: String) {
    repository.removeAssetFromProject(projectID: projectID, stableAssetID: stableAssetID)
    synchronize()
  }

  func importProject(_ payload: ImportedProjectPayload) {
    repository.importProject(payload)
    synchronize()
  }

  func projectItems(projectID: UUID) -> [ProjectAssetItem] {
    ProjectAssetInventory.items(projectID: projectID, database: repository.database)
  }

  func rightsAudit(projectID: UUID) -> RightsAuditReport {
    RightsAuditEngine.audit(
      items: projectItems(projectID: projectID), reviewed: repository.reviewedAssets,
      projectID: projectID)
  }

  func contactSheetPlan(
    project: ProjectRecord, columns: Int = 4, includeRights: Bool = true
  ) -> ContactSheetPlan {
    ContactSheetPlanner.plan(
      project: project, items: projectItems(projectID: project.id), columns: columns,
      includeRights: includeRights)
  }

  func attributionData(
    project: ProjectRecord, format: AttributionExportFormat,
    options: AttributionExportOptions = .init()
  ) throws -> Data {
    try AttributionExporter.data(
      format: format, project: project, items: projectItems(projectID: project.id), options: options
    )
  }

  func credits(projectID: UUID, style: CreditsStyle) -> String {
    AttributionExporter.credits(items: projectItems(projectID: projectID), style: style)
  }

  func portableProjectData(project: ProjectRecord) throws -> Data {
    try PortableProjectCodec.data(
      PortableProjectCodec.manifest(project: project, database: repository.database))
  }

  func importPortableProject(data: Data) throws -> ProjectRecord {
    let manifest = try PortableProjectCodec.decode(data)
    let payload = try PortableProjectCodec.importedPayload(
      from: manifest,
      existingProjectNames: Set(repository.projects.map { $0.name.localizedLowercase }))
    repository.importProject(payload)
    synchronize()
    return payload.project
  }

  func findDuplicates(projectID: UUID) async -> [DuplicateGroup] {
    let items = projectItems(projectID: projectID)
    let cache = repository.fileHashCache
    let result = await Task.detached(priority: .utility) {
      () -> ([String: String], [FileHashCacheRecord]) in
      var hashes: [String: String] = [:]
      var updates: [FileHashCacheRecord] = []
      for item in items {
        if Task.isCancelled { break }
        if let cached = FileHashService.cachedHash(for: item, cache: cache) {
          hashes[item.stableID] = cached
          continue
        }
        guard let path = item.localPath, FileManager.default.fileExists(atPath: path),
          let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let size = (attributes[.size] as? NSNumber)?.int64Value,
          let modified = attributes[.modificationDate] as? Date,
          let digest = try? FileHashService.sha256(of: URL(fileURLWithPath: path))
        else { continue }
        hashes[item.stableID] = digest
        updates.append(
          FileHashCacheRecord(
            localPath: path, fileSize: size, modificationDate: modified, sha256: digest))
      }
      return (hashes, updates)
    }.value
    for update in result.1 { repository.updateFileHashCache(update) }
    synchronize()
    let ignored = Set(
      repository.duplicateDecisions.filter { $0.projectID == projectID }.map(\.pairKey))
    return DuplicateDetectionEngine.find(items: items, hashes: result.0)
      .filter { !ignored.contains($0.decisionKey) }
  }

  func forceSave() { repository.forceSave() }

  private func synchronize() {
    projects = repository.projects
    segments = repository.segments
    favorites = repository.favorites
    history = repository.history
    downloads = repository.downloads
    reviewedAssets = repository.reviewedAssets
    duplicateDecisions = repository.duplicateDecisions
  }
}
