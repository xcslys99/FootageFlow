import Foundation

#if canImport(Testing)
  import Testing

  @testable import FootageFlow

  @Suite("FootageFlow Discovery Update")
  struct DiscoveryTests {
    private func fixture(_ name: String) throws -> Data {
      let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
      return try Data(contentsOf: url)
    }

    @Test("all search providers use the intended mode")
    func providerModes() {
      #expect(ProviderID.searchCases.count == 17)
      #expect(ProviderFactory.make(.nasa, apiKey: "").info.mode == .publicAPI)
      #expect(ProviderFactory.make(.libraryOfCongress, apiKey: "").info.mode == .publicAPI)
      #expect(ProviderFactory.make(.nationalArchives, apiKey: "").info.mode == .limited)
      #expect(ProviderFactory.make(.nationalArchives, apiKey: "key").info.mode == .officialAPI)
      #expect(ProviderFactory.make(.europeana, apiKey: "").info.mode == .limited)
      #expect(ProviderFactory.make(.europeana, apiKey: "key").info.mode == .officialAPI)
      #expect(ProviderFactory.make(.peertube, apiKey: "").info.mode == .publicAPI)
      #expect(ProviderFactory.make(.coverr, apiKey: "").info.mode == .limited)
      #expect(ProviderFactory.make(.coverr, apiKey: "key").info.mode == .officialAPI)
      #expect(ProviderFactory.make(.vimeo, apiKey: "").info.mode == .limited)
      #expect(ProviderFactory.make(.vimeo, apiKey: "key").info.mode == .officialAPI)
      #expect(ProviderFactory.make(.openverse, apiKey: "").info.mode == .publicAPI)
      #expect(ProviderFactory.make(.dailymotion, apiKey: "").info.mode == .publicAPI)
    }

    @Test("Openverse preserves item rights and direct media metadata")
    func openverseFixture() throws {
      let response = try JSONDecoder().decode(
        OpenverseSearchResponse.self, from: fixture("openverse"))
      #expect(response.resultCount == 1)
      #expect(response.pageCount == 2)
      let item = try #require(response.results.first)
      let asset = try #require(
        OpenverseProvider.asset(item, type: .image, query: "coffee", index: 0))
      #expect(asset.provider == .openverse)
      #expect(asset.mediaType == .image)
      #expect(asset.licenseStatus == .attributionRequired)
      #expect(asset.effectiveRightsInfo.known)
      #expect(asset.effectiveRightsInfo.attributionRequired)
      #expect(asset.isDirectlyDownloadable)
      #expect(asset.thumbnailURL?.scheme == "https")
      #expect(asset.originalMetadata["attribution"]?.contains("CC BY-SA 4.0") == true)
      let audio = try #require(
        OpenverseProvider.asset(item, type: .audio, query: "coffee", index: 0))
      #expect(audio.duration == 9)
    }

    @Test("Openverse rejects mature items defensively")
    func openverseMatureFilter() throws {
      let data = Data(
        #"{"result_count":1,"page_count":1,"results":[{"id":"mature","title":"Filtered","foreign_landing_url":"https://example.com/item","url":"https://example.com/item.jpg","mature":true}]}"#
          .utf8)
      let response = try JSONDecoder().decode(OpenverseSearchResponse.self, from: data)
      let item = try #require(response.results.first)
      #expect(OpenverseProvider.asset(item, type: .image, query: "fixture", index: 0) == nil)
    }

    @Test("Dailymotion is discovery-only and preserves public metadata")
    func dailymotionFixture() throws {
      let response = try JSONDecoder().decode(
        DailymotionSearchResponse.self, from: fixture("dailymotion"))
      #expect(response.hasMore)
      #expect(response.total == 42)
      let item = try #require(response.list.first)
      let asset = try #require(DailymotionProvider.asset(item, query: "city", index: 0))
      #expect(asset.provider == .dailymotion)
      #expect(asset.duration == 95)
      #expect(asset.creator == "Fixture Channel")
      #expect(asset.sourcePageURL.host == "www.dailymotion.com")
      #expect(!asset.downloadable)
      #expect(asset.downloadURL == nil)
      #expect(asset.licenseStatus == .unknown)
      #expect(asset.originalMetadata["discoveryOnly"] == "true")
    }

    @Test("creator workflow time ranges and output metadata are validated")
    func clipModels() throws {
      #expect(TimecodeParser.seconds("00:01:20") == 80)
      #expect(TimecodeParser.seconds("01:45.5") == 105.5)
      #expect(TimecodeParser.seconds("80") == 80)
      #expect(TimecodeParser.seconds("1:60") == nil)
      let range = try ClipTimeRange.parse(
        start: "00:01:20", end: "00:01:45", mediaDuration: 120)
      #expect(range.duration == 25)
      #expect(range.sectionArgument == "*80.000-105.000")
      #expect(throws: ClipRangeError.invalidRange) {
        try ClipTimeRange.parse(start: "20", end: "20", mediaDuration: 120)
      }
      #expect(throws: ClipRangeError.invalidRange) {
        try ClipTimeRange.parse(start: "20", end: "20.25", mediaDuration: 120)
      }
      let longRange = try ClipTimeRange.parse(
        start: "00:10:00", end: "01:10:00", mediaDuration: 5_000)
      #expect(longRange.duration == 3_600)
      #expect(throws: ClipRangeError.beyondDuration) {
        try ClipTimeRange.parse(start: "20", end: "121", mediaDuration: 120)
      }
      #expect(throws: ClipRangeError.unknownDuration) {
        try ClipTimeRange.parse(start: "20", end: "30", mediaDuration: nil)
      }
      #expect(YTDLPDownloadOptions.default.requiresFFmpeg)
      #expect(
        !YTDLPDownloadOptions(
          formatSelector: "best", downloadSubtitles: false, subtitleLanguages: nil
        ).requiresFFmpeg)
      let editingOptions = YTDLPDownloadOptions(
        formatSelector: LinkDownloadQuality.p720.formatSelector,
        downloadSubtitles: false, subtitleLanguages: nil,
        outputPreset: .editingCompatibleMP4, clipRange: range, mediaDuration: 120)
      #expect(editingOptions.effectiveFormatSelector.contains("vcodec^=avc1"))
      #expect(editingOptions.effectiveFormatSelector.contains("bestaudio[ext=m4a]"))
      #expect(editingOptions.effectiveFormatSelector.contains("height<=720"))
      #expect(editingOptions.effectiveFormatSelector.hasSuffix("/best"))
      let audioOptions = YTDLPDownloadOptions(
        formatSelector: LinkDownloadQuality.audioOnly.formatSelector,
        downloadSubtitles: false, subtitleLanguages: nil,
        outputPreset: .audioOnly, clipRange: range, mediaDuration: 120)
      #expect(audioOptions.effectiveFormatSelector == LinkDownloadQuality.audioOnly.formatSelector)
    }

    @Test("editing output survives download history and source sidecars")
    func workflowMetadataPersistence() throws {
      var asset = sampleAsset()
      asset.downloadStrategy = .ytDLP
      var prepared = asset.withEditingOutput(.editingCompatibleMP4)
      prepared.originalMetadata["linkClipStart"] = "5"
      prepared.originalMetadata["linkClipEnd"] = "15"
      prepared.originalMetadata["linkClipDuration"] = "10"
      #expect(prepared.stableID != asset.stableID)
      let record = DownloadRecord(
        asset: prepared, fileURL: URL(fileURLWithPath: "/tmp/fixture.mp4"), projectID: nil)
      #expect(record.outputPresetRaw == EditingOutputPreset.editingCompatibleMP4.rawValue)
      #expect(record.clipStartSeconds == 5)
      #expect(record.clipDurationSeconds == 10)

      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let mediaURL = directory.appendingPathComponent("fixture.mp4")
      try SourceSidecar.write(
        asset: prepared, mediaURL: mediaURL, projectName: "Creator", segmentIndex: nil)
      let data = try Data(contentsOf: directory.appendingPathComponent("fixture.source.json"))
      let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      #expect(json["outputPreset"] as? String == "editingCompatibleMP4")
      #expect(json["clipStartSeconds"] as? Double == 5)
      #expect(json["clipDurationSeconds"] as? Double == 10)
    }

    @Test("smart expansion builds the shared ten-language plan and remains bounded")
    func smartExpansion() {
      let cases = [
        ("hamburger", "cheeseburger"), ("fries", "potato fries"),
        ("coffee shop", "barista making coffee"), ("city night", "downtown night traffic"),
        ("factory worker", "manufacturing worker"),
        ("Apollo 11", "1969 moon landing"), ("俄乌战争", "Russian invasion of Ukraine"),
        ("台湾美食", "Taiwan street food"), ("台灣美食", "Taiwan street food"),
        ("台湾料理", "Taiwan cuisine"), ("comida taiwanesa", "Taiwan cuisine"),
        ("российско-украинская война", "Russian invasion of Ukraine"),
      ]
      for (query, expected) in cases {
        let values = KeywordEngine.keywords(for: query).map(\.text)
        #expect(values.first == query)
        #expect(values.contains(expected))
        #expect(values.count >= 10)
        #expect(values.count <= 14)
      }
      #expect(
        KeywordEngine.keywords(for: "coffee shop", smartExpansion: false).count == 10)
      let languageCases = [
        ("城市夜景", "city night"), ("都市夜景", "city night"),
        ("夜の街", "city night"), ("도시 야경", "city night"),
        ("ciudad de noche", "city night"), ("cidade à noite", "city night"),
        ("stadt bei nacht", "city night"), ("ville de nuit", "city night"),
        ("ночной город", "city night"),
      ]
      for (query, expected) in languageCases {
        #expect(KeywordEngine.keywords(for: query).map(\.text).contains(expected))
      }
      var disabled = KeywordEngine.keywords(for: "Apollo 11")
      disabled[1].isEnabled = false
      #expect(
        !KeywordEngine.providerQueries(from: disabled, provider: .openverse, mode: .publicAPI)
          .contains(disabled[1].text))
      let duplicate = [SearchKeyword(text: "Apollo 11"), SearchKeyword(text: "apollo 11")]
      #expect(
        KeywordEngine.providerQueries(from: duplicate, provider: .wikimedia, mode: .publicAPI)
          .count == 2)
      let values = KeywordEngine.keywords(for: "Apollo 11")
      #expect(
        KeywordEngine.providerQueries(from: values, provider: .youtube, mode: .publicAPI).count
          >= 10)
      #expect(
        KeywordEngine.providerQueries(from: values, provider: .wikimedia, mode: .publicAPI).count
          <= 14)
      #expect(
        KeywordEngine.providerQueries(from: values, provider: .europeana, mode: .limited).count
          == 1)
    }

    @Test("clipboard parser accepts only public media links")
    func clipboardLinks() {
      let values = LinkURLParser.mediaURLs(
        from:
          "normal note\nhttps://youtu.be/example\nhttps://vimeo.com/123\nhttps://youtu.be/example"
      )
      #expect(values.count == 2)
      #expect(LinkURLParser.mediaURLs(from: "").isEmpty)
      #expect(LinkURLParser.mediaURLs(from: "secret password text").isEmpty)
      #expect(LinkURLParser.mediaURLs(from: "http://127.0.0.1/private").isEmpty)
      #expect(LinkURLParser.mediaURLs(from: "https://example.com/file.mp4").count == 1)
      var session = ClipboardSuggestionSession(cooldown: 0)
      let first = session.freshMediaURLs(
        from: "https://youtu.be/example", existingURLs: [], now: Date(timeIntervalSince1970: 1))
      #expect(first.count == 1)
      _ = session.freshMediaURLs(
        from: "https://vimeo.com/123", existingURLs: [], now: Date(timeIntervalSince1970: 2))
      #expect(
        session.freshMediaURLs(
          from: "https://youtu.be/example", existingURLs: [], now: Date(timeIntervalSince1970: 3)
        ).isEmpty)
      var cooldown = ClipboardSuggestionSession(cooldown: 1)
      #expect(
        cooldown.freshMediaURLs(
          from: "https://youtu.be/one", existingURLs: [], now: Date(timeIntervalSince1970: 10)
        ).count == 1)
      #expect(
        cooldown.freshMediaURLs(
          from: "https://youtu.be/two", existingURLs: [], now: Date(timeIntervalSince1970: 10.5)
        ).isEmpty)
      #expect(
        cooldown.freshMediaURLs(
          from: "https://youtu.be/two", existingURLs: [], now: Date(timeIntervalSince1970: 12)
        ).count == 1)
    }

    @Test("legacy history and keyword JSON decode without multilingual fields")
    func legacySearchHistory() throws {
      let oldKeyword = Data(
        #"{"id":"00000000-0000-0000-0000-000000000001","text":"广州美食","isEnabled":true}"#.utf8)
      let decodedKeyword = try JSONDecoder().decode(SearchKeyword.self, from: oldKeyword)
      #expect(decodedKeyword.language == nil)
      #expect(decodedKeyword.origin == nil)

      let record = SearchHistoryRecord(
        originalQuery: "广州美食", keywords: ["广州美食"], providers: [.wikimedia],
        projectID: nil, resultCount: 3)
      let data = try JSONEncoder().encode(record)
      var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      object.removeValue(forKey: "keywordDetails")
      let legacy = try JSONSerialization.data(withJSONObject: object)
      let decoded = try JSONDecoder().decode(SearchHistoryRecord.self, from: legacy)
      #expect(decoded.keywords == ["广州美食"])
      #expect(decoded.keywordDetails == nil)
    }

    @Test("update checker compares releases, preserves notes, and trusts only official pages")
    func updateChecker() throws {
      #expect(SemanticAppVersion("v0.7.0")! > SemanticAppVersion("0.6.0")!)
      #expect(SemanticAppVersion("0.10.0")! > SemanticAppVersion("0.9.9")!)
      #expect(SemanticAppVersion("1.0.0-beta.2")! < SemanticAppVersion("1.0.0")!)
      #expect(SemanticAppVersion("1.0.0-beta.2")! < SemanticAppVersion("1.0.0-beta.10")!)

      let available = try AppUpdateService.evaluate(
        data: fixture("github-release"), currentVersion: "0.7.0")
      guard case .updateAvailable(let release) = available else {
        Issue.record("A newer fixture release should be offered")
        return
      }
      #expect(release.version == "0.8.0")
      #expect(release.notes.contains("Full release notes"))
      #expect(release.pageURL.absoluteString.hasSuffix("/releases/tag/v0.8.0"))
      #expect(release.publishedAt != nil)

      let current = try AppUpdateService.evaluate(
        data: fixture("github-release"), currentVersion: "0.8.0")
      #expect(current == .upToDate(latestVersion: "0.8.0"))

      var untrusted = try #require(
        JSONSerialization.jsonObject(with: fixture("github-release")) as? [String: Any])
      untrusted["html_url"] = "https://evil.example/download"
      let untrustedData = try JSONSerialization.data(withJSONObject: untrusted)
      let safe = try AppUpdateService.evaluate(data: untrustedData, currentVersion: "0.7.0")
      guard case .updateAvailable(let safeRelease) = safe else {
        Issue.record("The safe fallback should still offer the update")
        return
      }
      #expect(safeRelease.pageURL == AppUpdateService.latestReleasePageURL)
    }

    @Test("update reminder defers only the same release for 24 hours")
    func updateReminder() {
      let now = Date(timeIntervalSince1970: 1_800_000_000)
      let later = AppUpdateReminderPolicy.deferredUntil(from: now)
      #expect(later.timeIntervalSince(now) == 86_400)
      #expect(
        !AppUpdateReminderPolicy.shouldPrompt(
          releaseVersion: "0.8.0", currentVersion: "0.7.0", deferredVersion: "0.8.0",
          deferredUntil: later, now: now))
      #expect(
        AppUpdateReminderPolicy.shouldPrompt(
          releaseVersion: "0.8.0", currentVersion: "0.7.0", deferredVersion: "0.8.0",
          deferredUntil: later, now: later))
      #expect(
        AppUpdateReminderPolicy.shouldPrompt(
          releaseVersion: "0.9.0", currentVersion: "0.7.0", deferredVersion: "0.8.0",
          deferredUntil: later, now: now))
      #expect(
        !AppUpdateReminderPolicy.shouldPrompt(
          releaseVersion: "0.7.0", currentVersion: "0.7.0", deferredVersion: nil,
          deferredUntil: nil, now: now))
    }

    @Test("NASA manifest returns official HTTPS media without guessing rights")
    func nasaFixture() throws {
      let response = try JSONDecoder().decode(NASASearchResponse.self, from: fixture("nasa"))
      let item = try #require(response.collection.items.first)
      let asset = try #require(
        NASAProvider.asset(
          item,
          manifest: [
            "http://images-assets.nasa.gov/video/NASA-1/NASA-1~orig.mp4",
            "http://images-assets.nasa.gov/video/NASA-1/NASA-1~preview.mp4",
          ], query: "Apollo", index: 0))
      #expect(asset.duration == 90)
      #expect(asset.downloadURL?.scheme == "https")
      #expect(asset.isDirectlyDownloadable)
      #expect(!asset.effectiveRightsInfo.known)
    }

    @Test("Library of Congress uses official item and resource URLs")
    func locFixture() throws {
      let asset = try #require(
        LibraryOfCongressProvider.assets(
          from: fixture("library-of-congress"),
          request: SearchRequest(query: "film", mediaType: .video)
        ).first)
      #expect(asset.provider == .libraryOfCongress)
      #expect(asset.id == "loc-fixture")
      #expect(asset.sourcePageURL.host == "www.loc.gov")
      #expect(asset.downloadURL?.host == "tile.loc.gov")
      #expect(asset.effectiveRightsInfo.known)
    }

    @Test("NARA parsing preserves disclaimer and bypasses cache")
    func naraFixture() throws {
      let asset = try #require(
        NationalArchivesProvider.assets(
          from: fixture("national-archives"),
          request: SearchRequest(query: "film", mediaType: .video)
        ).first)
      #expect(asset.originalMetadata["disclaimer"] == ProviderPolicy.nationalArchivesNotice)
      #expect(asset.sourcePageURL.absoluteString == "https://catalog.archives.gov/id/123")
      guard case .prohibited = ProviderPolicy.cachePolicy(for: .nationalArchives) else {
        Issue.record("NARA must not use the normalized search cache")
        return
      }
    }

    @Test("Europeana rights and direct media are normalized")
    func europeanaFixture() throws {
      let response = try JSONDecoder().decode(
        EuropeanaSearchResponse.self, from: fixture("europeana"))
      let item = try #require(response.items.first)
      let asset = try #require(EuropeanaProvider.asset(item, query: "history", index: 0))
      #expect(asset.licenseStatus == .attributionRequired)
      #expect(asset.effectiveRightsInfo.openLicense)
      #expect(asset.isDirectlyDownloadable)
    }

    @Test("malformed discovery responses fail safely")
    func malformedResponses() {
      let malformed = Data(#"{"unexpected":true}"#.utf8)
      #expect(throws: (any Error).self) {
        try LibraryOfCongressProvider.assets(
          from: malformed, request: SearchRequest(query: "test"))
      }
      #expect(throws: (any Error).self) {
        try NationalArchivesProvider.assets(
          from: Data("not-json".utf8), request: SearchRequest(query: "test"))
      }
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(NASASearchResponse.self, from: malformed)
      }
    }

    @Test("advanced filters compose without inventing metadata")
    func advancedFilters() {
      let asset = sampleAsset()
      let filter = AdvancedSearchFilter(
        mediaType: .video, orientation: .landscape, resolution: .fullHD,
        duration: .underMinute, license: .openlyLicensed, selectedProviders: [.wikimedia],
        yearFrom: 2000, yearTo: 2002, downloadableOnly: true)
      #expect(filter.matches(asset))
      var conditional = asset
      conditional.downloadAvailability = .conditional
      #expect(!filter.matches(conditional))
      var unknownDate = asset
      unknownDate.publishedDate = nil
      #expect(!filter.matches(unknownDate))
    }

    @Test("selection never retains stale results")
    func selection() {
      let first = sampleAsset()
      var second = first
      second = MediaAsset(
        id: "2", provider: .nasa, title: "Second", description: nil, thumbnailURL: nil,
        previewURL: nil, downloadURL: nil,
        sourcePageURL: URL(string: "https://images.nasa.gov/details/2")!, creator: nil,
        license: nil, licenseURL: nil, licenseStatus: .unknown, width: nil, height: nil,
        duration: nil, fileType: nil, mediaType: .image, publishedDate: nil,
        downloadable: false, originalMetadata: [:], searchKeyword: "test", relevanceScore: 0.5)
      var selection = AssetSelection()
      selection.selectVisible([first, second])
      #expect(selection.count == 2)
      selection.retainAvailable([second])
      #expect(selection.count == 1)
      selection.clear()
      #expect(selection.count == 0)
    }

    @Test("attribution handles known and unknown rights")
    func attribution() {
      let known = sampleAsset()
      #expect(AttributionFormatter.attribution(for: known).contains("CC BY 4.0"))
      var unknown = known
      unknown.license = nil
      unknown.licenseStatus = .unknown
      unknown.rightsInfo = RightsInfo(statement: nil, known: false)
      #expect(
        AttributionFormatter.attribution(for: unknown).contains(tr("attribution.rightsUnknown")))
    }

    @Test("legacy MediaAsset JSON remains decodable")
    func backwardCompatibility() throws {
      var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(sampleAsset())) as? [String: Any])
      object.removeValue(forKey: "rightsInfo")
      object.removeValue(forKey: "downloadAvailability")
      object.removeValue(forKey: "thumbnailCandidates")
      let legacy = try JSONSerialization.data(withJSONObject: object)
      let decoded = try JSONDecoder().decode(MediaAsset.self, from: legacy)
      #expect(decoded.id == "1")
      #expect(decoded.effectiveRightsInfo.known)
    }

    @Test("localizations stay aligned")
    func localization() {
      let catalog = LocalizationCatalog()
      #expect(AppLanguage.allCases.count == 10)
      #expect(
        catalog.text("filter.downloadableOnly", language: .english, arguments: [])
          == "Downloadable Only")
      #expect(
        catalog.text("filter.downloadableOnly", language: .simplifiedChinese, arguments: [])
          == "仅显示可直接下载")
      for language in AppLanguage.allCases {
        let recommendation = catalog.text(
          "search.apiRecommendation", language: language, arguments: [])
        #expect(recommendation.contains("National Archives"))
        #expect(recommendation.contains("Europeana"))
        #expect(recommendation.contains("YouTube"))
        #expect(
          catalog.text("search.smartExpansion", language: language, arguments: [])
            != "Smart Expansion" || language == .english)
        #expect(
          !catalog.text("link.scope.clip", language: language, arguments: []).contains(
            "Unavailable"))
        #expect(
          !catalog.text("clipboard.setting", language: language, arguments: []).contains(
            "Unavailable"))
        #expect(
          !catalog.text("update.whatsNew", language: language, arguments: []).contains(
            "Unavailable"))
        #expect(
          catalog.text(
            "update.availableTitle", language: language, arguments: ["0.8.0"]
          ).contains("0.8.0"))
      }
    }

    private func sampleAsset() -> MediaAsset {
      MediaAsset(
        id: "1", provider: .wikimedia, title: "Fixture", description: nil,
        thumbnailURL: nil, previewURL: nil,
        downloadURL: URL(string: "https://example.com/fixture.mp4"),
        sourcePageURL: URL(string: "https://example.com/source")!, creator: "Creator",
        license: "CC BY 4.0",
        licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/"),
        licenseStatus: .attributionRequired, width: 1920, height: 1080, duration: 30,
        fileType: "video/mp4", mediaType: .video,
        publishedDate: ProviderUtilities.parseDate("2001"), downloadable: true,
        originalMetadata: [:], searchKeyword: "fixture", relevanceScore: 1,
        rightsInfo: RightsInfo(
          statement: "CC BY 4.0", known: true, openLicense: true,
          attributionRequired: true), downloadAvailability: .direct)
    }
  }
#endif
