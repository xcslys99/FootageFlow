import Foundation

#if canImport(Testing)
  import Testing
  @testable import FootageFlow

  @Suite("Project export and attribution workflow")
  struct ProjectWorkflowTests {
    @Test("attribution exports are UTF-8 stable and keep secrets and private paths out by default")
    func attributionExports() throws {
      let project = ProjectRecord(name: "广州 / Test 🎬")
      let localPath = ["", "Users", "alice", "Movies", "private", "clip.mp4"].joined(separator: "/")
      let item = ProjectAssetItem(
        asset: asset(), downloadedAt: .now, localFileName: "clip.mp4",
        localPath: localPath)
      for format in AttributionExportFormat.allCases {
        let data = try AttributionExporter.data(format: format, project: project, items: [item])
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("Fixture"))
        #expect(!text.contains(["", "Users", "alice"].joined(separator: "/")))
        #expect(!text.localizedCaseInsensitiveContains("secret-token"))
      }
      let csv = try #require(
        String(
          data: AttributionExporter.data(
            format: .csv, project: project, items: [item]), encoding: .utf8))
      #expect(csv.contains("Fixture, \"\"Title\"\""))
      let local = try #require(
        String(
          data: AttributionExporter.data(
            format: .csv, project: project, items: [item],
            options: AttributionExportOptions(includeLocalFilePaths: true)), encoding: .utf8))
      #expect(local.contains(localPath))
      let formula = try #require(
        String(
          data: AttributionExporter.data(
            format: .csv, project: project,
            items: [ProjectAssetItem(asset: asset(title: "=HYPERLINK(\"https://bad.example\")"))]),
          encoding: .utf8))
      #expect(formula.contains("'=HYPERLINK"))
      let html = try #require(
        String(
          data: AttributionExporter.data(
            format: .html, project: project,
            items: [ProjectAssetItem(asset: asset(title: "<script>bad</script>"))]
          ), encoding: .utf8))
      #expect(html.contains("&lt;script&gt;bad&lt;/script&gt;"))
      #expect(!html.contains("<script>bad</script>"))
    }

    @Test("rights audit never infers rights from provider identity or download availability")
    func rightsAudit() {
      var unknown = asset(provider: .nasa)
      unknown.licenseStatus = .unknown
      unknown.rightsInfo = RightsInfo(statement: nil, source: "NASA", known: false)
      let report = RightsAuditEngine.audit(
        items: [ProjectAssetItem(asset: unknown)], reviewed: [], projectID: UUID())
      #expect(report.summary.publicDomain == 0)
      #expect(report.summary.rightsUnknown == 1)
      #expect(report.entries[0].needsReview)
      #expect(RightsAuditFilter.needsReview.includes(report.entries[0]))
      #expect(RightsAuditFilter.rightsUnknown.includes(report.entries[0]))
      #expect(!RightsAuditFilter.publicDomain.includes(report.entries[0]))
    }

    @Test("portable backup redacts metadata and imports as a separate project without local paths")
    func portableRoundTrip() throws {
      let privatePath = ["", "Users", "alice", "Private", "script.md"].joined(separator: "/")
      let project = ProjectRecord(
        name: "Cross platform", script: "api_key=secret-token at " + privatePath)
      var media = asset()
      media.originalMetadata["api_token"] = "secret-token"
      let saved = SavedAssetRecord(asset: media, projectID: project.id)
      let downloadPath = ["", "Users", "alice", "Movies", "private.mp4"].joined(separator: "/")
      let download = DownloadRecord(
        asset: media, fileURL: URL(fileURLWithPath: downloadPath),
        projectID: project.id)
      let database = PersistentDatabase(
        projects: [project], favorites: [saved], downloads: [download])
      let manifest = PortableProjectCodec.manifest(project: project, database: database)
      let data = try PortableProjectCodec.data(manifest)
      let text = try #require(String(data: data, encoding: .utf8))
      #expect(!text.contains("secret-token"))
      #expect(!text.contains(["", "Users", "alice"].joined(separator: "/")))
      #expect(text.contains("[REDACTED]"))
      #expect(text.contains("[LOCAL PATH REDACTED]"))
      let decoded = try PortableProjectCodec.decode(data)
      let imported = try PortableProjectCodec.importedPayload(
        from: decoded, existingProjectNames: ["cross platform"])
      #expect(imported.project.id != project.id)
      #expect(imported.project.name.contains("Imported"))
      #expect(imported.downloads.first?.localPath.isEmpty == true)
      #expect(imported.favorites.first?.projectID == imported.project.id)
      var invalid = manifest
      invalid.downloads[0].relativeFileReference = "../not-safe.mp4"
      #expect(throws: PortableProjectError.self) {
        try PortableProjectCodec.decode(PortableProjectCodec.data(invalid))
      }
    }

    @Test("legacy databases decode without v0.8 optional collections")
    func legacyDatabaseDecodes() throws {
      let data = Data(
        #"{"projects":[],"segments":[],"favorites":[],"history":[],"downloads":[]}"#.utf8)
      let database = try JSONDecoder().decode(PersistentDatabase.self, from: data)
      #expect(database.reviewedAssets == nil)
      #expect(database.duplicateDecisions == nil)
      #expect(database.fileHashCache == nil)
    }

    @Test("macOS and Windows portable fixtures share the v1 manifest schema")
    func portableFixtures() throws {
      let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
      for file in [
        "macos-created-project-v1.footageflowproject",
        "windows-created-project-v1.footageflowproject",
      ] {
        let manifest = try PortableProjectCodec.decode(
          Data(contentsOf: folder.appendingPathComponent(file)))
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.application == "FootageFlow")
        #expect(!manifest.project.name.isEmpty)
      }
    }

    @Test("duplicate engine distinguishes exact URL matches from possible metadata")
    func duplicates() {
      let first = ProjectAssetItem(asset: asset(id: "one"))
      var secondAsset = asset(id: "two")
      secondAsset.sourcePageURL = URL(string: "https://example.com/source?id=1")!
      let second = ProjectAssetItem(asset: secondAsset)
      let groups = DuplicateDetectionEngine.find(items: [first, second])
      #expect(groups.contains { $0.reason == .sameOriginalURL })
      #expect(groups.first(where: { $0.reason == .sameOriginalURL })?.items.count == 2)
      #expect(
        groups.first(where: { $0.reason == .sameOriginalURL })?.displayReason
          == tr("project.duplicateSameOriginalURL"))
    }

    @Test("project duplicate decisions suppress only that project until reset")
    @MainActor func duplicateDecisions() async throws {
      let store = DataStore(inMemory: true)
      let project = store.addProject(name: "Duplicate test")
      let first = asset(id: "one", provider: .wikimedia)
      var second = asset(id: "two", provider: .pixabay)
      second.sourcePageURL = first.sourcePageURL
      store.addFavorite(asset: first, projectID: project.id)
      store.addFavorite(asset: second, projectID: project.id)
      let initial = await store.findDuplicates(projectID: project.id)
      let group = try #require(initial.first(where: { $0.reason == .sameOriginalURL }))
      store.setDuplicateDecision(
        projectID: project.id, pairKey: group.decisionKey, decision: .notDuplicate)
      #expect((await store.findDuplicates(projectID: project.id)).isEmpty)
      store.resetDuplicateDecisions(projectID: project.id)
      #expect(
        (await store.findDuplicates(projectID: project.id)).contains {
          $0.reason == .sameOriginalURL
        })
    }

    @Test("inventory and duplicate grouping remain deterministic for large projects")
    func largeProjectInventory() {
      let items = (0..<1_000).map { index in
        var value = asset(id: "fixture-\(index)", title: "Asset \(index)")
        value.sourcePageURL = URL(string: "https://example.com/source?id=\(index)")!
        value.downloadURL = URL(string: "https://example.com/video?id=\(index)")!
        return ProjectAssetItem(asset: value)
      }
      let groups = DuplicateDetectionEngine.find(items: items)
      #expect(groups.isEmpty)
      let plan = ContactSheetPlanner.plan(
        project: ProjectRecord(name: "Large"), items: items, columns: 4)
      #expect(plan.items.count == 1_000)
      #expect(plan.items.last?.index == 1_000)
    }

    @Test("streaming SHA-256 and contact plan are deterministic")
    func hashAndContactPlan() throws {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: url) }
      try Data("abc".utf8).write(to: url)
      #expect(
        try FileHashService.sha256(of: url)
          == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
      let project = ProjectRecord(name: "Sheet")
      let plan = ContactSheetPlanner.plan(
        project: project, items: [ProjectAssetItem(asset: asset())], columns: 9,
        includeRights: false)
      #expect(plan.columns == 5)
      #expect(plan.items.first?.title == "Fixture, \"Title\"")
      #expect(!plan.includeRights)
    }

    private func asset(
      id: String = "fixture", title: String = "Fixture, \"Title\"",
      provider: ProviderID = .wikimedia
    ) -> MediaAsset {
      MediaAsset(
        id: id, provider: provider, title: title, description: "line one\nline two",
        thumbnailURL: URL(string: "https://example.com/thumb.jpg"), previewURL: nil,
        downloadURL: URL(string: "https://example.com/video.mp4?token=secret-token"),
        sourcePageURL: URL(string: "https://example.com/source?id=1")!, creator: "Creator",
        license: "CC BY 4.0",
        licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/"),
        licenseStatus: .attributionRequired, width: 1920, height: 1080, duration: 12,
        fileType: "mp4", mediaType: .video, publishedDate: nil, downloadable: true,
        originalMetadata: ["token": "secret-token", "category": "fixture"],
        searchKeyword: "fixture",
        relevanceScore: 1,
        rightsInfo: RightsInfo(
          statement: "CC BY 4.0", known: true,
          openLicense: true, attributionRequired: true), downloadAvailability: .direct)
    }
  }
#endif
