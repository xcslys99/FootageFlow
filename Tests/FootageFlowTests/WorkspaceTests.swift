import Foundation
import Testing

@testable import FootageFlow

@Suite("Workspace and accessibility core")
struct WorkspaceTests {
  @Test("saved searches persist without changing existing project data")
  func savedSearchPersistence() {
    let store = PersistentStore(inMemory: true)
    let project = store.addProject(name: "Documentary")
    let saved = store.addSavedSearch(
      SavedSearchRecord(
        name: "City night", query: "city night", mediaType: .video,
        downloadableOnly: true, providerIDs: [ProviderID.wikimedia.rawValue]))
    #expect(store.projects == [project])
    #expect(store.savedSearches.count == 1)
    #expect(store.savedSearches.first?.providerSet == [.wikimedia])
    #expect(store.duplicateSavedSearch(id: saved.id)?.name == "City night (2)")
    store.deleteSavedSearch(id: saved.id)
    #expect(store.savedSearches.count == 1)
  }

  @Test("legacy databases decode without workspace collections")
  func legacyDatabase() throws {
    let data = "{\"projects\":[],\"segments\":[],\"favorites\":[],\"history\":[],\"downloads\":[]}"
      .data(using: .utf8)!
    let decoded = try JSONDecoder().decode(PersistentDatabase.self, from: data)
    #expect(decoded.savedSearches == nil)
    #expect(decoded.providerHealth == nil)
  }

  @Test("local global search indexes only FootageFlow metadata and categorizes results")
  func localIndex() async {
    let project = ProjectRecord(name: "Apollo Project", script: "Moon archive")
    let asset = sampleAsset(title: "Apollo 11 launch")
    let download = DownloadRecord(
      asset: asset, fileURL: URL(fileURLWithPath: "/tmp/Apollo-11.mp4"), projectID: project.id)
    let snapshot = WorkspaceSearchSnapshot(
      projects: [project], favorites: [SavedAssetRecord(asset: asset, projectID: project.id)],
      downloads: [download],
      history: [
        SearchHistoryRecord(
          originalQuery: "Apollo archive", keywords: ["Apollo"], providers: [.wikimedia],
          projectID: project.id, resultCount: 1)
      ], savedSearches: [SavedSearchRecord(name: "Apollo collection", query: "Apollo archive")],
      researchReferences: [])
    let index = WorkspaceSearchIndex()
    await index.rebuild(snapshot: snapshot)
    let results = await index.search("apollo")
    #expect(results.contains { $0.kind == .project })
    #expect(results.contains { $0.kind == .media })
    #expect(results.contains { $0.kind == .download })
    #expect(results.contains { $0.kind == .searchHistory })
    #expect(results.contains { $0.kind == .savedSearch })
    #expect(
      results.allSatisfy { $0.localPath == nil || $0.kind == .download || $0.kind == .localFile })
  }

  @Test("smart collections do not infer rights")
  func smartCollections() {
    let unknown = sampleAsset(title: "Unverified archive", licenseStatus: .unknown)
    let known = sampleAsset(title: "Known archive", licenseStatus: .publicDomain)
    let snapshot = WorkspaceSearchSnapshot(
      projects: [], favorites: [SavedAssetRecord(asset: unknown), SavedAssetRecord(asset: known)],
      downloads: [
        DownloadRecord(asset: unknown, fileURL: URL(fileURLWithPath: "/tmp/a.mp4"), projectID: nil)
      ],
      history: [], savedSearches: [], researchReferences: [])
    let collections = Dictionary(
      uniqueKeysWithValues: WorkspaceCollections.summaries(snapshot: snapshot).map {
        ($0.id, $0.count)
      })
    #expect(collections[.unknownRights] == 2)
    #expect(collections[.downloadedMedia] == 1)
    #expect(collections[.missingLocalMedia] == 1)
    #expect(collections[.attributionRequired] == 0)
  }

  @Test("workspace command catalog keeps unique stable identifiers")
  func commandCatalog() {
    #expect(Set(WorkspaceCommand.catalog.map(\.id)).count == WorkspaceCommand.catalog.count)
    #expect(WorkspaceCommand.catalog.contains { $0.id == .commandPalette && !$0.shortcut.isEmpty })
    #expect(WorkspaceCommand.fuzzyMatches("Open Provider Health", query: "oph"))
    #expect(WorkspaceCommand.fuzzyMatches("Global Search", query: "global"))
    #expect(!WorkspaceCommand.fuzzyMatches("Open Downloads", query: "rights"))
  }

  @Test("local index stays responsive with large persisted metadata")
  func largeLocalIndex() async {
    let history = (0..<10_000).map { index in
      SearchHistoryRecord(
        originalQuery: "Archive topic \(index)", keywords: ["archive", "topic"],
        providers: [.wikimedia], projectID: nil, resultCount: 1)
    }
    let searchIndex = WorkspaceSearchIndex()
    let started = ContinuousClock.now
    await searchIndex.rebuild(
      snapshot: WorkspaceSearchSnapshot(
        projects: [], favorites: [], downloads: [], history: history, savedSearches: [],
        researchReferences: []))
    let results = await searchIndex.search("archive topic 9999")
    #expect(results.count == 1)
    #expect(started.duration(to: .now) < .seconds(2))
  }

  @Test("global search keeps credential-looking text out of its local index")
  func globalSearchExcludesSecrets() async {
    let project = ProjectRecord(
      name: "Private research", script: "topic: archive\napi_key=not-searchable")
    let index = WorkspaceSearchIndex()
    await index.rebuild(
      snapshot: WorkspaceSearchSnapshot(
        projects: [project], favorites: [], downloads: [], history: [], savedSearches: [],
        researchReferences: []))
    #expect(await index.search("archive").count == 1)
    #expect(await index.search("not-searchable").isEmpty)
  }

  private func sampleAsset(title: String, licenseStatus: LicenseStatus = .unknown) -> MediaAsset {
    MediaAsset(
      id: UUID().uuidString, provider: .wikimedia, title: title, description: "Archive metadata",
      thumbnailURL: URL(string: "https://example.com/thumb.jpg"), previewURL: nil,
      downloadURL: URL(string: "https://example.com/file.mp4"),
      sourcePageURL: URL(string: "https://example.com/source")!, creator: nil,
      license: licenseStatus == .publicDomain ? "Public Domain" : nil, licenseURL: nil,
      licenseStatus: licenseStatus, width: 1920, height: 1080, duration: 30, fileType: "mp4",
      mediaType: .video, publishedDate: nil, downloadable: true, originalMetadata: [:],
      searchKeyword: title, relevanceScore: 0.8)
  }
}
