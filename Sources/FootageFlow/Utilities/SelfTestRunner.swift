import Foundation

enum SelfTestRunner {
  @MainActor static func run() -> Int32 {
    var passed = 0
    var failed: [String] = []
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
      if condition() { passed += 1 } else { failed.append(name) }
    }
    check(
      ProviderUtilities.licenseStatus(name: "CC BY 4.0") == .attributionRequired, "License CC BY")
    check(
      ProviderUtilities.licenseStatus(name: "Public Domain") == .publicDomain,
      "License public domain")
    check(ProviderUtilities.licenseStatus(name: nil) == .unknown, "License unknown")
    check(!FileNameSanitizer.sanitize("阿根廷/银行:挤兑?.mp4").contains("/"), "Filename sanitization")
    check(KeywordEngine.keywords(for: "2001年阿根廷银行挤兑").count >= 3, "Keyword expansion")
    check(KeywordEngine.splitScript("第一句话。第二句话。\n\n第三段。").count >= 2, "Script segmentation")
    check(
      URLValidator.isSafeRemote(URL(string: "https://example.com/media.mp4")),
      "HTTPS URL validation")
    check(
      !URLValidator.isSafeRemote(URL(string: "http://example.com/media.mp4")),
      "Unsafe URL rejection")
    let peerThumbnail = ThumbnailResolver.candidates(
      provider: .peertube, rawValues: ["/lazy-static/thumbnails/video.jpg"],
      originalPageURL: URL(string: "https://sepiasearch.org/w/video"),
      instanceURL: URL(string: "https://video.peer.example"))
    check(
      peerThumbnail.first?.absoluteString
        == "https://video.peer.example/lazy-static/thumbnails/video.jpg",
      "PeerTube instance thumbnail resolution")
    check(
      ThumbnailResolver.resolve("//cdn.example.com/a.jpg", relativeTo: nil)?.absoluteString
        == "https://cdn.example.com/a.jpg",
      "Protocol-relative thumbnail resolution")
    check(
      ThumbnailResolver.resolve("not a URL", relativeTo: nil) == nil,
      "Malformed thumbnail rejection")
    check(
      ThumbnailImageFormat.detect(data: Data([0xFF, 0xD8, 0xFF]), contentType: nil) == .jpeg,
      "JPEG thumbnail detection")
    check(
      ThumbnailImageFormat.detect(data: Data("RIFF0000WEBP".utf8), contentType: nil) == .webp,
      "WebP thumbnail detection")
    check(
      ThumbnailImageFormat.detect(
        data: Data([0, 0, 0, 20] + Array("ftypavif".utf8)), contentType: nil) == .avif,
      "AVIF thumbnail detection")
    check(
      ThumbnailResponseValidator.validate(
        status: 200, contentType: "text/html", data: Data("<html>404</html>".utf8)) == nil,
      "Thumbnail HTML rejection")
    check(
      !AppLogger.redact("Authorization: Bearer secret-token-value").contains(
        "secret-token-value"),
      "Log redaction")
    let safetyRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    check(
      DownloadPathSafety.isContained(
        safetyRoot.appendingPathComponent("Project/media.mp4"), in: safetyRoot),
      "Download path containment")
    check(
      !DownloadPathSafety.isContained(
        safetyRoot.deletingLastPathComponent().appendingPathComponent("outside.mp4"),
        in: safetyRoot
      ), "Download path traversal rejection")
    check(
      !DownloadPathSafety.projectDirectory(projectName: "../../escape", root: safetyRoot).path
        .contains("../"), "Project folder sanitization")
    let migrationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let legacyDatabase = migrationDirectory.appendingPathComponent("legacy.json")
    let currentDatabase = migrationDirectory.appendingPathComponent("current.json")
    try? FileManager.default.createDirectory(
      at: migrationDirectory, withIntermediateDirectories: true)
    try? Data("legacy".utf8).write(to: legacyDatabase)
    DataStore.migrateDatabaseIfNeeded(current: currentDatabase, legacy: legacyDatabase)
    check(
      (try? String(contentsOf: currentDatabase, encoding: .utf8)) == "legacy",
      "Legacy database migration")
    try? FileManager.default.removeItem(at: migrationDirectory)
    check(
      ProviderRuntimeState.from(error: ProviderError.missingAPIKey(.pexels)).availability
        == .authenticationRequired, "Provider auth state")
    check(
      ProviderRuntimeState.from(error: ProviderError.rateLimited(retryAfter: nil)).availability
        == .rateLimited, "Provider rate-limit state")
    check(
      ProviderRuntimeState.from(error: ProviderError.temporarilyBlocked(.pexels)).availability
        == .temporarilyBlocked, "Provider direct-search block state")
    check(
      ProviderFactory.make(.pexels, apiKey: "configured").info.mode == .officialAPI,
      "Pexels official API mode")
    check(
      ProviderFactory.make(.pexels, apiKey: "").info.mode == .directSearch,
      "Pexels direct mode")
    check(
      ProviderFactory.make(.pixabay, apiKey: "").info.mode == .directSearch,
      "Pixabay direct mode")
    check(ProviderID.searchCases.count == 17, "Seventeen search provider catalog")
    check(
      ProviderFactory.make(.peertube, apiKey: "").info.mode == .publicAPI,
      "PeerTube public API")
    check(
      ProviderFactory.make(.coverr, apiKey: "").info.mode == .limited,
      "Coverr no-key limited mode")
    check(
      ProviderFactory.make(.coverr, apiKey: "configured").info.mode == .officialAPI,
      "Coverr official API mode")
    check(
      ProviderFactory.make(.vimeo, apiKey: "").info.mode == .limited,
      "Vimeo no-key discovery mode")
    check(
      LinkURLParser.urls(from: "https://youtu.be/example\ninvalid\nhttps://vimeo.com/1").count
        == 2,
      "Link batch parser")
    check(
      LinkURLParser.urls(from: "http://127.0.0.1/private").isEmpty,
      "Link private-address rejection")
    check(
      LinkURLParser.urls(from: "https://example.com/watch?access_token=secret").isEmpty,
      "Link sensitive-query rejection")
    check(
      LinkURLParser.urls(from: "https://user:password@example.com/watch").isEmpty,
      "Link embedded-credential rejection")
    check(
      LinkDownloadQuality.audioOnly.formatSelector == "bestaudio[acodec!=none]/best",
      "Audio-only format selector")
    let feedbackURL = FeedbackURLs.url(
      for: .bug,
      context: FeedbackContext(platform: "macOS", osVersion: "test", language: "en"))
    check(
      feedbackURL.host == "github.com"
        && !feedbackURL.absoluteString.contains("/" + "Users" + "/"),
      "Safe feedback URL")
    check(ProviderFactory.make(.nasa, apiKey: "").info.mode == .publicAPI, "NASA public API")
    check(
      ProviderFactory.make(.libraryOfCongress, apiKey: "").info.mode == .publicAPI,
      "Library of Congress public API")
    check(
      ProviderFactory.make(.nationalArchives, apiKey: "").info.mode == .limited,
      "National Archives limited mode")
    check(
      ProviderFactory.make(.europeana, apiKey: "").info.mode == .limited,
      "Europeana limited mode")
    if case .rateLimited = YTDLPService.mapFailure("HTTP Error 429: Too Many Requests") {
      passed += 1
    } else {
      failed.append("yt-dlp rate-limit mapping")
    }
    if case .regionalRestriction = YTDLPService.mapFailure("not available in your country") {
      passed += 1
    } else {
      failed.append("yt-dlp regional restriction mapping")
    }
    let localizationSuite = "FootageFlowSelfTest.\(UUID().uuidString)"
    if let defaults = UserDefaults(suiteName: localizationSuite) {
      defaults.removePersistentDomain(forName: localizationSuite)
      let localization = LocalizationManager(defaults: defaults)
      check(localization.language == .english, "Localization default English")
      check(AppLanguage.allCases.count == 10, "Ten supported languages")
      check(localization.text("nav.quickSearch") == "Quick Search", "English localization")
      for language in AppLanguage.allCases {
        localization.setLanguage(language)
        let recommendation = localization.text("search.apiRecommendation")
        check(
          recommendation.contains("National Archives")
            && recommendation.contains("Europeana")
            && recommendation.contains("YouTube"),
          "\(language.rawValue) API recommendation")
        check(
          localization.text("media.retryThumbnail") != "media.retryThumbnail",
          "\(language.rawValue) thumbnail retry localization")
      }
      localization.setLanguage(.simplifiedChinese)
      check(localization.text("nav.quickSearch") == "快速搜索", "Chinese localization")
      check(
        localization.text("localization.fallbackProbe") == "English fallback",
        "Localization English fallback")
      check(
        LocalizationManager(defaults: defaults).language == .simplifiedChinese,
        "Localization persistence")
      defaults.removePersistentDomain(forName: localizationSuite)
    } else {
      failed.append("Localization test defaults")
    }

