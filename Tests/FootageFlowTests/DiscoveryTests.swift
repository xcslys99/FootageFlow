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
      #expect(ProviderID.searchCases.count == 15)
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
