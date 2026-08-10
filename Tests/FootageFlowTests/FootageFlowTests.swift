import Foundation

#if canImport(XCTest)
  import XCTest

  @testable import FootageFlow

  final class FootageFlowTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
      let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
      return try Data(contentsOf: url)
    }

    private func textFixture(_ name: String, extension fileExtension: String) throws -> String {
      let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: fileExtension))
      return try String(contentsOf: url, encoding: .utf8)
    }

    func testPexelsFixture() throws {
      let response = try JSONDecoder().decode(
        PexelsVideoResponse.self, from: fixture("pexels-video"))
      XCTAssertEqual(response.videos.first?.id, 7)
      XCTAssertEqual(response.videos.first?.videoFiles.first?.width, 1920)
    }

    func testPixabayFixture() throws {
      let response = try JSONDecoder().decode(
        PixabayVideoResponse.self, from: fixture("pixabay-video"))
      XCTAssertEqual(response.hits.first?.duration, 12)
      XCTAssertEqual(response.hits.first?.videos.medium?.height, 1080)
    }

    func testWikimediaFixture() throws {
      let response = try JSONDecoder().decode(WikimediaResponse.self, from: fixture("wikimedia"))
      XCTAssertEqual(response.query?.pages.first?.imageinfo?.first?.mime, "image/jpeg")
      XCTAssertEqual(
        response.query?.pages.first?.imageinfo?.first?.extmetadata?["LicenseShortName"]?.value,
        "CC BY 4.0")
    }

    func testYouTubeAndArchiveFixtures() throws {
      let youtube = try JSONDecoder().decode(YouTubeSearchResponse.self, from: fixture("youtube"))
      XCTAssertEqual(youtube.items.first?.id.videoId, "abc")
      let archive =
        try JSONSerialization.jsonObject(with: fixture("internet-archive")) as? [String: Any]
      let docs = (archive?["response"] as? [String: Any])?["docs"] as? [[String: Any]]
      XCTAssertEqual(docs?.first?["identifier"] as? String, "item1")
    }

    func testNASAParsingAssetManifestAndUnknownRights() throws {
      let response = try JSONDecoder().decode(NASASearchResponse.self, from: fixture("nasa"))
      let item = try XCTUnwrap(response.collection.items.first)
      let asset = try XCTUnwrap(
        NASAProvider.asset(
          item,
          manifest: [
            "http://images-assets.nasa.gov/video/NASA-1/NASA-1~orig.mp4",
            "http://images-assets.nasa.gov/video/NASA-1/NASA-1~preview.mp4",
          ], query: "Apollo 11", index: 0))
      XCTAssertEqual(asset.provider, .nasa)
      XCTAssertEqual(asset.mediaType, .video)
      XCTAssertEqual(asset.duration, 90)
      XCTAssertEqual(asset.downloadURL?.scheme, "https")
      XCTAssertTrue(asset.isDirectlyDownloadable)
      XCTAssertFalse(asset.effectiveRightsInfo.known)
      XCTAssertEqual(asset.licenseStatus, .unknown)
    }

    func testLibraryOfCongressParsingUsesOfficialResource() throws {
      let assets = try LibraryOfCongressProvider.assets(
        from: fixture("library-of-congress"),
        request: SearchRequest(query: "historic film", mediaType: .video))
      let asset = try XCTUnwrap(assets.first)
      XCTAssertEqual(asset.provider, .libraryOfCongress)
      XCTAssertEqual(asset.downloadURL?.host, "tile.loc.gov")
      XCTAssertEqual(asset.sourcePageURL.host, "www.loc.gov")
      XCTAssertTrue(asset.effectiveRightsInfo.known)
    }

    func testNationalArchivesParsingAndNoCachePolicy() throws {
      let assets = try NationalArchivesProvider.assets(
        from: fixture("national-archives"),
        request: SearchRequest(query: "archive film", mediaType: .video))
      let asset = try XCTUnwrap(assets.first)
      XCTAssertEqual(asset.provider, .nationalArchives)
      XCTAssertEqual(asset.sourcePageURL.absoluteString, "https://catalog.archives.gov/id/123")
      XCTAssertEqual(asset.originalMetadata["disclaimer"], ProviderPolicy.nationalArchivesNotice)
      XCTAssertTrue(asset.effectiveRightsInfo.known)
      if case .prohibited = ProviderPolicy.cachePolicy(for: .nationalArchives) {
      } else {
        XCTFail("NARA API results must not enter the shared search cache")
      }
    }

    func testEuropeanaParsingRightsAndMediaAvailability() throws {
      let response = try JSONDecoder().decode(
        EuropeanaSearchResponse.self, from: fixture("europeana"))
      let asset = try XCTUnwrap(
        response.items.first.flatMap { EuropeanaProvider.asset($0, query: "history", index: 0) })
      XCTAssertEqual(asset.provider, .europeana)
      XCTAssertEqual(asset.creator, "Museum Creator")
      XCTAssertEqual(asset.licenseStatus, .attributionRequired)
      XCTAssertTrue(asset.effectiveRightsInfo.openLicense)
      XCTAssertTrue(asset.isDirectlyDownloadable)
    }

    func testDiscoveryProviderModesAndCapabilities() {
      XCTAssertEqual(ProviderFactory.make(.nasa, apiKey: "").info.mode, .publicAPI)
      XCTAssertEqual(ProviderFactory.make(.libraryOfCongress, apiKey: "").info.mode, .publicAPI)
      XCTAssertEqual(ProviderFactory.make(.nationalArchives, apiKey: "").info.mode, .limited)
      XCTAssertEqual(
        ProviderFactory.make(.nationalArchives, apiKey: "configured").info.mode, .officialAPI)
      XCTAssertEqual(ProviderFactory.make(.europeana, apiKey: "").info.mode, .limited)
      XCTAssertEqual(ProviderFactory.make(.europeana, apiKey: "configured").info.mode, .officialAPI)
      XCTAssertTrue(NASAProvider().info.capabilities.supportsAudio)
    }

    func testMalformedDiscoveryResponsesFailWithoutCrashing() {
      let malformed = Data(#"{"unexpected":true}"#.utf8)
      XCTAssertThrowsError(
        try LibraryOfCongressProvider.assets(
          from: malformed, request: SearchRequest(query: "test")))
      XCTAssertThrowsError(
        try NationalArchivesProvider.assets(
          from: Data("not-json".utf8), request: SearchRequest(query: "test")))
      XCTAssertThrowsError(try JSONDecoder().decode(NASASearchResponse.self, from: malformed))
      XCTAssertThrowsError(try JSONDecoder().decode(EuropeanaSearchResponse.self, from: malformed))
    }

    func testAdvancedFiltersCanBeCombined() {
      var asset = sampleAsset()
      asset.publishedDate = ProviderUtilities.parseDate("2001")
      asset.rightsInfo = RightsInfo(
        statement: "CC BY 4.0", known: true, openLicense: true, attributionRequired: true)
      asset.downloadAvailability = .direct
      let filter = AdvancedSearchFilter(
        mediaType: .video, orientation: .landscape, resolution: .fullHD,
        duration: .underMinute, license: .openlyLicensed, selectedProviders: [.wikimedia],
        yearFrom: 2000, yearTo: 2002, downloadableOnly: true)
      XCTAssertTrue(filter.matches(asset))
      asset.downloadAvailability = .conditional
      XCTAssertFalse(filter.matches(asset))
    }

    func testSelectionAndAttributionFormatting() {
      let first = sampleAsset()
      var second = sampleAsset()
      second = MediaAsset(
        id: "2", provider: .nasa, title: "NASA Fixture", description: nil,
        thumbnailURL: nil, previewURL: nil, downloadURL: nil,
        sourcePageURL: URL(string: "https://images.nasa.gov/details/2")!, creator: nil,
        license: nil, licenseURL: nil, licenseStatus: .unknown, width: nil, height: nil,
        duration: nil, fileType: nil, mediaType: .image, publishedDate: nil,
        downloadable: false, originalMetadata: [:], searchKeyword: "test", relevanceScore: 1,
        rightsInfo: RightsInfo(statement: nil, known: false),
        downloadAvailability: .unavailable)
      var selection = AssetSelection()
      selection.toggle(first)
      selection.selectVisible([first, second])
      XCTAssertEqual(selection.count, 2)
      selection.retainAvailable([second])
      XCTAssertEqual(selection.count, 1)
      XCTAssertTrue(
        AttributionFormatter.source(for: first).contains(first.sourcePageURL.absoluteString))
      XCTAssertTrue(
        AttributionFormatter.attribution(for: second).contains(tr("attribution.rightsUnknown")))
      selection.clear()
      XCTAssertEqual(selection.count, 0)
    }

    func testUnifiedModelAndDeduplication() throws {
      let asset = sampleAsset()
      let decoded = try JSONDecoder().decode(MediaAsset.self, from: JSONEncoder().encode(asset))
      XCTAssertEqual(decoded, asset)
      XCTAssertEqual(SearchDeduplicator.apply([asset, asset]).count, 1)
    }

    func testLicenseMapping() {
      XCTAssertEqual(ProviderUtilities.licenseStatus(name: "CC BY-SA 4.0"), .attributionRequired)
      XCTAssertEqual(ProviderUtilities.licenseStatus(name: "Public Domain"), .publicDomain)
      XCTAssertEqual(ProviderUtilities.licenseStatus(name: nil), .unknown)
    }

    func testFilenameAndKeywords() {
      XCTAssertFalse(FileNameSanitizer.sanitize("银行/挤兑:2001?.mp4").contains("/"))
      XCTAssertGreaterThanOrEqual(KeywordEngine.keywords(for: "2001年阿根廷银行挤兑").count, 3)
      XCTAssertGreaterThanOrEqual(KeywordEngine.splitScript("第一句话。第二句话。\n\n第三段。").count, 2)
    }

    func testURLValidationAndLogRedaction() throws {
      XCTAssertEqual(
        try URLValidator.remote(URL(string: "https://example.com/file.mp4")).host, "example.com")
      XCTAssertThrowsError(try URLValidator.remote(URL(string: "http://example.com/file.mp4")))
      XCTAssertThrowsError(
        try URLValidator.remote(URL(string: "https://user:secret@example.com/file.mp4")))
      XCTAssertFalse(
        AppLogger.redact("Authorization: Bearer secret-token-value").contains("secret-token-value"))
    }

    func testDownloadPathContainmentAndSanitization() {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
      XCTAssertTrue(
        DownloadPathSafety.isContained(root.appendingPathComponent("Project/media.mp4"), in: root))
      XCTAssertFalse(
        DownloadPathSafety.isContained(
          root.deletingLastPathComponent().appendingPathComponent("outside.mp4"), in: root))
      let directory = DownloadPathSafety.projectDirectory(projectName: "../../escape", root: root)
      XCTAssertTrue(DownloadPathSafety.isContained(directory, in: root))
      XCTAssertFalse(directory.path.contains("../"))
    }

    func testLegacyDatabaseMigrationPreservesSource() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let legacy = directory.appendingPathComponent("legacy.json")
      let current = directory.appendingPathComponent("current.json")
      try Data("legacy-data".utf8).write(to: legacy)
      PersistentStore.migrateDatabaseIfNeeded(current: current, legacy: legacy)
      XCTAssertEqual(try String(contentsOf: current, encoding: .utf8), "legacy-data")
      XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testProviderFailureStateMapping() {
      XCTAssertEqual(
        ProviderRuntimeState.from(error: ProviderError.missingAPIKey(.pexels)).availability,
        .authenticationRequired)
      XCTAssertEqual(
        ProviderRuntimeState.from(error: ProviderError.rateLimited(retryAfter: 10)).availability,
        .rateLimited)
      XCTAssertEqual(
        ProviderRuntimeState.from(error: ProviderError.serverUnavailable).availability, .unavailable
      )
      XCTAssertEqual(
        ProviderRuntimeState.from(error: ProviderError.temporarilyBlocked(.pexels)).availability,
        .temporarilyBlocked)
      XCTAssertEqual(
        ProviderRuntimeState.from(error: ProviderError.invalidAPIKey).availability,
        .authenticationRequired)
    }

    func testPexelsAndPixabayAutomaticallySelectProviderMode() {
      XCTAssertEqual(ProviderFactory.make(.pexels, apiKey: "configured").info.mode, .officialAPI)
      XCTAssertTrue(ProviderFactory.make(.pexels, apiKey: "configured").info.requiresAPIKey)
      XCTAssertEqual(ProviderFactory.make(.pexels, apiKey: "").info.mode, .directSearch)
      XCTAssertFalse(ProviderFactory.make(.pexels, apiKey: "").info.requiresAPIKey)
      XCTAssertEqual(ProviderFactory.make(.pixabay, apiKey: "configured").info.mode, .officialAPI)
      XCTAssertEqual(ProviderFactory.make(.pixabay, apiKey: "  ").info.mode, .directSearch)
    }

    func testDirectSearchFixturesDoNotGuessLicense() throws {
      let pexels = DirectSearchHTMLParser.parse(
        html: try textFixture("pexels-direct", extension: "html"), provider: .pexels,
        expectedType: .image, query: "Argentina bank", limit: 10)
      XCTAssertEqual(pexels.count, 1)
      XCTAssertEqual(pexels.first?.creator, "Fixture Creator")
      XCTAssertEqual(pexels.first?.licenseStatus, .unknown)
      XCTAssertTrue(pexels.first?.downloadable == true)

      let pixabay = DirectSearchHTMLParser.parse(
        html: try textFixture("pixabay-direct", extension: "html"), provider: .pixabay,
        expectedType: .video, query: "city traffic", limit: 10)
      XCTAssertEqual(pixabay.first?.duration, 12)
      XCTAssertEqual(pixabay.first?.licenseStatus, .unknown)
      XCTAssertEqual(pixabay.first?.fileType, "mp4")
    }

    func testDirectSearchRejectsLookalikeProviderDomainsAndRecognizesEmptyPages() {
      let malicious =
        #"<script type="application/ld+json">{"@type":"ImageObject","url":"https://evilpexels.com/photo/fake-1/","contentUrl":"https://example.com/fake.jpg"}</script>"#
      XCTAssertTrue(
        DirectSearchHTMLParser.parse(
          html: malicious, provider: .pexels, expectedType: .image, query: "test", limit: 5
        ).isEmpty)
      XCTAssertTrue(DirectSearchHTMLParser.indicatesNoResults("No results were found"))
    }

    func testDirectSearch403IsIsolatedAndFriendly() async {
      let provider = PexelsDirectProvider(loader: BlockedDirectLoader())
      do {
        _ = try await provider.search(SearchRequest(query: "bank", mediaType: .image))
        XCTFail("Expected direct search to be temporarily blocked")
      } catch let error as ProviderError {
        XCTAssertEqual(ProviderRuntimeState.from(error: error).availability, .temporarilyBlocked)
        XCTAssertTrue((error.errorDescription ?? "").contains("Pexels"))
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }

    func testYTDLPSearchAndCanonicalYouTubeURL() async throws {
      let response =
        #"{"entries":[{"id":"abc123","title":"Fixture Video","url":"abc123","duration":42,"channel":"Fixture Channel","thumbnails":[{"url":"https://i.ytimg.com/vi/abc123/hqdefault.jpg","width":480,"height":360}]}]}"#
      let service = YTDLPService(
        runner: StubExternalRunner(result: .success(output: response)),
        executableURL: try executableFixture())
      let assets = try await YouTubeYTDLPProvider(service: service).search(
        SearchRequest(query: "financial crisis", mediaType: .video, pageSize: 3))
      XCTAssertEqual(assets.first?.title, "Fixture Video")
      XCTAssertEqual(
        assets.first?.sourcePageURL.absoluteString, "https://www.youtube.com/watch?v=abc123")
      XCTAssertEqual(assets.first?.effectiveDownloadStrategy, .ytDLP)
      XCTAssertEqual(assets.first?.licenseStatus, .unknown)
    }

    func testYTDLPDownloadSuccessWithMockRunner() async throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let destination = directory.appendingPathComponent("fixture.mp4")
      let service = YTDLPService(
        runner: StubExternalRunner(
          result: .success(output: destination.path), fileToCreate: destination),
        executableURL: try executableFixture())
      let saved = try await service.download(
        sourceURL: URL(string: "https://www.youtube.com/watch?v=abc123")!, directory: directory,
        fileStem: "fixture")
      XCTAssertEqual(saved.standardizedFileURL, destination.standardizedFileURL)
      XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
    }

    func testYTDLPFailureClassification() {
      if case .rateLimited = YTDLPService.mapFailure("HTTP Error 429: Too Many Requests") {
      } else {
        XCTFail("429 should be rate limited")
      }
      if case .videoUnavailable = YTDLPService.mapFailure("ERROR: Video unavailable") {
      } else {
        XCTFail("Unavailable video should be classified")
      }
      if case .regionalRestriction = YTDLPService.mapFailure("not available in your country") {
      } else {
        XCTFail("Regional restriction should be classified")
      }
      if case .temporarilyBlocked(.youtube) = YTDLPService.mapFailure("Sign in to confirm your age")
      {
      } else {
        XCTFail("Login-gated video should be access restricted")
      }
    }

    func testYTDLPNeverLoadsUserConfigurationOrBrowserCookies() {
      let service = YTDLPService(executableURL: nil)
      XCTAssertTrue(service.commonArguments.contains("--ignore-config"))
      XCTAssertFalse(
        service.commonArguments.contains { $0.localizedCaseInsensitiveContains("cookie") })
    }

    func testLocalizationDefaultSwitchPersistenceAndFallback() throws {
      #if canImport(Combine)
        let suite = "FootageFlowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = LocalizationManager(defaults: defaults)
        XCTAssertEqual(AppLanguage.allCases.count, 10)
        XCTAssertEqual(localization.language, .english)
        XCTAssertEqual(localization.text("nav.quickSearch"), "Quick Search")
        localization.setLanguage(.simplifiedChinese)
        XCTAssertEqual(localization.text("nav.quickSearch"), "快速搜索")
        XCTAssertEqual(localization.text("localization.fallbackProbe"), "English fallback")
        localization.setLanguage(.russian)
        XCTAssertEqual(LocalizationManager(defaults: defaults).language, .russian)
        let catalog = LocalizationCatalog()
        for language in AppLanguage.allCases {
          let recommendation = catalog.text(
            "search.apiRecommendation", language: language, arguments: [])
          XCTAssertTrue(recommendation.contains("Europeana"), "Missing Europeana in \(language)")
          XCTAssertTrue(recommendation.contains("YouTube"), "Missing YouTube in \(language)")
          XCTAssertNotEqual(recommendation, "search.apiRecommendation")
        }
      #else
        let catalog = LocalizationCatalog()
        XCTAssertEqual(AppLanguage.allCases.count, 10)
        XCTAssertEqual(
          catalog.text("nav.quickSearch", language: .english, arguments: []), "Quick Search")
        XCTAssertEqual(
          catalog.text("nav.quickSearch", language: .simplifiedChinese, arguments: []), "快速搜索")
        XCTAssertEqual(
          catalog.text("localization.fallbackProbe", language: .simplifiedChinese, arguments: []),
          "English fallback")
        XCTAssertEqual(
          catalog.text("nav.quickSearch", language: .japanese, arguments: []), "クイック検索")
      #endif
    }

    func testProjectCRUDAndPersistence() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let databaseURL = directory.appendingPathComponent("database.json")
      let first = PersistentStore(fileURL: databaseURL)
      let project = first.addProject(name: "Test Project")
      first.toggleFavorite(asset: sampleAsset(), projectID: project.id)
      first.addHistory(
        SearchHistoryRecord(
          originalQuery: "test", keywords: ["test"], providers: [.wikimedia], projectID: project.id,
          resultCount: 1))
      first.addDownload(
        DownloadRecord(
          asset: sampleAsset(), fileURL: directory.appendingPathComponent("test.mp4"),
          projectID: project.id))
      let reopened = PersistentStore(fileURL: databaseURL)
      XCTAssertEqual(reopened.projects.first?.name, "Test Project")
      XCTAssertEqual(reopened.favorites.count, 1)
      reopened.deleteProject(id: project.id)
      XCTAssertTrue(reopened.projects.isEmpty)
      XCTAssertNil(reopened.favorites.first?.projectID)
      XCTAssertNil(reopened.history.first?.projectID)
      XCTAssertNil(reopened.downloads.first?.projectID)
    }

    func testSidecarGeneration() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let mediaURL = directory.appendingPathComponent("test.mp4")
      try SourceSidecar.write(
        asset: sampleAsset(), mediaURL: mediaURL, projectName: "Test", segmentIndex: 1)
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: directory.appendingPathComponent("test.source.txt").path))
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: directory.appendingPathComponent("test.source.json").path))
    }

    private func sampleAsset() -> MediaAsset {
      MediaAsset(
        id: "1", provider: .wikimedia, title: "Test", description: nil, thumbnailURL: nil,
        previewURL: nil, downloadURL: URL(string: "https://example.com/test.mp4"),
        sourcePageURL: URL(string: "https://example.com/source")!, creator: "Creator",
        license: "CC BY", licenseURL: nil, licenseStatus: .attributionRequired, width: 1920,
        height: 1080, duration: 10, fileType: "video/mp4", mediaType: .video, publishedDate: nil,
        downloadable: true, originalMetadata: [:], searchKeyword: "test", relevanceScore: 1)
    }

    private func executableFixture() throws -> URL {
      #if os(Windows)
        let fileName = "FootageFlow-test-tool-\(UUID().uuidString).exe"
      #else
        let fileName = "FootageFlow-test-tool-\(UUID().uuidString)"
      #endif
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
      XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
      #if !os(Windows)
        try FileManager.default.setAttributes(
          [.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: url.path)
      #endif
      addTeardownBlock { try? FileManager.default.removeItem(at: url) }
      return url
    }
  }

  private struct BlockedDirectLoader: DirectSearchPageLoading {
    func load(_ url: URL, provider: ProviderID) async throws -> String {
      throw ProviderError.temporarilyBlocked(provider)
    }
  }

  private struct StubExternalRunner: ExternalToolRunning {
    enum Result: Sendable {
      case success(output: String)
      case failure(message: String)
    }

    let result: Result
    var fileToCreate: URL? = nil

    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws
      -> ExternalToolResult
    {
      if let fileToCreate {
        _ = FileManager.default.createFile(atPath: fileToCreate.path, contents: Data("video".utf8))
      }
      return switch result {
      case .success(let output):
        ExternalToolResult(
          standardOutput: Data((output + "\n").utf8), standardError: Data(), exitCode: 0)
      case .failure(let message):
        ExternalToolResult(
          standardOutput: Data(), standardError: Data(message.utf8), exitCode: 1)
      }
    }
  }
#endif