    let sample = MediaAsset(
      id: "1", provider: .wikimedia, title: "Test", description: nil, thumbnailURL: nil,
      previewURL: nil, downloadURL: URL(string: "https://example.com/a.mp4"),
      sourcePageURL: URL(string: "https://example.com/item")!, creator: "A", license: "CC BY",
      licenseURL: nil, licenseStatus: .attributionRequired, width: 1920, height: 1080,
      duration: 10,
      fileType: "video/mp4", mediaType: .video, publishedDate: nil, downloadable: true,
      originalMetadata: [:], searchKeyword: "test", relevanceScore: 1)
    var linkFilenameSample = sample
    linkFilenameSample.originalMetadata["sourceName"] = "X / Twitter"
    check(
      !FileNameSanitizer.fileName(asset: linkFilenameSample).contains("/"),
      "Link source filename sanitization")
    let linkDownloadRecord = DownloadRecord(
      asset: linkFilenameSample,
      fileURL: safetyRoot.appendingPathComponent("Project/link.mp4"), projectID: nil)
    check(linkDownloadRecord.sourceName == "X / Twitter", "Link download source persistence")
    let duplicate = sample
    check(SearchDeduplicator.apply([sample, duplicate]).count == 1, "Search deduplication")
    let discoveryFilter = AdvancedSearchFilter(
      mediaType: .video, orientation: .landscape, resolution: .fullHD,
      duration: .underMinute, license: .knownOnly, selectedProviders: [.wikimedia],
      downloadableOnly: true)
    check(discoveryFilter.matches(sample), "Discovery filters")
    var selection = AssetSelection()
    selection.selectVisible([sample])
    check(selection.count == 1, "Batch selection")
    check(
      AttributionFormatter.attribution(for: sample).contains(sample.sourcePageURL.absoluteString),
      "Attribution formatter")
    check(
      (try? JSONDecoder().decode(MediaAsset.self, from: JSONEncoder().encode(sample))) == sample,
      "Unified model Codable")

