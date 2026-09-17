import Foundation

#if canImport(Testing)
  import Testing
  @testable import FootageFlow

  @Suite("Search duplicate review")
  struct SearchDuplicateReviewTests {
    @Test("Exact URL, canonical URL, and provider native ID remain separate evidence")
    func exactEvidence() {
      let source = URL(string: "https://example.org/item/42?utm_source=feed")!
      let canonical = URL(string: "https://example.org/item/42")!
      let first = asset("a", provider: .wikimedia, source: source)
      let second = asset("b", provider: .internetArchive, source: canonical)
      let third = asset("a", provider: .wikimedia, source: URL(string: "https://elsewhere.org/a")!)
      let review = SearchDuplicateAnalyzer.analyze([first, second, third])
      #expect(review.resultCount == 3)
      #expect(review.uniqueCount == 1)
      #expect(review.groups.count == 1)
      #expect(review.groups[0].confidence == .exact)
      #expect(review.groups[0].memberIDs == [first.stableID, second.stableID, third.stableID])
      #expect(Set(review.groups[0].evidence).isSuperset(of: ["sourceURL", "providerID"]))
    }

    @Test("Cross-provider same URL survives search-query deduplication")
    func retainsVersions() {
      let original = asset("same", provider: .wikimedia)
      let differentProvider = asset(
        "same", provider: .internetArchive, source: original.sourcePageURL)
      let deduplicated = SearchDeduplicator.apply([original, original, differentProvider])
      #expect(deduplicated.count == 2)
      #expect(SearchDuplicateAnalyzer.analyze(deduplicated).groups.count == 1)
    }

    @Test("A source page with both image and video is not one media version")
    func differentMediaTypes() {
      let video = asset("shared")
      var image = asset("shared", provider: .internetArchive, source: video.sourcePageURL)
      image.mediaType = .image
      #expect(SearchDuplicateAnalyzer.analyze([video, image]).groups.isEmpty)
    }

    @Test("Potential archive content selectors are not removed as tracking")
    func conservativeCanonicalization() {
      let first = asset("a", source: URL(string: "https://archive.example/item?source=alpha")!)
      let second = asset(
        "b", provider: .internetArchive,
        source: URL(string: "https://archive.example/item?source=beta")!)
      #expect(SearchDuplicateAnalyzer.analyze([first, second]).groups.isEmpty)
    }

    @Test("Metadata corroboration groups transcodes but not different footage")
    func metadata() {
      let first = asset(
        "a", title: "Berlin historic skyline night", creator: "Museum", duration: 42,
        width: 1280, height: 720)
      let larger = asset(
        "b", provider: .internetArchive, title: "Historic Berlin night skyline",
        creator: "Museum", duration: 42.2, width: 1920, height: 1080)
      let otherDuration = asset(
        "c", provider: .youtube, title: first.title,
        creator: "Museum", duration: 500)
      let otherContent = asset(
        "d", provider: .pexels, title: "Factory workers operate machines",
        creator: "Factory", duration: 42)
      let review = SearchDuplicateAnalyzer.analyze([first, larger, otherDuration, otherContent])
      #expect(review.groups.count == 1)
      #expect(review.groups[0].confidence == .likely)
      #expect(review.groups[0].memberIDs == [first.stableID, larger.stableID])
      #expect(review.groups[0].recommendedID == larger.stableID)
      #expect(review.uniqueCount == 3)
    }

    @Test("Local thumbnail hashes need corroboration and never convey rights")
    func thumbnailAndRights() {
      var unknown = asset(
        "a", title: "Shared footage from museum", creator: "Archive", duration: 17)
      unknown.licenseStatus = .unknown
      var known = asset(
        "b", provider: .internetArchive, title: "A completely different title",
        creator: "Archive", duration: 17)
      known.licenseStatus = .publicDomain
      known.license = "Public Domain"
      let review = SearchDuplicateAnalyzer.analyze(
        [unknown, known],
        thumbnailHashes: [unknown.stableID: 0xDEAD_BEEF, known.stableID: 0xDEAD_BEEF])
      #expect(review.groups.count == 1)
      #expect(review.groups[0].confidence == .likely)
      #expect(unknown.licenseStatus == .unknown)
      #expect(unknown.effectiveRightsInfo.known == false)
      #expect(known.licenseStatus == .publicDomain)
      let unrelated = asset(
        "c", provider: .youtube, title: "Another subject", creator: "Other", duration: 17)
      #expect(
        SearchDuplicateAnalyzer.analyze(
          [unknown, unrelated], thumbnailHashes: [unknown.stableID: 1, unrelated.stableID: 1]
        ).groups.isEmpty)
    }

    @Test("Perceptual hash rejects blank thumbnails and distinguishes gradients")
    func perceptualHash() {
      #expect(ThumbnailDHash.compute(luminance: Array(repeating: 128, count: 72)) == nil)
      let descending = (0..<72).map { UInt8(240 - ($0 % 9) * 20) }
      let ascending = (0..<72).map { UInt8(20 + ($0 % 9) * 20) }
      #expect(ThumbnailDHash.compute(luminance: descending) == UInt64.max)
      #expect(ThumbnailDHash.compute(luminance: ascending) == 0)
      #expect(ThumbnailDHash.compute(luminance: []) == nil)
    }

    #if os(macOS)
      @Test("macOS ImageIO fingerprints a real repository PNG")
      func macOSImageDecode() throws {
        let file = URL(fileURLWithPath: #filePath)
          .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
          .appendingPathComponent("docs/images/quick-search-v0121.png")
        let data = try Data(contentsOf: file)
        #expect(DuplicateThumbnailHashService.hashImageData(data) != nil)
      }
    #endif

    @Test("Only plausible image candidates enter bounded background hashing")
    func thumbnailCandidates() {
      var first = asset("a", title: "Unrelated label", creator: "Museum", duration: 20)
      var second = asset(
        "b", provider: .internetArchive,
        title: "Other title", creator: "Museum", duration: 20)
      first.thumbnailURL = URL(string: "https://example.org/a.jpg")
      second.thumbnailURL = URL(string: "https://example.org/b.jpg")
      let review = SearchDuplicateAnalyzer.analyze([first, second])
      #expect(Set(review.thumbnailCandidateIDs) == [first.stableID, second.stableID])
    }

    @Test("Cancellation and partial provider failure leave original results visible")
    func fallback() {
      let values = [asset("a"), asset("b", provider: .youtube)]
      #expect(SearchDuplicateAnalyzer.analyze(values, isCancelled: { true }).entries.count == 2)
      #expect(SearchDuplicateAnalyzer.analyze([values[0]]).resultCount == 1)
    }

    @Test("Duplicate review has usable text in all ten interface languages")
    func localization() {
      let catalog = LocalizationCatalog()
      for language in AppLanguage.allCases {
        for key in [
          "duplicate.exact", "duplicate.likely", "duplicate.possible",
          "duplicate.grouped", "duplicate.allResults", "duplicate.recommendedVersion",
          "duplicate.detectSetting", "duplicate.collapseSetting",
        ] {
          let value = catalog.text(key, language: language, arguments: [])
          #expect(value != key && value != "Unavailable")
        }
        let summary = catalog.text(
          "duplicate.summary", language: language, arguments: [80, 57, 9])
        #expect(summary.contains("80") && summary.contains("57") && summary.contains("9"))
      }
    }

    @Test("Indexed 100, 500 and 1000 result scans retain every candidate")
    func scale() {
      for count in [100, 500, 1000] {
        let values = (0..<count).map { index in
          asset(
            "asset-\(index)", title: "Distinct subject \(index) location \(index)",
            duration: Double(index + 1))
        }
        let start = Date()
        let review = SearchDuplicateAnalyzer.analyze(values)
        #expect(review.resultCount == count)
        #expect(review.uniqueCount == count)
        #expect(review.groups.isEmpty)
        #expect(Date().timeIntervalSince(start) < 5)
      }
    }

    private func asset(
      _ id: String, provider: ProviderID = .wikimedia,
      source: URL? = nil, title: String = "Example media", creator: String? = nil,
      duration: Double? = nil, width: Int? = nil, height: Int? = nil
    ) -> MediaAsset {
      MediaAsset(
        id: id, provider: provider, title: title, description: nil,
        thumbnailURL: nil, previewURL: nil, downloadURL: nil,
        sourcePageURL: source ?? URL(
          string: "https://example.org/media/\(provider.rawValue)/\(id)")!,
        creator: creator, license: nil, licenseURL: nil, licenseStatus: .unknown,
        width: width, height: height, duration: duration, fileType: "mp4", mediaType: .video,
        publishedDate: nil, downloadable: false, originalMetadata: [:],
        searchKeyword: "example", relevanceScore: 1)
    }
  }
#endif