    let store = DataStore(inMemory: true)
    let project = store.addProject(name: "Test Project")
    check(
      store.projects.count == 1 && store.projects.first?.name == "Test Project", "Project create")
    store.toggleFavorite(asset: sample, projectID: project.id)
    check(store.favorites.count == 1, "Favorite persist model")
    store.addHistory(
      SearchHistoryRecord(
        originalQuery: "test", keywords: ["test"], providers: [.wikimedia], projectID: project.id,
        resultCount: 1))
    store.addDownload(
      DownloadRecord(
        asset: sample, fileURL: safetyRoot.appendingPathComponent("Project/test.mp4"),
        projectID: project.id))
    store.deleteProject(id: project.id)
    check(
      store.projects.isEmpty && store.favorites.first?.projectID == nil
        && store.history.first?.projectID == nil && store.downloads.first?.projectID == nil,
      "Project delete isolation")

    let pexelsJSON = Data(
      "{\"videos\":[{\"id\":7,\"width\":1920,\"height\":1080,\"duration\":8,\"url\":\"https://pexels.com/v/7\",\"image\":\"https://img/7.jpg\",\"user\":{\"name\":\"Creator\",\"url\":\"https://pexels.com/u\"},\"video_files\":[{\"width\":1920,\"height\":1080,\"link\":\"https://cdn/7.mp4\",\"file_type\":\"video/mp4\"}]}]}"
        .utf8)
    check(
      (try? JSONDecoder().decode(PexelsVideoResponse.self, from: pexelsJSON).videos.first?.id)
        == 7,
      "Pexels fixture parse")
    let pixabayJSON = Data(
      "{\"hits\":[{\"id\":8,\"pageURL\":\"https://pixabay.com/videos/8\",\"videos\":{\"medium\":{\"url\":\"https://cdn/8.mp4\",\"width\":1920,\"height\":1080}}}]}"
        .utf8)
    check(
      (try? JSONDecoder().decode(PixabayVideoResponse.self, from: pixabayJSON).hits.first?.id)
        == 8,
      "Pixabay fixture parse")
    let wikiJSON = Data(
      "{\"query\":{\"pages\":[{\"pageid\":9,\"title\":\"File:Test.jpg\",\"imageinfo\":[{\"url\":\"https://upload/test.jpg\",\"width\":100,\"height\":80}]}]}}"
        .utf8)
    check(
      (try? JSONDecoder().decode(WikimediaResponse.self, from: wikiJSON).query?.pages.first?
        .pageid)
        == 9, "Wikimedia fixture parse")
    let youtubeJSON = Data(
      "{\"items\":[{\"id\":{\"videoId\":\"abc\"},\"snippet\":{\"publishedAt\":\"2020-01-01T00:00:00Z\",\"channelId\":\"c\",\"title\":\"T\",\"description\":\"D\",\"channelTitle\":\"C\",\"thumbnails\":{}}}]}"
        .utf8)
    check(
      (try? JSONDecoder().decode(YouTubeSearchResponse.self, from: youtubeJSON).items.first?.id
        .videoId) == "abc", "YouTube fixture parse")
    let archiveJSON = Data(
      "{\"response\":{\"docs\":[{\"identifier\":\"item1\",\"title\":\"Archive\"}]}}".utf8)
    let archiveRoot = try? JSONSerialization.jsonObject(with: archiveJSON) as? [String: Any]
    let archiveDocs = (archiveRoot?["response"] as? [String: Any])?["docs"] as? [[String: Any]]
    check(
      archiveDocs?.first?["identifier"] as? String == "item1", "Internet Archive fixture parse")

    print("SELF_TEST passed=\(passed) failed=\(failed.count)")
    for name in failed { print("FAIL \(name)") }
    return failed.isEmpty ? 0 : 1
  }
}
